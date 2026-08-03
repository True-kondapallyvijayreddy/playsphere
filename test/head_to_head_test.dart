import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/career/head_to_head.dart';

/// A career profile aggregates totals. It cannot answer the question people
/// actually ask about a rival — not "how good is he" but "how do I do against
/// him". A player 400 points lower rated can still be 4-1 up.
void main() {
  Fixture singles(
    String a,
    String b, {
    required String? winner,
    DateTime? at,
    FixtureStatus status = FixtureStatus.completed,
    MatchResultType type = MatchResultType.normal,
    bool isDraw = false,
    String sportId = 'badminton',
  }) =>
      Fixture(
        id: '$a-$b-${at?.millisecondsSinceEpoch ?? 0}',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: a,
        entrantBId: b,
        entrantAName: a,
        entrantBName: b,
        status: status,
        resultType: type,
        winnerEntrantId: winner,
        isDraw: isDraw,
        sportId: sportId,
        completedAt: at,
      );

  Fixture doubles(
    List<String> sideA,
    List<String> sideB, {
    required bool aWon,
  }) =>
      Fixture(
        id: '${sideA.join()}-${sideB.join()}',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'teamA',
        entrantBId: 'teamB',
        entrantAName: 'Team A',
        entrantBName: 'Team B',
        status: FixtureStatus.completed,
        winnerEntrantId: aWon ? 'teamA' : 'teamB',
        lineupA: [for (final u in sideA) MatchPlayer(id: u, uid: u, name: u)],
        lineupB: [for (final u in sideB) MatchPlayer(id: u, uid: u, name: u)],
        sportId: 'badminton',
      );

  group('singles, where the entrant is the person', () {
    test('a record is built against each opponent', () {
      // Individual events name nobody in a line-up: the entrant id IS the uid.
      final rows = HeadToHead.forPlayer(
        uid: 'ravi',
        fixtures: [
          singles('ravi', 'arun', winner: 'ravi'),
          singles('arun', 'ravi', winner: 'ravi', at: DateTime(2026, 2, 1)),
          singles('ravi', 'arun', winner: 'arun', at: DateTime(2026, 3, 1)),
          singles('ravi', 'kiran', winner: 'kiran'),
        ],
      );

      final arun = rows.firstWhere((r) => r.opponentUid == 'arun');
      expect(arun.played, 3);
      expect(arun.won, 2);
      expect(arun.lost, 1);
      expect(arun.line, '2–1');
      expect(arun.isAhead, isTrue);
    });

    test('the record is from the subject\'s point of view, both ways round',
        () {
      final fixtures = [singles('ravi', 'arun', winner: 'arun')];
      expect(
        HeadToHead.forPlayer(uid: 'ravi', fixtures: fixtures).single.won,
        0,
      );
      expect(
        HeadToHead.forPlayer(uid: 'arun', fixtures: fixtures).single.won,
        1,
      );
    });

    test('most-played first — one meeting is not a rivalry', () {
      final rows = HeadToHead.forPlayer(
        uid: 'ravi',
        fixtures: [
          singles('ravi', 'once', winner: 'ravi'),
          singles('ravi', 'often', winner: 'ravi'),
          singles('ravi', 'often', winner: 'often'),
          singles('ravi', 'often', winner: 'ravi'),
        ],
      );
      expect(rows.first.opponentUid, 'often');
    });

    test('when they last met is reported', () {
      final rows = HeadToHead.forPlayer(
        uid: 'ravi',
        fixtures: [
          singles('ravi', 'arun', winner: 'ravi', at: DateTime(2023, 5, 1)),
          singles('ravi', 'arun', winner: 'arun', at: DateTime(2026, 5, 1)),
        ],
      );
      // "3-2 but you have not played since 2023" is a different fact from
      // "3-2 this season".
      expect(rows.single.lastMet, DateTime(2026, 5, 1));
    });

    test('a draw counts as played but as neither a win nor a loss', () {
      final rows = HeadToHead.forPlayer(
        uid: 'a',
        fixtures: [singles('a', 'b', winner: null, isDraw: true)],
      );
      expect(rows.single.played, 1);
      expect(rows.single.won, 0);
      expect(rows.single.lost, 0);
      expect(rows.single.drawn, 1);
      expect(rows.single.isLevel, isTrue);
    });
  });

  group('what does not count', () {
    test('a walkover says nothing about how two players match up', () {
      final rows = HeadToHead.forPlayer(
        uid: 'a',
        fixtures: [
          singles('a', 'b',
              winner: 'a',
              status: FixtureStatus.walkover,
              type: MatchResultType.walkover),
        ],
      );
      expect(rows, isEmpty);
    });

    test('an unplayed match does not appear', () {
      final rows = HeadToHead.forPlayer(
        uid: 'a',
        fixtures: [
          singles('a', 'b', winner: null, status: FixtureStatus.scheduled),
        ],
      );
      expect(rows, isEmpty);
    });

    test('a retirement counts — somebody played', () {
      final rows = HeadToHead.forPlayer(
        uid: 'a',
        fixtures: [
          singles('a', 'b', winner: 'a', type: MatchResultType.retired),
        ],
      );
      expect(rows.single.won, 1);
    });

    test('a match the player was not in is ignored', () {
      final rows = HeadToHead.forPlayer(
        uid: 'bystander',
        fixtures: [singles('a', 'b', winner: 'a')],
      );
      expect(rows, isEmpty);
    });
  });

  group('doubles', () {
    test('a record is kept against each individual, not against the pair', () {
      // "How do I do against that pair" is not a question anybody asks; the
      // question is always about a person.
      final rows = HeadToHead.forPlayer(
        uid: 'me',
        fixtures: [
          doubles(['me', 'partner'], ['x', 'y'], aWon: true),
          doubles(['me', 'other'], ['x', 'z'], aWon: false),
        ],
      );
      final byId = {for (final r in rows) r.opponentUid: r};
      expect(byId.keys.toSet(), {'x', 'y', 'z'});
      expect(byId['x']!.played, 2);
      expect(byId['x']!.won, 1);
      expect(byId['y']!.played, 1);
    });

    test('a partner is never recorded as an opponent', () {
      final rows = HeadToHead.forPlayer(
        uid: 'me',
        fixtures: [doubles(['me', 'partner'], ['x', 'y'], aWon: true)],
      );
      expect(rows.any((r) => r.opponentUid == 'partner'), isFalse);
    });
  });

  group('between two players', () {
    test('the pairwise record is found, or null when they never met', () {
      final fixtures = [singles('a', 'b', winner: 'a')];
      expect(
        HeadToHead.between(uid: 'a', opponentUid: 'b', fixtures: fixtures)!.won,
        1,
      );
      expect(
        HeadToHead.between(uid: 'a', opponentUid: 'zz', fixtures: fixtures),
        isNull,
      );
    });

    test('sports met in are tracked — a rivalry can span more than one', () {
      final rows = HeadToHead.forPlayer(
        uid: 'a',
        fixtures: [
          singles('a', 'b', winner: 'a'),
          singles('a', 'b', winner: 'b', sportId: 'tennis'),
        ],
      );
      expect(rows.single.sportIds, {'badminton', 'tennis'});
    });
  });
}
