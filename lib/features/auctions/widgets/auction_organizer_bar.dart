import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/auction.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/ui_kit.dart';
import '../auction_providers.dart';

/// The organizer's controls, as ONE next action rather than a panel of them.
///
/// ## Why there is only ever one button
///
/// An auction moves through six states and each one has exactly one thing the
/// organizer is supposed to do next. A panel showing all six as peers — open
/// registration, open bidding, reveal, lock, cancel — is a panel where the
/// destructive one sits beside the routine one and the correct one is not
/// distinguishable from the five that are wrong right now.
///
/// So this shows the single legal next step, in the language of the thing it
/// does, with what it will cost stated underneath. Everything else lives
/// behind the overflow menu, where cancelling is a deliberate hunt rather
/// than a neighbour of Reveal.
class AuctionOrganizerBar extends ConsumerStatefulWidget {
  const AuctionOrganizerBar({super.key, required this.auction});

  final Auction auction;

  @override
  ConsumerState<AuctionOrganizerBar> createState() =>
      _AuctionOrganizerBarState();
}

class _AuctionOrganizerBarState extends ConsumerState<AuctionOrganizerBar> {
  bool _busy = false;

  Auction get _a => widget.auction;

  Future<void> _run(Future<void> Function() body, String success) async {
    setState(() => _busy = true);
    try {
      await body();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The bidding deadline, asked for at the moment it is actually knowable.
  ///
  /// Presets rather than a bare date picker, because "10 days" is how an
  /// organizer thinks about this and converting it to a date in their head is
  /// a step at which they will pick the wrong Tuesday. The custom option is
  /// there for the one who wants the reveal at 5pm on match eve.
  Future<DateTime?> _askDeadline() async {
    final now = DateTime.now();
    return showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'When do the bids open?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Every sealed bid opens at once at this moment and the highest '
                'offer on each player wins. Owners can change their bids '
                'freely until then.',
                style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              for (final option in const [
                (label: 'In 2 days', days: 2),
                (label: 'In 5 days', days: 5),
                (label: 'In 10 days', days: 10),
                (label: 'In 2 weeks', days: 14),
              ])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule, size: 20),
                  title: Text(option.label),
                  subtitle: Text(
                    _pretty(now.add(Duration(days: option.days))),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.of(sheet)
                      .pop(now.add(Duration(days: option.days))),
                ),
              const Divider(height: 20),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined, size: 20),
                title: const Text('Pick a date and time'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: sheet,
                    initialDate: now.add(const Duration(days: 5)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (date == null || !sheet.mounted) return;
                  final time = await showTimePicker(
                    context: sheet,
                    initialTime: const TimeOfDay(hour: 17, minute: 0),
                  );
                  if (!sheet.mounted) return;
                  Navigator.of(sheet).pop(DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time?.hour ?? 17,
                    time?.minute ?? 0,
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pretty(DateTime t) =>
      '${t.day}/${t.month}/${t.year}, ${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(auctionRepositoryProvider);
    final waiting = ref.watch(pendingAuctionJoinCountProvider(_a.id));

    final (String? label, String note, Future<void> Function()? action) =
        switch (_a.status) {
      AuctionStatus.draft => (
          'Publish it',
          'Nobody can see this auction or join it until you publish. Your '
              'code is ${_a.joinCode}.',
          () => repo.openRegistration(_a.id),
        ),
      AuctionStatus.registration => (
          'Open bidding',
          waiting > 0
              ? '$waiting ${waiting == 1 ? 'person is' : 'people are'} still '
                  'waiting for you to approve them. Approve everyone first — '
                  'nobody can be added once bidding opens.'
              : 'Set the closing time. Owners bid privately until then.',
          () async {
            final closes = await _askDeadline();
            if (closes == null) return;
            await repo.openBidding(auctionId: _a.id, closesAt: closes);
          },
        ),
      AuctionStatus.bidding => (
          'Reveal now',
          'Bids open automatically at the closing time. Use this only if '
              'everybody has finished early.',
          () => repo.revealNow(_a.id),
        ),
      AuctionStatus.revealed => (
          'Lock the squads',
          'Squads are final and no more swaps are possible. Do this when play '
              'starts.',
          () => repo.lockSquads(_a.id),
        ),
      AuctionStatus.locked => (null, 'Squads are final.', null),
      AuctionStatus.cancelled => (null, 'This auction was called off.', null),
    };

    return PsCard(
      color: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 16, color: Ps.muted),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'You run this auction',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Ps.muted,
                  ),
                ),
              ),
              PsOverflowMenu(
                actions: [
                  PsAction(
                    label: 'Settings',
                    icon: Icons.tune,
                    onSelected: () =>
                        context.push(Routes.auctionSettings(_a.id)),
                  ),
                  PsAction(
                    label: 'Approve people',
                    icon: Icons.how_to_reg,
                    onSelected: () => context.push(Routes.auctionPeople(_a.id)),
                  ),
                  // Only from `revealed`, and only when there is something to
                  // sell. `openAuctionBidding` re-checks both.
                  if (_a.status == AuctionStatus.revealed)
                    PsAction(
                      label: 'Another round for unsold players',
                      icon: Icons.replay,
                      onSelected: () async {
                        final closes = await _askDeadline();
                        if (closes == null) return;
                        await _run(
                          () => repo.openBidding(
                            auctionId: _a.id,
                            closesAt: closes,
                          ),
                          'Round ${_a.round + 1} is open.',
                        );
                      },
                    ),
                  if (_a.status == AuctionStatus.draft)
                    PsAction(
                      label: 'Delete this draft',
                      icon: Icons.delete_outline,
                      destructive: true,
                      onSelected: () async {
                        await _run(
                          () => repo.deleteDraft(_a.id, _a.joinCode),
                          'Draft deleted.',
                        );
                        if (context.mounted) context.pop();
                      },
                    )
                  else if (_a.status != AuctionStatus.cancelled)
                    PsAction(
                      label: 'Call it off',
                      icon: Icons.cancel_outlined,
                      destructive: true,
                      onSelected: () => _confirmCancel(repo),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: const TextStyle(
              fontSize: 12.5,
              color: Ps.muted,
              height: 1.4,
            ),
          ),
          if (label != null && action != null) ...[
            const SizedBox(height: 12),
            PsPrimaryButton(
              label: _busy ? 'Working…' : label,
              onPressed:
                  _busy ? null : () => _run(action, '$label — done.'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(dynamic repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Call off this auction?'),
        content: const Text(
          'Everybody who joined will see that it was called off. Squads and '
          'bids are kept as a record but nothing can move again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Call it off'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => repo.cancelAuction(_a.id), 'Auction called off.');
  }
}
