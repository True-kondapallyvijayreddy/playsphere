import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../core/providers.dart';
import '../../../domain/cheer.dart';

/// Lets whoever is watching make a noise for one of the two sides.
///
/// ## Why it is under the scoreboard and not beside it
///
/// The people this exists for are not at the ground. A parent at work, a
/// clubmate on a bus, a cousin in another city — they open a live link, see a
/// score, and have no way to be present. The score already tells them what is
/// happening; this is the part that tells the players somebody is there.
///
/// One cheer per person, addressed to a side. Tapping again takes it back and
/// tapping a different one changes it, so the tally counts PEOPLE rather than
/// taps — a number anyone can inflate by holding a button is not support, it
/// is a game, and it would make the honest number meaningless.
///
/// Hidden once the match has a result. Cheering a finished match is shouting
/// at a photograph, and leaving the control there invites a tally that keeps
/// climbing days after everyone has gone home — the same staleness that made
/// the LIVE badge worthless.
class CheerBar extends ConsumerWidget {
  const CheerBar({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!fixture.isLiveAt(DateTime.now())) return const SizedBox.shrink();

    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SizedBox.shrink();

    final tally = ref
            .watch(cheersProvider(FixtureRef(
              fixture.orgId,
              fixture.compId,
              fixture.id,
            )))
            .valueOrNull ??
        const CheerTally();

    final theme = Theme.of(context);

    Future<void> send(Cheer cheer, String side) async {
      // Tapping the reaction you already sent, to the side you already sent it
      // to, takes it back.
      final withdrawing = tally.mine == cheer && tally.mineSide == side;
      unawaited(HapticFeedback.selectionClick());
      try {
        await ref.read(scoringServiceProvider).sendCheer(
              orgId: fixture.orgId,
              compId: fixture.compId,
              fixtureId: fixture.id,
              uid: uid,
              cheer: withdrawing ? null : cheer,
              side: side,
            );
      } catch (_) {
        // Swallowed on purpose. A cheer that did not send is not worth an
        // error dialog in front of somebody watching a match, and the next tap
        // will try again.
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Cheer them on', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (tally.total > 0)
                  Text(
                    '${tally.total} '
                    '${tally.total == 1 ? 'person' : 'people'} cheering',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _SideRow(
              name: fixture.entrantAName,
              side: 'a',
              counts: tally.forA,
              total: tally.totalA,
              mine: tally.mineSide == 'a' ? tally.mine : null,
              onCheer: send,
            ),
            const SizedBox(height: 8),
            _SideRow(
              name: fixture.entrantBName,
              side: 'b',
              counts: tally.forB,
              total: tally.totalB,
              mine: tally.mineSide == 'b' ? tally.mine : null,
              onCheer: send,
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.name,
    required this.side,
    required this.counts,
    required this.total,
    required this.mine,
    required this.onCheer,
  });

  final String name;
  final String side;
  final Map<Cheer, int> counts;
  final int total;
  final Cheer? mine;
  final Future<void> Function(Cheer, String) onCheer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (total > 0)
              Text('$total', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in Cheer.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _CheerChip(
                    cheer: c,
                    count: counts[c] ?? 0,
                    selected: mine == c,
                    onTap: () => onCheer(c, side),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheerChip extends StatelessWidget {
  const _CheerChip({
    required this.cheer,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final Cheer cheer;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      // The words matter as much as the emoji: an emoji-only control is
      // unusable to anyone reading with a screen reader.
      message: cheer.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Semantics(
          button: true,
          selected: selected,
          label: '${cheer.label}, $count',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(cheer.emoji, style: const TextStyle(fontSize: 16)),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text('$count', style: theme.textTheme.labelSmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
