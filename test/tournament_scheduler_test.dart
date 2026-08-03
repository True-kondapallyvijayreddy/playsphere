import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/draw/tournament_scheduler.dart';

/// The constraint that only exists above a single draw: one person entered in
/// singles, doubles and mixed is three different `Entrant`s and one human, and
/// a per-draw scheduler keyed on entrant id will put them on two courts at the
/// same minute and see nothing wrong.
void main() {
  const scheduler = TournamentScheduler();

  final day = DateTime(2026, 9, 12);

  List<CourtRef> courts(int n, {String venue = 'v1'}) => [
        for (var i = 1; i <= n; i++)
          CourtRef(
            venueId: venue,
            venueName: 'Hall',
            courtId: 'c$i',
            courtName: 'Court $i',
          ),
      ];

  List<ScheduleWindow> slots({int hours = 8}) =>
      TournamentScheduler.buildSlots(
        firstDay: day,
        dayCount: 1,
        openHour: 9,
        closeHour: 9 + hours,
        slotMinutes: 30,
      );

  SchedulableMatch match(
    String compId,
    int index,
    List<String> uids, {
    int round = 1,
    bool group = false,
    int priority = 0,
    int minutes = 30,
  }) =>
      SchedulableMatch(
        compId: compId,
        matchIndex: index,
        round: round,
        playerUids: uids.toSet(),
        isGroupStage: group,
        priority: priority,
        matchMinutes: minutes,
      );

  group('courts are shared across events', () {
    test('two events cannot both take the only court at once', () {
      final result = scheduler.schedule(
        matches: [
          match('singles', 0, ['p1', 'p2']),
          match('doubles', 0, ['p3', 'p4']),
        ],
        courts: courts(1),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      expect(result.isComplete, isTrue);
      final a = result.placements['singles#0']!;
      final b = result.placements['doubles#0']!;
      expect(
        a.window.overlaps(b.window),
        isFalse,
        reason: 'scheduling each draw on its own is what produces two matches '
            'called to the same court at the same time',
      );
    });

    test('two courts run two events simultaneously', () {
      final result = scheduler.schedule(
        matches: [
          match('singles', 0, ['p1', 'p2']),
          match('doubles', 0, ['p3', 'p4']),
        ],
        courts: courts(2),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      final a = result.placements['singles#0']!;
      final b = result.placements['doubles#0']!;
      expect(a.window.start, b.window.start);
      expect(a.court.key, isNot(b.court.key));
    });

    test('the same court name at two venues is two different courts', () {
      final twoVenues = [
        const CourtRef(
          venueId: 'v1',
          venueName: 'School Hall',
          courtId: 'c1',
          courtName: 'Court 1',
        ),
        const CourtRef(
          venueId: 'v2',
          venueName: 'Stadium',
          courtId: 'c1',
          courtName: 'Court 1',
        ),
      ];
      expect(twoVenues[0].key, isNot(twoVenues[1].key));

      final result = scheduler.schedule(
        matches: [
          match('a', 0, ['p1', 'p2']),
          match('b', 0, ['p3', 'p4']),
        ],
        courts: twoVenues,
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );
      // Both can run at once precisely because they are different courts.
      expect(
        result.placements['a#0']!.window.start,
        result.placements['b#0']!.window.start,
      );
    });
  });

  group('players are shared across events', () {
    test('one player in two draws is never on two courts at once', () {
      // p1 is in the singles and the doubles. Plenty of courts — the
      // constraint is the person, not the room.
      final result = scheduler.schedule(
        matches: [
          match('singles', 0, ['p1', 'p2']),
          match('doubles', 0, ['p1', 'p3']),
        ],
        courts: courts(6),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      expect(result.isComplete, isTrue);
      final a = result.placements['singles#0']!;
      final b = result.placements['doubles#0']!;
      expect(a.window.overlaps(b.window), isFalse);
    });

    test('the rest gap is honoured between draws, not just within one', () {
      final result = scheduler.schedule(
        matches: [
          match('singles', 0, ['p1', 'p2']),
          match('mixed', 0, ['p1', 'p9']),
        ],
        courts: courts(6),
        slots: slots(),
        minRestBetweenMatches: const Duration(minutes: 45),
      );

      final a = result.placements['singles#0']!;
      final b = result.placements['mixed#0']!;
      final gap = a.window.gapTo(b.window);
      expect(
        gap >= const Duration(minutes: 45),
        isTrue,
        reason: 'a player must not be called straight from one event to '
            'another; got $gap',
      );
    });

    test('a player in three draws gets three separated matches', () {
      final result = scheduler.schedule(
        matches: [
          match('singles', 0, ['p1', 'a']),
          match('doubles', 0, ['p1', 'b']),
          match('mixed', 0, ['p1', 'c']),
        ],
        courts: courts(6),
        slots: slots(),
        minRestBetweenMatches: const Duration(minutes: 20),
      );

      expect(result.isComplete, isTrue);
      final windows = [
        result.placements['singles#0']!.window,
        result.placements['doubles#0']!.window,
        result.placements['mixed#0']!.window,
      ];
      for (var i = 0; i < windows.length; i++) {
        for (var j = i + 1; j < windows.length; j++) {
          expect(windows[i].overlaps(windows[j]), isFalse);
        }
      }
    });

    test('an over-entered player is reported, with a reason that helps', () {
      // One court, one hour, three matches all containing p1: impossible.
      final result = scheduler.schedule(
        matches: [
          match('e1', 0, ['p1', 'a']),
          match('e2', 0, ['p1', 'b']),
          match('e3', 0, ['p1', 'c']),
        ],
        courts: courts(1),
        slots: TournamentScheduler.buildSlots(
          firstDay: day,
          dayCount: 1,
          openHour: 9,
          closeHour: 10,
          slotMinutes: 30,
        ),
        minRestBetweenMatches: const Duration(minutes: 60),
      );

      expect(result.unplaced, isNotEmpty);
      expect(result.unplaced.first.reason, contains('rest gap'));
    });
  });

  group('ordering within and between draws', () {
    test('a later round never starts before the round feeding it ends', () {
      final result = scheduler.schedule(
        matches: [
          match('ko', 0, ['p1', 'p2']),
          match('ko', 1, ['p3', 'p4']),
          match('ko', 2, ['p1', 'p3'], round: 2),
        ],
        courts: courts(4),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      final semiEnds = [
        result.placements['ko#0']!.window.end,
        result.placements['ko#1']!.window.end,
      ];
      final finalStart = result.placements['ko#2']!.window.start;
      for (final end in semiEnds) {
        expect(finalStart.isBefore(end), isFalse);
      }
    });

    test('group matches are placed before the knockout that follows', () {
      final result = scheduler.schedule(
        matches: [
          match('gk', 10, ['p1', 'p3'], round: 1),
          match('gk', 0, ['p1', 'p2'], round: 1, group: true),
        ],
        courts: courts(1),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      // Both rounds are 1 — only the group flag can order them correctly.
      expect(
        result.placements['gk#0']!.window.start
            .isBefore(result.placements['gk#10']!.window.start),
        isTrue,
      );
    });

    test('priority puts the under-13s on court first', () {
      // The real constraint: finish the children's events before lunch.
      final result = scheduler.schedule(
        matches: [
          match('senior', 0, ['s1', 's2'], priority: 5),
          match('u13', 0, ['k1', 'k2'], priority: 0),
        ],
        courts: courts(1),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      expect(
        result.placements['u13#0']!.window.start
            .isBefore(result.placements['senior#0']!.window.start),
        isTrue,
      );
    });

    test('scheduling is deterministic — the same input gives the same day',
        () {
      List<SchedulableMatch> input() => [
            match('b', 1, ['p3', 'p4']),
            match('a', 0, ['p1', 'p2']),
            match('a', 1, ['p5', 'p6']),
          ];
      final first = scheduler.schedule(
        matches: input(),
        courts: courts(2),
        slots: slots(),
      );
      final second = scheduler.schedule(
        matches: input(),
        courts: courts(2),
        slots: slots(),
      );

      for (final key in first.placements.keys) {
        expect(
          second.placements[key]!.window.start,
          first.placements[key]!.window.start,
          reason: 'an organizer has to be able to explain why a match moved',
        );
      }
    });
  });

  group('honest failure', () {
    test('no courts is reported as needing a venue, not as a crash', () {
      final result = scheduler.schedule(
        matches: [match('a', 0, ['p1', 'p2'])],
        courts: const [],
        slots: slots(),
      );
      expect(result.placements, isEmpty);
      expect(result.unplaced.single.reason, contains('venue'));
    });

    test('an undecided placeholder waits rather than failing', () {
      final result = scheduler.schedule(
        matches: [match('ko', 5, const [], round: 3)],
        courts: courts(2),
        slots: slots(),
      );
      expect(result.unplaced.single.reason, contains('Waiting on an earlier'));
    });

    test('a longer match consumes the time it actually needs', () {
      final result = scheduler.schedule(
        matches: [
          match('final', 0, ['p1', 'p2'], minutes: 90),
          match('final', 1, ['p1', 'p3'], round: 2),
        ],
        courts: courts(1),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );

      final first = result.placements['final#0']!;
      expect(first.window.end.difference(first.window.start).inMinutes, 90);
      expect(
        result.placements['final#1']!.window.start.isBefore(first.window.end),
        isFalse,
      );
    });

    test('finishesAt reports when the day actually ends', () {
      final result = scheduler.schedule(
        matches: [
          for (var i = 0; i < 4; i++) match('a', i, ['p$i', 'q$i']),
        ],
        courts: courts(1),
        slots: slots(),
        minRestBetweenMatches: Duration.zero,
      );
      // Four 30-minute matches on one court from 09:00.
      expect(result.finishesAt, DateTime(2026, 9, 12, 11, 0));
    });
  });

  group('slot grid', () {
    test('a day stops at closing time and resumes the next morning', () {
      final grid = TournamentScheduler.buildSlots(
        firstDay: day,
        dayCount: 2,
        openHour: 9,
        closeHour: 12,
        slotMinutes: 60,
      );
      expect(grid.length, 6);
      expect(grid[2].end, DateTime(2026, 9, 12, 12));
      expect(
        grid[3].start,
        DateTime(2026, 9, 13, 9),
        reason: 'a match must not be scheduled overnight just because the '
            'arithmetic allowed it',
      );
    });

    test('a nonsensical window produces no slots rather than throwing', () {
      expect(
        TournamentScheduler.buildSlots(
          firstDay: day,
          dayCount: 1,
          openHour: 18,
          closeHour: 9,
          slotMinutes: 30,
        ),
        isEmpty,
      );
    });
  });
}
