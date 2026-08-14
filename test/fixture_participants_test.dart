import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';

/// Who played, on the two shapes a match can have.
///
/// The bug this protects against is not a crash — it is two screens quietly
/// disagreeing. `career_stats` is settled by a trigger that has always had an
/// entrant fallback, while every career SCREEN reads
/// `collectionGroup('fixtures').where('playerUids', arrayContains: uid)`. When
/// `playerUids` was derived from the line-ups alone, an individual event —
/// which never fills one — was counted in the total and invisible in the list.
/// A player's profile said 128 matches and their match history showed 96.
void main() {
  Fixture fixture({
    List<MatchPlayer> lineupA = const [],
    List<MatchPlayer> lineupB = const [],
    String? entrantAUid,
    String? entrantBUid,
    String entrantAId = 'a',
    String entrantBId = 'b',
  }) =>
      Fixture(
        id: 'f1',
        orgId: 'org1',
        compId: 'comp1',
        entrantAId: entrantAId,
        entrantBId: entrantBId,
        entrantAName: 'Alice',
        entrantBName: 'Bhavya',
        entrantAUid: entrantAUid,
        entrantBUid: entrantBUid,
        status: FixtureStatus.completed,
        lineupA: lineupA,
        lineupB: lineupB,
      );

  group('playerUids', () {
    test('a team match reads from the line-ups, as it always has', () {
      final f = fixture(
        lineupA: const [
          MatchPlayer(id: 'p1', name: 'Rahul', uid: 'uid_1'),
          MatchPlayer(id: 'p2', name: 'Karthik', uid: 'uid_2'),
        ],
        lineupB: const [MatchPlayer(id: 'p3', name: 'Vikram', uid: 'uid_3')],
      );
      expect(f.playerUids, unorderedEquals(['uid_1', 'uid_2', 'uid_3']));
    });

    test('an individual draw names its players through the entrant uids', () {
      final f = fixture(entrantAUid: 'uid_alice', entrantBUid: 'uid_bhavya');
      expect(f.playerUids, unorderedEquals(['uid_alice', 'uid_bhavya']));
    });

    test('a mixed fixture keeps both halves', () {
      // A club team against a lone qualifier. Taking one source over the
      // other, rather than the union, would drop half the match.
      final f = fixture(
        lineupA: const [MatchPlayer(id: 'p1', name: 'Rahul', uid: 'uid_1')],
        entrantBUid: 'uid_solo',
      );
      expect(f.playerUids, unorderedEquals(['uid_1', 'uid_solo']));
    });

    test('guests contribute nothing — there is no profile to credit', () {
      final f = fixture(
        lineupA: const [
          MatchPlayer(id: 'p1', name: 'Rahul', uid: 'uid_1'),
          MatchPlayer(id: 'guest_1', name: 'Visitor'),
        ],
      );
      expect(f.playerUids, ['uid_1']);
    });

    test('a player named on both sources is counted once', () {
      final f = fixture(
        lineupA: const [MatchPlayer(id: 'p1', name: 'Alice', uid: 'uid_alice')],
        entrantAUid: 'uid_alice',
      );
      expect(f.playerUids, ['uid_alice']);
    });
  });

  group('sideForUid', () {
    test('resolves an individual entrant to their side', () {
      final f = fixture(entrantAUid: 'uid_alice', entrantBUid: 'uid_bhavya');
      expect(f.sideForUid('uid_alice'), 'a');
      expect(f.sideForUid('uid_bhavya'), 'b');
      expect(f.sideForUid('uid_stranger'), isNull);
    });

    test('a line-up still wins over an entrant uid', () {
      final f = fixture(
        lineupB: const [MatchPlayer(id: 'p1', name: 'Alice', uid: 'uid_alice')],
        entrantAUid: 'uid_alice',
      );
      // Named on B's team sheet, so B is the answer — the sheet is what a
      // scorer actually typed.
      expect(f.sideForUid('uid_alice'), 'b');
    });
  });

  group('scoredPlayers', () {
    test('stands in for a side that is one person', () {
      final f = fixture(
        entrantAId: 'uid_alice',
        entrantAUid: 'uid_alice',
        entrantBId: 'uid_bhavya',
        entrantBUid: 'uid_bhavya',
      );
      expect(f.scoredPlayers.map((p) => p.id),
          unorderedEquals(['uid_alice', 'uid_bhavya']));
      // Keyed by the ENTRANT id, because that is the key the scoring engine
      // wrote `scoreState.players` under.
      expect(f.scoredPlayers.first.id, 'uid_alice');
      expect(f.scoredPlayers.first.name, 'Alice');
    });

    test('does not stand in for a side that has a team sheet', () {
      final f = fixture(
        lineupA: const [MatchPlayer(id: 'p1', name: 'Rahul', uid: 'uid_1')],
        entrantAUid: 'uid_captain',
        entrantBUid: 'uid_solo',
      );
      expect(f.scoredPlayers.map((p) => p.id), ['p1', 'b']);
    });
  });

  group('Entrant.soloUid', () {
    Entrant entrant({
      required EntrantType type,
      String? uid,
      List<String> memberUids = const [],
    }) =>
        Entrant(
          id: 'e1',
          displayName: 'Somebody',
          entrantType: type,
          uid: uid,
          memberUids: memberUids,
        );

    test('an individual entrant is their own account', () {
      expect(
        entrant(type: EntrantType.individual, uid: 'uid_alice').soloUid,
        'uid_alice',
      );
    });

    test('a team is never one person, however small its roster', () {
      // The rule that keeps a squad out of `playerUids`. Folding a roster in
      // would credit a match to people who watched it — and because the
      // settlement rules gate career-stat writes on that field, it would let a
      // scorer write results onto their profiles.
      expect(
        entrant(
          type: EntrantType.team,
          uid: 'uid_captain',
          memberUids: const ['uid_captain', 'uid_partner'],
        ).soloUid,
        isNull,
      );
    });

    test('an entrant with no account has no account', () {
      expect(entrant(type: EntrantType.individual).soloUid, isNull);
      expect(entrant(type: EntrantType.individual, uid: '').soloUid, isNull);
    });
  });

  group('round trip', () {
    test('survives serialization', () {
      final f = fixture(entrantAUid: 'uid_alice', entrantBUid: 'uid_bhavya');
      final map = f.toCreate();
      expect(map['entrantAUid'], 'uid_alice');
      expect(map['entrantBUid'], 'uid_bhavya');
      // The stored summary the collection-group query reads. It has to be on
      // the document, not merely derivable, because Firestore cannot query a
      // getter.
      expect(map['playerUids'], unorderedEquals(['uid_alice', 'uid_bhavya']));
    });

    test('a copy made to record a score cannot change who is playing', () {
      final f = fixture(entrantAUid: 'uid_alice', entrantBUid: 'uid_bhavya');
      final scored = f.copyWith(status: FixtureStatus.completed);
      expect(scored.entrantAUid, 'uid_alice');
      expect(scored.entrantBUid, 'uid_bhavya');
      expect(scored.playerUids, unorderedEquals(['uid_alice', 'uid_bhavya']));
    });
  });
}
