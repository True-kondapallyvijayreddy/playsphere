import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/tournament_official.dart';
import 'package:playsphere/core/models/venue.dart';
import 'package:playsphere/core/models/venue_plan.dart';
import 'package:playsphere/domain/draw/draft_season_plan.dart';
import 'package:playsphere/domain/draw/match_duration.dart';
import 'package:playsphere/domain/draw/officials_coverage.dart';

/// The Play Store complaint these were written from, stated as a test: an
/// organizer with twelve cricket matches added four grounds, found out only
/// after generating a timetable that it did not fit, went back and added a
/// fifth. Every number needed to answer that was on the form before anything
/// was written, so the answer has to be available there.
void main() {
  SeasonGround ground(
    String id, {
    int openHour = 9,
    int closeHour = 18,
    int courts = 1,
    List<DaySession> sessions = const [],
  }) =>
      SeasonGround(
        venue: Venue(
          id: id,
          orgId: 'org',
          name: id,
          openHour: openHour,
          closeHour: closeHour,
          courts: [
            for (var i = 0; i < courts; i++)
              Court(id: '$id-$i', name: 'Pitch ${i + 1}'),
          ],
        ),
        plan: VenuePlan(venueId: id, sessions: sessions),
      );

  SeasonEventPlan cricket({int entrants = 13, Set<String> grounds = const {}}) =>
      SeasonEventPlan(
        key: 'cricket-open',
        label: 'Cricket Open',
        sportId: 'cricket',
        entrants: entrants,
        format: CompetitionFormat.knockout,
        matchMinutes: MatchDuration.estimate(sportId: 'cricket'),
        groundIds: grounds,
      );

  final start = DateTime(2026, 10, 1);

  group('MatchDuration', () {
    test('a T20 is three and a quarter hours, not the old flat thirty', () {
      // The number that made every cricket season impossible: 30 minutes.
      expect(MatchDuration.estimate(sportId: 'cricket'), 195);
      expect(
        MatchDuration.explain(sportId: 'cricket'),
        contains('20 overs a side'),
      );
    });

    test('the ruleset drives it, so a shorter format costs less ground', () {
      final t20 = MatchDuration.estimate(sportId: 'cricket');
      final t10 = MatchDuration.estimate(
        sportId: 'cricket',
        rules: const {'oversPerInnings': 10},
      );
      final odi = MatchDuration.estimate(
        sportId: 'cricket',
        rules: const {'oversPerInnings': 50},
      );
      expect(t10, lessThan(t20));
      expect(odi, greaterThan(t20));
    });

    test('every catalogue sport gets a usable, bounded answer', () {
      for (final sportId in const [
        'cricket', 'badminton', 'football', 'hockey', 'kabaddi', 'kho_kho',
        'basketball', 'volleyball', 'table_tennis', 'tennis', 'chess',
        'carrom', 'squash', 'pickleball', 'padel', 'athletics_sprint',
      ]) {
        final minutes = MatchDuration.estimate(sportId: sportId);
        expect(minutes, greaterThanOrEqualTo(MatchDuration.minMinutes),
            reason: sportId);
        expect(minutes, lessThanOrEqualTo(MatchDuration.maxMinutes),
            reason: sportId);
        // Round numbers, because a slot grid built on 187 is unreadable.
        expect(minutes % 5, 0, reason: sportId);
      }
    });

    test('a badminton court turns over far faster than a cricket square', () {
      expect(
        MatchDuration.estimate(sportId: 'badminton'),
        lessThan(MatchDuration.estimate(sportId: 'cricket')),
      );
    });
  });

  group('the twelve-match season', () {
    test('four grounds on one day does not fit, and says by how much', () {
      final plan = DraftSeasonPlan.build(
        start: start,
        end: start,
        grounds: [for (var i = 0; i < 4; i++) ground('g$i')],
        events: [cricket()],
      );

      expect(plan.matchesRequired, 12);
      expect(plan.fits, isFalse);
      // A 09:00–18:00 ground holds two 3h15 matches. Four grounds, eight.
      expect(plan.report.totalCapacity, 8);
      expect(plan.unplacedMatches, 4);
      expect(plan.report.problems, isNotEmpty);
    });

    test('adding grounds closes the gap, one ground at a time', () {
      int unplaced(int grounds) => DraftSeasonPlan.build(
            start: start,
            end: start,
            grounds: [for (var i = 0; i < grounds; i++) ground('g$i')],
            events: [cricket()],
          ).unplacedMatches;

      // The organizer's own sequence: four is short, five is closer, six
      // fits. Nothing about that needed a timetable to be generated first.
      expect(unplaced(4), 4);
      expect(unplaced(5), 2);
      expect(unplaced(6), 0);
    });

    test('adding a day fits it on the grounds already booked', () {
      final plan = DraftSeasonPlan.build(
        start: start,
        end: start.add(const Duration(days: 1)),
        grounds: [for (var i = 0; i < 4; i++) ground('g$i')],
        events: [cricket()],
      );

      expect(plan.fits, isTrue);
      expect(plan.days, hasLength(2));
      // Day one fills, day two takes the rest — which is the answer to "how
      // many days do I need to book".
      expect(plan.days.first.matches, 8);
      expect(plan.days.last.matches, 4);
      expect(plan.daysUsed, 2);
    });

    test('floodlights fit it on one day without another ground', () {
      final plan = DraftSeasonPlan.build(
        start: start,
        end: start,
        grounds: [
          for (var i = 0; i < 4; i++)
            ground(
              'g$i',
              sessions: const [
                DaySession(startMinute: 6 * 60, endMinute: 23 * 60),
              ],
            ),
        ],
        events: [cricket()],
      );

      // The "ground is booked 24 hours with lights" case. Same four grounds,
      // seventeen hours instead of nine, and the season fits.
      expect(plan.fits, isTrue);
      expect(plan.report.totalCapacity, greaterThanOrEqualTo(12));
    });
  });

  group('the plan is honest about what it is measuring', () {
    test('a performance event takes no ground time', () {
      const longJump = SeasonEventPlan(
        key: 'lj',
        label: 'Long jump',
        sportId: 'athletics_field',
        entrants: 20,
        format: CompetitionFormat.finalOnly,
        matchMinutes: 30,
        isTimetabled: false,
      );
      expect(longJump.matchesRequired, 0);

      final plan = DraftSeasonPlan.build(
        start: start,
        end: start,
        grounds: [ground('g0')],
        events: [longJump],
      );
      expect(plan.matchesRequired, 0);
    });

    test('two sports on one ground are caught, not counted twice', () {
      // Cricket alone fits and badminton alone fits, and they are on the same
      // field. The check that finds it is the pool check, not the total.
      final plan = DraftSeasonPlan.build(
        start: start,
        end: start,
        grounds: [ground('shared', openHour: 9, closeHour: 18)],
        events: [
          cricket(entrants: 3),
          SeasonEventPlan(
            key: 'badminton',
            label: 'Badminton Open',
            sportId: 'badminton',
            entrants: 8,
            format: CompetitionFormat.knockout,
            matchMinutes: MatchDuration.estimate(sportId: 'badminton'),
          ),
        ],
      );

      expect(plan.fits, isFalse);
      expect(plan.report.pools.any((p) => p.events.length > 1), isTrue);
    });

    test('an event pinned to one ground is measured against that ground', () {
      final plan = DraftSeasonPlan.build(
        start: start,
        end: start,
        grounds: [ground('main'), ground('spare')],
        events: [cricket(grounds: {'main'})],
      );

      // Two grounds hold four; the one it is allowed on holds two.
      expect(plan.report.totalCapacity, 4);
      expect(plan.report.perEvent.single.capacity, 2);
      expect(plan.fits, isFalse);
    });

    test('nothing is claimed before there are dates, grounds and events', () {
      expect(
        DraftSeasonPlan.build(
          start: null,
          end: null,
          grounds: [ground('g')],
          events: [cricket()],
        ).matchesRequired,
        0,
      );
      expect(
        DraftSeasonPlan.build(
          start: start,
          end: start,
          grounds: const [],
          events: [cricket()],
        ).matchesRequired,
        0,
      );
    });
  });

  group('officials coverage', () {
    TournamentOfficial umpire(
      String name, {
      List<String> sports = const [],
      List<String> days = const [],
      int perDay = 8,
    }) =>
        TournamentOfficial(
          uid: name,
          name: name,
          sports: sports,
          availableDates: days,
          maxMatchesPerDay: perDay,
        );

    final days = DraftSeasonPlan.build(
      start: start,
      end: start.add(const Duration(days: 1)),
      grounds: [for (var i = 0; i < 4; i++) ground('g$i')],
      events: [cricket()],
    ).days;

    test('an empty panel covers nothing and says how much is needed', () {
      final coverage = OfficialsCoverage.of(
        panel: const [],
        events: [cricket()],
        days: days,
      );
      expect(coverage.matches, 12);
      expect(coverage.capacity, 0);
      expect(coverage.fits, isFalse);
    });

    test('capacity counts only the days somebody actually said yes to', () {
      final everyDay = OfficialsCoverage.of(
        panel: [umpire('Ravi', perDay: 3)],
        events: [cricket()],
        days: days,
      );
      final oneDay = OfficialsCoverage.of(
        panel: [umpire('Ravi', perDay: 3, days: const ['2026-10-01'])],
        events: [cricket()],
        days: days,
      );

      // Two playing days at three a day, against one.
      expect(everyDay.capacity, 6);
      expect(oneDay.capacity, 3);
    });

    test('a sport nobody covers is a failure even with people to spare', () {
      final coverage = OfficialsCoverage.of(
        panel: [umpire('Anita', sports: const ['badminton'], perDay: 20)],
        events: [cricket()],
        days: days,
      );

      // Plenty of capacity, and not one person who can call a cricket match.
      // This is the panel that reads as complete until Saturday morning.
      expect(coverage.capacity, greaterThan(coverage.matches));
      expect(coverage.uncoveredSports, contains('Cricket'));
      expect(coverage.fits, isFalse);
    });

    test('an unrestricted official covers whatever the season runs', () {
      final coverage = OfficialsCoverage.of(
        panel: [umpire('Ravi', perDay: 8)],
        events: [cricket()],
        days: days,
      );
      expect(coverage.uncoveredSports, isEmpty);
      expect(coverage.fits, isTrue);
    });
  });

  group('guest officials', () {
    test('a guest gets an id that says it is not an account', () {
      final id = newGuestOfficialId();
      expect(id.startsWith(guestOfficialPrefix), isTrue);
      // Two added in the same breath must not collide onto one roster row.
      expect(id, isNot(newGuestOfficialId()));
    });
  });
}
