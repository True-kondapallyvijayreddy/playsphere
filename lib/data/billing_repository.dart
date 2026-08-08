import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/billing.dart';
import 'org_repository.dart' show guard, guardStream;

/// What actually takes the money.
///
/// ## Why this is an interface with a do-nothing implementation
///
/// PlaySphere is launching its paid plans at ₹0 (see [Pricing.introOfferActive]).
/// The tempting shortcut is to skip the payment concept entirely and just set
/// a flag on the club — but then the day the price goes live, the *entire*
/// purchase path is new code meeting a real card for the first time, and the
/// entitlement, the expiry, the ledger and the receipt are all being written
/// for the first time under money.
///
/// So instead everything except the charge itself is real from day one. The
/// gateway is the one seam, [FreeCheckout] is the only implementation today,
/// and turning on Razorpay means writing a second implementation and swapping
/// the provider — no caller changes.
abstract class PaymentGateway {
  /// Collects [amountPaise] and returns the processor's reference for it, or
  /// null when no processor was involved (a zero-rupee activation).
  ///
  /// Throws to abort the purchase. A gateway that throws must not have taken
  /// money — the caller writes no entitlement and no ledger row.
  Future<String?> collect({
    required int amountPaise,
    required String description,
  });

  /// The name recorded on the ledger row, for reconciliation.
  String get name;
}

/// The launch-offer gateway: grants the plan without charging.
///
/// Refuses to be used for a non-zero amount rather than silently letting a
/// paid plan through for free. If [Pricing.introOfferActive] is turned off
/// while this is still the wired-in gateway, every purchase fails loudly at
/// the first tap — which is the correct outcome, and vastly better than
/// discovering a month later that a thousand clubs were given ₹999 plans.
class FreeCheckout implements PaymentGateway {
  const FreeCheckout();

  @override
  String get name => 'none';

  @override
  Future<String?> collect({
    required int amountPaise,
    required String description,
  }) async {
    if (amountPaise != 0) {
      throw const ValidationException(
        'Card payments are not switched on yet, so this cannot be charged '
        'for. Nothing has been taken from your account.',
      );
    }
    return null;
  }
}

/// Buying a plan, and reading back what was bought.
///
/// ## Why the entitlement and the ledger are written in one batch
///
/// These two writes must not be able to come apart. An entitlement without a
/// ledger row is a club on a paid plan with nothing explaining why, which is
/// unauditable and unrefundable. A ledger row without an entitlement is a
/// customer who has paid and got nothing, which is the same problem pointed
/// at the person instead of the books. A batch makes both land or neither.
class BillingRepository {
  const BillingRepository({this.gateway = const FreeCheckout()});

  final PaymentGateway gateway;

  /// Activates or renews an organization's plan.
  ///
  /// Returns the ledger id, so the caller can show a receipt reference
  /// without a second read.
  ///
  /// [existing] is the club's current plan state, and is what makes an early
  /// renewal add to the remaining term rather than truncate it — see
  /// [PlanState.extendedFrom].
  Future<String> purchaseOrgPlan({
    required String orgId,
    required String payerUid,
    required OrgPlan plan,
    PlanState existing = PlanState.none,
    DateTime? now,
  }) =>
      guard(() async {
        final at = now ?? DateTime.now();
        final amount = Pricing.orgPricePaise(plan);
        final validUntil = existing.extendedFrom(at);

        // Collect BEFORE writing anything. A gateway that throws leaves no
        // trace, which is what makes a failed payment retryable — the club
        // has no half-granted plan to reconcile away first.
        final ref = await gateway.collect(
          amountPaise: amount,
          description: 'PlaySphere ${plan.label} plan — 1 year',
        );

        final paymentRef = Refs.payments.doc();
        final batch = Refs.db.batch();

        batch.set(
          paymentRef,
          PlanPayment(
            id: paymentRef.id,
            payerUid: payerUid,
            kind: PlanPaymentKind.orgPlan,
            subjectId: orgId,
            planWire: plan.wire,
            amountPaise: amount,
            listPricePaise: Pricing.orgListPricePaise(plan),
            validUntil: validUntil,
            gateway: gateway.name,
            gatewayRef: ref,
          ).toCreate(),
        );

        batch.update(Refs.org(orgId), {
          'plan': plan.wire,
          'planActivatedAt': _activationStamp(existing.activatedAt),
          'planValidUntil': Timestamp.fromDate(validUntil),
          'planPaymentId': paymentRef.id,
        });

        await batch.commit();
        return paymentRef.id;
      });

  /// The same, for a player buying Premium.
  Future<String> purchaseMemberPlan({
    required String uid,
    required MemberPlan plan,
    PlanState existing = PlanState.none,
    DateTime? now,
  }) =>
      guard(() async {
        final at = now ?? DateTime.now();
        final amount = Pricing.memberPricePaise(plan);
        final validUntil = existing.extendedFrom(at);

        final ref = await gateway.collect(
          amountPaise: amount,
          description: 'PlaySphere ${plan.label} — 1 year',
        );

        final paymentRef = Refs.payments.doc();
        final batch = Refs.db.batch();

        batch.set(
          paymentRef,
          PlanPayment(
            id: paymentRef.id,
            payerUid: uid,
            kind: PlanPaymentKind.memberPlan,
            subjectId: uid,
            planWire: plan.wire,
            amountPaise: amount,
            listPricePaise: Pricing.memberListPricePaise(plan),
            validUntil: validUntil,
            gateway: gateway.name,
            gatewayRef: ref,
          ).toCreate(),
        );

        batch.update(Refs.user(uid), {
          'plan': plan.wire,
          'planActivatedAt': _activationStamp(existing.activatedAt),
          'planValidUntil': Timestamp.fromDate(validUntil),
          'planPaymentId': paymentRef.id,
        });

        await batch.commit();
        return paymentRef.id;
      });

  /// Takes payment for a club that does not exist yet, and returns the grant
  /// to be written in the same batch as the club.
  ///
  /// Charging here rather than inside `createOrganization` is what makes a
  /// declined payment leave nothing behind: no club, no membership, no invite
  /// code, no ledger row. See [ClubPlanGrant] for why the two writes have to
  /// end up in one batch afterwards.
  Future<ClubPlanGrant> purchasePlanForNewClub({
    required String payerUid,
    required OrgPlan plan,
    DateTime? now,
  }) =>
      guard(() async {
        final at = now ?? DateTime.now();
        final amount = Pricing.orgPricePaise(plan);

        final gatewayRef = await gateway.collect(
          amountPaise: amount,
          description: 'PlaySphere ${plan.label} plan — 1 year',
        );

        return ClubPlanGrant(
          plan: plan,
          payerUid: payerUid,
          // Allocated here rather than by the batch, because the club
          // document has to carry the id of the row that paid for it and the
          // row has to carry the id of the club — the two references are
          // circular and one of them has to be minted first.
          paymentId: Refs.payments.doc().id,
          validUntil: at.add(const Duration(days: Pricing.termDays)),
          amountPaise: amount,
          gateway: gateway.name,
          gatewayRef: gatewayRef,
        );
      });

  /// This person's receipts, newest first — plan purchases and ground
  /// bookings alike.
  Stream<List<PlanPayment>> watchMyPayments(String uid) => guardStream(
        () => Refs.payments
            .where('payerUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots()
            .map((s) => s.docs.map(PlanPayment.fromDoc).toList(growable: false)),
      );
}

/// Preserves the original activation date across a renewal, and stamps the
/// server clock on a first purchase.
///
/// "Member since" is a different fact from "paid until", and overwriting the
/// first every time the second is extended would erase the only record of how
/// long a club has actually been with PlaySphere.
Object _activationStamp(DateTime? existing) => existing == null
    ? FieldValue.serverTimestamp()
    : Timestamp.fromDate(existing);
