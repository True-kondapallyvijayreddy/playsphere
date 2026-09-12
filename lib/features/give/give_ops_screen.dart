/// Where the Give network's data actually goes.
///
/// ## The gap this closes
///
/// A donor filled in `GiveDonateScreen` and the row landed as
/// [DonationStatus.submitted]. A club filled in `GiveRaiseNeedScreen` and the
/// row landed unverified — which, per `GiveRepository.watchVerifiedNeeds`,
/// means invisible to every donor in the country. Both were then stuck: the
/// nine-stage pipeline `DonationStatus` describes and the `verified` flag the
/// whole needs board hangs off were writable only by the `admin` claim, and no
/// screen in the product ever asked to write them. So "give" collected real
/// commitments from real people and put them somewhere nobody on the team
/// could see, act on, or even be told about.
///
/// This screen is the desk. `functions/index.js`'s `onGiveDonationSubmitted`
/// and `onGiveNeedRaised` page whoever is on the `give` desk of
/// `platformStaff`, so the queue is found without anybody deciding to look.
///
/// ## Why advancing a donation is one tap and not a form
///
/// The pipeline is walked by somebody standing at a collection point holding
/// a bag of kit, on a phone, usually one-handed. `DonationStatus.step` already
/// encodes the order, so the console offers the next stage as a button and
/// keeps the full ladder behind a menu for the cases that skip or branch —
/// which is what [DonationStatus.rejected] sharing a step with `cleaned` is
/// about.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/give_donation.dart';
import '../../core/models/give_need.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

/// Which half of the desk is open. A route parameter rather than screen state
/// so the ops hub can link straight at the needs queue — the two are separate
/// jobs done by different people on different days, and landing on donations
/// when you came to verify a need is a wasted tap every single time.
enum GiveOpsTab { donations, needs }

class GiveOpsScreen extends ConsumerStatefulWidget {
  const GiveOpsScreen({super.key, this.initialTab = GiveOpsTab.donations});

  final GiveOpsTab initialTab;

  @override
  ConsumerState<GiveOpsScreen> createState() => _GiveOpsScreenState();
}

class _GiveOpsScreenState extends ConsumerState<GiveOpsScreen> {
  late GiveOpsTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isPlatformAdminProvider);

    return AppScaffold(
      title: 'Give desk',
      subtitle: 'Donations arriving, needs to verify',
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AsyncErrorStrip(value: isAdmin, what: 'your access'),
        data: (admin) {
          if (!admin) {
            return const EmptyState(
              icon: Icons.lock_outline,
              title: 'PlaySphere staff only',
              message:
                  'This is where donations are moved through the pipeline and '
                  'raised needs are verified.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SegmentedButton<GiveOpsTab>(
                  segments: const [
                    ButtonSegment(
                      value: GiveOpsTab.donations,
                      label: Text('Donations'),
                      icon: Icon(Icons.inventory_2_outlined),
                    ),
                    ButtonSegment(
                      value: GiveOpsTab.needs,
                      label: Text('Needs'),
                      icon: Icon(Icons.fact_check_outlined),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              Expanded(
                child: _tab == GiveOpsTab.donations
                    ? const _DonationQueue()
                    : const _NeedQueue(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Donations
// ---------------------------------------------------------------------------

class _DonationQueue extends ConsumerStatefulWidget {
  const _DonationQueue();

  @override
  ConsumerState<_DonationQueue> createState() => _DonationQueueState();
}

class _DonationQueueState extends ConsumerState<_DonationQueue> {
  /// Null is "everything", and it is first because the desk's normal question
  /// is "what is in the building", not "what is at stage four".
  DonationStatus? _filter = DonationStatus.submitted;

  static const _filters = <DonationStatus?>[
    DonationStatus.submitted,
    DonationStatus.collected,
    DonationStatus.inspected,
    DonationStatus.graded,
    DonationStatus.packed,
    DonationStatus.assigned,
    null,
  ];

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(giveDonationQueueProvider(_filter));

    // Mounted here rather than inside each card. `_DonationCard._assign`
    // needs the verified-need list the instant somebody taps Assign, and a
    // `ref.read` of a provider no widget is watching answers null — which
    // would have shown "no verified need to assign this against" on a desk
    // with a board full of them. One listener for the whole tab.
    ref.watch(giveNeedQueueProvider(true));

    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(_filters[i]?.label ?? 'Everything'),
              selected: _filter == _filters[i],
              onSelected: (_) => setState(() => _filter = _filters[i]),
            ),
          ),
        ),
        Expanded(
          child: AsyncView(
            value: queue,
            onRetry: () => ref.invalidate(giveDonationQueueProvider(_filter)),
            skeleton: const PsListSkeleton(),
            builder: (rows) => rows.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_outlined,
                    title: _filter == null
                        ? 'No donations yet'
                        : 'Nothing at "${_filter!.label}"',
                    message: _filter == DonationStatus.submitted
                        ? 'Everything donors have offered has been picked up.'
                        : null,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      ContentBounds(
                        maxWidth: 760,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final d in rows) _DonationCard(donation: d),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _DonationCard extends ConsumerWidget {
  const _DonationCard({required this.donation});

  final GiveDonation donation;

  /// The stage the desk will almost always want next.
  ///
  /// Reads the ladder off [DonationStatus.step] rather than hard-coding a
  /// successor per stage, so adding a stage to the enum does not silently
  /// leave this returning the wrong one. Rejection is never suggested — it is
  /// a judgement, and offering it as the obvious next tap next to a bag of
  /// perfectly good boots would be wrong in both directions.
  DonationStatus? get _next {
    if (donation.status == DonationStatus.rejected ||
        donation.status == DonationStatus.distributed) {
      return null;
    }
    final ladder = DonationStatus.values
        .where((s) => s != DonationStatus.rejected)
        .toList()
      ..sort((a, b) => a.step.compareTo(b.step));
    final i = ladder.indexOf(donation.status);
    return i < 0 || i + 1 >= ladder.length ? null : ladder[i + 1];
  }

  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    DonationStatus to,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(giveRepositoryProvider)
          .advanceDonation(donation.id, to: to);
      messenger.showSnackBar(
        SnackBar(content: Text('Marked ${to.label.toLowerCase()}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _assign(BuildContext context, WidgetRef ref) async {
    final needs = ref.read(giveNeedQueueProvider(true)).valueOrNull ?? const [];
    if (needs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No verified need to assign this against yet'),
        ),
      );
      return;
    }
    final chosen = await showModalBottomSheet<GiveNeed>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NeedPickerSheet(needs: needs),
    );
    if (chosen == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(giveRepositoryProvider)
          .assignDonationToNeed(donation.id, needId: chosen.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Assigned to "${chosen.title}"')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final created = donation.createdAt;
    final isMoney = donation.type == GiveDonationType.money;
    final next = _next;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isMoney
                      ? Icons.currency_rupee
                      : Icons.inventory_2_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    donation.donorName ?? 'A donor',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(donation.status.label),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: donation.status.isTerminalRejection
                      ? theme.colorScheme.errorContainer
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                donation.city,
                if (created != null) DateFormat('d MMM').format(created),
              ].where((s) => s.isNotEmpty).join(' · '),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),

            const SizedBox(height: 8),
            if (isMoney)
              Text(
                // The rules deliberately never let a client claim money moved
                // — this is a lead to call back, and saying so on the card
                // keeps a volunteer from ticking it off as banked.
                'Pledged \u{20B9}${(donation.amountPaise / 100).round()} — '
                'a callback, not a payment received',
                style: theme.textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final line in donation.items)
                    Chip(
                      label: Text('${line.quantity} × ${line.category.label}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),

            for (final line in donation.items)
              if (line.note != null && line.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${line.category.label}: ${line.note}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),

            // The one field on this document a volunteer genuinely needs and
            // no public screen may ever show — see `firestore.rules` on
            // `giveDonations`, which is why the read is staff-or-donor only.
            if (donation.donorPhone != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16),
                  const SizedBox(width: 6),
                  SelectableText(
                    donation.donorPhone!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],

            if (donation.assignedNeedId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Assigned to a need',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),

            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (next != null)
                  FilledButton.icon(
                    onPressed: () => _advance(context, ref, next),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text('Mark ${next.label.toLowerCase()}'),
                  ),
                if (!isMoney && donation.assignedNeedId == null)
                  OutlinedButton.icon(
                    onPressed: () => _assign(context, ref),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Assign to a need'),
                  ),
                PopupMenuButton<DonationStatus>(
                  tooltip: 'Set any stage',
                  onSelected: (s) => _advance(context, ref, s),
                  itemBuilder: (_) => [
                    for (final s in DonationStatus.values)
                      if (s != donation.status)
                        PopupMenuItem(value: s, child: Text(s.label)),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz, size: 18),
                        SizedBox(width: 4),
                        Text('Other stage'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Picking which verified need a donation goes against.
class _NeedPickerSheet extends StatelessWidget {
  const _NeedPickerSheet({required this.needs});

  final List<GiveNeed> needs;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text(
              'Assign against',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          for (final n in needs)
            ListTile(
              title: Text(n.title),
              subtitle: Text(
                [
                  n.orgName ?? n.playerName ?? n.beneficiaryType.label,
                  if (n.city.isNotEmpty) n.city,
                  '${n.items.length} item${n.items.length == 1 ? '' : 's'} short',
                ].join(' · '),
              ),
              onTap: () => Navigator.pop(context, n),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Needs
// ---------------------------------------------------------------------------

class _NeedQueue extends ConsumerStatefulWidget {
  const _NeedQueue();

  @override
  ConsumerState<_NeedQueue> createState() => _NeedQueueState();
}

class _NeedQueueState extends ConsumerState<_NeedQueue> {
  /// Unverified first, deliberately: a need sitting here unverified is not
  /// merely un-triaged, it is invisible to every donor in the country. That
  /// is the queue with a cost attached to the waiting.
  bool? _verified = false;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(giveNeedQueueProvider(_verified));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('To verify'),
                selected: _verified == false,
                onSelected: (_) => setState(() => _verified = false),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Verified'),
                selected: _verified == true,
                onSelected: (_) => setState(() => _verified = true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('All'),
                selected: _verified == null,
                onSelected: (_) => setState(() => _verified = null),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(
            value: queue,
            onRetry: () => ref.invalidate(giveNeedQueueProvider(_verified)),
            skeleton: const PsListSkeleton(),
            builder: (rows) => rows.isEmpty
                ? EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: _verified == false
                        ? 'Nothing waiting to be verified'
                        : 'No needs here',
                    message: _verified == false
                        ? 'Every need a club has raised is on the public '
                            'board.'
                        : null,
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      ContentBounds(
                        maxWidth: 760,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final n in rows) _NeedCard(need: n),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _NeedCard extends ConsumerWidget {
  const _NeedCard({required this.need});

  final GiveNeed need;

  Future<void> _setVerified(
    BuildContext context,
    WidgetRef ref,
    bool verified,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(giveRepositoryProvider)
          .setNeedVerified(need.id, verified: verified);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            verified
                ? 'Verified — it is on the public board now'
                : 'Taken off the public board',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    GiveNeedStatus status,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(giveRepositoryProvider).setNeedStatus(need.id, status);
      messenger.showSnackBar(
        SnackBar(content: Text('Marked ${status.label.toLowerCase()}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final created = need.createdAt;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    need.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (need.verified)
                  Chip(
                    label: const Text('Verified'),
                    avatar: const Icon(Icons.verified, size: 16),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.primaryContainer,
                  )
                else
                  const Chip(
                    label: Text('Not on the board'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                need.orgName ?? need.playerName ?? need.beneficiaryType.label,
                if (need.city.isNotEmpty) need.city,
                if (need.playersCount != null) '${need.playersCount} players',
                if (created != null) DateFormat('d MMM').format(created),
              ].join(' · '),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            if (need.description != null && need.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(need.description!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final line in need.items)
                  Chip(
                    label: Text('${line.quantity} × ${line.category.label}'),
                    visualDensity: VisualDensity.compact,
                  ),
                for (final line in need.fulfilled)
                  Chip(
                    label: Text('${line.quantity} × ${line.category.label}'),
                    avatar: const Icon(Icons.check, size: 14),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!need.verified)
                  FilledButton.icon(
                    onPressed: () => _setVerified(context, ref, true),
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Verify and publish'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _setVerified(context, ref, false),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('Unpublish'),
                  ),
                PopupMenuButton<GiveNeedStatus>(
                  tooltip: 'Set status',
                  onSelected: (s) => _setStatus(context, ref, s),
                  itemBuilder: (_) => [
                    for (final s in GiveNeedStatus.values)
                      if (s != need.status)
                        PopupMenuItem(value: s, child: Text(s.label)),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz, size: 18),
                        SizedBox(width: 4),
                        Text('Status'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
