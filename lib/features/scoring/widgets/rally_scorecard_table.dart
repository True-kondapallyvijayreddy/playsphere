import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../core/providers.dart';
import '../../../domain/scoring/rally_timeline.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/ui_kit.dart';
import 'duel_pad.dart';

/// The set-by-set card under a racket pad: points won, and how they were won.
///
/// ## Why serve and receive, and not more
///
/// A racket scorecard traditionally carries five columns — points, service
/// points, receive points, aces and unforced errors — and this one carries
/// three, deliberately. Points and the serve split are FACTS THIS APP HAS: the
/// engine knows who was serving before every rally, because the laws of the
/// sport say so and the engine implements them, so the split is derived rather
/// than entered and cannot be wrong unless the score is wrong.
///
/// Aces and errors are not. Nothing on the pad distinguishes an ace from a
/// rally won on the fifteenth shot — one tap enters both — so the two columns
/// could only ever be zeroes wearing a heading. A column of zeroes on a
/// scorecard is worse than a missing column: the missing one asks a question,
/// and the zeroes answer it wrongly. They arrive when the pad captures them,
/// and the pad will capture them when a scorer is asked to spend a second tap
/// on it — which is a decision about somebody's match day, not about a table.
class RallyScorecardTable extends ConsumerWidget {
  const RallyScorecardTable({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    if (plugin is! RallyTimeline) return const SizedBox.shrink();

    final ctx = fixture.scoringContext();
    final events = ref
        .watch(matchTimelineProvider(
          FixtureRef(fixture.orgId, fixture.compId, fixture.id),
        ))
        .valueOrNull;
    if (events == null || events.isEmpty) return const SizedBox.shrink();

    final card = plugin.rallyScorecard(events, ctx);
    // Null where the sport does not track serve, or where the log is
    // windowed too far to replay. Both are "we cannot say", and a card that
    // cannot say anything should not be on the screen taking up the space
    // where the point log is.
    if (card == null || card.periods.isEmpty) return const SizedBox.shrink();

    return PsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 17, color: Ps.muted),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Scorecard',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Ps.ink,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                'by ${card.periodNoun.toLowerCase()}',
                style: const TextStyle(fontSize: 11, color: Ps.faint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Table(card: card, ctx: ctx),
          const SizedBox(height: 8),
          const Text(
            'PTS points won · SRV won while serving · RCV won while receiving',
            style: TextStyle(fontSize: 10.5, color: Ps.faint),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.card, required this.ctx});

  final RallyScorecard card;
  final ScoringContext ctx;

  @override
  Widget build(BuildContext context) {
    const headStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
      color: Ps.faint,
    );

    Widget cell(String text, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: color ?? Ps.ink,
            ),
          ),
        );

    TableRow row(
      String label,
      List<int> a,
      List<int> b, {
      bool strong = false,
    }) =>
        TableRow(
          decoration: strong
              ? const BoxDecoration(
                  border: Border(top: BorderSide(color: Ps.border)),
                )
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: Ps.muted,
                ),
              ),
            ),
            for (final v in a)
              cell('$v', strong: strong, color: DuelPad.accentFor(Side.a)),
            for (final v in b)
              cell('$v', strong: strong, color: DuelPad.accentFor(Side.b)),
          ],
        );

    final shareA = card.serveShareA();
    final shareB = card.serveShareB();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Both sides' names sit above their own three columns, because a
        // header of PTS SRV RCV PTS SRV RCV with nothing above it is a table
        // nobody can read the second half of.
        Row(
          children: [
            const SizedBox(width: 52),
            Expanded(
              child: Text(
                ctx.entrantAName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: DuelPad.accentFor(Side.a),
                ),
              ),
            ),
            Expanded(
              child: Text(
                ctx.entrantBName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: DuelPad.accentFor(Side.b),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {0: FixedColumnWidth(52)},
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                for (final h in ['PTS', 'SRV', 'RCV', 'PTS', 'SRV', 'RCV'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(h, textAlign: TextAlign.center, style: headStyle),
                  ),
              ],
            ),
            for (final (i, p) in card.periods.indexed)
              row(
                '${card.periodNoun} ${i + 1}',
                [p.pointsA, p.serveWonA, p.receiveWonA],
                [p.pointsB, p.serveWonB, p.receiveWonB],
              ),
            row(
              'Total',
              [card.totalA, card.serveWonA, card.totalA - card.serveWonA],
              [card.totalB, card.serveWonB, card.totalB - card.serveWonB],
              strong: true,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(
              width: 52,
              child: Text(
                'On serve',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Ps.muted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                _pct(shareA),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: DuelPad.accentFor(Side.a),
                ),
              ),
            ),
            Expanded(
              child: Text(
                _pct(shareB),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: DuelPad.accentFor(Side.b),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// An em dash for a side that has not scored. See [RallyScorecard.serveShareA].
  static String _pct(double? share) =>
      share == null ? '—' : '${(share * 100).round()}%';
}
