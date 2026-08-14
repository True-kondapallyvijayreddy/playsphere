import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/billing.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/plan_card.dart';
import '../../shared/real_payment_sheet.dart';

/// Which half of club creation is on screen.
///
/// Two steps rather than one long form, because the two halves are answered
/// by different parts of a person's brain and often by different people: the
/// coach knows the club's name and whether members need approving, and the
/// treasurer is the one who cares what it costs. Putting the price at the
/// bottom of a form is how it gets missed, and a club discovering a charge
/// after it has already named itself and set its rules is the worst possible
/// moment to introduce one.
enum _Step { details, plan }

class CreateOrgScreen extends ConsumerStatefulWidget {
  const CreateOrgScreen({super.key});

  @override
  ConsumerState<CreateOrgScreen> createState() => _CreateOrgScreenState();
}

class _CreateOrgScreenState extends ConsumerState<CreateOrgScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();

  OrgType _type = OrgType.school;
  OrgVisibility _visibility = OrgVisibility.public;
  bool _requireApproval = true;
  bool _busy = false;
  _Step _step = _Step.details;

  /// Always the paid tier at this point. The free tier exists for clubs whose
  /// plan has lapsed, not as something to choose at creation — offering it
  /// here would mean explaining a distinction that does not yet matter to
  /// somebody who has not run a single event.
  static const _plan = OrgPlan.club;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    super.dispose();
  }

  void _toPlanStep() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = _Step.plan);
  }

  Future<void> _create() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _busy = true);
    try {
      if (Pricing.introOfferActive) {
        await _createWithLaunchOfferGrant(user);
      } else {
        await _createFreeThenUpgrade(user);
      }
    } catch (e) {
      // Back to the plan step rather than the details form: the details are
      // fine, it was the purchase that failed, and dumping the person at the
      // top of a form they already filled in reads as having lost their work.
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Organization _draftOrg(AppUser user) => Organization(
        id: '',
        name: _name.text.trim(),
        orgType: _type,
        visibility: _visibility,
        ownerUid: user.uid,
        inviteCode: Organization.generateInviteCode(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        requiresApprovalToJoin: _requireApproval,
      );

  /// The launch-offer path, unchanged: charge (a no-op at ₹0) before
  /// creating, so a declined card — once cards are real — leaves no club, no
  /// membership and no invite code behind.
  Future<void> _createWithLaunchOfferGrant(AppUser user) async {
    final billing = ref.read(billingRepositoryProvider);
    final grant =
        await billing.purchasePlanForNewClub(payerUid: user.uid, plan: _plan);
    final orgId = await ref.read(orgRepositoryProvider).createOrganization(
          org: _draftOrg(user),
          founder: user,
          planGrant: grant,
        );
    if (mounted) context.pushReplacement(Routes.org(orgId));
  }

  /// The real-money path. "Charge first, create second" cannot hold here —
  /// there is no club to hand a plan to until *after* the club exists, and a
  /// Razorpay redirect confirms on its own schedule, not this call's. So the
  /// club is created immediately on [OrgPlan.free] (never a lockout — see
  /// `Organization.hasPaidPlanAt`), and payment is asked for as an upgrade
  /// against the club id that now exists. Declining the payment sheet leaves
  /// a real, working free club behind rather than nothing — the honest
  /// trade-off for a flow that can't collect the card before the thing being
  /// paid for exists.
  Future<void> _createFreeThenUpgrade(AppUser user) async {
    final orgId = await ref.read(orgRepositoryProvider).createOrganization(
          org: _draftOrg(user),
          founder: user,
        );
    if (!mounted) return;

    final pending = await ref.read(razorpayCheckoutProvider).start(
          kind: PlanPaymentKind.orgPlan,
          subjectId: orgId,
          planWire: _plan.wire,
        );
    if (!mounted) return;
    await showRealPaymentSheet(
      context,
      paymentId: pending.paymentId,
      url: pending.url,
    );
    if (mounted) context.pushReplacement(Routes.org(orgId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_step) {
          _Step.details => 'Create an organization',
          _Step.plan => 'Confirm and create',
        }),
        leading: _step == _Step.plan
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to details',
                onPressed:
                    _busy ? null : () => setState(() => _step = _Step.details),
              )
            : null,
      ),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 560,
          child: switch (_step) {
            _Step.details => _detailsForm(context),
            _Step.plan => _planStep(context),
          },
        ),
      ),
    );
  }

  Widget _detailsForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. St. Xavier\'s High School',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 3) ? 'At least 3 characters' : null,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<OrgType>(
            value: _type,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in OrgType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _city,
            decoration: const InputDecoration(
              labelText: 'City or district (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _visibility == OrgVisibility.public,
                  onChanged: (v) => setState(() => _visibility =
                      v ? OrgVisibility.public : OrgVisibility.unlisted),
                  title: const Text('Public'),
                  subtitle: const Text(
                    'Anyone can find this organization and follow its '
                    'live matches without an account. Turn this off and '
                    'only members can see anything.',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _requireApproval,
                  onChanged: (v) => setState(() => _requireApproval = v),
                  title: const Text('Approve new members'),
                  subtitle: const Text(
                    'Recommended for schools and colleges — people who '
                    'use the invite code wait for an admin before they '
                    'can enter competitions.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _toPlanStep,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
          const SizedBox(height: 12),
          Text(
            'One more step — the club plan.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _planStep(BuildContext context) {
    final theme = Theme.of(context);
    final payable = Pricing.orgPricePaise(_plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                _name.text.trim().isEmpty
                    ? '?'
                    : _name.text.trim().characters.first.toUpperCase(),
              ),
            ),
            title: Text(
              _name.text.trim(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              [_type.label, if (_city.text.trim().isNotEmpty) _city.text.trim()]
                  .join(' · '),
            ),
          ),
        ),
        const SizedBox(height: 20),

        const PlanCard(
          title: 'Club plan',
          blurb: 'Everything PlaySphere does, for the whole organization.',
          payablePaise: 0,
          listPricePaise: Pricing.clubYearlyPaise,
          period: 'per year',
          globalMonthlyUsdCents: Pricing.orgMonthlyUsdCents,
          features: [
            'Unlimited members — no per-player charge, ever',
            'Unlimited events, tournaments and seasons',
            'Live scoring across every sport, with offline support',
            'Draws, fixtures, standings, rankings and certificates',
            'Career records and ratings for every member',
            'Club feed, gallery, files and inter-club challenges',
          ],
          footnote:
              'Renews yearly. You can leave the plan at any time and the club '
              'keeps every match, result and record it has already made.',
        ),
        const SizedBox(height: 20),

        // The payment summary. Deliberately a real total line rather than a
        // "free" banner: this is the row that will one day carry ₹999 and a
        // card-entry sheet, and it should not change shape when it does.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Club plan · 1 year',
                  value: Pricing.formatPaise(Pricing.clubYearlyPaise),
                ),
                if (payable < Pricing.clubYearlyPaise)
                  _SummaryRow(
                    label: 'Launch offer',
                    value:
                        '− ${Pricing.formatPaise(Pricing.clubYearlyPaise - payable)}',
                    emphasis: theme.colorScheme.primary,
                  ),
                const Divider(height: 22),
                _SummaryRow(
                  label: 'Payable today',
                  value: payable == 0 ? '₹0' : Pricing.formatPaise(payable),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          child: Text(
            _busy
                ? 'Creating…'
                : payable == 0
                    ? 'Proceed & create club'
                    : 'Pay ${Pricing.formatPaise(payable)} & create club',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          payable == 0
              ? 'Nothing to pay today. No card is asked for and none is stored.'
              : 'You will be taken to a secure payment page.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.emphasis,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
        ?.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
      color: emphasis,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
