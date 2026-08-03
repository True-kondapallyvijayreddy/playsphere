import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/dispute.dart';
import 'package:playsphere/domain/draw/officials_roster.dart';
import 'package:playsphere/domain/draw/tournament_scheduler.dart';

/// An umpire from one of the two clubs playing is the most common complaint at
/// a grassroots tournament, and it is almost never actual bias — it is that
/// nobody checked, and the losing side has no way to know nobody checked.
void main() {
  final day = DateTime(2026, 9, 12);

  ScheduleWindow at(int hour, {int minutes = 30}) => ScheduleWindow(
        start: DateTime(day.year, day.month, day.day, hour),
        end: DateTime(day.year, day.month, day.day, hour)
            .add(Duration(minutes: minutes)),
      );

  OfficiatingSlot slot(
    String id,
    int hour, {
    Set<String> clubs = const {},
    String court = 'v1/c1',
  }) =>
      OfficiatingSlot(
        fixtureId: id,
        window: at(hour),
        courtKey: court,
        contestingClubIds: clubs,
      );

  AvailableOfficial official(
    String uid, {
    String? club,
    int max = 8,
  }) =>
      AvailableOfficial(uid: uid, name: uid, clubId: club, maxMatches: max);

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
