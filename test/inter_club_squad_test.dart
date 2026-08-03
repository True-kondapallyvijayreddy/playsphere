import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';

/// Step 6 of the Sports OS flow: ABC challenges XYZ, and XYZ picks its own
/// players.
///
/// The thing being asserted is ownership. A challenge fixture lives inside
/// the hosting club's tenant, so every pre-existing write path was anchored
/// to authority there — which meant the visiting club could not name a single
/// player on its own team sheet. These tests pin the mapping that makes
/// "which side is mine" answerable from the fixture alone, because
/// `firestore.rules` answers it the same way and the two must agree.
Fixture challengeFixture({
  bool lockedA = false,
  bool lockedB = false,
}) =>
    Fixture(
      id: 'fx1',
      // Hosted by the club that ACCEPTED the challenge.
      orgId: 'xyz_club',
      compId: 'comp1',
      // The challenger is side A, the host is side B — and the entrant ids
      // are the clubs' own ids. That is what this file is really guarding.
      entrantAId: 'abc_club',
      entrantBId: 'xyz_club',
      entrantAName: 'ABC Club',
      entrantBName: 'XYZ Club',
      status: FixtureStatus.scheduled,
      participantOrgIds: const ['abc_club', 'xyz_club'],
      squadLockedA: lockedA,
      squadLockedB: lockedB,
    );

Fixture internalFixture() => const Fixture(
      id: 'fx2',
      orgId: 'school1',
      compId: 'comp2',
      entrantAId: 'entrant_blue',
      entrantBId: 'entrant_red',
      entrantAName: 'Blue House',
      entrantBName: 'Red House',
      status: FixtureStatus.scheduled,
    );

void main() {
  group('which side a club owns', () {
    test('the visiting club owns side A', () {
      expect(challengeFixture().sideForOrg('abc_club'), 'a');
    });

    test('the hosting club owns side B', () {
      expect(challengeFixture().sideForOrg('xyz_club'), 'b');
    });

    test('an unrelated club owns neither', () {
      expect(challengeFixture().sideForOrg('some_other_club'), isNull);
    });

    test('an internal competition has no per-club sides at all', () {
      // Entrants here are houses, not clubs. The hosting club's organizers
      // run both sides, exactly as before — reading a side out of these ids
      // would be meaningless.
      final f = internalFixture();
      expect(f.sideForOrg('school1'), isNull);
      expect(f.sideForOrg('entrant_blue'), isNull);
    });
  });

  group('squad locks', () {
    test('nothing is locked to begin with', () {
      final f = challengeFixture();
      expect(f.squadLockedA, isFalse);
      expect(f.squadLockedB, isFalse);
      expect(f.bothSquadsLocked, isFalse);
    });

    test('a lock is reported against the club that set it', () {
      final f = challengeFixture(lockedA: true);
      expect(f.squadLockedFor('abc_club'), isTrue);
      expect(f.squadLockedFor('xyz_club'), isFalse);
    });

    test('the match is ready only when both clubs have locked', () {
      expect(challengeFixture(lockedA: true).bothSquadsLocked, isFalse);
      expect(challengeFixture(lockedB: true).bothSquadsLocked, isFalse);
      expect(
        challengeFixture(lockedA: true, lockedB: true).bothSquadsLocked,
        isTrue,
      );
    });

    test('an entrant that is not in this match is never locked', () {
      expect(
        challengeFixture(lockedA: true, lockedB: true)
            .squadLockedFor('some_other_club'),
        isFalse,
      );
    });
  });

  group('the wire format', () {
    test('locks survive a round trip and default to unlocked', () {
      final data = challengeFixture(lockedA: true).toCreate();
      expect(data['squadLockedA'], isTrue);
      expect(data['squadLockedB'], isFalse);
    });

    test('a fixture written before locks existed reads as unlocked', () {
      // Absent fields must not read as locked, or every match already in the
      // database would become uneditable.
      const f = Fixture(
        id: 'old',
        orgId: 'o',
        compId: 'c',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'A',
        entrantBName: 'B',
        status: FixtureStatus.scheduled,
      );
      expect(f.squadLockedA, isFalse);
      expect(f.squadLockedB, isFalse);
    });
  });

  group('playerUids spans both squads', () {
    test('a side-only write must still summarise the whole match', () {
      // `playerUids` is what the settlement rules read to decide whether a
      // scorer may write ratings onto a player's profile. If one club's write
      // replaced it with only its own players, the opponent's players would
      // be dropped from the match they actually played in.
      const f = Fixture(
        id: 'fx1',
        orgId: 'xyz_club',
        compId: 'comp1',
        entrantAId: 'abc_club',
        entrantBId: 'xyz_club',
        entrantAName: 'ABC Club',
        entrantBName: 'XYZ Club',
        status: FixtureStatus.scheduled,
        participantOrgIds: ['abc_club', 'xyz_club'],
        lineupA: [MatchPlayer(id: 'u1', name: 'Ravi', uid: 'u1')],
        lineupB: [MatchPlayer(id: 'u2', name: 'Sita', uid: 'u2')],
      );
      expect(f.playerUids, containsAll(['u1', 'u2']));
    });

    test('guests contribute nothing, since nothing can accrue to them', () {
      const f = Fixture(
        id: 'fx1',
        orgId: 'o',
        compId: 'c',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'A',
        entrantBName: 'B',
        status: FixtureStatus.scheduled,
        lineupA: [MatchPlayer(id: 'g1', name: 'Borrowed player')],
        lineupB: [MatchPlayer(id: 'u2', name: 'Sita', uid: 'u2')],
      );
      expect(f.playerUids, ['u2']);
    });
  });
}
