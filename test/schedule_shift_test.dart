import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/draw/schedule_shift.dart';

/// A generated schedule is an allocation, and every constraint it solved is
/// relative — courts, order, rest gaps, round dependencies. When the first
/// round starts an hour late none of that becomes wrong; only the clock does.
/// So the organizer's fix is to move the plan bodily, not to redraw it.
void main() {
  final day = DateTime(2026, 9, 12);

  Fixture at(
    String id,
    int hour,
    int minute, {
    FixtureStatus status = FixtureStatus.scheduled,
    int lastSeq = 0,
    String? court,
  }) =>
      Fixture(
        id: id,
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'A',
        entrantBId: 'B',
        entrantAName: 'A',
        entrantBName: 'B',
        status: status,
        lastSeq: lastSeq,
        courtId: court,
        scheduledAt: DateTime(day.year, day.month, day.day, hour, minute),
      );

  Fixture unscheduled(String id) => Fixture(
        id: id,
        orgId: 'o1',
        compId: 'c1',
        entrantAId: '',
        entrantBId: '',
        entrantAName: 'To be decided',
        entrantBName: 'To be decided',
        status: FixtureStatus.scheduled,
      );

  group('moving the whole day', () {
    test('every pending match moves by the same amount', () {
      final plan = ScheduleShift.plan(
        fixtures: [at('a', 9, 30), at('b', 10, 0), at('c', 10, 30)],
        by: const Duration(hours: 1),
      );

      expect(plan.movedCount, 3);
      expect(plan.moves['a'], DateTime(2026, 9, 12, 10, 30));
      expect(plan.moves['b'], DateTime(2026, 9, 12, 11, 0));
      expect(plan.moves['c'], DateTime(2026, 9, 12, 11, 30));
    });

    test('the gaps between matches are preserved exactly', () {
      // The point of shifting rather than regenerating: the plan the organizer
      // announced survives, so a player told they are third on court 2 is
      // still third on court 2.
      final plan = ScheduleShift.plan(
        fixtures: [at('a', 9, 0), at('b', 9, 25), at('c', 11, 40)],
        by: const Duration(minutes: 55),
      );
      expect(
        plan.moves['b']!.difference(plan.moves['a']!),
        const Duration(minutes: 25),
      );
      expect(
        plan.moves['c']!.difference(plan.moves['b']!),
        const Duration(minutes: 135),
      );
    });

    test('a negative shift pulls the day earlier', () {
      // A round that finished ahead of time — the organizer wants the
      // afternoon back.
      final plan = ScheduleShift.plan(
        fixtures: [at('a', 14, 0)],
        by: const Duration(minutes: -30),
      );
      expect(plan.moves['a'], DateTime(2026, 9, 12, 13, 30));
    });

    test('the new first and last start are reported', () {
      final plan = ScheduleShift.plan(
        fixtures: [at('a', 9, 0), at('b', 17, 0)],
        by: const Duration(hours: 1),
      );
      expect(plan.newFirstStart, DateTime(2026, 9, 12, 10, 0));
      expect(plan.newLastStart, DateTime(2026, 9, 12, 18, 0));
    });
  });

  group('what never moves', () {
    test('a played match keeps its time — it is part of the record', () {
      final plan = ScheduleShift.plan(
        fixtures: [
          at('done', 9, 0, status: FixtureStatus.completed),
          at('next', 10, 0),
        ],
        by: const Duration(hours: 1),
      );
      expect(plan.moves.containsKey('done'), isFalse);
      expect(plan.skippedPlayed, 1);
      expect(plan.moves['next'], DateTime(2026, 9, 12, 11, 0));
    });

    test('a live match is left alone — somebody is scoring it', () {
      final plan = ScheduleShift.plan(
        fixtures: [
          at('live', 9, 30, status: FixtureStatus.live, lastSeq: 14),
          at('later', 11, 0),
        ],
        by: const Duration(hours: 1),
      );
      expect(plan.moves.containsKey('live'), isFalse);
      expect(plan.skippedLive, 1);
    });

    test('a match with events but not yet flagged live is still left alone',
        () {
      // The clock has already caught up with it, whatever the status field
      // happens to say at this instant.
      final plan = ScheduleShift.plan(
        fixtures: [at('started', 9, 30, lastSeq: 3)],
        by: const Duration(hours: 1),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.skippedLive, 1);
    });

    test('a walkover is history and does not move', () {
      final plan = ScheduleShift.plan(
        fixtures: [at('wo', 9, 0, status: FixtureStatus.walkover)],
        by: const Duration(hours: 1),
      );
      expect(plan.skippedPlayed, 1);
      expect(plan.isEmpty, isTrue);
    });

    test('a placeholder with no time has nothing to shift', () {
      final plan = ScheduleShift.plan(
        fixtures: [unscheduled('tbd'), at('real', 10, 0)],
        by: const Duration(hours: 1),
      );
      expect(plan.skippedUnscheduled, 1);
      expect(plan.movedCount, 1);
    });
  });

  group('moving only part of the day', () {
    test('a morning that ran to time is left alone', () {
      final plan = ScheduleShift.plan(
        fixtures: [at('am', 9, 0), at('pm1', 14, 0), at('pm2', 15, 0)],
        by: const Duration(minutes: 45),
        from: DateTime(2026, 9, 12, 13, 0),
      );
      expect(plan.skippedEarlier, 1);
      expect(plan.moves.containsKey('am'), isFalse);
      expect(plan.moves['pm1'], DateTime(2026, 9, 12, 14, 45));
      expect(plan.moves['pm2'], DateTime(2026, 9, 12, 15, 45));
    });

    test('a match exactly on the cut-off does move', () {
      final plan = ScheduleShift.plan(
        fixtures: [at('edge', 13, 0)],
        by: const Duration(minutes: 30),
        from: DateTime(2026, 9, 12, 13, 0),
      );
      expect(plan.moves['edge'], DateTime(2026, 9, 12, 13, 30));
    });
  });

  group('"we are starting at half past ten now"', () {
    test('the offset is computed from the earliest pending match', () {
      // The organizer does not think "push by fifty-five minutes" — they
      // think "we start at 10:30", and everything follows by exactly as much.
      final plan = ScheduleShift.planNewStart(
        fixtures: [at('a', 9, 30), at('b', 10, 0), at('c', 11, 15)],
        newStart: DateTime(2026, 9, 12, 10, 30),
      );

      expect(plan.by, const Duration(hours: 1));
      expect(plan.moves['a'], DateTime(2026, 9, 12, 10, 30));
      expect(plan.moves['b'], DateTime(2026, 9, 12, 11, 0));
      expect(plan.moves['c'], DateTime(2026, 9, 12, 12, 15));
    });

    test('already-played matches do not drag the offset backwards', () {
      // The morning ran. "When do we start again" is a question about what
      // is left, so the 8am match that finished must not be the anchor.
      final plan = ScheduleShift.planNewStart(
        fixtures: [
          at('done', 8, 0, status: FixtureStatus.completed),
          at('next', 11, 0),
        ],
        newStart: DateTime(2026, 9, 12, 11, 30),
      );
      expect(plan.by, const Duration(minutes: 30));
      expect(plan.moves['next'], DateTime(2026, 9, 12, 11, 30));
    });

    test('nothing pending means nothing to do, and no crash', () {
      final plan = ScheduleShift.planNewStart(
        fixtures: [at('done', 9, 0, status: FixtureStatus.completed)],
        newStart: DateTime(2026, 9, 12, 12, 0),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.by, Duration.zero);
    });

    test('earliestPending ignores played and in-progress matches', () {
      expect(
        ScheduleShift.earliestPending([
          at('done', 8, 0, status: FixtureStatus.completed),
          at('live', 9, 0, status: FixtureStatus.live, lastSeq: 2),
          at('next', 10, 0),
          at('later', 12, 0),
        ]),
        DateTime(2026, 9, 12, 10, 0),
      );
    });
  });

  group('courts are untouched', () {
    test('shifting moves the clock and nothing else', () {
      // Regenerating could hand a player a different court for reasons they
      // cannot see. Shifting must not.
      final fixtures = [
        at('a', 9, 0, court: 'Court 1'),
        at('b', 9, 0, court: 'Court 2'),
      ];
      final plan = ScheduleShift.plan(
        fixtures: fixtures,
        by: const Duration(hours: 1),
      );
      // The plan carries times only — court assignments are not in it at all,
      // so nothing downstream can change them.
      expect(plan.moves.keys.toSet(), {'a', 'b'});
      expect(plan.moves['a'], plan.moves['b']);
    });
  });
}
