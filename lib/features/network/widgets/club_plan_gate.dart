import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/billing.dart';
import '../../../core/models/organization.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/real_payment_sheet.dart';
import '../../../shared/section_header.dart';

/// What a club whose plan has lapsed sees instead of a composer.
///
/// ## Why the gate carries the renewal and does not just point at one
///
/// Until this existed, a club's plan could be bought at exactly one moment —
/// the last step of creating the club (`CreateOrgScreen`) — and never again.
/// `BillingRepository.purchaseOrgPlan` and the `orgPlan` leg of the Razorpay
/// flow were both written, tested and unreachable, so a club whose year ran
/// out had no way back onto the plan from anywhere in the app. A paywall that
/// points at a renewal the product does not have is not a paywall, it is a
/// wall; this is the renewal, on the screen where somebody first discovers
/// they need it.
///
/// It also says plainly what still works without it. Nothing that was already
/// happening stops: the club keeps every thread it is in and can answer every
/// club that writes to it. Only reaching out to somebody new is the paid move
/// — see `ClubNetworkRepository`, and `PremiumScreen`, whose reasoning about
/// never taking away what a free user already had this follows.
class ClubPlanGate extends ConsumerStatefulWidget {
  const ClubPlanGate({super.key, required this.club});

  /// The club being spoken as. Null while its document is still loading, in
  /// which case the renewal is offered but not yet actionable.
  final Organization? club;

  @override
  ConsumerState<ClubPlanGate> createState() => _ClubPlanGateState();
}

class _ClubPlanGateState extends ConsumerState<ClubPlanGate> {
  bool _busy = false;

  Future<void> _renew() async {
    final club = widget.club;
    final payerUid = ref.read(authUidProvider);
    if (club == null || payerUid == null) return;

    setState(() => _busy = true);
    try {
      if (Pricing.introOfferActive) {
        // The launch-offer path: ₹0, synchronous, entitlement and ledger row
        // written in the same batch. Identical to what club creation does.
        await ref.read(billingRepositoryProvider).purchaseOrgPlan(
              orgId: club.id,
              payerUid: payerUid,
              plan: OrgPlan.club,
              // Passing what the club already holds is what makes an early
              // renewal add to the remaining term instead of truncating it —
              // see `PlanState.extendedFrom`.
              existing: club.planState,
            );
      } else {
        // The real-money path. Nothing here writes the entitlement: the
        // server's webhook does, once Razorpay has confirmed — see
        // `RazorpayCheckout`.
        final pending = await ref.read(razorpayCheckoutProvider).start(
              kind: PlanPaymentKind.orgPlan,
              subjectId: club.id,
              planWire: OrgPlan.club.wire,
            );
        if (!mounted) return;
        final paid = await showRealPaymentSheet(
          context,
          paymentId: pending.paymentId,
          url: pending.url,
        );
        if (!paid) return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${club.name} is on the club plan.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    final payable = Pricing.orgPricePaise(OrgPlan.club);

    return SafeArea(
      top: false,
      child: ContentBounds(
        maxWidth: 820,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: QuietCard(
          icon: Icons.workspace_premium_outlined,
          title: 'Reaching out needs the club plan',
          message: '${club?.name ?? 'This club'} can still read every '
              'conversation it is in and reply to any club that writes '
              'first. Starting a new one is part of the plan.',
          action: FilledButton(
            onPressed: _busy || club == null ? null : _renew,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    payable == 0
                        ? 'Renew free for a year'
                        : 'Renew for ${Pricing.formatPaise(payable)} a year',
                  ),
          ),
        ),
      ),
    );
  }
}
