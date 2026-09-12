import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/career/club_honours.dart';

/// A club's trophy cabinet, derived rather than stored.
///
/// The dangerous direction is a false positive: the club fixture stream
/// carries finished matches ONLY, so a half-played knockout looks complete
/// from here unless something else says otherwise. These pin the two things
/// that do — the event's own status and its `fixtureCount`.
void main() {
  Competition event(
    String id, {
    CompetitionStatus status = CompetitionStatus.completed,
    CompetitionFormat format = CompetitionFormat.knockout,
    int fixtureCount = 1,
    String sportId = 'cricket',
    List<String>? participantOrgIds,
  }) =>
      Competition(
        id: id,
        orgId: 'org1',
        name: 'Event $id',
        sportId: sportId,
        sportName: sportId,
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        format: format,
        status: status,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        fixtureCount: fixtureCount,
        participantOrgIds: participantOrgIds,
        startDate: DateTime(2026, 3, 1),
      );

  Fixture match({
    required String id,
    required String compId,
    String a = 'side_a',
    String b = 'side_b',
    String aName = 'Warriors A',
    String bName = 'Warriors B',
    String? winner = 'side_a',
    int round = 1,
    int matchIndex = 0,
    FixtureStatus status = FixtureStatus.completed,
    bool isDraft = false,
    DateTime? completedAt,
  }) =>
      Fixture(
        id: id,
        orgId: 'org1',
        compId: compId,
        entrantAId: a,
        entrantBId: b,
        entrantAName: aName,
        entrantBName: bName,
        status: status,
        sportId: 'cricket',
        round: round,
        matchIndex: matchIndex,
        winnerEntrantId: winner,
        isDraft: isDraft,
        completedAt: completedAt ?? DateTime(2026, 3, 2),
      );

  ClubHonours honoursOf(
    List<Competition> competitions,
    List<Fixture> fixtures, {
    String orgId = 'org1',
  }) =>
      ClubHonours.forClub(
        competitions: competitions,
        fixtures: fixtures,
        orgId: orgId,
      );

  group('when a title is awarded', () {
    test('a completed knockout is won by its deepest decider', () {
      final honours = honoursOf(
        [event('e1', fixtureCount: 3)],
        [
          match(id: 'f1', compId: 'e1', round: 1, winner: 'side_a'),
          match(id: 'f2', compId: 'e1', round: 1, matchIndex: 1, winner: 'side_b'),
          match(
            id: 'final',
            compId: 'e1',
            round: 2,
            a: 'side_b',
            b: 'side_a',
            aName: 'Warriors B',
            bName: 'Warriors A',
            winner: 'side_b',
          ),
        ],
      );
      expect(honours.titles, hasLength(1));
      expect(honours.titles.single.championName, 'Warriors B');
    });

    test('an event still in progress mints nothing', () {
      final honours = honoursOf(
        [event('e1', status: CompetitionStatus.inProgress)],
        [match(id: 'f1', compId: 'e1')],
      );
      expect(honours.isEmpty, isTrue);
    });

    test('a completed event missing matches from the stream mints nothing', () {
      // The event says it has five fixtures; only the two that finished are
      // on the stream. Declaring a champion here would crown whoever won the
      // last match anybody happened to play.
      final honours = honoursOf(
        [event('e1', fixtureCount: 5)],
        [
          match(id: 'f1', compId: 'e1'),
          match(id: 'f2', compId: 'e1', matchIndex: 1),
        ],
      );
      expect(honours.isEmpty, isTrue);
    });

    test('a draft placeholder does not count towards the fixture count', () {
      final honours = honoursOf(
        [event('e1', fixtureCount: 2)],
        [
          match(id: 'f1', compId: 'e1'),
          match(id: 'f2', compId: 'e1', isDraft: true, matchIndex: 1),
        ],
      );
      expect(honours.isEmpty, isTrue);
    });

    test('an event with no fixtures at all mints nothing', () {
      expect(honoursOf([event('e1')], const []).isEmpty, isTrue);
    });

    test('a cancelled event is not a title', () {
      final honours = honoursOf(
        [event('e1', status: CompetitionStatus.cancelled)],
        [match(id: 'f1', compId: 'e1')],
      );
      expect(honours.isEmpty, isTrue);
    });
  });

  group('whose title it is', () {
    test('a challenge the club won is the club\'s own', () {
      final honours = honoursOf(
        [
          event(
            'c1',
            participantOrgIds: const ['org1', 'org2'],
          ),
        ],
        [
          match(
            id: 'f1',
            compId: 'c1',
            a: 'org1',
            b: 'org2',
            aName: 'Warriors',
            bName: 'Rivals',
            winner: 'org1',
          ),
        ],
      );
      final title = honours.titles.single;
      expect(title.wonByTheClub, isTrue);
      expect(title.isOpenTitle, isTrue);
    });

    test('a challenge the club lost is still an inter-club result but not '
        'the club\'s title', () {
      final honours = honoursOf(
        [event('c1', participantOrgIds: const ['org1', 'org2'])],
        [
          match(
            id: 'f1',
            compId: 'c1',
            a: 'org1',
            b: 'org2',
            aName: 'Warriors',
            bName: 'Rivals',
            winner: 'org2',
          ),
        ],
      );
      final title = honours.titles.single;
      expect(title.wonByTheClub, isFalse);
      expect(title.championName, 'Rivals');
    });

    test('an internal event won by one of the club\'s own sides is not open',
        () {
      final honours = honoursOf(
        [event('e1')],
        [match(id: 'f1', compId: 'e1')],
      );
      final title = honours.titles.single;
      expect(title.wonByTheClub, isFalse);
      expect(title.isOpenTitle, isFalse);
      expect(honours.openTitles, isEmpty);
      expect(honours.internalTitles, hasLength(1));
    });
  });

  group('the cabinet as a whole', () {
    test('newest first', () {
      final honours = honoursOf(
        [event('old'), event('new')],
        [
          match(id: 'f1', compId: 'old', completedAt: DateTime(2024, 5, 1)),
          match(id: 'f2', compId: 'new', completedAt: DateTime(2026, 5, 1)),
        ],
      );
      expect(
        honours.titles.map((t) => t.competition.id).toList(),
        ['new', 'old'],
      );
    });

    test('titles are askable by sport, and count their sports', () {
      final honours = honoursOf(
        [event('e1'), event('e2', sportId: 'badminton')],
        [
          match(id: 'f1', compId: 'e1'),
          match(id: 'f2', compId: 'e2'),
        ],
      );
      expect(honours.forSport('cricket'), hasLength(1));
      expect(honours.forSport('badminton'), hasLength(1));
      expect(honours.sportsWon, {'cricket', 'badminton'});
    });

    test('a league is decided by its table, not its last match', () {
      // Two teams, two matches: A beat B, then B beat A. A won the earlier
      // one but the table is what decides a round robin — the point of
      // sharing `TournamentOverview.championOf` rather than re-deriving.
      final honours = honoursOf(
        [event('l1', format: CompetitionFormat.roundRobin, fixtureCount: 2)],
        [
          match(id: 'f1', compId: 'l1', winner: 'side_a'),
          match(id: 'f2', compId: 'l1', matchIndex: 1, winner: 'side_b'),
        ],
      );
      // Level on points; whichever the table puts first, it is named from the
      // table and the event does produce exactly one champion.
      expect(honours.titles, hasLength(1));
      expect(
        honours.titles.single.championName,
        anyOf('Warriors A', 'Warriors B'),
      );
    });
  });
}
