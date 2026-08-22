import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/fixture.dart';
import '../../../core/providers.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/ui_kit.dart';
import 'duel_pad.dart';

/// The running record of everything the scorer entered, newest first.
///
/// ## Why a scoreboard is not enough
///
/// A scoreboard says what the score is. It cannot say how it got there, and
/// "how it got there" is the entire content of every argument that happens
/// beside a court: a point given to the wrong side three rallies ago, a set
/// that ended at 21-19 when one player is certain it was 21-20, a serve nobody
/// agrees on. Before this the answer to all of them was the scorer's memory.
///
/// So every entry is here, in order, with the time it was entered and the
/// score it produced. A disputed point is now a thing you scroll to.
///
/// ## Why withdrawn entries stay
///
/// A point that was undone is drawn struck through rather than removed. The
/// event log is append-only for exactly this reason — a mistake and its
/// correction are both part of the record — and quietly deleting the row would
/// hand back the one thing that design was protecting: the ability to show
/// somebody what was entered AND that it was taken back. A timeline that
/// silently rewrites itself is not evidence of anything.
///
/// ## Why the sport writes the lines
///
/// Every line comes from `plugin.timeline` — see [MatchEventLine]. This widget
/// knows about rows, colours and times, and nothing whatsoever about points,
/// sets, wickets or goals.
class PointLog extends ConsumerStatefulWidget {
  const PointLog({
    super.key,
    required this.fixture,
    this.initiallyShown = 8,
  });

  final Fixture fixture;

  /// How many rows before the "show everything" fold.
  ///
  /// Eight is about one service block. Enough that the last exchange is on
  /// screen without scrolling, short enough that the scorecard below it is
  /// still reachable — this sits under the pad on the scorer's own screen, and
  /// the pad is what they came for.
  final int initiallyShown;

  @override
  ConsumerState<PointLog> createState() => _PointLogState();
}

class _PointLogState extends ConsumerState<PointLog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    // The deep window, not the 60-event feed: a rally engine derives the
    // score beside each point by replaying, and a replay that starts mid-match
    // prints numbers that contradict the pad above it. See
    // [matchTimelineProvider].
    final events = ref.watch(
      matchTimelineProvider(FixtureRef(f.orgId, f.compId, f.id)),
    );

    return PsCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 17, color: Ps.muted),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Point by point',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Ps.ink,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (events.valueOrNull != null)
                Text(
                  '${events.value!.length} entries',
                  style: const TextStyle(fontSize: 11.5, color: Ps.faint),
                ),
            ],
          ),
          const SizedBox(height: 8),
          events.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            // Stated plainly. The log is the audit trail, and "we could not
            // load it" is a materially different thing from "nothing has
            // happened", which is what an empty list would imply.
            error: (e, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'The log could not be loaded. The score above is unaffected.',
                style: TextStyle(fontSize: 12.5, color: Ps.muted),
              ),
            ),
            data: (list) => _body(list),
          ),
        ],
      ),
    );
  }

  Widget _body(List<MatchEvent> events) {
    final f = widget.fixture;
    final plugin = ScoringRegistry.resolve(f.scoringPluginKey);
    // Newest first — the row a scorer wants is almost always the one they just
    // entered, and on a phone that has to be the row nearest the pad.
    final entries =
        plugin.timeline(events, f.scoringContext()).reversed.toList();

    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          'Nothing recorded yet. Every point you enter shows up here with the '
          'time it was scored.',
          style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
        ),
      );
    }

    final shown =
        _expanded ? entries : entries.take(widget.initiallyShown).toList();
    final hidden = entries.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in shown) _Row(entry: e),
        if (hidden > 0 || _expanded)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Show less' : 'Show all $hidden earlier',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final MatchTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final line = entry.line;
    final sided = line.side != Side.neutral;
    final accent = sided ? DuelPad.accentFor(line.side) : Ps.muted;

    // A set break is a band across the row, not another line in the column.
    // Forty near-identical rows need shape more than they need detail, and the
    // break is the only place the shape can come from.
    if (line.isMilestone) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(
              line.text.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                line.detail ?? '',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final struck = entry.withdrawn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // The colour chip carries "which side" so the text does not have to
          // be read at all to see the pattern of an exchange.
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
              color: struck ? Ps.faint : accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: struck ? Ps.faint : Ps.ink,
                decoration: struck ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (struck)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'undone',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Ps.faint,
                ),
              ),
            )
          else if (line.detail != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                line.detail!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Ps.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          SizedBox(
            width: 42,
            child: Text(
              entry.event.at == null ? '· · ·' : _hhmm(entry.event.at!),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11.5,
                color: Ps.faint,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Local wall-clock time, to the minute.
  ///
  /// Not seconds: the sketch's log reads 12:23, and a scorer matching a
  /// disputed point against a phone photo or a memory is working in minutes.
  /// Not a relative "2m ago" either — that changes under them while they read
  /// it, and two rows that both said "2m ago" would lose the order the log
  /// exists to preserve.
  static String _hhmm(DateTime at) => DateFormat.Hm().format(at.toLocal());
}
