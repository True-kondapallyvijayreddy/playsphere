import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/venue.dart';
import 'package:playsphere/core/models/venue_plan.dart';
import 'package:playsphere/domain/draw/match_count.dart';
import 'package:playsphere/domain/draw/schedule_guarantees.dart';
import 'package:playsphere/domain/draw/season_capacity.dart';
import 'package:playsphere/domain/draw/tournament_scheduler.dart';

/// The season the plan describes: a cricket ground open 08:00–20:00 with
/// three-hour matches, and a table-tennis hall of six tables running 45-minute
/// matches across a morning and an evening session.
Venue _ground({
  String id = 'ground',
  String name = 'Narsingi Cricket Ground',
  int courts = 1,
  int open = 8,
  int close = 20,
}) =>
    Venue(
      id: id,
      orgId: 'org',
      name: name,
      openHour: open,
      closeHour: close,
      courts: [
        for (var i = 1; i <= courts; i++)
          Court(id: 'c$i', name: 'Area $i'),
      ],
    );

final _june10 = DateTime(2026, 6, 10);

SchedulableMatch _match({
  required String comp,
  required int index,
  Set<String> players = const {'p1', 'p2'},
  Set<String> teams = const {},
  String sportId = '',
  int minutes = 180,
  int round = 1,
  EventAvailability availability = EventAvailability.anywhere,
}) =>
    SchedulableMatch(
      compId: comp,
      matchIndex: index,
      round: round,
      playerUids: players,
      teamKeys: teams,
      sportId: sportId,
      matchMinutes: minutes,
      availability: availability,
    );

void main() {
  group('capacity is computed, never taken on trust', () {
    test('an 8am-8pm day with 3h matches and 30m turnaround holds three', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground()],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
        },
      );

      expect(calendars, hasLength(1));
      expect(
        calendars.single.capacity(matchMinutes: 180, turnaroundMinutes: 30),
        3,
      );
    });

    test('an organiser limit of 4 against a day that holds 3 reports both', () {
      final line = SeasonCapacity.lineFor(
        venue: _ground(),
        plan: const VenuePlan(
          venueId: 'ground',
          matchMinutes: 180,
          turnaroundMinutes: 30,
          maxMatchesPerCourtPerDay: 4,
        ),
        seasonStart: _june10,
        dayCount: 1,
      );

      expect(line.organiserLimitPerCourtPerDay, 4);
      expect(line.computedPerCourtPerDay, 3);
      // The stricter of the two is what a schedule is built against.
      expect(line.effectivePerCourtPerDay, 3);
      expect(line.limitExceedsReality, isTrue);
    });

    test('an organiser limit BELOW what fits is the one that is used', () {
      final line = SeasonCapacity.lineFor(
        venue: _ground(),
        plan: const VenuePlan(
          venueId: 'ground',
          matchMinutes: 180,
          turnaroundMinutes: 30,
          maxMatchesPerCourtPerDay: 2,
        ),
        seasonStart: _june10,
        dayCount: 1,
      );

      expect(line.computedPerCourtPerDay, 3);
      expect(line.effectivePerCourtPerDay, 2);
      expect(line.limitExceedsReality, isFalse);
    });

    test('six tables are six simultaneous resources, not one', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground(id: 'hall', name: 'TT Hall', courts: 6, open: 9, close: 21)],
        plans: {
          'hall': const VenuePlan(
            venueId: 'hall',
            matchMinutes: 45,
            turnaroundMinutes: 15,
          ),
        },
      );

      expect(calendars, hasLength(6));
      for (final c in calendars) {
        expect(c.capacity(matchMinutes: 45, turnaroundMinutes: 15), 12);
      }
    });

    test('a feasible season is green and an impossible one names the gap', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 6,
        venues: [_ground()],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
        },
      );
      final keys = {for (final c in calendars) c.court.key};

      final fits = SeasonCapacity.assess(
        calendars: calendars,
        demands: [
          EventDemand(
            compId: 'cricket',
            label: 'Cricket',
            matchesRequired: 15,
            eligibleCourtKeys: keys,
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
        ],
      );
      expect(fits.isFeasible, isTrue);
      expect(fits.totalCapacity, 18);

      final doesNot = SeasonCapacity.assess(
        calendars: calendars,
        demands: [
          EventDemand(
            compId: 'cricket',
            label: 'Cricket',
            matchesRequired: 45,
            eligibleCourtKeys: keys,
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
        ],
      );
      expect(doesNot.isFeasible, isFalse);
      expect(doesNot.shortfall, 45 - 18);
      expect(doesNot.suggestions, isNotEmpty);
      expect(doesNot.problems.join(' '), contains('45'));
    });

    test('two events sharing one ground are caught, though each alone fits',
        () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 2,
        venues: [_ground()],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
        },
      );
      final keys = {for (final c in calendars) c.court.key};

      final report = SeasonCapacity.assess(
        calendars: calendars,
        demands: [
          EventDemand(
            compId: 'a',
            label: 'Cricket A',
            matchesRequired: 5,
            eligibleCourtKeys: keys,
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
          EventDemand(
            compId: 'b',
            label: 'Cricket B',
            matchesRequired: 5,
            eligibleCourtKeys: keys,
            matchMinutes: 180,
            turnaroundMinutes: 30,
          ),
        ],
      );

      // Six slots over two days; each event of five fits on its own.
      expect(report.perEvent.every((e) => e.fits), isTrue);
      // Ten between them do not.
      expect(report.isFeasible, isFalse);
      expect(report.problems.join(' '), contains('share the same grounds'));
    });
  });

  group('a venue is only open when it says it is', () {
    test('a blacked-out day offers no slots on it', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 4,
        venues: [_ground()],
        plans: {
          'ground': VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
            blackouts: [VenueBlackout(date: DateTime(2026, 6, 12))],
          ),
        },
      );

      final days = calendars.single.slotStarts.map((d) => d.day).toSet();
      expect(days, {10, 11, 13});
    });

    test('a part-day blackout removes only the hours it covers', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground()],
        plans: {
          'ground': VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
            blackouts: [
              VenueBlackout(
                date: _june10,
                startMinute: 14 * 60,
                endMinute: 17 * 60,
              ),
            ],
          ),
        },
      );

      // The day is cut into 08:00–14:00 and 17:00–20:00. Each holds one
      // three-hour match — the second start in the morning piece would be
      // 11:30 and would run to 14:30, into the blackout — so nothing is
      // offered inside the closed hours, and nothing straddles them.
      final hours = calendars.single.slotStarts.map((d) => d.hour).toList();
      expect(hours, [8, 17]);
    });

    test('two sessions with a lunch break between them place nothing at 13:00',
        () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground(id: 'hall', name: 'Hall', courts: 1)],
        plans: {
          'hall': const VenuePlan(
            venueId: 'hall',
            matchMinutes: 45,
            turnaroundMinutes: 15,
            sessions: [
              DaySession(startMinute: 8 * 60, endMinute: 12 * 60),
              DaySession(startMinute: 14 * 60, endMinute: 19 * 60),
            ],
          ),
        },
      );

      final hours = calendars.single.slotStarts.map((d) => d.hour).toSet();
      expect(hours.contains(12), isFalse);
      expect(hours.contains(13), isFalse);
      expect(hours.contains(8), isTrue);
      expect(hours.contains(14), isTrue);
    });

    test('a match that would overrun a session is not started in it', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground()],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
            sessions: [DaySession(startMinute: 8 * 60, endMinute: 12 * 60)],
          ),
        },
      );

      // 08:00 fits (ends 11:00). 11:30 would end at 14:30 and is not offered.
      expect(calendars.single.slotStarts.map((d) => d.hour), [8]);
      expect(
        calendars.single.admits(ScheduleWindow(
          start: DateTime(2026, 6, 10, 11, 30),
          end: DateTime(2026, 6, 10, 14, 30),
        )),
        isFalse,
      );
    });

    test('a ground lent to cricket refuses a badminton draw', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground()],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            sportIds: {'cricket'},
            matchMinutes: 60,
            turnaroundMinutes: 0,
          ),
        },
      );

      final schedule = const TournamentScheduler().schedule(
        matches: [
          _match(comp: 'badminton', index: 1, sportId: 'badminton', minutes: 60),
        ],
        calendars: calendars,
      );

      expect(schedule.placements, isEmpty);
      expect(schedule.unplaced.single.reason, contains('no usable'));
    });
  });

  group('the scheduler respects what the venue plan says', () {
    test('a daily maximum of two leaves the third match for the next day', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 3,
        venues: [_ground()],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            matchMinutes: 180,
            turnaroundMinutes: 30,
            maxMatchesPerCourtPerDay: 2,
          ),
        },
      );

      final matches = [
        for (var i = 1; i <= 3; i++)
          _match(comp: 'cricket', index: i, players: {'a$i', 'b$i'}),
      ];
      final schedule = const TournamentScheduler().schedule(
        matches: matches,
        calendars: calendars,
      );

      expect(schedule.placements, hasLength(3));
      final firstDay = schedule.placements.values
          .where((p) => p.window.start.day == 10)
          .length;
      expect(firstDay, 2, reason: 'the ceiling the organiser set is a rule');

      expect(
        ScheduleGuarantees.verify(
          matches: matches,
          schedule: schedule,
          minRestBetweenMatches: const Duration(minutes: 20),
          calendars: calendars,
        ),
        isEmpty,
      );
    });

    test('a person moving venues is owed rest plus travel', () {
      final venues = [
        _ground(id: 'g', name: 'Ground', open: 8, close: 20),
        _ground(id: 'h', name: 'Hall', open: 8, close: 20),
      ];
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: venues,
        plans: {
          'g': const VenuePlan(
            venueId: 'g',
            matchMinutes: 60,
            turnaroundMinutes: 0,
          ),
          'h': const VenuePlan(
            venueId: 'h',
            matchMinutes: 60,
            turnaroundMinutes: 0,
          ),
        },
      );

      final matches = [
        _match(comp: 'cricket', index: 1, players: {'rahul'}, minutes: 60),
        _match(comp: 'tt', index: 1, players: {'rahul'}, minutes: 60),
      ];

      final schedule = const TournamentScheduler().schedule(
        matches: matches,
        calendars: calendars,
        minRestBetweenMatches: const Duration(minutes: 30),
        venueTransition: const Duration(minutes: 20),
      );

      expect(schedule.placements, hasLength(2));
      final windows = schedule.placements.values.toList()
        ..sort((a, b) => a.window.start.compareTo(b.window.start));
      final gap = windows[1].window.start.difference(windows[0].window.end);

      // Same venue would only owe 30 minutes; a different one owes 50.
      final sameVenue =
          windows[0].court.venueId == windows[1].court.venueId;
      expect(gap.inMinutes, greaterThanOrEqualTo(sameVenue ? 30 : 50));

      expect(
        ScheduleGuarantees.verify(
          matches: matches,
          schedule: schedule,
          minRestBetweenMatches: const Duration(minutes: 30),
          calendars: calendars,
          venueTransition: const Duration(minutes: 20),
        ),
        isEmpty,
      );
    });

    test('one team is never in two matches at once, whatever the line-ups', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 2,
        venues: [_ground(courts: 3)],
        plans: {
          'ground': const VenuePlan(
            venueId: 'ground',
            matchMinutes: 60,
            turnaroundMinutes: 0,
          ),
        },
      );

      // Deliberately disjoint squads: eleven of sixteen play, and the two
      // line-ups share nobody. Only the team identity can catch this.
      final matches = [
        _match(
          comp: 'league',
          index: 1,
          players: {'x1', 'x2'},
          teams: {'teamA'},
          minutes: 60,
        ),
        _match(
          comp: 'league',
          index: 2,
          players: {'y1', 'y2'},
          teams: {'teamA'},
          minutes: 60,
        ),
      ];

      final schedule = const TournamentScheduler().schedule(
        matches: matches,
        calendars: calendars,
        minRestBetweenMatches: Duration.zero,
      );

      expect(schedule.placements, hasLength(2));
      final windows = schedule.placements.values.toList();
      expect(windows[0].window.overlaps(windows[1].window), isFalse);
    });

    test('the verifier catches a team double-booked by hand', () {
      final matches = [
        _match(comp: 'l', index: 1, players: {'x'}, teams: {'teamA'}, minutes: 60),
        _match(comp: 'l', index: 2, players: {'y'}, teams: {'teamA'}, minutes: 60),
      ];
      const courtA = CourtRef(
        venueId: 'g',
        venueName: 'Ground',
        courtId: 'c1',
        courtName: 'A',
      );
      const courtB = CourtRef(
        venueId: 'g',
        venueName: 'Ground',
        courtId: 'c2',
        courtName: 'B',
      );
      final at9 = ScheduleWindow(
        start: DateTime(2026, 6, 10, 9),
        end: DateTime(2026, 6, 10, 10),
      );

      final violations = ScheduleGuarantees.verify(
        matches: matches,
        schedule: TournamentSchedule(
          placements: {
            'l#1': Placement(court: courtA, window: at9),
            'l#2': Placement(court: courtB, window: at9),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: Duration.zero,
      );

      expect(
        violations.map((v) => v.kind),
        contains(ScheduleViolationKind.teamDoubleBooked),
      );
    });

    test('a match forced into a blackout is caught by the verifier', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 1,
        venues: [_ground()],
        plans: {
          'ground': VenuePlan(
            venueId: 'ground',
            matchMinutes: 60,
            turnaroundMinutes: 0,
            blackouts: [
              VenueBlackout(
                date: _june10,
                startMinute: 14 * 60,
                endMinute: 17 * 60,
              ),
            ],
          ),
        },
      );

      final match = _match(comp: 'c', index: 1, minutes: 60);
      final violations = ScheduleGuarantees.verify(
        matches: [match],
        schedule: TournamentSchedule(
          placements: {
            'c#1': Placement(
              court: calendars.single.court,
              window: ScheduleWindow(
                start: DateTime(2026, 6, 10, 15),
                end: DateTime(2026, 6, 10, 16),
              ),
            ),
          },
          unplaced: const [],
        ),
        minRestBetweenMatches: Duration.zero,
        calendars: calendars,
      );

      expect(
        violations.map((v) => v.kind),
        contains(ScheduleViolationKind.outsideVenueAvailability),
      );
    });
  });

  group('a draw\'s size is known before it is drawn', () {
    test('ten teams, round robin', () {
      expect(
        MatchCount.forDraw(
          format: CompetitionFormat.roundRobin,
          config: const DrawConfig(),
          entrants: 10,
        ),
        45,
      );
    });

    test('ten players, knockout', () {
      expect(
        MatchCount.forDraw(
          format: CompetitionFormat.knockout,
          config: const DrawConfig(),
          entrants: 10,
        ),
        9,
      );
    });

    test('groups then knockout counts both phases', () {
      // Ten teams in two groups of five: 10 + 10 group matches, then four
      // qualifiers producing three knockout ties.
      expect(
        MatchCount.forDraw(
          format: CompetitionFormat.groupThenKnockout,
          config: const DrawConfig(numGroups: 2, qualifiersPerGroup: 2),
          entrants: 10,
        ),
        23,
      );
    });

    test('uneven groups are counted as they are actually dealt', () {
      // Seven into two groups is 4 and 3 — 6 + 3 matches, not 2 × 4.5.
      expect(
        MatchCount.forDraw(
          format: CompetitionFormat.roundRobin,
          config: const DrawConfig(useGroups: true, numGroups: 2),
          entrants: 7,
        ),
        9,
      );
    });

    test('a field too small to play anybody needs no matches', () {
      expect(
        MatchCount.forDraw(
          format: CompetitionFormat.knockout,
          config: const DrawConfig(),
          entrants: 1,
        ),
        0,
      );
    });
  });

  group('nothing changes for a season that never opened the planner', () {
    test('a venue with no plan is open its own hours, every day', () {
      final calendars = SeasonCapacity.buildCalendars(
        seasonStart: _june10,
        dayCount: 2,
        venues: [_ground(open: 9, close: 19)],
        defaultMatchMinutes: 30,
        defaultTurnaroundMinutes: 5,
      );

      expect(calendars, hasLength(1));
      expect(calendars.single.maxPerDay, 0);
      expect(calendars.single.sportIds, isEmpty);
      final hours = calendars.single.slotStarts.map((d) => d.hour);
      expect(hours.reduce((a, b) => a < b ? a : b), 9);
      expect(hours.reduce((a, b) => a > b ? a : b), lessThan(19));
    });

    test('the uniform slot grid still schedules exactly as it did', () {
      const court = CourtRef(
        venueId: 'v',
        venueName: 'V',
        courtId: 'c',
        courtName: 'C',
      );
      final slots = TournamentScheduler.buildSlots(
        firstDay: _june10,
        dayCount: 1,
        openHour: 9,
        closeHour: 12,
        slotMinutes: 30,
      );

      final schedule = const TournamentScheduler().schedule(
        matches: [
          _match(comp: 'a', index: 1, players: {'p'}, minutes: 30),
          _match(comp: 'a', index: 2, players: {'q'}, minutes: 30),
        ],
        courts: const [court],
        slots: slots,
      );

      expect(schedule.placements, hasLength(2));
      expect(schedule.isComplete, isTrue);
    });
  });
}
