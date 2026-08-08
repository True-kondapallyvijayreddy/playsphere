import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/tournament/tournament_overview.dart';

/// The tournament summary is derived on every read, never stored — a
/// tournament's progress is a pure function of its matches, and persisting it
/// would mean a headline number that can silently disagree with the results it
/// claims to summarise. These pin what it derives.
void main() {
  Competition event(
    String id,
    String name, {
    CompetitionFormat format = CompetitionFormat.knockout,
  }) =>
      Competition(
        id: id,
        orgId: 'o1',
        name: name,
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: format,
        status: CompetitionStatus.inProgress,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        tournamentId: 't1',
      );

  Fixture match(
    String compId,
    int index, {
    required FixtureStatus status,
    String? winner,
    int round = 1,
    DateTime? at,
    String a = 'A',
    String b = 'B',
    DateTime? lastEventAt,
  }) =>
      Fixture(
        id: '$compId-$index',
        orgId: 'o1',
        compId: compId,
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: status,
        round: round,
        matchIndex: index,
        scheduledAt: at,
        winnerEntrantId: winner,
        tournamentId: 't1',
        // A live match has a scoreboard somebody is touching. Counting one
        // as live now takes more than the status field — a fixture stays in
        // `live` after a scorer abandons it, and those were being reported
        // as on court days later (Bug #1 / #15, see live_status_test.dart).
        lastSeq: status == FixtureStatus.live ? 8 : 0,
        lastEventAt: status == FixtureStatus.live
            ? (lastEventAt ??
                DateTime.now().subtract(const Duration(minutes: 3)))
            : null,
      );

  group('progress across every event', () {
    test('counts played and remaining over the whole tournament', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'U13 Singles'), event('e2', 'Senior Singles')],
        fixtures: [
          match('e1', 0, status: FixtureStatus.completed, winner: 'A'),
          match('e1', 1, status: FixtureStatus.scheduled),
          match('e2', 0, status: FixtureStatus.completed, winner: 'A'),
          match('e2', 1, status: FixtureStatus.live),
        ],
      );

      expect(o.totalMatches, 4);
      expect(o.playedMatches, 2);
      expect(o.remainingMatches, 2);
      expect(o.liveMatches, 1);
      expect(o.progress, 0.5);
      expect(o.isComplete, isFalse);
    });

    test('an event with no matches drawn yet reports zero, not a crash', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Not drawn')],
        fixtures: const [],
      );
      expect(o.totalMatches, 0);
      expect(o.progress, 0);
      expect(o.isComplete, isFalse, reason: 'nothing played is not complete');
      expect(o.events.single.total, 0);
    });

    test('each event only counts its own matches', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'A'), event('e2', 'B')],
        fixtures: [
          match('e1', 0, status: FixtureStatus.completed, winner: 'A'),
          match('e2', 0, status: FixtureStatus.scheduled),
          match('e2', 1, status: FixtureStatus.scheduled),
        ],
      );
      final byName = {for (final e in o.events) e.competition.name: e};
      expect(byName['A']!.total, 1);
      expect(byName['B']!.total, 2);
      expect(byName['B']!.played, 0);
    });

    test('events are listed in a stable order as results land', () {
      // Sorted by name rather than by progress, so the list does not reshuffle
      // under an organizer's finger every time a match finishes.
      final o = TournamentOverview.from(
        events: [event('e2', 'Zeta'), event('e1', 'Alpha')],
        fixtures: const [],
      );
      expect(o.events.map((e) => e.competition.name), ['Alpha', 'Zeta']);
    });
  });

  group('who is champion', () {
    test('nobody is champion while a match is still unplayed', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0, status: FixtureStatus.completed, winner: 'A'),
          match('e1', 1, status: FixtureStatus.scheduled),
        ],
      );
      expect(
        o.events.single.champion,
        isNull,
        reason: 'a leader mid-tournament is not a champion',
      );
      expect(o.champions, isEmpty);
    });

    test('the winner of the deepest round takes the title', () {
      // Found by round rather than by a fixture labelled "Final": a round
      // robin has no final, a groups draw numbers two phases from 1, and a
      // double-elimination reset may never be played.
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0,
              status: FixtureStatus.completed, winner: 'A', a: 'A', b: 'B'),
          match('e1', 1,
              status: FixtureStatus.completed, winner: 'C', a: 'C', b: 'D'),
          match('e1', 2,
              status: FixtureStatus.completed,
              winner: 'C',
              round: 2,
              a: 'A',
              b: 'C'),
        ],
      );
      expect(o.events.single.champion, 'C');
      expect(o.champions.single.competition.name, 'Singles');
    });

    test('a walkover still crowns whoever it was awarded to', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0,
              status: FixtureStatus.walkover, winner: 'B', a: 'A', b: 'B'),
        ],
      );
      expect(o.events.single.champion, 'B');
    });

    test('an event with no result at all has no champion', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [match('e1', 0, status: FixtureStatus.scheduled)],
      );
      expect(o.events.single.champion, isNull);
    });

    test('completed events are counted', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Done'), event('e2', 'Running')],
        fixtures: [
          match('e1', 0, status: FixtureStatus.completed, winner: 'A'),
          match('e2', 0, status: FixtureStatus.completed, winner: 'A'),
          match('e2', 1, status: FixtureStatus.scheduled),
        ],
      );
      expect(o.completedEvents, 1);
      expect(o.isComplete, isFalse);
    });
  });

  group('the order-of-play board', () {
    final now = DateTime(2026, 9, 12, 11, 0);

    test('live matches appear on court now', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          // Heartbeat tied to this test's own clock, not the wall clock: the
          // board is asked what is on court at `now`, so the scoreboard has
          // to have moved shortly before `now` to qualify.
          match('e1', 0,
              status: FixtureStatus.live,
              lastEventAt: now.subtract(const Duration(minutes: 4))),
          match('e1', 1, status: FixtureStatus.scheduled),
        ],
        now: now,
      );
      expect(o.onCourtNow.length, 1);
      expect(o.onCourtNow.single.matchIndex, 0);
    });

    test('a match abandoned mid-scoreboard is not on court', () {
      // Bug #1: the order-of-play board was listing matches nobody had
      // touched in days as though they were being played right now.
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0,
              status: FixtureStatus.live,
              lastEventAt: now.subtract(const Duration(days: 3))),
        ],
        now: now,
      );
      expect(o.onCourtNow, isEmpty);
      expect(o.liveMatches, 0);
    });

    test('up next skips matches whose time has long passed', () {
      // A match due two hours ago is not "up next" — it is late, and putting
      // it at the top of the board hides what is actually about to start.
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0,
              status: FixtureStatus.scheduled,
              at: DateTime(2026, 9, 12, 9, 0)),
          match('e1', 1,
              status: FixtureStatus.scheduled,
              at: DateTime(2026, 9, 12, 11, 30)),
        ],
        now: now,
      );
      expect(o.upNext.map((f) => f.matchIndex), [1]);
    });

    test('a completed match never appears as up next', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0,
              status: FixtureStatus.completed,
              winner: 'A',
              at: DateTime(2026, 9, 12, 12, 0)),
        ],
        now: now,
      );
      expect(o.upNext, isEmpty);
    });

    test('the board is capped so it stays a board, not a fixture list', () {
      final o = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          for (var i = 0; i < 30; i++)
            match('e1', i,
                status: FixtureStatus.scheduled,
                at: DateTime(2026, 9, 12, 12, i)),
        ],
        now: now,
      );
      expect(o.upNext.length, 8);
    });

    test('the last scheduled start is reported, and is null when unscheduled',
        () {
      final scheduled = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [
          match('e1', 0,
              status: FixtureStatus.scheduled,
              at: DateTime(2026, 9, 12, 12, 0)),
          match('e1', 1,
              status: FixtureStatus.scheduled,
              at: DateTime(2026, 9, 12, 16, 30)),
        ],
        now: now,
      );
      expect(scheduled.scheduledThrough, DateTime(2026, 9, 12, 16, 30));

      final unscheduled = TournamentOverview.from(
        events: [event('e1', 'Singles')],
        fixtures: [match('e1', 0, status: FixtureStatus.scheduled)],
        now: now,
      );
      expect(
        unscheduled.scheduledThrough,
        isNull,
        reason: 'nothing scheduled is different from finishing now',
      );
    });
  });
}
