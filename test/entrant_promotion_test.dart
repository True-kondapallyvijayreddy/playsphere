import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/tournament/entrant_promoter.dart';

void main() {
  const promoter = EntrantPromoter();

  Registration reg(
    String uid, {
    String? name,
    String? house,
    String? team,
    String? partnerUid,
    bool solo = false,
  }) =>
      Registration(
        uid: uid,
        displayName: name ?? uid.toUpperCase(),
        status: RegistrationStatus.confirmed,
        houseName: house,
        teamName: team,
        partnerUid: partnerUid,
        isSoloDoubles: solo,
      );

  group('EntrantPromoter - school houses', () {
    test('groups students into one entrant per house', () {
      final result = promoter.promote(
        mode: TeamEntryMode.houseBatch,
        confirmed: [
          reg('u1', house: 'Red House'),
          reg('u2', house: 'Blue House'),
          reg('u3', house: 'Red House'),
        ],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 2);

      final red = result.entrants.firstWhere((e) => e.displayName == 'Red House');
      expect(red.id, 'house_red_house');
      expect(red.entrantType, EntrantType.team);
      expect(red.memberUids, ['u1', 'u3']);
    });

    test('blocks rather than silently dropping a student into the first house',
        () {
      final result = promoter.promote(
        mode: TeamEntryMode.houseBatch,
        confirmed: [
          reg('u1', name: 'Alice', house: 'Red House'),
          reg('u2', name: 'Bob', house: 'Blue House'),
          reg('u3', name: 'Charlie'),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.entrants, isEmpty);
      expect(result.problems.single, contains('Charlie'));
      expect(result.problems.single, contains('no house'));
    });

    test('blocks when only one house has members', () {
      final result = promoter.promote(
        mode: TeamEntryMode.houseBatch,
        confirmed: [reg('u1', house: 'Red House'), reg('u2', house: 'Red House')],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.single, contains('two houses'));
    });

    test('reports every problem at once, not just the first', () {
      final result = promoter.promote(
        mode: TeamEntryMode.houseBatch,
        confirmed: [reg('u1', house: 'Red House'), reg('u2', name: 'Bob')],
      );

      expect(result.problems.length, 2);
    });
  });

  group('EntrantPromoter - pre-formed teams', () {
    test('groups captain-led squads by team name', () {
      final result = promoter.promote(
        mode: TeamEntryMode.preformedTeam,
        confirmed: [
          reg('u1', team: 'Deccan Chargers'),
          reg('u2', team: 'Deccan Chargers'),
          reg('u3', team: 'St Marks FC'),
        ],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 2);
      expect(
        result.entrants.map((e) => e.id),
        containsAll(['team_deccan_chargers', 'team_st_marks_fc']),
      );
    });

    test('does not fall through to an individual bracket', () {
      final result = promoter.promote(
        mode: TeamEntryMode.preformedTeam,
        confirmed: [
          reg('u1', team: 'A'),
          reg('u2', team: 'B'),
          reg('u3', name: 'Loose Player'),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.single, contains('Loose Player'));
      // Blocked outright — the point is that it does not quietly emit three
      // individual entrants and call that a football tournament.
      expect(result.entrants, isEmpty);
    });
  });

  group('EntrantPromoter - player pool', () {
    test('refuses to promote a pool and points at the team builder', () {
      final result = promoter.promote(
        mode: TeamEntryMode.playerPool,
        confirmed: [for (var i = 0; i < 44; i++) reg('u$i')],
      );

      expect(result.isReady, isFalse);
      expect(result.entrants, isEmpty);
      expect(result.problems.single, contains('Team Builder & Draft'));
    });
  });

  group('EntrantPromoter - doubles', () {
    test('pairs two players who named each other', () {
      final result = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: [
          reg('u1', name: 'Alice', partnerUid: 'u2'),
          reg('u2', name: 'Bob', partnerUid: 'u1'),
          reg('u3', name: 'Cara', partnerUid: 'u4'),
          reg('u4', name: 'Dev', partnerUid: 'u3'),
        ],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 2);
      expect(result.entrants.first.displayName, 'Alice / Bob');
      expect(result.entrants.first.memberUids, ['u1', 'u2']);
    });

    test('accepts a one-sided pick when the partner has also registered', () {
      final result = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: [
          reg('u1', name: 'Alice', partnerUid: 'u2'),
          reg('u2', name: 'Bob'),
          reg('u3', name: 'Cara', solo: true),
          reg('u4', name: 'Dev', solo: true),
        ],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 2);
      expect(result.entrants.first.memberUids, ['u1', 'u2']);
    });

    test('blocks when a named partner never registered', () {
      final result = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: [
          reg('u1', name: 'Alice', partnerUid: 'ghost'),
          reg('u2', name: 'Bob', partnerUid: 'u3'),
          reg('u3', name: 'Cara', partnerUid: 'u2'),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.single, contains('Alice'));
      expect(result.problems.single, contains('has not confirmed'));
    });

    test('never quietly claims a player who named somebody else', () {
      // Alice names Bob; Bob names Cara. The old code paired Alice with
      // whoever was next in the list and nobody found out.
      final result = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: [
          reg('u1', name: 'Alice', partnerUid: 'u2'),
          reg('u2', name: 'Bob', partnerUid: 'u3'),
          reg('u3', name: 'Cara', partnerUid: 'u2'),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.first, contains('named somebody else'));
    });

    test('auto-pairs the free-agent pool in entry order', () {
      final result = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: [
          reg('u1', name: 'Alice', solo: true),
          reg('u2', name: 'Bob', solo: true),
          reg('u3', name: 'Cara', solo: true),
          reg('u4', name: 'Dev', solo: true),
        ],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 2);
      expect(result.entrants[0].memberUids, ['u1', 'u2']);
      expect(result.entrants[1].memberUids, ['u3', 'u4']);
    });

    test('blocks on an odd free agent instead of inventing a TBD partner', () {
      final result = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: [
          reg('u1', name: 'Alice', solo: true),
          reg('u2', name: 'Bob', solo: true),
          reg('u3', name: 'Cara', solo: true),
          reg('u4', name: 'Dev', solo: true),
          reg('u5', name: 'Eve', solo: true),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.single, contains('Eve'));
      expect(result.problems.single, contains('looking for a partner'));
      expect(
        result.entrants.any((e) => e.displayName.contains('TBD')),
        isFalse,
      );
    });

    test('pair ids are stable across a re-lock', () {
      List<Registration> field() => [
            reg('u1', name: 'Alice', partnerUid: 'u2'),
            reg('u2', name: 'Bob', partnerUid: 'u1'),
            reg('u3', name: 'Cara', partnerUid: 'u4'),
            reg('u4', name: 'Dev', partnerUid: 'u3'),
          ];

      final first = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: field(),
      );
      final second = promoter.promote(
        mode: TeamEntryMode.doubles,
        confirmed: field().reversed.toList(),
      );

      expect(
        first.entrants.map((e) => e.id).toSet(),
        second.entrants.map((e) => e.id).toSet(),
      );
    });
  });

  group('EntrantPromoter - individuals', () {
    test('promotes one entrant per registration', () {
      final result = promoter.promote(
        mode: TeamEntryMode.individual,
        confirmed: [reg('u1'), reg('u2'), reg('u3')],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 3);
      expect(
        result.entrants.every((e) => e.entrantType == EntrantType.individual),
        isTrue,
      );
    });

    test('blocks a field of one', () {
      final result = promoter.promote(
        mode: TeamEntryMode.individual,
        confirmed: [reg('u1')],
      );

      expect(result.isReady, isFalse);
    });
  });

  group('EntrantPromoter - teams that entered as teams', () {
    Registration teamReg(
      String teamId, {
      required String name,
      List<String> squad = const ['a', 'b'],
    }) =>
        Registration(
          uid: teamId,
          displayName: name,
          status: RegistrationStatus.confirmed,
          teamName: name,
          teamId: teamId,
          memberUids: squad,
        );

    test('one entrant per team, carrying the squad and the team link', () {
      final result = promoter.promote(
        // The mode an event created from the ordinary form carries. A team
        // entry must not be re-derived from it.
        mode: TeamEntryMode.individual,
        confirmed: [
          teamReg('t1', name: 'Hyderabad CC A', squad: ['p1', 'p2', 'p3']),
          teamReg('t2', name: 'Hyderabad CC B', squad: ['p4', 'p5']),
        ],
      );

      expect(result.isReady, isTrue);
      expect(result.entrants.length, 2);

      final a = result.entrants.firstWhere((e) => e.id == 't1');
      expect(a.displayName, 'Hyderabad CC A');
      expect(a.entrantType, EntrantType.team);
      expect(a.teamId, 't1');
      expect(a.memberUids, ['p1', 'p2', 'p3']);
      // A side is not a person, however few people are in it.
      expect(a.soloUid, isNull);
    });

    test('does not silently draw individuals alongside teams', () {
      final result = promoter.promote(
        mode: TeamEntryMode.preformedTeam,
        confirmed: [
          teamReg('t1', name: 'Sunrise A'),
          teamReg('t2', name: 'Sunrise B'),
          reg('stray'),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.single, contains('individual player'));
    });

    test('refuses a team whose squad was emptied after it entered', () {
      final result = promoter.promote(
        mode: TeamEntryMode.preformedTeam,
        confirmed: [
          teamReg('t1', name: 'Sunrise A'),
          teamReg('t2', name: 'Sunrise B', squad: const []),
        ],
      );

      expect(result.isReady, isFalse);
      expect(result.problems.single, contains('Sunrise B'));
    });

    test('one team is not a field', () {
      final result = promoter.promote(
        mode: TeamEntryMode.preformedTeam,
        confirmed: [teamReg('t1', name: 'Sunrise A')],
      );

      expect(result.isReady, isFalse);
    });
  });
}
