import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';

/// Naming a team on your own side of a challenge match.
///
/// A challenge produces a fixture between two CLUBS — `entrantAId` and
/// `entrantBId` hold orgIds, and the whole squad-call mechanism keys off that
/// identity, in the app and independently in `firestore.rules`. So the team a
/// club fields is carried as a separate pointer rather than by overwriting
/// the entrant, and these tests protect the two ways that could go wrong: a
/// pointer that quietly displaces the club it belongs to, and a pointer that
/// survives a write path which had no business touching it.
void main() {
  Fixture fixture({
    String? teamAId,
    String? teamAName,
    String? teamBId,
    String? teamBName,
    bool lockedA = false,
  }) =>
      Fixture(
        id: 'fix_1',
        orgId: 'org_host',
        compId: 'comp_1',
        entrantAId: 'org_guest',
        entrantBId: 'org_host',
        entrantAName: 'Gachibowli Club',
        entrantBName: 'Kondapur Club',
        status: FixtureStatus.scheduled,
        participantOrgIds: const ['org_guest', 'org_host'],
        sportId: 'cricket',
        squadLockedA: lockedA,
        teamAId: teamAId,
        teamAName: teamAName,
        teamBId: teamBId,
        teamBName: teamBName,
      );

  group('side identity', () {
    test('naming a team does not change which club owns the side', () {
      final f = fixture(teamAId: 'team_u19', teamAName: 'Gachibowli U-19');

      // The whole squad-call chain — who may open a call, who may register,
      // which side a member lands on — resolves through this. If naming a
      // team moved it, every one of those breaks silently.
      expect(f.sideForOrg('org_guest'), 'a');
      expect(f.sideForOrg('org_host'), 'b');
      expect(f.entrantAId, 'org_guest');
    });

    test('a club that is not in the match still gets no side', () {
      expect(fixture(teamAId: 'team_u19').sideForOrg('org_other'), isNull);
    });
  });

  group('what the scoreboard says', () {
    test('the named team wins over the club name', () {
      final f = fixture(teamAId: 'team_u19', teamAName: 'Gachibowli U-19');
      // The club name is already above the fixture; repeating it where the
      // side should be is what made "one club, four teams" unreadable.
      expect(f.displayNameA(), 'Gachibowli U-19');
      // ...and the side that named nobody still reads as the club.
      expect(f.displayNameB(), 'Kondapur Club');
    });

    test('with no team named at all, nothing changes', () {
      final f = fixture();
      expect(f.displayNameA(), 'Gachibowli Club');
      expect(f.displayNameB(), 'Kondapur Club');
    });
  });

  group('readiness', () {
    test('one side named is not both', () {
      final f = fixture(teamAId: 'team_u19', teamAName: 'Gachibowli U-19');
      expect(f.anyTeamNamed, isTrue);
      expect(f.bothTeamsNamed, isFalse);
    });

    test('both named is the signal to start', () {
      final f = fixture(
        teamAId: 'team_u19',
        teamAName: 'Gachibowli U-19',
        teamBId: 'team_sunday',
        teamBName: 'Kondapur Sunday XI',
      );
      expect(f.bothTeamsNamed, isTrue);
    });

    test('a match where neither club uses a team is not stuck unready', () {
      // Naming a team is optional on both sides — a club opening its side to
      // its whole membership is the behaviour this was built next to, not a
      // half-finished version of it.
      final f = fixture();
      expect(f.anyTeamNamed, isFalse);
      expect(f.bothTeamsNamed, isFalse);
    });
  });

  group('the pointer survives only its own write path', () {
    test('copyWith cannot drop a named team', () {
      final f = fixture(
        teamAId: 'team_u19',
        teamAName: 'Gachibowli U-19',
        teamBId: 'team_sunday',
        teamBName: 'Kondapur Sunday XI',
      );
      // `copyWith` runs on every scoring event. A stale Fixture carried
      // through it must not be able to un-name a side between two
      // deliveries — the same reasoning that keeps `isDraft` and `sourceType`
      // off the parameter list.
      final after = f.copyWith(status: FixtureStatus.live);
      expect(after.teamAId, 'team_u19');
      expect(after.teamBName, 'Kondapur Sunday XI');
      expect(after.status, FixtureStatus.live);
    });

    test('a team survives a round trip through the wire format', () {
      final map = fixture(
        teamAId: 'team_u19',
        teamAName: 'Gachibowli U-19',
      ).toCreate();
      expect(map['teamAId'], 'team_u19');
      expect(map['teamAName'], 'Gachibowli U-19');
      // Written as explicit nulls rather than omitted, so a later write can
      // clear a side without the field having to be created first.
      expect(map.containsKey('teamBId'), isTrue);
      expect(map['teamBId'], isNull);
    });
  });

  group('locking', () {
    test('a locked side is what freezes the team, not the naming itself', () {
      final locked = fixture(
        teamAId: 'team_u19',
        teamAName: 'Gachibowli U-19',
        lockedA: true,
      );
      // Lock is per-side and per-club, and side A's lock says nothing about
      // side B — the two clubs do not answer to each other.
      expect(locked.squadLockedFor('org_guest'), isTrue);
      expect(locked.squadLockedFor('org_host'), isFalse);
      expect(locked.bothSquadsLocked, isFalse);
    });
  });
}
