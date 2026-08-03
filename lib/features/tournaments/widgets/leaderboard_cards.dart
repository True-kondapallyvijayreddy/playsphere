import 'package:flutter/material.dart';

import '../../../domain/tournament/tournament_leaderboard.dart';

/// Every group across every event, on one screen.
///
/// The alternative is opening fifteen events one at a time to answer "how are
/// the groups doing", which is what an organizer actually wants to know
/// between rounds and what a parent wants before deciding whether to stay.
class GroupsSummaryCard extends StatelessWidget {
  const GroupsSummaryCard({super.key, required this.leaderboard});

  final TournamentLeaderboard? leaderboard;

  @override
  Widget build(BuildContext context) {
    final board = leaderboard;
    if (board == null || !board.hasGroups) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final live = board.liveGroups.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_rows_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Groups', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    live == 0
                        ? 'all decided'
                        : '$live still live',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: live == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final g in board.groups) _GroupRow(group: g),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = group;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 8,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: g.isComplete
                      ? theme.colorScheme.primary
                      : g.isDecided
                          ? theme.colorScheme.outlineVariant
                          : theme.colorScheme.tertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${g.eventName} · Group ${g.groupId}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  g.leader == null
                      ? 'Not started · ${g.total} matches'
                      : '${g.leader} leads on ${g.leaderPoints} '
                          '· ${g.played}/${g.total} played'
                          '${g.remaining > 0 ? '' : ' · final'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${g.qualifiers} qualify',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who has had the best tournament, across every event they entered.
///
/// No single points table can answer this — a player entered in singles,
/// doubles and mixed appears in three of them as three unrelated rows. It is
/// also the board that replaces a Telegram message, because it names people
/// rather than draws.
class LeaderboardCard extends StatelessWidget {
  const LeaderboardCard({super.key, required this.leaderboard});

  final TournamentLeaderboard? leaderboard;

  @override
  Widget build(BuildContext context) {
    final board = leaderboard;
    if (board == null || board.players.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final top = board.top();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.leaderboard_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Leaderboard', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Across every event. Walkovers are left out — turning up is '
                'not a good tournament.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 26),
                  Expanded(
                    child: Text('Player', style: theme.textTheme.labelSmall),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text('W',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text('L',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text('Win %',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (var i = 0; i < top.length; i++)
                _PlayerRow(rank: i + 1, record: top[i]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.rank, required this.record});

  final int rank;
  final PlayerRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    final rate = r.winRate;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: r.titles > 0
                ? Icon(Icons.emoji_events,
                    size: 16, color: theme.colorScheme.primary)
                : Text(
                    '$rank',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (r.eventsEntered > 1 || r.titles > 0 || r.finals > 0)
                  Text(
                    [
                      if (r.titles > 0)
                        '${r.titles} title${r.titles == 1 ? '' : 's'}',
                      if (r.finals > r.titles)
                        '${r.finals - r.titles} runner-up',
                      if (r.eventsEntered > 1)
                        '${r.eventsEntered} events',
                    ].join(' · '),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            child: Text('${r.won}',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 30,
            child: Text('${r.lost}',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall),
          ),
          SizedBox(
            width: 46,
            child: Text(
              // Blank below three matches rather than "100%": a player who won
              // their only match is not on a hundred per cent in any sense
              // worth printing.
              rate == null ? '—' : '${(rate * 100).round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
