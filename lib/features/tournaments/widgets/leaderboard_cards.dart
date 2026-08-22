import 'package:flutter/material.dart';

import '../../../domain/scoring/scoring_registry.dart';
import '../../../domain/tournament/player_boards.dart';
import '../../../domain/tournament/tournament_leaderboard.dart';
import '../../../shared/ui_kit.dart';

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
                    live == 0 ? 'all decided' : '$live still live',
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
class LeaderboardCard extends StatefulWidget {
  const LeaderboardCard({
    super.key,
    required this.leaderboard,
    this.onTapEntrant,
  });

  final TournamentLeaderboard? leaderboard;

  /// Opens one competitor's season. Null on the public page, where there is
  /// no season-entrant route to land on and a row that looks pressable and
  /// is not would be worse than a row that does not.
  final void Function(PlayerRecord record)? onTapEntrant;

  @override
  State<LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<LeaderboardCard> {
  /// Null is "All sports" — the combined board, which is what the card
  /// opened on before the filter existed and what a single-sport season
  /// only ever shows.
  String? _sportId;

  @override
  Widget build(BuildContext context) {
    final board = widget.leaderboard;
    if (board == null || board.players.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // A sport that has since been detached from the season leaves a selection
    // pointing at a board that no longer exists; falling back to the combined
    // one is better than an empty table with a live-looking filter.
    final selected = board.bySport.containsKey(_sportId) ? _sportId : null;
    final top = board.topFor(selected);

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
                  const Spacer(),
                  // Only when there is genuinely a choice. A control with one
                  // option is a control that costs a read and answers nothing.
                  if (board.isMultiSport)
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selected,
                        isDense: true,
                        borderRadius: BorderRadius.circular(12),
                        style: theme.textTheme.bodySmall,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All sports'),
                          ),
                          for (final id in board.sportIds)
                            DropdownMenuItem<String?>(
                              value: id,
                              child: Text(board.sportNames[id] ?? id),
                            ),
                        ],
                        onChanged: (v) => setState(() => _sportId = v),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                selected == null
                    ? 'Across every event. Walkovers are left out — turning '
                        'up is not a good tournament.'
                    : '${board.sportNames[selected] ?? selected} only — '
                        'these are their matches in this sport, not their '
                        'season totals.',
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
                _PlayerRow(
                  rank: i + 1,
                  record: top[i],
                  onTap: widget.onTapEntrant == null
                      ? null
                      : () => widget.onTapEntrant!(top[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.rank,
    required this.record,
    this.onTap,
  });

  final int rank;
  final PlayerRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    final rate = r.winRate;

    return InkWell(
      onTap: onTap,
      child: Padding(
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
                        if (r.eventsEntered > 1) '${r.eventsEntered} events',
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
                  textAlign: TextAlign.end, style: theme.textTheme.bodySmall),
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
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

/// The per-player charts — a tournament's batting and bowling boards, and the
/// same thing for whatever counters a non-cricket engine happens to record.
///
/// ## Why the tabs are not "Batting / Bowling / Fielding"
///
/// Because that is a cricket answer and this runs for fifteen sports.
/// [PlayerBoards] discovers the counters the matches actually recorded, in
/// descending order of how many players have a figure for one, so football
/// draws Goals and Assists, kabaddi draws raid points, and cricket draws Runs
/// and Wickets — without any of them being named here. A sport added next year
/// gets its charts for free; a hard-coded tab list would have given it three
/// empty ones.
///
/// The computation has existed and been correct since §17 shipped. Nothing
/// rendered it, which is the only reason a tournament's charts were missing.
///
/// ## Sports
///
/// [bySport] is what a multi-sport season passes; a single-sport tournament
/// passes [boards] and gets no sport row at all. The row appears only when
/// there is genuinely more than one sport to choose between — a season that
/// happens to run one sport should not grow a control with a single option.
class PlayerBoardsCard extends StatefulWidget {
  /// Both null is the ordinary first build — the providers hand over
  /// `valueOrNull`, which is null until the fixture stream has ticked once.
  /// The card draws nothing in that state, which is what it should do before
  /// it knows whether there is anything to draw.
  const PlayerBoardsCard({super.key, this.boards, this.bySport});

  /// One set of charts, for a single-sport tournament.
  final PlayerBoards? boards;

  /// Charts per sport id, for a season that spans several.
  final Map<String, PlayerBoards>? bySport;

  @override
  State<PlayerBoardsCard> createState() => _PlayerBoardsCardState();
}

class _PlayerBoardsCardState extends State<PlayerBoardsCard> {
  int _selected = 0;
  int _sport = 0;

  @override
  Widget build(BuildContext context) {
    final sports = widget.bySport;
    final sportIds = sports == null ? const <String>[] : sports.keys.toList();
    // Clamped for the same reason the board index is: a sport's last match can
    // be un-verified between two builds and take its whole tab with it.
    final sportIndex =
        sportIds.isEmpty ? 0 : _sport.clamp(0, sportIds.length - 1);

    final boards = sports == null
        ? widget.boards
        : (sportIds.isEmpty ? null : sports[sportIds[sportIndex]]);

    // Nothing to draw is the normal state for a chess or a kabaddi draw whose
    // engine records no per-player counters, and for a tournament on its first
    // morning. An empty card explaining itself would be noise on both.
    if (boards == null || boards.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // A board can vanish between builds — a result is corrected, a counter
    // drops to zero — and a stale index would throw rather than degrade.
    final index = _selected.clamp(0, boards.boards.length - 1);
    final board = boards.boards[index];
    final top = board.entries.take(10).toList();

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
                  const Icon(Icons.insights_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Player charts', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Totals across every match in this tournament. Only finished, '
                'verified matches count.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              // Only when there is a genuine choice. One sport does not need a
              // control saying so.
              if (sportIds.length > 1) ...[
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < sportIds.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(SportCatalog.byId(sportIds[i]).name),
                            selected: i == sportIndex,
                            // The counter tabs belong to the sport that was
                            // showing, so switching sport starts again at its
                            // own leading chart rather than at whatever index
                            // the last sport happened to be on.
                            onSelected: (_) => setState(() {
                              _sport = i;
                              _selected = 0;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < boards.boards.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(psHumanizeCounter(boards.boards[i].key)),
                          selected: i == index,
                          onSelected: (_) => setState(() => _selected = i),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 26),
                  Expanded(
                    child: Text('Player', style: theme.textTheme.labelSmall),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text('M',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      psHumanizeCounter(board.key),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (var i = 0; i < top.length; i++)
                _BoardRow(rank: i + 1, entry: top[i]),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.rank, required this.entry});

  final int rank;
  final BoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: rank == 1
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
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                // A guest can top a tournament's run chart without ever having
                // installed the app. Saying so is more honest than leaving the
                // row looking like a profile that cannot be opened.
                if (entry.uid == null) ...[
                  const SizedBox(width: 6),
                  Text(
                    'guest',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 34,
            child: Text('${entry.matches}',
                textAlign: TextAlign.end, style: theme.textTheme.bodySmall),
          ),
          SizedBox(
            width: 56,
            child: Text(
              _format(entry.value),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Whole numbers stay whole; rates and averages keep two places — the same
  /// rule the stat breakdown formats by, so a figure reads identically on both.
  static String _format(num v) => v is int || v == v.roundToDouble()
      ? psGrouped(v.round())
      : v.toStringAsFixed(2);
}
