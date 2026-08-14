/// What PlaySphere charges for, and what having paid entitles you to.
///
/// Every amount in this file is an integer count of paise, for the reason
/// spelled out at the top of `payment.dart`: a rupee is not representable in
/// binary floating point, and a price that drifts by a paisa across a renewal
/// and a refund makes the books not balance.
///
/// ## Why the price lives in code and the entitlement lives in Firestore
///
/// The price of a plan is a business decision that changes for everyone at
/// once — it belongs in one constant that a release can move. What somebody
/// actually bought does not: an org that paid ₹999 in 2026 holds that plan
/// until it expires no matter what the list price does afterwards. So the
/// document stores the plan they hold and when it runs out, never the amount
/// the plan costs today.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// What an organization has paid for.
///
/// Ordered least-privileged first, same convention as `MembershipRole`, so
/// "does this org have at least X" is a rank comparison rather than a set
/// membership test that has to be updated every time a tier is added.
enum OrgPlan {
  /// Never paid, or paid and lapsed. The club still works — this is
  /// deliberately not a lockout. A club whose plan expired mid-season must
  /// not lose the fixtures it already ran, and a member turning up to score a
  /// match is the worst possible moment to discover the treasurer forgot to
  /// renew.
  free('free', 'Free', 0),

  /// The paid tier every club, school, village and community buys. One price,
  /// no seat count — see [Pricing.clubYearlyPaise].
  club('club', 'Club', 1);

  const OrgPlan(this.wire, this.label, this.rank);

  final String wire;
  final String label;
  final int rank;

  static OrgPlan fromWire(String? w) => OrgPlan.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => OrgPlan.free,
      );
}

/// What an individual player has paid for.
enum MemberPlan {
  /// The default, and deliberately a complete product: create a PlaySphere
  /// ID, join clubs, enter events, play, be scored, appear in results.
  ///
  /// Nothing a player needs in order to *take part in sport* is ever behind
  /// [premium]. Gating participation would break the only growth loop the
  /// product has — a club brings 200 members, and 200 members who cannot play
  /// bring nobody.
  free('free', 'Free', 0),

  /// Depth on top of participation: full career history, analytics, the
  /// shareable sports portfolio, and no ads.
  premium('premium', 'Premium', 1);

  const MemberPlan(this.wire, this.label, this.rank);

  final String wire;
  final String label;
  final int rank;

  static MemberPlan fromWire(String? w) => MemberPlan.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => MemberPlan.free,
      );
}

/// Every price in the product, in one place.
///
/// ## The launch offer
///
/// [introOfferActive] is what makes the club and premium checkouts cost ₹0
/// today. It is a switch rather than a set of zeroed constants so that the
/// list price stays visible the whole time — the checkout shows ₹999 struck
/// through and ₹0 payable, which is what makes the offer read as an offer
/// instead of the product looking free and then mysteriously growing a price
/// later. Flipping this to `false` is the entire change needed to start
/// charging; nothing downstream of it hardcodes zero.
class Pricing {
  const Pricing._();

  /// ₹999 a year for a whole organization, however many members it has.
  ///
  /// Deliberately not per-seat. A village club with 400 members and a school
  /// with 40 are the same ₹999, because the thing being sold is the club's
  /// ability to run its sport, and a per-head price punishes exactly the
  /// large communities whose members are the network PlaySphere is trying to
  /// build.
  static const clubYearlyPaise = 99900;

  /// ₹99 a year for one player.
  ///
  /// Billed yearly and never monthly. At ₹8/month the payment processing fee
  /// alone eats a fifth of the charge, and the app-store commission a further
  /// 15% — a monthly cadence at this price point loses money on collection
  /// before it pays for anything.
  static const premiumYearlyPaise = 9900;

  /// While true, both plans are granted at ₹0.
  ///
  /// The subscription, the expiry date and the ledger row are all written
  /// exactly as they will be when money changes hands. Only the amount is
  /// zero — so the day this flips, there is no untested code path being
  /// exercised for the first time against a real card.
  static const introOfferActive = true;

  /// How long a purchase lasts. One year, for both plans.
  static const termDays = 365;

  /// What the payer is actually charged today for [plan].
  static int orgPricePaise(OrgPlan plan) => switch (plan) {
        OrgPlan.free => 0,
        OrgPlan.club => introOfferActive ? 0 : clubYearlyPaise,
      };

  /// The undiscounted price, shown struck through next to [orgPricePaise].
  static int orgListPricePaise(OrgPlan plan) => switch (plan) {
        OrgPlan.free => 0,
        OrgPlan.club => clubYearlyPaise,
      };

  static int memberPricePaise(MemberPlan plan) => switch (plan) {
        MemberPlan.free => 0,
        MemberPlan.premium => introOfferActive ? 0 : premiumYearlyPaise,
      };

  static int memberListPricePaise(MemberPlan plan) => switch (plan) {
        MemberPlan.free => 0,
        MemberPlan.premium => premiumYearlyPaise,
      };

  /// What a buyer is actually charged today for a club-store product whose
  /// club set [listPricePaise]. Same `introOfferActive` flag as the plans
  /// above — commerce launches free for the same reason they did: every
  /// order, receipt and ledger row is written exactly as it will be once
  /// money changes hands, so turning this off is the only change needed.
  static int productPricePaise(int listPricePaise) =>
      introOfferActive ? 0 : listPricePaise;

  // -------------------------------------------------------------------
  // Global pricing.
  //
  // India bills yearly, in rupees, through whatever gateway ends up wired
  // into `PaymentGateway` — see `BillingRepository`. A market outside India
  // is a different shape of purchase, not just a different number: the
  // vision this implements prices it monthly, in US cents, which is its own
  // billing period (`GlobalPricing.periodDays`), not a currency conversion
  // of the Indian one.
  //
  // What THIS class provides is the pricing itself — real figures, real
  // formatting, fully tested. What it deliberately does not provide is a
  // second checkout: charging in USD needs a processor that can do that
  // (Razorpay's core product is India-only), and picking one is a business
  // decision, not something to bolt on silently while wiring a display
  // figure. Until that exists, `orgMonthlyUsdCents`/`memberMonthlyUsdCents`
  // are shown as information ("this is what it costs outside India") on the
  // same screens that sell the Indian plan, never charged.
  // -------------------------------------------------------------------

  /// $9.00/month, in cents — see the block comment above.
  static const orgMonthlyUsdCents = 900;

  /// $0.99/month, in cents.
  static const memberMonthlyUsdCents = 99;

  /// A monthly cadence, unlike India's yearly [termDays] — see the block
  /// comment above for why this is a deliberate product difference, not a
  /// currency conversion of the same term.
  static const globalTermDays = 30;

  /// "$9.00", "$0.99" — cents formatted the way a US price tag reads, kept
  /// separate from [formatPaise] because the two currencies round
  /// differently (paise never shows a decimal for a whole-rupee price; a
  /// dollar price always shows both cents places, `$9.00` not `$9`).
  static String formatUsdCents(int cents) {
    if (cents == 0) return 'Free';
    return '\$${(cents / 100).toStringAsFixed(2)}';
  }

  /// "₹999", "₹8.50", "Free" — for display only, never for arithmetic.
  ///
  /// Whole rupees lose the decimal because every price in this product is a
  /// whole number of rupees and "₹999.00" reads like a form field rather than
  /// a price. The fractional branch exists for refund and split amounts,
  /// which genuinely can land on a paisa.
  static String formatPaise(int paise) {
    if (paise == 0) return 'Free';
    if (paise % 100 == 0) return '₹${paise ~/ 100}';
    return '₹${(paise / 100).toStringAsFixed(2)}';
  }
}

/// One organization's or one player's paid state.
///
/// Stored as fields on the document that already exists (`orgs/{orgId}` and
/// `users/{uid}`) rather than in a subscriptions collection of its own. The
/// deciding constraint is `firestore.rules`: a rule can read the document it
/// is already guarding for free, but resolving a second document costs a
/// `get()` on every single evaluation, and the entitlement has to be checked
/// on paths that run thousands of times a match. The ledger — the record of
/// each individual charge — is separate, and lives in `payments/`.
class PlanState {
  const PlanState({
    required this.activatedAt,
    required this.validUntil,
    this.lastPaymentId,
  });

  final DateTime? activatedAt;

  /// When the entitlement lapses. Null means it was never bought.
  final DateTime? validUntil;

  /// The `payments/{id}` row that most recently extended this. The audit
  /// trail from "this club is on the paid plan" back to "and here is the
  /// charge that did it" has to exist before anyone asks for a refund.
  final String? lastPaymentId;

  static const none = PlanState(activatedAt: null, validUntil: null);

  /// Whether the entitlement is live *right now*.
  ///
  /// Takes [asOf] rather than reading the clock so the expiry logic is
  /// testable without waiting a year, and so a whole screen renders against
  /// one consistent instant instead of re-reading `now` per widget.
  bool isActiveAt(DateTime asOf) {
    final until = validUntil;
    return until != null && until.isAfter(asOf);
  }

  /// Days left, floored at zero. Negative would be "days since it lapsed",
  /// which no caller wants and every caller would forget to handle.
  int daysRemainingAt(DateTime asOf) {
    final until = validUntil;
    if (until == null) return 0;
    final left = until.difference(asOf).inDays;
    return left < 0 ? 0 : left;
  }

  /// Within a month of lapsing — when the renewal prompt starts appearing.
  bool renewsSoonAt(DateTime asOf) =>
      isActiveAt(asOf) && daysRemainingAt(asOf) <= 30;

  static PlanState fromDocData(
    Map<String, dynamic> d, {
    required String activatedKey,
    required String validUntilKey,
    required String lastPaymentKey,
  }) =>
      PlanState(
        activatedAt: Fs.dateOrNull(d[activatedKey]),
        validUntil: Fs.dateOrNull(d[validUntilKey]),
        lastPaymentId: Fs.strOrNull(d[lastPaymentKey]),
      );

  /// Extends an entitlement from whichever is later: now, or the expiry it
  /// already has.
  ///
  /// Renewing early must not throw away the remainder of the term already
  /// paid for. Someone who renews with two months left gets fourteen months,
  /// not twelve — anything else quietly charges them for time they own, and
  /// the support ticket that follows costs more than the sale.
  DateTime extendedFrom(DateTime now, {int days = Pricing.termDays}) {
    final base = (validUntil != null && validUntil!.isAfter(now))
        ? validUntil!
        : now;
    return base.add(Duration(days: days));
  }
}

/// One charge, at `payments/{paymentId}`.
///
/// Written for ₹0 launch-offer activations too. A ledger with holes in it is
/// not a ledger: "how many clubs activated in March" and "how many clubs paid
/// in March" are different questions, and the first one is unanswerable if
/// free activations leave no row. The zero rows also mean the reporting,
/// reconciliation and refund paths are exercised from day one rather than
/// first meeting real data on the day the price goes live.
class PlanPayment {
  const PlanPayment({
    required this.id,
    required this.payerUid,
    required this.kind,
    required this.subjectId,
    required this.planWire,
    required this.amountPaise,
    required this.listPricePaise,
    required this.validUntil,
    this.gateway = 'none',
    this.gatewayRef,
    this.status = PlanPaymentStatus.paid,
    this.createdAt,
  });

  final String id;

  /// Who tapped Pay. For an org plan this is the owner or admin acting on the
  /// club's behalf, not the club — a club cannot hold a card.
  final String payerUid;

  final PlanPaymentKind kind;

  /// The org id or the uid the entitlement was granted to.
  final String subjectId;

  /// `OrgPlan.wire` or `MemberPlan.wire`. Stored as the wire string rather
  /// than the enum because a ledger row must stay readable after the enum it
  /// came from has been renamed or retired.
  final String planWire;

  /// What was actually collected. Zero during the launch offer.
  final int amountPaise;

  /// What it would have cost. Keeping both is what makes "we gave away
  /// ₹4.2 lakh of launch offers" a query rather than an estimate.
  final int listPricePaise;

  final DateTime? validUntil;

  /// Which processor took the money. `none` for a zero-rupee activation,
  /// `razorpay` once the gateway is live. Explicit so the reconciliation job
  /// can skip rows that were never going to appear in a settlement file.
  final String gateway;

  /// The processor's own id for this charge, for reconciliation.
  final String? gatewayRef;

  final PlanPaymentStatus status;

  final DateTime? createdAt;

  bool get isFree => amountPaise == 0;

  factory PlanPayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return PlanPayment(
      id: doc.id,
      payerUid: Fs.str(d['payerUid']),
      kind: PlanPaymentKind.fromWire(Fs.str(d['kind'])),
      subjectId: Fs.str(d['subjectId']),
      planWire: Fs.str(d['plan']),
      amountPaise: Fs.integer(d['amountPaise']),
      listPricePaise: Fs.integer(d['listPricePaise']),
      validUntil: Fs.dateOrNull(d['validUntil']),
      gateway: Fs.str(d['gateway'], 'none'),
      gatewayRef: Fs.strOrNull(d['gatewayRef']),
      status: PlanPaymentStatus.fromWire(Fs.strOrNull(d['status'])),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'payerUid': payerUid,
        'kind': kind.wire,
        'subjectId': subjectId,
        'plan': planWire,
        'amountPaise': amountPaise,
        'listPricePaise': listPricePaise,
        'currency': 'INR',
        'validUntil': Fs.ts(validUntil),
        'gateway': gateway,
        'gatewayRef': gatewayRef,
        // Written explicitly rather than left to `fromWire`'s default: this
        // constructor is only ever called once money has already moved (or
        // the launch offer made ₹0 count as moved), never for a pending
        // Razorpay row — those are written by `createPaymentLink` directly.
        'status': PlanPaymentStatus.paid.wire,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// A plan bought for a club that does not exist yet.
///
/// Club creation is the one purchase where the entitlement cannot be written
/// with an `update`, because the document being entitled is being created in
/// the same breath. Splitting it into "create the club, then buy the plan"
/// opens a window a dropped connection can land in, leaving a club that was
/// paid for and never got its plan.
///
/// So this carries everything the purchase decided — which plan, what was
/// charged, how long it runs, what the processor called it — and hands back
/// the two payloads `OrgRepository.createOrganization` needs to put into the
/// same batch as the club itself. The billing rules stay in the billing
/// layer; the org repository only batches what it is given.
class ClubPlanGrant {
  const ClubPlanGrant({
    required this.plan,
    required this.payerUid,
    required this.paymentId,
    required this.validUntil,
    required this.amountPaise,
    required this.gateway,
    this.gatewayRef,
  });

  final OrgPlan plan;
  final String payerUid;
  final String paymentId;
  final DateTime validUntil;
  final int amountPaise;
  final String gateway;
  final String? gatewayRef;

  /// The plan fields to merge into the new `orgs/{orgId}` document.
  Map<String, Object?> orgFields() => {
        'plan': plan.wire,
        'planActivatedAt': FieldValue.serverTimestamp(),
        'planValidUntil': Fs.ts(validUntil),
        'planPaymentId': paymentId,
      };

  /// The `payments/{paymentId}` row, now that the club's id is known.
  Map<String, Object?> ledgerRow(String orgId) => PlanPayment(
        id: paymentId,
        payerUid: payerUid,
        kind: PlanPaymentKind.orgPlan,
        subjectId: orgId,
        planWire: plan.wire,
        amountPaise: amountPaise,
        listPricePaise: Pricing.orgListPricePaise(plan),
        validUntil: validUntil,
        gateway: gateway,
        gatewayRef: gatewayRef,
      ).toCreate();
}

/// What a [PlanPayment] bought, which decides where the entitlement lands.
enum PlanPaymentKind {
  orgPlan('org_plan'),
  memberPlan('member_plan'),
  groundBooking('ground_booking'),

  /// A club-store purchase — see `ClubCommerceRepository.placeOrder`.
  /// `subjectId` is the order id and `planWire` the product id, the closest
  /// fit `PlanPayment`'s entitlement-shaped fields have for a one-off good
  /// rather than a renewable plan; there is no `validUntil` for a jersey.
  clubStore('club_store');

  const PlanPaymentKind(this.wire);
  final String wire;

  static PlanPaymentKind fromWire(String? w) =>
      PlanPaymentKind.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => PlanPaymentKind.orgPlan,
      );
}

/// Where a row stands, for the payments that do not settle in the same
/// breath they were created — see `createPaymentLink` in
/// `functions/razorpay.js`.
///
/// Every row written before this existed was written only *after* money had
/// already changed hands (`FreeCheckout`, at ₹0, or nothing at all) — there
/// was never a pending state to record. So a legacy row with no `status`
/// field reads back as [paid] rather than [pending]: the absence means
/// "written under the old, always-settled model", not "still waiting".
enum PlanPaymentStatus {
  /// The Razorpay order/link exists but no money has moved yet.
  created('created'),

  /// Waiting on Razorpay's webhook — the payer has the checkout page open.
  pending('pending'),

  /// The webhook confirmed the charge and the entitlement was granted.
  paid('paid'),

  /// The gateway request itself failed, or the webhook never arrived and the
  /// link expired. No entitlement was granted.
  failed('failed');

  const PlanPaymentStatus(this.wire);
  final String wire;

  static PlanPaymentStatus fromWire(String? w) =>
      PlanPaymentStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => PlanPaymentStatus.paid,
      );
}
