import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../domain/career/club_honours.dart';
import '../../../domain/career/club_record.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/ui_kit.dart';
import 'club_record_widgets.dart';

/// A club's record, sport by sport, behind the same tab strip a player's
/// profile uses for theirs.
///
/// This is `_SportBreakdown` from `career_profile_screen.dart` asked of a
/// club instead of a person, deliberately down to the control — see
/// [PsUnderlineTabs], which the two now share. A player who has learned to
/// read their own profile can read a club's without learning anything, and
/// that matters most for the reader this section exists for: somebody
/// deciding whether to join, who has seen their own numbers and wants to
/// know what this club's look like.
///
/// What a club gets that a player does not: an honours line (a player wins
/// matches, a club wins titles), and a top-players board — the club IS its
/// players, and "who would I be playing alongside" is the question a squad
/// list of names cannot answer but a scoring board can.
class ClubSportBreakdown extends StatefulWidget {
  const ClubSportBreakdown({
    super.key,
    required this.orgId,
    required this.record,
    required this.honours,
  });

  final String orgId;
  final ClubRecord record;
  final ClubHonours honours;

  @override
  State<ClubSportBreakdown> createState() => _ClubSportBreakdownState();
}

class _ClubSportBreakdownState extends State<ClubSportBreakdown> {
  /// The sport showing, held as an id rather than an index so it survives the
  /// strip reordering underneath when a finished match changes what this club
  /// plays most — the same reason the profile's version holds an id.
  String? _selected;

  /// Six counters, then stop. A full cricket tally runs to a dozen, and a
  /// club page that opens with twelve tiles is a spreadsheet. The sport's own
  /// page carries every one of them.
  static const _maxTiles = 6;

  /// Three players on the home page. The full board is one tap away.
  static const _topPlayers = 3;

  @override
  Widget build(BuildContext context) {
    final sports = widget.record.sports;
    if (sports.isEmpty) return const SizedBox.shrink();

    final selected = sports.firstWhere(
      (s) => s.sportId == _selected,
      orElse: () => sports.first,
    );
    final sportName = SportCatalog.byId(selected.sportId).name;

    final counters = selected.tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final tiles = counters.take(_maxTiles).toList();
    final leaders = selected.topPlayers(_topPlayers);
    final titles = widget.honours.forSport(selected.sportId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsUnderlineTabs(
          labels: [
            for (final s in sports) SportCatalog.byId(s.sportId).name,
          ],
          selected: sports.indexOf(selected),
          onSelected: (i) => setState(() => _selected = sports[i].sportId),
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClubRecordStats.ofSport(selected),
              if (selected.decided > 0) ...[
                const SizedBox(height: 12),
                ClubFormBar(
                  won: selected.won,
                  lost: selected.lost,
                  drawn: selected.drawn,
                ),
              ],
              if (titles.isNotEmpty || selected.mvps > 0) ...[
                const SizedBox(height: 12),
                _AchievementLine(
                  titles: titles.length,
                  mvps: selected.mvps,
                  sportName: sportName,
                ),
              ],
            ],
          ),
        ),
        if (tiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              // Three across on a phone, more where there is room — the same
              // sizing the profile's grid uses, so the two pages line up when
              // somebody flips between them.
              final columns = (constraints.maxWidth / 130).floor().clamp(2, 4);
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.75,
                children: [
                  for (final tile in tiles)
                    PsCounterTile(
                      label: tile.key,
                      value: tile.value,
                      onTap: () => context.push(
                        Routes.clubSportStats(widget.orgId, selected.sportId),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        if (leaders.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClubTopPlayers(
            record: selected,
            limit: _topPlayers,
            title: 'Top $sportName players',
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push(
              Routes.clubSportStats(widget.orgId, selected.sportId),
            ),
            icon: const Icon(Icons.query_stats, size: 18),
            label: Text('Full $sportName record, board and matches'),
          ),
        ),
      ],
    );
  }
}

/// "2 titles · 14 player-of-the-match awards" — the line that makes a record
/// read as a club's rather than a database's.
///
/// Rendered only when there is something in it. A zero next to the word
/// "titles" is not a boast, and a club that has not won one yet is better
/// served by the line simply not being there.
class _AchievementLine extends StatelessWidget {
  const _AchievementLine({
    required this.titles,
    required this.mvps,
    required this.sportName,
  });

  final int titles;
  final int mvps;
  final String sportName;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (titles > 0)
        '${psGrouped(titles)} ${titles == 1 ? 'title' : 'titles'}',
      if (mvps > 0)
        '${psGrouped(mvps)} player-of-the-match '
            '${mvps == 1 ? 'award' : 'awards'}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        const Icon(Icons.emoji_events_outlined, size: 15, color: Ps.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Ps.ink,
            ),
          ),
        ),
      ],
    );
  }
}
