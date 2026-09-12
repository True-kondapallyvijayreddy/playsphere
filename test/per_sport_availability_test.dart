import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/draw/schedule_guarantees.dart';
import 'package:playsphere/domain/draw/tournament_scheduler.dart';

/// A multi-sport season is not one competition on one ground.
///
/// The badminton is in the indoor hall, the cricket is on the main field, and
/// the football is on the far pitch on Sunday — each of them open at different
/// hours. Scheduled against one shared pool of courts and one shared day
/// window, the timetable is arithmetically sound and physically impossible: it
/// calls a cricket match to badminton court 3 and prints it as fact.
///
/// These are the promises that stop that, checked against the scheduler rather
/// than described in a comment near it.
void main() {
  const scheduler = TournamentScheduler();

  final day = DateTime(2026, 9, 12);

  CourtRef court(String venueId, String venueName, int n) => CourtRef(
        venueId: venueId,
        venueName: venueName,
        courtId: 'c$n',
        courtName: 'Court $n',
      );

  final hall = [court('hall', 'Indoor Hall', 1), court('hall', 'Indoor Hall', 2)];
  final field = [court('field', 'Main Field', 1)];

  List<ScheduleWindow> slots({
    int dayCount = 3,
    int openHour = 8,
    int closeHour = 20,
  }) =>
      TournamentScheduler.buildSlots(
        firstDay: day,
        dayCount: dayCount,
        openHour: openHour,
        closeHour: closeHour,
        slotMinutes: 30,
      );

  SchedulableMatch match(
    String compId,
    int index,
    List<String> uids, {
    EventAvailability availability = EventAvailability.anywhere,
    int minutes = 30,
  }) =>
      SchedulableMatch(
        compId: compId,
        matchIndex: index,
        round: 1,
        playerUids: uids.toSet(),
        matchMinutes: minutes,
        availability: availability,
      );

  group('a sport plays only at its own grounds', () {
    test('a badminton draw is never sent to the cricket field', () {
      final result = scheduler.schedule(
        matches: [
          for (var i = 0; i < 4; i++)
            match(
              'badminton',
              i,
              ['b${i}a', 'b${i}b'],
              availability: const EventAvailability(venueIds: {'hall'}),
            ),
        ],
        courts: [...hall, ...field],
        slots: slots(),
      );

      expect(result.placements, hasLength(4));
      for (final p in result.placements.values) {
        expect(p.court.venueId, 'hall');
      }
    });

    test('two sports on two grounds run at the same time, not in turn', () {
      final result = scheduler.schedule(
        matches: [
          match('badminton', 0, ['b1', 'b2'],
              availability: const EventAvailability(venueIds: {'hall'})),
          match('cricket', 0, ['c1', 'c2'],
              availability: const EventAvailability(venueIds: {'field'})),
        ],
        courts: [...hall, ...field],
        slots: slots(),
      );

      final badminton = result.placements['badminton#0']!;
      final cricket = result.placements['cricket#0']!;
      expect(badminton.court.venueId, 'hall');
      expect(cricket.court.venueId, 'field');
      // Different grounds are not a shared resource, so neither waits on the
      // other. This is the whole practical payoff of the feature: a sports day
      // finishes in a morning instead of running to the evening.
      expect(badminton.window.start, cricket.window.start);
    });

    test('an event confined to a ground with no courts says exactly that', () {
      final result = scheduler.schedule(
        matches: [
          match('archery', 0, ['a1', 'a2'],
              availability: const EventAvailability(venueIds: {'range'})),
        ],
        courts: [...hall, ...field],
        slots: slots(),
      );

      expect(result.placements, isEmpty);
      expect(result.unplaced.single.reason, contains('no usable'));
    });
  });

  group('a sport plays only on its own days', () {
    test('a Sunday-only event takes no Saturday slot', () {
      final sunday = day.add(const Duration(days: 2));
      final result = scheduler.schedule(
        matches: [
          match(
            'football',
            0,
            ['f1', 'f2'],
            availability: EventAvailability(
              firstDay: sunday,
              lastDay: sunday,
            ),
          ),
        ],
        courts: field,
        slots: slots(),
      );

      final placed = result.placements['football#0']!;
      expect(placed.window.start.day, sunday.day);
    });

    test('a draw too big for the days it was given is reported, not spilled',
        () {
      // One court, one day, three hours: six slots. Eight matches cannot fit,
      // and the ones that do not must be named rather than quietly moved to
      // the next day the season happens to own.
      final result = scheduler.schedule(
        matches: [
          for (var i = 0; i < 8; i++)
            match(
              'cricket',
              i,
              ['c${i}a', 'c${i}b'],
              availability: EventAvailability(
                firstDay: day,
                lastDay: day,
                dayStartHour: 9,
                dayEndHour: 12,
              ),
            ),
        ],
        courts: field,
        slots: slots(),
      );

      expect(result.placements.length, lessThan(8));
      expect(result.unplaced, isNotEmpty);
      for (final p in result.placements.values) {
        expect(p.window.start.day, day.day);
        expect(p.window.start.hour, greaterThanOrEqualTo(9));
        expect(p.window.end.hour, lessThanOrEqualTo(12));
      }
    });
  });

  group('a sport plays only within its own hours', () {
    test('a hall free from 16:00 gets nothing in the morning', () {
      final result = scheduler.schedule(
        matches: [
          for (var i = 0; i < 3; i++)
            match(
              'badminton',
              i,
              ['b${i}a', 'b${i}b'],
              availability: const EventAvailability(
                dayStartHour: 16,
                dayEndHour: 19,
              ),
            ),
        ],
        courts: hall,
        slots: slots(),
      );

      expect(result.placements, hasLength(3));
      for (final p in result.placements.values) {
        expect(p.window.start.hour, greaterThanOrEqualTo(16));
      }
    });

    test('a match that would run past closing is not started', () {
      // 90 minutes against a ground that shuts at 17:00: the last legal start
      // is 15:30, and 16:00 would leave a side on the field after the gate is
      // locked.
      final result = scheduler.schedule(
        matches: [
          match(
            'cricket',
            0,
            ['c1', 'c2'],
            minutes: 90,
            availability: const EventAvailability(
              dayStartHour: 15,
              dayEndHour: 17,
            ),
          ),
        ],
        courts: field,
        slots: slots(),
      );

      final placed = result.placements['cricket#0']!;
      expect(placed.window.end.hour, lessThanOrEqualTo(17));
      expect(placed.window.start.hour, 15);
    });

    test('an event given hours the day never reaches is told why', () {
      final result = scheduler.schedule(
        matches: [
          match(
            'chess',
            0,
            ['c1', 'c2'],
            availability: const EventAvailability(
              dayStartHour: 21,
              dayEndHour: 23,
            ),
          ),
        ],
        courts: hall,
        // The grid stops at 20:00, so nothing this event may use exists.
        slots: slots(closeHour: 20),
      );

      expect(result.placements, isEmpty);
      expect(
        result.unplaced.single.reason,
        contains('days and hours this event was given'),
      );
    });
  });

  group('the restriction is verified, not merely intended', () {
    test('a schedule respecting every event window passes the guarantees', () {
      final matches = [
        for (var i = 0; i < 3; i++)
          match('badminton', i, ['b${i}a', 'b${i}b'],
              availability: const EventAvailability(
                venueIds: {'hall'},
                dayStartHour: 16,
                dayEndHour: 20,
              )),
        for (var i = 0; i < 3; i++)
          match('cricket', i, ['c${i}a', 'c${i}b'],
              availability: const EventAvailability(venueIds: {'field'})),
      ];
      final schedule = scheduler.schedule(
        matches: matches,
        courts: [...hall, ...field],
        slots: slots(),
      );

      expect(
        ScheduleGuarantees.verify(
          matches: matches,
          schedule: schedule,
          minRestBetweenMatches: const Duration(minutes: 20),
        ),
        isEmpty,
      );
    });

    test('a match forced onto the wrong ground is caught', () {
      final wrong = match('badminton', 0, ['b1', 'b2'],
          availability: const EventAvailability(venueIds: {'hall'}));

      final violations = ScheduleGuarantees.verify(
        matches: [wrong],
        schedule: TournamentSchedule(
          placements: {
            wrong.key: Placement(
              court: field.single,
              window: ScheduleWindow(
                start: DateTime(2026, 9, 12, 10),
                end: DateTime(2026, 9, 12, 10, 30),
              ),
            ),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: const Duration(minutes: 20),
      );

      expect(violations, hasLength(1));
      expect(
        violations.single.kind,
        ScheduleViolationKind.outsideEventAvailability,
      );
      expect(violations.single.detail, contains('Main Field'));
    });

    test('a match forced outside its hours is caught', () {
      final wrong = match('badminton', 0, ['b1', 'b2'],
          availability:
              const EventAvailability(dayStartHour: 16, dayEndHour: 20));

      final violations = ScheduleGuarantees.verify(
        matches: [wrong],
        schedule: TournamentSchedule(
          placements: {
            wrong.key: Placement(
              court: hall.first,
              window: ScheduleWindow(
                start: DateTime(2026, 9, 12, 9),
                end: DateTime(2026, 9, 12, 9, 30),
              ),
            ),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: const Duration(minutes: 20),
      );

      expect(
        violations.single.kind,
        ScheduleViolationKind.outsideEventAvailability,
      );
    });
  });

  group('nothing changes for a season that said nothing', () {
    test('an unrestricted match still reaches every court and every slot', () {
      // Three separate draws, so nothing is serialised by the round barrier —
      // what is left is the greedy fill that existed before availability did.
      final result = scheduler.schedule(
        matches: [
          for (var i = 0; i < 3; i++) match('draw$i', 0, ['o${i}a', 'o${i}b']),
        ],
        courts: [...hall, ...field],
        slots: slots(),
      );

      expect(result.placements, hasLength(3));
      // All three at the earliest slot, one per court, across BOTH venues —
      // an unrestricted event is still offered every court in the pool.
      final starts = {
        for (final p in result.placements.values) p.window.start,
      };
      expect(starts, hasLength(1));
      expect(
        {for (final p in result.placements.values) p.court.venueId},
        {'hall', 'field'},
      );
    });

    test('EventAvailability.anywhere restricts nothing', () {
      const anywhere = EventAvailability.anywhere;
      expect(anywhere.isUnrestricted, isTrue);
      expect(anywhere.allowsCourt(field.single), isTrue);
      expect(
        anywhere.allowsWindow(ScheduleWindow(
          start: DateTime(2030, 1, 1, 3),
          end: DateTime(2030, 1, 1, 4),
        )),
        isTrue,
      );
    });
  });
}
