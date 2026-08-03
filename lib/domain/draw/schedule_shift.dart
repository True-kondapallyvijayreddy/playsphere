import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';

/// What shifting a schedule would actually do, worked out before anything is
/// written.
class ShiftPlan {
  const ShiftPlan({
    required this.moves,
    required this.by,
    required this.skippedPlayed,
    required this.skippedLive,
    required this.skippedUnscheduled,
    required this.skippedEarlier,
    required this.newFirstStart,
    required this.newLastStart,
  });

  /// fixtureId → its new start time.
  final Map<String, DateTime> moves;

  /// How much everything moved by. Negative pulls the day earlier, which is
  /// the case where a round finished ahead of time and the organizer wants
  /// the afternoon back.
  final Duration by;

  /// Matches left alone because they are already history.
  final int skippedPlayed;

  /// Matches left alone because a scorer is standing over them right now.
  final int skippedLive;

  /// Matches with no time to shift — a knockout placeholder that has not been
  /// given even a provisional slot.
  final int skippedUnscheduled;

  /// Matches before the cut-off, when one was given.
  final int skippedEarlier;

  final DateTime? newFirstStart;
  final DateTime? newLastStart;

  int get movedCount => moves.length;

  bool get isEmpty => moves.isEmpty;
}

/// Moves a whole schedule without redrawing it.
///
/// ## Why this is not "generate the schedule again"
///
/// A generated schedule is an allocation: who is on which court, in what
/// order, with the rest gaps and the round dependencies all satisfied. When
/// the first round starts an hour late, none of that becomes wrong — every
/// constraint the scheduler solved still holds, because they are all
/// *relative*. Only the clock is wrong.
///
/// Regenerating would re-solve the whole allocation and could hand a player a
/// different court, a different opponent order, and a different time of day
/// for reasons they cannot see. Shifting keeps the plan the organizer already
/// announced and moves it bodily, which is what "we are running an hour late"
/// actually means to everyone standing in the hall.
///
/// ## What never moves
///
/// - **A played match.** Its time is part of the record.
/// - **A live match.** Somebody is scoring it; the clock has already caught
///   up with it and there is nothing to postpone.
/// - **A match with no time at all.** A placeholder that was never given even
///   a provisional slot has nothing to shift; it gets one when the round
///   ahead of it resolves.
class ScheduleShift {
  const ScheduleShift._();

  /// Plans a shift of [by] over [fixtures].
  ///
  /// When [from] is given, only matches due at or after it move — which is
  /// how an organizer pushes back the rest of the day without disturbing the
  /// morning that already ran to time.
  static ShiftPlan plan({
    required List<Fixture> fixtures,
    required Duration by,
    DateTime? from,
  }) {
    final moves = <String, DateTime>{};
    var played = 0;
    var live = 0;
    var unscheduled = 0;
    var earlier = 0;

    for (final f in fixtures) {
      if (f.status.isResulted || f.status == FixtureStatus.abandoned) {
        played++;
        continue;
      }
      if (f.isLive || f.lastSeq > 0) {
        live++;
        continue;
      }
      final at = f.scheduledAt;
      if (at == null) {
        unscheduled++;
        continue;
      }
      if (from != null && at.isBefore(from)) {
        earlier++;
        continue;
      }
      moves[f.id] = at.add(by);
    }

    DateTime? first;
    DateTime? last;
    for (final t in moves.values) {
      if (first == null || t.isBefore(first)) first = t;
      if (last == null || t.isAfter(last)) last = t;
    }

    return ShiftPlan(
      moves: moves,
      by: by,
      skippedPlayed: played,
      skippedLive: live,
      skippedUnscheduled: unscheduled,
      skippedEarlier: earlier,
      newFirstStart: first,
      newLastStart: last,
    );
  }

  /// Plans the shift that puts the earliest still-to-be-played match at
  /// [newStart], moving everything else by the same amount.
  ///
  /// This is the operation an organizer actually reaches for. They do not
  /// think "push everything by fifty-five minutes"; they think "we are
  /// starting at half past ten now", and everything else should follow by
  /// exactly as much.
  static ShiftPlan planNewStart({
    required List<Fixture> fixtures,
    required DateTime newStart,
  }) {
    final current = earliestPending(fixtures);
    if (current == null) {
      return plan(fixtures: fixtures, by: Duration.zero);
    }
    return plan(fixtures: fixtures, by: newStart.difference(current));
  }

  /// The start time of the earliest match still waiting to be played.
  ///
  /// Deliberately ignores matches already played or in progress: after the
  /// morning has run, "when do we start again" is a question about the
  /// afternoon.
  static DateTime? earliestPending(List<Fixture> fixtures) {
    DateTime? earliest;
    for (final f in fixtures) {
      if (f.status != FixtureStatus.scheduled || f.lastSeq > 0) continue;
      final at = f.scheduledAt;
      if (at == null) continue;
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    return earliest;
  }
}
