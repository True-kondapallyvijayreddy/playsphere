import 'package:flutter/material.dart';

import '../../../core/models/fixture.dart';
import '../../../domain/scoring/player_stats.dart';
import '../../../domain/scoring/plugins/cricket_plugin.dart';
import '../../../domain/scoring/plugins/cricket_scorecard.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../domain/scoring/scoring_registry.dart';

/// The scorecard — who did what, rather than only what the score is.
///
/// Twelve of the seventeen engines have always computed a [BoxScore], and
/// cricket has always built a full [InningsCard] with batting, bowling and
/// falls of wicket. Nothing rendered any of it: the scoring pad and the
/// spectator screen showed a headline, a status line and a summary string, so
/// the per-player statistics that every career profile is built from were
/// invisible in the one place people actually look for them — during and just
/// after the match.
///
/// This deliberately consumes the domain types as they already are. There is
/// no view model: a [BoxScore] already knows its columns, how to format each
/// one and which of them are derived, so the table renders whatever a plugin
/// declares without knowing anything about the sport.
class MatchScorecard extends StatefulWidget {
  const MatchScorecard({super.key, required this.fixture});

  final Fixture fixture;

  /// Below this, two cards side by side are two unreadable columns rather than
  /// a comparison. A phone gets the switcher; a tablet, a desktop and the
  /// public live page get both at once.
  static const double sideBySideMinWidth = 720;

  @override
  State<MatchScorecard> createState() => _MatchScorecardState();
}

/// One side's card, with the label the switcher shows for it.
class _CardSection {
  const _CardSection({
    required this.label,
    required this.child,
    required this.isActive,
  });

  final String label;
  final Widget child;

  /// Whether this is the side currently batting/serving. Drives which tab the
  /// switcher opens on during a live match.
  final bool isActive;
}

class _MatchScorecardState extends State<MatchScorecard> {
  /// Which card the narrow layout is showing, once the viewer has chosen.
  ///
  /// Null means "follow the match" — the batting side, recomputed every build.
  /// A tap pins it, because a spectator who has deliberately opened the other
  /// team's card should not have it yanked away at the innings break.
  int? _pinned;

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final ctx = fixture.scoringContext();
    final theme = Theme.of(context);

    final sections = <_CardSection>[];

    // Cricket first: its card is structurally unlike every other sport's —
    // two disciplines, a batting order, an innings — and flattening it into a
    // generic table would lose the thing a cricketer opens a scorecard for.
    if (plugin is CricketPlugin) {
      final cards = plugin.allCards(fixture.scoreState, ctx);
      for (var i = 0; i < cards.length; i++) {
        final card = cards[i];
        sections.add(
          _CardSection(
            label: ctx.nameFor(card.battingSide),
            // The LAST innings is the one being played. Cricket's sides are
            // innings rather than teams, so "who is batting" is positional.
            isActive: i == cards.length - 1,
            child: InningsCardView(
              card: card,
              teamName: ctx.nameFor(card.battingSide),
            ),
          ),
        );
      }
    } else {
      for (final side in const [Side.a, Side.b]) {
        final box = plugin.boxScore(fixture.scoreState, ctx, side);
        if (box == null || box.appeared.isEmpty) continue;
        sections.add(
          _CardSection(
            label: box.teamName,
            // Every other sport's two cards are both live for the whole match
            // — there is no "batting side" in badminton — so neither is
            // singled out and the switcher opens on the first.
            isActive: false,
            child: BoxScoreTable(boxScore: box),
          ),
        );
      }
    }

    // Nothing to show is the normal state before the first ball, and an empty
    // "Scorecard" heading over an empty card reads as a fault.
    if (sections.isEmpty) return const SizedBox.shrink();

    final header = Text('Scorecard', style: theme.textTheme.titleMedium);

    // One card needs neither a switcher nor a second column — a first innings
    // in progress, or a sport that only produced one box score.
    if (sections.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const SizedBox(height: 8), sections.first.child],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= MatchScorecard.sideBySideMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: sections[i].child),
                  ],
                ],
              ),
            ],
          );
        }

        // Narrow: one at a time, opening on whoever is batting.
        final activeIndex = sections.indexWhere((s) => s.isActive);
        final shown = _pinned ?? (activeIndex >= 0 ? activeIndex : 0);
        final index = shown.clamp(0, sections.length - 1);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < sections.length; i++)
                    ButtonSegment(
                      value: i,
                      label: Text(sections[i].label),
                      icon: sections[i].isActive
                          ? const Icon(Icons.sports_cricket, size: 14)
                          : null,
                    ),
                ],
                selected: {index},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _pinned = s.first),
              ),
            ),
            const SizedBox(height: 8),
            sections[index].child,
          ],
        );
      },
    );
  }
}

/// One side's per-player statistics, as the sport's own engine declared them.
///
/// The column set comes from the plugin, so football renders goals and assists
/// and kabaddi renders raid and tackle points through exactly this widget.
class BoxScoreTable extends StatelessWidget {
  const BoxScoreTable({super.key, required this.boxScore});

  final BoxScore boxScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = boxScore.appeared;
    final absent = boxScore.players.where((p) => !p.appeared).toList();
    final totals = boxScore.teamTotals;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(boxScore.teamName, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // A box score can carry a dozen columns and this has to survive a
            // 320dp phone, so the table scrolls inside the card rather than
            // overflowing the page.
            _HorizontalTable(
              child: DataTable(
                headingRowHeight: 34,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 40,
                columnSpacing: 18,
                columns: [
                  const DataColumn(label: Text('Player')),
                  for (final c in boxScore.columns)
                    DataColumn(
                      label: Tooltip(
                        message: c.label,
                        child: Text(c.shortLabel),
                      ),
                      numeric: true,
                    ),
                ],
                rows: [
                  for (final p in players)
                    DataRow(
                      cells: [
                        DataCell(Text(p.name)),
                        for (final c in boxScore.columns)
                          DataCell(
                            Text(
                              c.format(p.tally),
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (players.isNotEmpty)
                    DataRow(
                      cells: [
                        DataCell(
                          Text('Total', style: theme.textTheme.labelLarge),
                        ),
                        for (final c in boxScore.columns)
                          DataCell(
                            Text(
                              // Derived columns are recomputed from the summed
                              // tally, never averaged from the rows: a team
                              // shooting percentage is total made over total
                              // attempted, and averaging player percentages
                              // silently weights a one-shot substitute the same
                              // as a starter.
                              c.format(totals),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (absent.isNotEmpty) ...[
              const SizedBox(height: 6),
              // Named but unused players read as a row of zeroes otherwise,
              // which says "contributed nothing" rather than "did not play".
              Text(
                'Did not play: ${absent.map((p) => p.name).join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full cricket innings, in the shape a cricketer expects to read it.
class InningsCardView extends StatelessWidget {
  const InningsCardView({
    super.key,
    required this.card,
    required this.teamName,
  });

  final InningsCard card;
  final String teamName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batted = card.batting.where((b) => b.battedYet).toList();
    final didNotBat = card.batting.where((b) => !b.battedYet).toList();
    final bowled = card.bowling.where((b) => b.legalBalls > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(teamName, style: theme.textTheme.titleSmall),
                ),
                Text(
                  card.headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Text(
              'Run rate ${card.runRate.toStringAsFixed(2)}'
              '${card.isClosed ? '' : ' · in progress'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),

            if (batted.isNotEmpty)
              _HorizontalTable(
                child: DataTable(
                  headingRowHeight: 34,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 44,
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Batter')),
                    DataColumn(label: Text('R'), numeric: true),
                    DataColumn(label: Text('B'), numeric: true),
                    DataColumn(label: Text('4s'), numeric: true),
                    DataColumn(label: Text('6s'), numeric: true),
                    DataColumn(label: Text('SR'), numeric: true),
                  ],
                  rows: [
                    for (final b in batted)
                      DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(b.isNotOut ? '${b.name} *' : b.name),
                                if (b.dismissal != null)
                                  Text(
                                    b.dismissal!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          DataCell(Text('${b.runs}')),
                          DataCell(Text('${b.balls}')),
                          DataCell(Text('${b.fours}')),
                          DataCell(Text('${b.sixes}')),
                          DataCell(Text(b.strikeRate.toStringAsFixed(1))),
                        ],
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 6),
            Text(
              'Extras ${card.extrasTotal}'
              '${_extrasBreakdown(card.extras)}',
              style: theme.textTheme.bodySmall,
            ),
            if (didNotBat.isNotEmpty)
              Text(
                'Did not bat: ${didNotBat.map((b) => b.name).join(', ')}',
                style: theme.textTheme.bodySmall,
              ),

            if (bowled.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Bowling', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              _HorizontalTable(
                child: DataTable(
                  headingRowHeight: 34,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 40,
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Bowler')),
                    DataColumn(label: Text('O'), numeric: true),
                    DataColumn(label: Text('M'), numeric: true),
                    DataColumn(label: Text('R'), numeric: true),
                    DataColumn(label: Text('W'), numeric: true),
                    DataColumn(label: Text('Econ'), numeric: true),
                  ],
                  rows: [
                    for (final b in bowled)
                      DataRow(
                        cells: [
                          DataCell(Text(b.name)),
                          DataCell(Text(b.oversText)),
                          DataCell(Text('${b.maidens}')),
                          DataCell(Text('${b.runsConceded}')),
                          DataCell(Text('${b.wickets}')),
                          DataCell(Text(b.economy.toStringAsFixed(2))),
                        ],
                      ),
                  ],
                ),
              ),
            ],

            if (card.fallOfWickets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Fall of wickets', style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                [
                  for (final f in card.fallOfWickets)
                    '${f.wicketNumber}-${f.runs} (${f.name}, ${f.oversText})',
                ].join('   '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// " (b 4, lb 2, w 5)" — omitted entirely when every extra is zero, because
  /// a row of zeroes is noise on a card people read at a glance.
  static String _extrasBreakdown(Map<String, int> extras) {
    const labels = {
      'bye': 'b',
      'legBye': 'lb',
      'wide': 'w',
      'noBall': 'nb',
    };
    final parts = [
      for (final e in extras.entries)
        if (e.value > 0) '${labels[e.key] ?? e.key} ${e.value}',
    ];
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }
}

/// Wraps a wide table so it scrolls sideways inside its card instead of
/// overflowing a phone.
class _HorizontalTable extends StatelessWidget {
  const _HorizontalTable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );
  }
}
