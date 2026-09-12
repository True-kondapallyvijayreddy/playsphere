import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/plan_card.dart';
import '../../shared/real_payment_sheet.dart';

/// PlaySphere Premium — what a player can buy for themselves.
///
/// ## What is deliberately NOT behind this
///
/// Nothing needed to take part in sport. Creating an ID, joining clubs,
/// entering events, playing, being scored, appearing in results and seeing
/// your own scorecards are all free and stay free. That is not generosity: a
/// club brings 200 members onto the platform, and 200 members who cannot play
/// bring nobody else, so gating participation would break the only growth
/// loop the product has.
///
/// What Premium sells is depth on the identity a player already owns — the
/// full career history rather than the recent slice, the analytics rather
/// than the totals, the portfolio they can send to a selector, and the app
/// without ads. A free member loses nothing they had; a Premium member gets
/// more of what they already care about.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _busy = false;

  Future<void> _subscribe() async {
    final me = ref.read(authUserProvider).valueOrNull;
    if (me == null) return;

    setState(() => _busy = true);
    try {
      if (Pricing.introOfferActive) {
        // The launch-offer path: synchronous, ₹0, entitlement written in the
        // same call. Unchanged by any of this.
        await ref.read(billingRepositoryProvider).purchaseMemberPlan(
              uid: me.uid,
              plan: MemberPlan.premium,
              // Passing the current state is what makes an early renewal add
              // to the remaining term instead of resetting it — see
              // PlanState.extendedFrom.
              existing: me.planState,
            );
      } else {
        // The real-money path: start a Razorpay payment link, send the payer
        // to it, and wait for the server's own confirmation. Nothing here
        // writes the entitlement — see `RazorpayCheckout`'s doc comment.
        final pending = await ref.read(razorpayCheckoutProvider).start(
              kind: PlanPaymentKind.memberPlan,
              subjectId: me.uid,
              planWire: MemberPlan.premium.wire,
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
          const SnackBar(content: Text('Premium is active. Enjoy.')),
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
    final theme = Theme.of(context);
    final me = ref.watch(authUserProvider).valueOrNull;
    final now = DateTime.now();
    final isPremium = me?.hasPremiumAt(now) ?? false;
    final payable = Pricing.memberPricePaise(MemberPlan.premium);

    return AppScaffold(
      title: 'PlaySphere Premium',
      subtitle: isPremium ? 'Active' : 'Your sports identity, in full',
      body: ListView(
        children: [
          ContentBounds(
            maxWidth: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isPremium) ...[
                  _ActiveBanner(
                    validUntil: me!.planState.validUntil,
                    daysLeft: me.planState.daysRemainingAt(now),
                    renewsSoon: me.planState.renewsSoonAt(now),
                  ),
                  const SizedBox(height: 20),
                ],

                PlanCard(
                  title: 'Premium',
                  blurb: 'For players who want the whole record, not the '
                      'headline.',
                  payablePaise: payable,
                  listPricePaise: Pricing.premiumYearlyPaise,
                  period: 'per year',
                  highlighted: !isPremium,
                  globalMonthlyUsdCents: Pricing.memberMonthlyUsdCents,
                  features: const [
                    'Your full career history, every match, for life',
                    'Advanced performance analytics and form trends',
                    'Cross-sport rating index and detailed rankings',
                    'Head-to-head records against any opponent',
                    'A shareable sports portfolio for selectors and coaches',
                    'Every memory and certificate, in full resolution',
                    'No ads anywhere in the app',
                  ],
                  footnote: 'Billed once a year, not monthly — at ₹99 a year '
                      'a monthly charge would cost more to collect than it '
                      'is worth. Cancel any time; your record is yours '
                      'either way.',
                ),
                const SizedBox(height: 20),

                // The line that matters most on this screen, and the reason
                // it is stated rather than implied: a player deciding whether
                // to pay needs to know that not paying costs them nothing
                // they already have.
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sports_cricket_outlined,
                                size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Playing is always free',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Joining clubs, entering events, playing matches, '
                          'being scored and appearing in results never cost '
                          'anything and never will. Premium adds depth to the '
                          'record you already own — it does not unlock the '
                          'sport.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: _busy ? null : _subscribe,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(
                    _busy
                        ? 'Activating…'
                        : isPremium
                            ? 'Extend by another year'
                            : payable == 0
                                ? 'Proceed & activate Premium'
                                : 'Pay ${Pricing.formatPaise(payable)} a year',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  payable == 0
                      ? 'Nothing to pay today. No card is asked for and none '
                          'is stored.'
                      : 'You will be taken to a secure payment page.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 28),

                const _Receipts(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({
    required this.validUntil,
    required this.daysLeft,
    required this.renewsSoon,
  });

  final DateTime? validUntil;
  final int daysLeft;
  final bool renewsSoon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: renewsSoon
          ? theme.colorScheme.tertiaryContainer
          : theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(
          renewsSoon ? Icons.schedule : Icons.workspace_premium,
          color: renewsSoon
              ? theme.colorScheme.onTertiaryContainer
              : theme.colorScheme.onPrimaryContainer,
        ),
        title: Text(
          renewsSoon ? 'Premium ends soon' : 'Premium is active',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          validUntil == null
              ? '$daysLeft days left'
              : '$daysLeft days left — through '
                  '${DateFormat('d MMMM yyyy').format(validUntil!)}',
        ),
      ),
    );
  }
}

/// Every charge on this account, including the ₹0 ones.
///
/// Shown even while everything is free, because the ledger is real from day
/// one (see `PlanPayment`) and a person who activated Premium during the
/// launch offer should be able to point at the record of it — not least when
/// the price goes live and they want to know what they are being asked to
/// renew.
class _Receipts extends ConsumerWidget {
  const _Receipts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final payments = ref.watch(myPaymentsProvider).valueOrNull ?? const [];
    if (payments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your receipts', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final p in payments)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              switch (p.kind) {
                PlanPaymentKind.orgPlan => Icons.shield_outlined,
                PlanPaymentKind.memberPlan => Icons.workspace_premium_outlined,
                PlanPaymentKind.groundBooking => Icons.stadium_outlined,
                PlanPaymentKind.clubStore => Icons.storefront_outlined,
              },
              size: 20,
            ),
            title: Text(switch (p.kind) {
              PlanPaymentKind.orgPlan => 'Club plan',
              PlanPaymentKind.memberPlan => 'Premium membership',
              PlanPaymentKind.groundBooking => 'Ground booking',
              PlanPaymentKind.clubStore => 'Club store order',
            }),
            subtitle: Text(
              p.createdAt == null
                  ? 'Just now'
                  : DateFormat('d MMM yyyy').format(p.createdAt!),
            ),
            trailing: Text(
              p.isFree ? 'Free' : Pricing.formatPaise(p.amountPaise),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
