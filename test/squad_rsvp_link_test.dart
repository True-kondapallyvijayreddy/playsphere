import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/announcement.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';

/// Joining an availability call to one club's side of a challenge match.
///
/// The two halves existed and nothing connected them: a club could ask who
/// was free, and a club could fill its side, but `MatchCall` carried no
/// fixture — so an organizer read the poll and retyped every name, and the
/// two lists then drifted apart. These tests protect the join itself and the
/// two ways it could go wrong: a call that answers for the wrong match, and a
/// call that answers for the wrong side of the right one.
void main() {
  MatchCall call({FixtureCallTarget? target}) => MatchCall(
        sportId: 'cricket',
        matchDate: DateTime(2026, 8, 30, 16),
        venue: 'Gachibowli Ground',
        maxPlayers: 12,
        forFixture: target,
      );

  const target = FixtureCallTarget(
    orgId: 'org_host',
    compId: 'comp_1',
    fixtureId: 'fix_1',
    side: 'b',
  );

  group('what a call is asking about', () {
    test('an ordinary club call is bound to no match', () {
      // Still the common case: clubs poll availability BEFORE there is a
      // fixture, and requiring one first would forbid the order most clubs
      // work in.
      final c = call();
      expect(c.isForFixture, isFalse);
      expect(c.forFixture, isNull);
    });

    test('a squad call names the match and the side', () {
      final c = call(target: target);
      expect(c.isForFixture, isTrue);
      expect(c.forFixture!.fixtureId, 'fix_1');
      expect(c.forFixture!.side, 'b');
    });

    test('all four ids survive the wire, so the fixture stays addressable',
        () {
      // A visiting club's call sits on its OWN board while the fixture lives
      // under the host, so the path cannot be reconstructed from the
      // announcement's own orgId.
      final back = MatchCall.fromMap(call(target: target).toMap());
      expect(back!.forFixture!.orgId, 'org_host');
      expect(back.forFixture!.compId, 'comp_1');
      expect(back.forFixture!.fixtureId, 'fix_1');
      expect(back.forFixture!.side, 'b');
    });

    test('a target that cannot address a fixture degrades to none', () {
      // Rendering an "add them to the squad" button that leads nowhere is
      // worse than treating this as the ordinary poll it has become.
      final back = MatchCall.fromMap({
        'sportId': 'cricket',
        'matchDate': DateTime(2026, 8, 30).millisecondsSinceEpoch,
        'forFixture': {'orgId': 'org_host', 'compId': 'comp_1', 'side': 'b'},
      });
      expect(back?.forFixture, isNull);
    });

    test('a call with no kick-off is not a call at all', () {
      expect(MatchCall.fromMap({'sportId': 'cricket'}), isNull);
    });
  });

  group('readiness', () {
    Fixture fixture({bool lockedA = false, bool lockedB = false}) => Fixture(
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
          squadLockedB: lockedB,
        );

    test('one side locked is not ready', () {
      final f = fixture(lockedA: true);
      expect(f.bothSquadsLocked, isFalse);
      // ...and the lock is per-club, so A's does not speak for B.
      expect(f.squadLockedFor('org_guest'), isTrue);
      expect(f.squadLockedFor('org_host'), isFalse);
    });

    test('both locked is the signal to start', () {
      expect(fixture(lockedA: true, lockedB: true).bothSquadsLocked, isTrue);
    });

    test('a club outside the match locks nothing', () {
      expect(
        fixture(lockedA: true, lockedB: true).squadLockedFor('org_other'),
        isFalse,
      );
    });
  });

  group('who a call can speak for', () {
    test('two calls for the same match but different sides do not mix', () {
      const a = FixtureCallTarget(
        orgId: 'org_host',
        compId: 'comp_1',
        fixtureId: 'fix_1',
        side: 'a',
      );
      // Both clubs poll about the same fixture, on their own boards. The side
      // is what keeps one club's yeses off the other's team sheet — and it is
      // derived from the club, never typed.
      expect(a.fixtureId, target.fixtureId);
      expect(a.side, isNot(target.side));
    });
  });
}
