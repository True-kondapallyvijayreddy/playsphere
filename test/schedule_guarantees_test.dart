import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/draw/schedule_guarantees.dart';
import 'package:playsphere/domain/draw/tournament_scheduler.dart';

/// The five promises made to an organizer, checked against randomly generated
/// seasons rather than against one hand-picked example.
///
/// Hand-written cases prove the scheduler handles the situations somebody
/// thought of. The clash that ruins a Saturday is the one nobody thought of —
/// the player entered in four draws, the day with more matches than daylight,
/// the two venues that each named a court "Court 1". So the shape of the
/// season is generated, and the invariants are asserted over whatever comes
/// out.
void main() {
  group('schedule guarantees', () {
    /// A season: several events, players entered in more than one of them,
    /// a handful of courts, a couple of days.
    ({
      List<SchedulableMatch> matches,
      List<CourtRef> courts,
      List<ScheduleWindow> slots,
    }) randomSeason(Random rng) {
      final eventCount = 1 + rng.nextInt(6);
      final playerPool = List.generate(4 + rng.nextInt(30), (i) => 'p$i');

      final matches = <SchedulableMatch>[];
      for (var e = 0; e < eventCount; e++) {
        final compId = 'event$e';
        final rounds = 1 + rng.nextInt(3);
        var index = 0;
        for (var round = 1; round <= rounds; round++) {
          final inRound = 1 + rng.nextInt(6);
          for (var m = 0; m < inRound; m++) {
            // Two distinct people, drawn from a pool shared across events —
            // which is what makes cross-event conflicts possible at all.
            final a = playerPool[rng.nextInt(playerPool.length)];
            var b = playerPool[rng.nextInt(playerPool.length)];
            if (b == a) continue;
            matches.add(SchedulableMatch(
              compId: compId,
              matchIndex: index++,
              round: round,
              playerUids: {a, b},
              isGroupStage: round == 1 && rng.nextBool(),
              priority: rng.nextInt(3),
              matchMinutes: [20, 30, 45, 60][rng.nextInt(4)],
            ));
          }
        }
      }

      // Two venues that both call a court "Court 1", on purpose: a bare court
      // name cannot tell them apart, and a scheduler that keys on one will
      // happily book both halls at once.
      final courts = <CourtRef>[];
      for (var v = 0; v < 1 + rng.nextInt(2); v++) {
        for (var c = 0; c < 1 + rng.nextInt(4); c++) {
          courts.add(CourtRef(
            venueId: 'venue$v',
            venueName: 'Venue $v',
            courtId: 'court$c',
            courtName: 'Court ${c + 1}',
          ));
        }
      }

      final slots = TournamentScheduler.buildSlots(
        firstDay: DateTime(2026, 3, 7),
        dayCount: 1 + rng.nextInt(2),
        openHour: 8,
        closeHour: 18,
        slotMinutes: 15 + rng.nextInt(4) * 15,
      );

      return (matches: matches, courts: courts, slots: slots);
    }

    test('no schedule over 300 random seasons ever breaks a guarantee', () {
      final rng = Random(20260315);
      var totalPlaced = 0;

      for (var run = 0; run < 300; run++) {
        final season = randomSeason(rng);
        final minRest = Duration(minutes: [0, 10, 20, 45][rng.nextInt(4)]);

        final schedule = const TournamentScheduler().schedule(
          matches: season.matches,
          courts: season.courts,
          slots: season.slots,
          minRestBetweenMatches: minRest,
        );
        totalPlaced += schedule.placements.length;

        final violations = ScheduleGuarantees.verify(
          matches: season.matches,
          schedule: schedule,
          minRestBetweenMatches: minRest,
        );

        expect(
          violations,
          isEmpty,
          reason: 'run $run with ${season.matches.length} matches, '
              '${season.courts.length} courts, rest ${minRest.inMinutes}m '
              'produced: ${violations.join(' | ')}',
        );
      }

      // Guards the test itself: a scheduler that placed nothing would satisfy
      // every invariant above and prove nothing at all.
      expect(totalPlaced, greaterThan(1000));
    });

    test('regenerating the same season gives the identical schedule', () {
      final season = randomSeason(Random(7));
      const rest = Duration(minutes: 20);

      final first = const TournamentScheduler().schedule(
        matches: season.matches,
        courts: season.courts,
        slots: season.slots,
        minRestBetweenMatches: rest,
      );
      final second = const TournamentScheduler().schedule(
        matches: season.matches,
        courts: season.courts,
        slots: season.slots,
        minRestBetweenMatches: rest,
      );

      expect(second.placements.length, first.placements.length);
      for (final key in first.placements.keys) {
        expect(second.placements[key]!.court.key,
            first.placements[key]!.court.key);
        expect(second.placements[key]!.window.start,
            first.placements[key]!.window.start);
      }
    });
  });

  group('the verifier actually catches things', () {
    // A verifier that never fails is worth nothing, so each violation is
    // constructed deliberately and the check is asserted to find it.
    const court = CourtRef(
      venueId: 'v',
      venueName: 'Hall',
      courtId: 'c1',
      courtName: 'Court 1',
    );
    const other = CourtRef(
      venueId: 'v',
      venueName: 'Hall',
      courtId: 'c2',
      courtName: 'Court 2',
    );

    ScheduleWindow at(int hour, int minute, int mins) => ScheduleWindow(
          start: DateTime(2026, 3, 7, hour, minute),
          end: DateTime(2026, 3, 7, hour, minute).add(Duration(minutes: mins)),
        );

    test('catches a double-booked court', () {
      final matches = [
        const SchedulableMatch(
            compId: 'e', matchIndex: 0, round: 1, playerUids: {'a', 'b'}),
        const SchedulableMatch(
            compId: 'e', matchIndex: 1, round: 1, playerUids: {'c', 'd'}),
      ];
      final violations = ScheduleGuarantees.verify(
        matches: matches,
        schedule: TournamentSchedule(
          placements: {
            'e#0': Placement(court: court, window: at(9, 0, 30)),
            'e#1': Placement(court: court, window: at(9, 15, 30)),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: Duration.zero,
      );
      expect(violations.map((v) => v.kind),
          contains(ScheduleViolationKind.courtDoubleBooked));
    });

    test('catches one person on two courts at once', () {
      final matches = [
        const SchedulableMatch(
            compId: 'singles', matchIndex: 0, round: 1, playerUids: {'a', 'b'}),
        // Same person, different event — the case a per-event scheduler
        // cannot see at all.
        const SchedulableMatch(
            compId: 'doubles', matchIndex: 0, round: 1, playerUids: {'a', 'c'}),
      ];
      final violations = ScheduleGuarantees.verify(
        matches: matches,
        schedule: TournamentSchedule(
          placements: {
            'singles#0': Placement(court: court, window: at(9, 0, 30)),
            'doubles#0': Placement(court: other, window: at(9, 10, 30)),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: Duration.zero,
      );
      expect(violations.map((v) => v.kind),
          contains(ScheduleViolationKind.playerDoubleBooked));
    });

    test('catches a rest gap shorter than promised', () {
      final matches = [
        const SchedulableMatch(
            compId: 'e', matchIndex: 0, round: 1, playerUids: {'a', 'b'}),
        const SchedulableMatch(
            compId: 'e', matchIndex: 1, round: 2, playerUids: {'a', 'c'}),
      ];
      final violations = ScheduleGuarantees.verify(
        matches: matches,
        schedule: TournamentSchedule(
          placements: {
            'e#0': Placement(court: court, window: at(9, 0, 30)),
            // Five minutes later, against a promised twenty.
            'e#1': Placement(court: other, window: at(9, 35, 30)),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: const Duration(minutes: 20),
      );
      expect(violations.map((v) => v.kind),
          contains(ScheduleViolationKind.restGapTooShort));
    });

    test('catches a semi-final placed before its quarter-final finishes', () {
      final matches = [
        const SchedulableMatch(
            compId: 'e', matchIndex: 0, round: 1, playerUids: {'a', 'b'}),
        const SchedulableMatch(
            compId: 'e', matchIndex: 1, round: 2, playerUids: {'c', 'd'}),
      ];
      final violations = ScheduleGuarantees.verify(
        matches: matches,
        schedule: TournamentSchedule(
          placements: {
            'e#0': Placement(court: court, window: at(11, 0, 60)),
            'e#1': Placement(court: other, window: at(10, 0, 30)),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: Duration.zero,
      );
      expect(violations.map((v) => v.kind),
          contains(ScheduleViolationKind.roundOutOfOrder));
    });

    test('a group match and a knockout match do not fake a round conflict', () {
      // Both phases number rounds from 1. Comparing across them would report
      // a group round-2 match as starting "before" knockout round 1.
      final matches = [
        const SchedulableMatch(
          compId: 'e',
          matchIndex: 0,
          round: 1,
          playerUids: {'a', 'b'},
          isGroupStage: true,
        ),
        const SchedulableMatch(
          compId: 'e',
          matchIndex: 1,
          round: 1,
          playerUids: {'c', 'd'},
        ),
      ];
      final violations = ScheduleGuarantees.verify(
        matches: matches,
        schedule: TournamentSchedule(
          placements: {
            'e#0': Placement(court: court, window: at(9, 0, 30)),
            'e#1': Placement(court: other, window: at(9, 0, 30)),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: Duration.zero,
      );
      expect(violations, isEmpty);
    });
  });
}
