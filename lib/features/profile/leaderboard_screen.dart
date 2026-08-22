import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/career/leaderboard.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';

/// The app-wide "who leads in this stat" board — CricHeroes' and every top
/// tournament's "Orange Cap" pattern, reached by tapping a counter on a
/// player's own profile.
///
/// Read-only and world-facing: `functions/leaderboard.js` has already made
/// every eligibility decision (public visibility, not a minor) before this
/// screen ever sees a row, so there is nothing left to filter here — see
/// [LeaderboardRepository] for why that split keeps a client-side filter
/// from ever being the thing standing between a minor and the open internet.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({
    super.key,
    required this.sportId,
    required this.statKey,
    this.highlightUid,
  });

  final String sportId;
  final String statKey;

  /// The player whose stat tile linked here, if any — their row (if they've
  /// reached the top 50) is picked out the same way a tapped stat's own row
  /// is highlighted on `PlayerStatsScreen`.
  final String? highlightUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = LeaderboardKey(sportId: sportId, statKey: statKey);
    final board = ref.watch(leaderboardProvider(key));
    final sport = SportCatalog.byId(sportId);
    final statLabel = psHumanizeCounter(statKey);

    return Scaffold(
      appBar: AppBar(title: Text('${sport.name} · $statLabel')),
      body: AsyncView(
        value: board,
        onRetry: () => ref.invalidate(leaderboardProvider(key)),
        builder: (leaderboard) {
          if (leaderboard == null || leaderboard.isEmpty) {
            return EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'No leaderboard yet',
              message: 'Nobody with a public profile has a $statLabel '
                  'total in ${sport.name} yet — leaderboards rebuild '
                  'hourly as matches finish.',
            );
          }

          final onBoard = highlightUid == null
              ? null
              : leaderboard.entryFor(highlightUid!);
          final showsSelf = highlightUid != null && onBoard != null;

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (highlightUid != null && !showsSelf)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: PsCard(
                          child: Text(
                            'Not in the top ${Leaderboard.maxEntries} yet — '
                            'keep playing to climb.',
                            style: TextStyle(fontSize: 13, color: Ps.muted),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    for (final entry in leaderboard.entries)
                      _LeaderboardRow(
                        entry: entry,
                        isSelf: entry.uid == highlightUid,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.isSelf});

  final LeaderboardEntry entry;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: isSelf ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: _RankAvatar(
          rank: entry.rank,
          name: entry.displayName,
          imageUrl: entry.photoUrl,
          seed: entry.uid,
        ),
        title: Text(
          entry.displayName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: Text(
          _formatValue(entry.value),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        onTap: () => context.push(Routes.profile(entry.uid)),
      ),
    );
  }

  static String _formatValue(num v) => v is int || v == v.roundToDouble()
      ? psGrouped(v.round())
      : v.toStringAsFixed(2);
}

/// Rank number beside an avatar — same layout `RisingTalentScreen` uses for
/// its own boards, kept local rather than shared since the two screens have
/// no other code in common.
class _RankAvatar extends StatelessWidget {
  const _RankAvatar({
    required this.rank,
    required this.name,
    this.imageUrl,
    this.seed,
  });

  final int rank;
  final String name;
  final String? imageUrl;
  final String? seed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 56,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(width: 6),
          // Was a round mark with a generic person glyph behind it, so
          // every player without a photo was the same faceless silhouette.
          PsAvatar(name: name, photoUrl: imageUrl, seed: seed, size: 30),
        ],
      ),
    );
  }
}
