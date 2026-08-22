import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/dispute.dart';
import 'package:playsphere/domain/draw/officials_roster.dart';
import 'package:playsphere/domain/draw/tournament_scheduler.dart';

/// An umpire from one of the two clubs playing is the most common complaint at
/// a grassroots tournament, and it is almost never actual bias — it is that
/// nobody checked, and the losing side has no way to know nobody checked.
void main() {
  final day = DateTime(2026, 9, 12);

  ScheduleWindow at(int hour, {int minutes = 30, int? onDay}) => ScheduleWindow(
        start: DateTime(day.year, day.month, onDay ?? day.day, hour),
        end: DateTime(day.year, day.month, onDay ?? day.day, hour)
            .add(Duration(minutes: minutes)),
      );

  OfficiatingSlot slot(
    String id,
    int hour, {
    Set<String> clubs = const {},
    String court = 'v1/c1',
    String? sport,
    int? onDay,
  }) =>
      OfficiatingSlot(
        fixtureId: id,
        window: at(hour, onDay: onDay),
        courtKey: court,
        contestingClubIds: clubs,
        sportId: sport,
      );

  AvailableOfficial official(
    String uid, {
    String? club,
    int max = 8,
    List<String> sports = const [],
    Set<String> days = const {},
  }) =>
      AvailableOfficial(
        uid: uid,
        name: uid,
        clubId: club,
        maxMatches: max,
        sports: sports,
        availableDays: days,
      );

  const assigner = OfficialsAssigner();

  group('neutrality is a hard constraint', () {
    test('an official is never put on their own club\'s match', () {
      final roster = assigner.assign(
        slots: [slot('f1', 9, clubs: {'kompally', 'gachibowli'})],
        officials: [
          official('partisan', club: 'kompally'),
          official('neutral', club: 'other'),
        ],
      );
      expect(roster.assignments.single.official.uid, 'neutral');
    });

    test('an unaffiliated official is never blocked', () {
      // The most useful kind of official to have.
      final roster = assigner.assign(
        slots: [slot('f1', 9, clubs: {'a', 'b'})],
        officials: [official('freelance')],
      );
      expect(roster.assignments.single.official.uid, 'freelance');
    });

    test('rather than quietly using a partisan official, it reports why', () {
      // The organizer may still decide "both captains are happy with Ravi" —
      // but the system must not make that call for them silently.
      final roster = assigner.assign(
        slots: [slot('f1', 9, clubs: {'kompally', 'gachibowli'})],
        officials: [
          official('a', club: 'kompally'),
          official('b', club: 'gachibowli'),
        ],
      );
      expect(roster.assignments, isEmpty);
      expect(roster.unstaffed.single.reason, contains('neutral'));
      expect(roster.isComplete, isFalse);
    });
  });

  group('an official cannot be in two places', () {
    test('overlapping matches go to different officials', () {
      final roster = assigner.assign(
        slots: [
          slot('f1', 9, court: 'v1/c1'),
          slot('f2', 9, court: 'v1/c2'),
        ],
        officials: [official('a'), official('b')],
      );
      final uids =
          roster.assignments.map((a) => a.official.uid).toSet();
      expect(uids.length, 2);
    });

    test('a turnaround gap is respected between an official\'s matches', () {
      // They have to walk across the hall and read the next team sheet.
      final roster = assigner.assign(
        slots: [slot('f1', 9), slot('f2', 9)],
        officials: [official('solo')],
        turnaround: const Duration(minutes: 15),
      );
      expect(roster.assignments.length, 1);
      expect(roster.unstaffed.single.reason, contains('another court'));
    });

    test('back-to-back is allowed once the gap is met', () {
      final roster = assigner.assign(
        slots: [slot('f1', 9), slot('f2', 11)],
        officials: [official('solo')],
        turnaround: const Duration(minutes: 10),
      );
      expect(roster.assignments.length, 2);
    });
  });

  group('load', () {
    test('an official is not booked past their own limit', () {
      // An umpire standing for fourteen matches is not officiating the last
      // four, and a roster that does that quietly loses a club its volunteers.
      final roster = assigner.assign(
        slots: [for (var h = 9; h < 15; h++) slot('f$h', h)],
        officials: [official('capped', max: 2)],
      );
      expect(roster.assignments.length, 2);
      expect(roster.loadByUid['capped'], 2);
      expect(roster.unstaffed.length, 4);
    });

    test('work spreads rather than landing on whoever is first', () {
      final roster = assigner.assign(
        slots: [for (var h = 9; h < 13; h++) slot('f$h', h)],
        officials: [official('a'), official('b')],
      );
      expect(roster.loadByUid['a'], 2);
      expect(roster.loadByUid['b'], 2);
    });

    test('no officials at all is reported, not crashed', () {
      final roster = assigner.assign(slots: [slot('f1', 9)], officials: []);
      expect(roster.unstaffed.single.reason, contains('No officials'));
    });

    test('the limit is per day, not per tournament', () {
      // A cap of two across a three-day season is not a limit on anything.
      // The same person may take two on each of the three days.
      final roster = assigner.assign(
        slots: [
          for (var d = 12; d <= 14; d++)
            for (final h in [9, 11]) slot('f${d}_$h', h, onDay: d),
        ],
        officials: [official('capped', max: 2)],
      );
      expect(roster.assignments.length, 6);
      expect(roster.loadByUid['capped'], 6);
      expect(roster.loadByUidByDay['capped']!['2026-09-12'], 2);
      expect(roster.loadByUidByDay['capped']!['2026-09-14'], 2);
    });
  });

  group('sport is a hard constraint', () {
    test('a badminton umpire is never put on the kabaddi mat', () {
      final roster = assigner.assign(
        slots: [slot('f1', 9, sport: 'kabaddi')],
        officials: [
          official('shuttle', sports: const ['badminton']),
          official('mat', sports: const ['kabaddi']),
        ],
      );
      expect(roster.assignments.single.official.uid, 'mat');
    });

    test('an official with no sports listed takes anything', () {
      // The default has to stay open, or a panel built in a hurry is a panel
      // that staffs nothing.
      final roster = assigner.assign(
        slots: [slot('f1', 9, sport: 'kho_kho')],
        officials: [official('generalist')],
      );
      expect(roster.assignments.single.official.uid, 'generalist');
    });

    test('a sport nobody covers says so, rather than blaming the timetable',
        () {
      // The reason decides the organizer's next action, and "everybody is
      // busy" sends them to reshuffle a schedule that was never the problem.
      final roster = assigner.assign(
        slots: [slot('f1', 9, sport: 'kabaddi')],
        officials: [official('shuttle', sports: const ['badminton'])],
      );
      expect(roster.assignments, isEmpty);
      expect(roster.unstaffed.single.reason, contains('kabaddi'));
      expect(roster.unstaffedBySport['kabaddi'], hasLength(1));
    });

    test('four sports are staffed from one panel, each by its own people', () {
      // The multi-sport season this exists for: nobody ends up on a court
      // they cannot officiate, and nothing is left unstaffed.
      final roster = assigner.assign(
        slots: [
          slot('b1', 9, sport: 'badminton'),
          slot('k1', 9, sport: 'kabaddi', court: 'v1/c2'),
          slot('c1', 11, sport: 'cricket'),
          slot('t1', 11, sport: 'table_tennis', court: 'v1/c2'),
        ],
        officials: [
          official('bee', sports: const ['badminton', 'table_tennis']),
          official('kay', sports: const ['kabaddi', 'cricket']),
        ],
      );
      expect(roster.isComplete, isTrue);
      for (final a in roster.assignments) {
        final sport = {
          'b1': 'badminton',
          'k1': 'kabaddi',
          'c1': 'cricket',
          't1': 'table_tennis',
        }[a.fixtureId];
        expect(a.official.sports, contains(sport));
      }
    });
  });

  group('availability by date', () {
    test('somebody free only on Saturday is not given the Sunday final', () {
      final roster = assigner.assign(
        slots: [slot('sun', 9, onDay: 13)],
        officials: [official('saturday', days: const {'2026-09-12'})],
      );
      expect(roster.assignments, isEmpty);
      expect(roster.unstaffed.single.reason, contains('unavailable'));
    });

    test('they are still used on the day they said they could come', () {
      final roster = assigner.assign(
        slots: [slot('sat', 9, onDay: 12), slot('sun', 9, onDay: 13)],
        officials: [
          official('saturday', days: const {'2026-09-12'}),
          official('sunday', days: const {'2026-09-13'}),
        ],
      );
      expect(roster.isComplete, isTrue);
      expect(
        roster.assignments.firstWhere((a) => a.fixtureId == 'sat').official.uid,
        'saturday',
      );
      expect(
        roster.assignments.firstWhere((a) => a.fixtureId == 'sun').official.uid,
        'sunday',
      );
    });

    test('no dates recorded means every day', () {
      // Most volunteers at a one-day club meet are there for the day, and
      // demanding a date list before anyone can be added would put a form
      // between an organizer and the panel they are building.
      final roster = assigner.assign(
        slots: [slot('sat', 9, onDay: 12), slot('sun', 9, onDay: 13)],
        officials: [official('anytime')],
      );
      expect(roster.assignments.length, 2);
    });

    test('sport is reported before availability when both would fail', () {
      // Ordered as the funnel is, so the message names the first wall rather
      // than the last.
      final roster = assigner.assign(
        slots: [slot('f1', 9, sport: 'kabaddi', onDay: 13)],
        officials: [
          official(
            'wrong-on-both-counts',
            sports: const ['badminton'],
            days: const {'2026-09-12'},
          ),
        ],
      );
      expect(roster.unstaffed.single.reason, contains('kabaddi'));
    });
  });

  group('the protest window', () {
    final finished = DateTime(2026, 9, 12, 14, 0);

    test('a result is open to protest for an hour', () {
      expect(
        withinProtestWindow(finished, now: DateTime(2026, 9, 12, 14, 30)),
        isTrue,
      );
      expect(
        withinProtestWindow(finished, now: DateTime(2026, 9, 12, 15, 30)),
        isFalse,
      );
    });

    test('a match with no result cannot be protested', () {
      expect(withinProtestWindow(null), isFalse);
    });

    test('a scorecard locks once the window passes with nothing open', () {
      // What a bracket should check before advancing anybody.
      expect(
        scorecardIsLocked(
          completedAt: finished,
          hasOpenDispute: false,
          now: DateTime(2026, 9, 12, 16, 0),
        ),
        isTrue,
      );
    });

    test('an open protest keeps the scorecard unlocked past the window', () {
      // A bracket cannot advance while an earlier match might be overturned.
      expect(
        scorecardIsLocked(
          completedAt: finished,
          hasOpenDispute: true,
          now: DateTime(2026, 9, 13),
        ),
        isFalse,
      );
    });

    test('a match still inside its window is not yet locked', () {
      expect(
        scorecardIsLocked(
          completedAt: finished,
          hasOpenDispute: false,
          now: DateTime(2026, 9, 12, 14, 10),
        ),
        isFalse,
      );
    });
  });

  group('dispute status', () {
    test('only an open protest is unresolved', () {
      expect(DisputeStatus.open.isResolved, isFalse);
      for (final s in [
        DisputeStatus.upheld,
        DisputeStatus.rejected,
        DisputeStatus.withdrawn,
      ]) {
        expect(s.isResolved, isTrue, reason: s.wire);
      }
    });

    test('every wire token round-trips', () {
      for (final s in DisputeStatus.values) {
        expect(DisputeStatus.fromWire(s.wire), s);
      }
      for (final r in DisputeReason.values) {
        expect(DisputeReason.fromWire(r.wire), r);
      }
      expect(DisputeStatus.fromWire(null), DisputeStatus.open);
    });
  });
}
