import 'package:flutter/foundation.dart';

import '../../core/models/fixture.dart' show MatchEvent;
import 'scoring_plugin.dart';

/// The point-by-point timeline shared by every rally sport.
///
/// ## What it is for
///
/// Badminton, table tennis, tennis, volleyball and throwball all record the
/// same event forty to ninety times a match — "that side won the rally" — and
/// a column of forty identical lines is not a record of anything. What makes
/// it a record is the two things this mixin adds around each point: the score
/// it produced, and the breaks where a set closed.
///
///     Team A +1        21 - 18      12:23
///     SET 1 — Team A 21 - 18 Team B
///     Team B +1         0 -  1      12:24
///
/// That is an audit trail. A player who says they were on 19 can be answered
/// from it, and a set that ended at the wrong score can be found in it.
///
/// ## Why it replays instead of storing the score on the event
///
/// The running score is not a fact about a point; it is a fact about every
/// point before it. Writing it onto the event at scoring time would freeze a
/// number that a later undo invalidates — undo the 15th point and the score
/// printed beside points 16 through 30 is wrong, permanently, in the one
/// record that exists to be trusted. Replaying derives it fresh every time, so
/// the timeline always agrees with the scoreboard above it.
///
/// The cost is a replay per rebuild, over a log that tops out around ninety
/// events for these sports. That is nothing, and it is why this is a rally
/// mixin rather than something on the base contract: cricket's log is
/// thousands of deliveries and must not pay it.
mixin RallyTimeline on ScoringPlugin {
  /// The sets or games already finished, as the engine stores them — each a
  /// map with `a` and `b`. The engines disagree on the key
  /// (`completedSets` versus `completedGames`), which is exactly why this is
  /// asked of them rather than read from the state here.
  List<Map<String, dynamic>> rallyCompletedPeriods(Map<String, dynamic> state);

  /// What one of those is called in this sport — 'Set' or 'Game'.
  String get rallyPeriodNoun;

  /// The action type this engine logs when a side wins the rally.
  ///
  /// Asked rather than assumed: badminton calls it `rally` and the others call
  /// it `point`, and a mixin that guessed would have quietly rendered every
  /// badminton point as "Anand — rally" — a wrong line in the one record that
  /// exists to be trusted, produced by the layer that is supposed to keep
  /// sport vocabulary out of shared code.
  String get rallyPointAction => 'point';

  @override
  MatchEventLine? describeEvent(MatchEvent event, ScoringContext ctx) {
    final side = Side.fromWire(event.payload['side'] as String?);
    if (side == Side.neutral) return super.describeEvent(event, ctx);

    return switch (event.type) {
      // The sketch's own words. "+1" and "−1" are what the buttons say, so
      // they are what the log should say — a scorer checking their own work
      // should not have to translate between the control they pressed and the
      // line it produced.
      _ when event.type == rallyPointAction =>
        MatchEventLine(text: '${ctx.nameFor(side)} +1', side: side),
      'correct' => MatchEventLine(text: '${ctx.nameFor(side)} −1', side: side),
      'retire' => MatchEventLine(
          text: '${ctx.nameFor(side)} retired',
          side: side,
          isMilestone: true,
        ),
      _ => super.describeEvent(event, ctx),
    };
  }

  @override
  List<MatchTimelineEntry> timeline(
    List<MatchEvent> events,
    ScoringContext ctx,
  ) {
    final sorted = [...events]..sort((x, y) => x.seq.compareTo(y.seq));
    final withdrawn = ScoringPlugin.resolveWithdrawn([
      for (final e in sorted)
        LoggedAction(seq: e.seq, action: ScoringPlugin.actionOf(e)),
    ]);

    // A log that does not start at the first event cannot be replayed into
    // running scores. The stream is windowed (see `matchTimelineProvider`), so
    // on a long enough match the earliest points are simply not here — and a
    // replay from `initialState` over what IS here would produce a plausible,
    // confident, wrong number beside every line. The lines are still worth
    // showing; the scores are not, so they are dropped.
    final complete = sorted.isEmpty || sorted.first.seq <= 1;

    var state = initialState(ctx);
    var closed = rallyCompletedPeriods(state).length;
    final out = <MatchTimelineEntry>[];

    for (final e in sorted) {
      // An undo is bookkeeping. Its effect is already visible — the point it
      // withdrew is struck through — and a row saying "Undo" beside it would
      // report the same fact twice.
      if (e.type == ScoringPlugin.undoActionType) continue;

      if (e.type == ScoringPlugin.restartActionType) {
        state = initialState(ctx);
        closed = 0;
        out.add(MatchTimelineEntry(
          event: e,
          line: const MatchEventLine(
            text: 'Match restarted',
            isMilestone: true,
          ),
        ));
        continue;
      }

      final line = describeEvent(e, ctx);
      if (line == null) continue;

      // A withdrawn event is shown but never applied: it is on the record and
      // it did not happen, and the score beside the points after it has to
      // reflect the second of those.
      if (withdrawn.contains(e.seq)) {
        out.add(MatchTimelineEntry(event: e, line: line, withdrawn: true));
        continue;
      }

      final result = apply(state, ScoringPlugin.actionOf(e), ctx);
      if (result.isAccepted) state = result.state;

      if (!complete) {
        out.add(MatchTimelineEntry(event: e, line: line));
        continue;
      }

      final periods = rallyCompletedPeriods(state);
      if (periods.length > closed) {
        // The point that closed the set becomes the break, rather than the
        // break being a row of its own. There is exactly one event either way,
        // and hanging it on the real event keeps every row in the timeline
        // traceable to something a scorer actually pressed.
        final p = periods.last;
        closed = periods.length;
        out.add(MatchTimelineEntry(
          event: e,
          line: MatchEventLine(
            text: '$rallyPeriodNoun ${periods.length}',
            side: line.side,
            detail: '${ctx.entrantAName} ${p['a'] ?? 0} - '
                '${p['b'] ?? 0} ${ctx.entrantBName}',
            isMilestone: true,
          ),
        ));
      } else {
        out.add(MatchTimelineEntry(
          event: e,
          line: MatchEventLine(
            text: line.text,
            side: line.side,
            detail: headline(state, ctx),
            isMilestone: line.isMilestone,
          ),
        ));
      }
    }

    return out;
  }

  /// Which side is serving in [state], or null when this sport does not track
  /// it well enough to attribute a point to serve or receive.
  ///
  /// Null is the honest default rather than a guess: an engine that cannot say
  /// who was serving produces a scorecard WITHOUT the serve columns, which is
  /// a smaller card and a true one. The alternative — assuming side A serves
  /// first and alternating — would fill five columns of a scorecard with
  /// fiction that looks exactly like fact.
  Side? rallyServingSide(Map<String, dynamic> state, ScoringContext ctx) => null;

  /// Points won, split by whether the winner was serving, per period.
  ///
  /// ## Why this replays instead of reading counters off the state
  ///
  /// For the same reason [timeline] does. Serve statistics are a fact about
  /// every point that has been played, and the state map holds only the score
  /// as it stands — an engine that accumulated `serviceWins` into its state
  /// would have to unwind them on an undo, in four engines, correctly, and
  /// the first one that got it slightly wrong would produce a scorecard that
  /// disagreed with the point log beneath it forever after.
  ///
  /// Replaying costs one pass over a log that tops out around ninety events
  /// for these sports, and it cannot drift: the serve attribution comes from
  /// asking the ENGINE who was serving immediately before each point, so it
  /// follows that sport's real laws — badminton's serve-follows-the-rally,
  /// table tennis's every-two-points, tennis's per-game — rather than a rule
  /// re-implemented here and left to rot.
  RallyScorecard? rallyScorecard(List<MatchEvent> events, ScoringContext ctx) {
    final sorted = [...events]..sort((x, y) => x.seq.compareTo(y.seq));

    // A windowed log cannot be replayed into totals, and a partial serve
    // percentage is worse than none — see [timeline]'s note on the same trap.
    if (sorted.isNotEmpty && sorted.first.seq > 1) return null;

    final withdrawn = ScoringPlugin.resolveWithdrawn([
      for (final e in sorted)
        LoggedAction(seq: e.seq, action: ScoringPlugin.actionOf(e)),
    ]);

    var state = initialState(ctx);
    if (rallyServingSide(state, ctx) == null) return null;

    var closed = rallyCompletedPeriods(state).length;
    final periods = <_RallyPeriodTally>[_RallyPeriodTally()];

    for (final e in sorted) {
      if (e.type == ScoringPlugin.undoActionType) continue;
      if (e.type == ScoringPlugin.restartActionType) {
        state = initialState(ctx);
        closed = 0;
        periods
          ..clear()
          ..add(_RallyPeriodTally());
        continue;
      }
      if (withdrawn.contains(e.seq)) continue;

      final side = Side.fromWire(e.payload['side'] as String?);
      final isPoint = e.type == rallyPointAction && side != Side.neutral;
      // Asked BEFORE the point is applied: the serve moves as a consequence
      // of the rally in three of these four sports, so reading it afterwards
      // would credit half the points to the wrong column.
      final server = isPoint ? rallyServingSide(state, ctx) : null;

      final result = apply(state, ScoringPlugin.actionOf(e), ctx);
      if (result.isAccepted) state = result.state;

      if (isPoint) {
        periods.last.add(side, onServe: server == side);
      }

      final done = rallyCompletedPeriods(state);
      if (done.length > closed) {
        closed = done.length;
        periods.add(_RallyPeriodTally());
      }
    }

    // The trailing period is only real if something happened in it. A match
    // sitting between sets would otherwise show an empty "Set 3" row.
    if (periods.length > 1 && periods.last.isEmpty) periods.removeLast();

    return RallyScorecard(
      periodNoun: rallyPeriodNoun,
      periods: [
        for (final p in periods)
          RallyPeriodStats(
            pointsA: p.pointsA,
            pointsB: p.pointsB,
            serveWonA: p.serveWonA,
            serveWonB: p.serveWonB,
            receiveWonA: p.pointsA - p.serveWonA,
            receiveWonB: p.pointsB - p.serveWonB,
          ),
      ],
    );
  }
}

class _RallyPeriodTally {
  int pointsA = 0;
  int pointsB = 0;
  int serveWonA = 0;
  int serveWonB = 0;

  bool get isEmpty => pointsA == 0 && pointsB == 0;

  void add(Side side, {required bool onServe}) {
    if (side == Side.a) {
      pointsA++;
      if (onServe) serveWonA++;
    } else if (side == Side.b) {
      pointsB++;
      if (onServe) serveWonB++;
    }
  }
}

/// Points won on serve and on receive, per period — the scorecard beneath a
/// racket pad.
@immutable
class RallyScorecard {
  const RallyScorecard({required this.periodNoun, required this.periods});

  /// 'Set' or 'Game', so the rows can be labelled in the sport's own words.
  final String periodNoun;

  /// Oldest first; the last entry is the period in play.
  final List<RallyPeriodStats> periods;

  int get totalA => periods.fold(0, (s, p) => s + p.pointsA);
  int get totalB => periods.fold(0, (s, p) => s + p.pointsB);
  int get serveWonA => periods.fold(0, (s, p) => s + p.serveWonA);
  int get serveWonB => periods.fold(0, (s, p) => s + p.serveWonB);

  /// Share of this side's points that were won while serving.
  ///
  /// Null rather than zero for a side that has not scored: 0% claims they
  /// served and lost, and they have not served a point yet.
  double? serveShareA() => totalA == 0 ? null : serveWonA / totalA;
  double? serveShareB() => totalB == 0 ? null : serveWonB / totalB;
}

@immutable
class RallyPeriodStats {
  const RallyPeriodStats({
    required this.pointsA,
    required this.pointsB,
    required this.serveWonA,
    required this.serveWonB,
    required this.receiveWonA,
    required this.receiveWonB,
  });

  final int pointsA;
  final int pointsB;
  final int serveWonA;
  final int serveWonB;
  final int receiveWonA;
  final int receiveWonB;
}
