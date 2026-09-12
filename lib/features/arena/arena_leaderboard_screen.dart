import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/arena_stats.dart';
import '../../core/providers.dart';
import '../../domain/arena/arena_game.dart';
import '../../domain/arena/arena_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import 'arena_providers.dart';

/// The Arena ladder.
///
/// Wins, draws and losses, and nothing else. It is stated at the top of the
/// screen that this is not a rating and does not touch anybody's Glicko,
/// career record or club standing — because a table of names in a sports app
/// looks exactly like a ranking, and this one is not one.
class ArenaLeaderboardScreen extends ConsumerStatefulWidget {
  const ArenaLeaderboardScreen({super.key});

  @override
  ConsumerState<ArenaLeaderboardScreen> createState() =>
      _ArenaLeaderboardScreenState();
}

class _ArenaLeaderboardScreenState
    extends ConsumerState<ArenaLeaderboardScreen> {
  /// Null is "every game".
  String? _gameId;

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final rows = ref.watch(arenaLeaderboardProvider);
    final mine = ref.watch(myArenaStatsProvider).valueOrNull;

    return AppScaffold(
      title: 'Arena ladder',
      subtitle: 'Just for the fun of it',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const _NotARatingNote(),
          _GameFilter(
            selected: _gameId,
            onPick: (id) => setState(() => _gameId = id),
          ),
          if (mine != null) _YourRecord(stats: mine, gameId: _gameId),
          rows.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: PsListSkeleton(),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The ladder could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Ps.muted),
              ),
            ),
            data: (all) {
              // Re-sorted here rather than in the query: ordering on
              // `byGame.<id>.won` would need one composite index per game to
              // reorder a list this screen already holds. See
              // `Refs.arenaLeaderboard`.
              final ranked = all
                  .where((s) => !s.recordFor(_gameId).isEmpty)
                  .toList()
                ..sort((a, b) {
                  final ra = a.recordFor(_gameId);
                  final rb = b.recordFor(_gameId);
                  final byWins = rb.won.compareTo(ra.won);
                  if (byWins != 0) return byWins;
                  return rb.played.compareTo(ra.played);
                });

              if (ranked.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: Text(
                    'Nobody has finished a game here yet. Play one and this '
                    'fills up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Ps.muted),
                  ),
                );
              }

              return Column(
                children: [
                  for (var i = 0; i < ranked.length; i++)
                    _LadderRow(
                      place: i + 1,
                      stats: ranked[i],
                      record: ranked[i].recordFor(_gameId),
                      isYou: ranked[i].uid == uid,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotARatingNote extends StatelessWidget {
  const _NotARatingNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.emoji_events_outlined, size: 20, color: Ps.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'A tally of Arena games and nothing more. It does not affect '
              'your Glicko, your career record or your club standings, and it '
              'is not a measure of how well you play — it is a scoreboard '
              'between friends.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: Ps.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameFilter extends StatelessWidget {
  const _GameFilter({required this.selected, required this.onPick});

  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? id) {
      final active = id == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: active,
          onSelected: (_) => onPick(id),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : Ps.ink,
          ),
          selectedColor: Ps.primary,
          backgroundColor: Ps.surface,
          side: BorderSide(color: active ? Ps.primary : Ps.border),
          showCheckmark: false,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      child: Row(
        children: [
          chip('All games', null),
          for (final game in ArenaGames.all) chip(game.name, game.id),
        ],
      ),
    );
  }
}

class _YourRecord extends StatelessWidget {
  const _YourRecord({required this.stats, required this.gameId});

  final ArenaStats stats;
  final String? gameId;

  @override
  Widget build(BuildContext context) {
    final record = stats.recordFor(gameId);
    final ArenaGame? game =
        gameId == null ? null : ArenaGames.byId(gameId);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ps.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game == null ? 'Your record' : 'Your ${game.name} record',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.isEmpty
                      ? 'No finished games yet.'
                      : '${record.played} played · ${record.summary}',
                  style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                ),
              ],
            ),
          ),
          if (!record.isEmpty)
            Text(
              '${record.score.round()}%',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Ps.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.place,
    required this.stats,
    required this.record,
    required this.isYou,
  });

  final int place;
  final ArenaStats stats;
  final ArenaGameRecord record;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(
          color: isYou ? Ps.primary.withValues(alpha: 0.5) : Ps.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$place',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: place <= 3 ? Ps.primary : Ps.faint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          PsAvatar(
            name: stats.displayName,
            photoUrl: stats.photoUrl,
            seed: stats.uid,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isYou ? '${stats.displayName} (you)' : stats.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${record.played} played · ${record.summary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                ),
              ],
            ),
          ),
          Text(
            '${record.won}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Ps.ink,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 3, top: 4),
            child: Text('W', style: TextStyle(fontSize: 10, color: Ps.faint)),
          ),
        ],
      ),
    );
  }
}
