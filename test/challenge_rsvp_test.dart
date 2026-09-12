import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/announcement.dart';

/// Asking a club who is in for a challenge, before the challenge is agreed.
///
/// Two things are new here and both are load-bearing.
///
/// [ChallengeCallTarget] is what lets the question be asked at all. A club
/// could only ask about a match that already existed, which meant asking after
/// the date was fixed — so a captain who could not raise eleven had to go back
/// and apologise for a fixture their own club had committed to. The target is
/// also the thread that ties the answers to the team sheet later: the fixture
/// `acceptChallenge` creates carries the same challenge id as its `sourceId`,
/// which is how `SquadRsvpActions` finds these answers without a second call.
///
/// [MatchCall.invitedUids] is what makes the question answerable. A village
/// club has a hundred and twenty members and an eleven-a-side match; asking
/// everybody produces forty yeses and twenty-nine apologies.
void main() {
  MatchCall call({
    ChallengeCallTarget? target,
    List<String> invitedUids = const [],
  }) =>
      MatchCall(
        sportId: 'cricket',
        matchDate: DateTime(2026, 8, 29, 16),
        venue: 'Gachibowli Ground',
        maxPlayers: 11,
        forChallenge: target,
        invitedUids: invitedUids,
      );

  Announcement post({
    String authorUid = 'uid_captain',
    ChallengeCallTarget? target,
    List<String> invitedUids = const [],
  }) =>
      Announcement(
        id: 'a1',
        orgId: 'org_village',
        authorUid: authorUid,
        authorName: 'Captain',
        title: 'We have challenged Kompally — who is in?',
        content: '',
        poll: const Poll(options: Rsvp.options),
        match: call(target: target, invitedUids: invitedUids),
      );

  const target = ChallengeCallTarget(
    challengeId: 'chal_7',
    opponentName: 'Kompally Sports Academy',
  );

  group('what a call is asking about', () {
    test('an ordinary club call is bound to no challenge', () {
      final c = call();
      expect(c.isForChallenge, isFalse);
      expect(c.forChallenge, isNull);
    });

    test('a challenge call names the challenge and the opponent', () {
      final c = call(target: target);
      expect(c.isForChallenge, isTrue);
      expect(c.forChallenge!.challengeId, 'chal_7');
      // Denormalized so a card can say who the match is against without a
      // second read — the same reason Challenge carries both clubs' names.
      expect(c.forChallenge!.opponentName, 'Kompally Sports Academy');
    });

    test('the target survives the wire, so the answers stay findable', () {
      // This is the join that lets a fortnight-old poll fill a team sheet the
      // day the opponent finally accepts. Lose it in the codec and the
      // organizer is retyping names again.
      final restored = MatchCall.fromMap(call(target: target).toMap());
      expect(restored!.forChallenge!.challengeId, 'chal_7');
      expect(restored.forChallenge!.opponentName, 'Kompally Sports Academy');
    });

    test('a target with no challenge id degrades to an ordinary call', () {
      // Better a plain availability call than a card whose "add them to the
      // squad" button points at nothing — the same degradation
      // FixtureCallTarget makes.
      expect(
        ChallengeCallTarget.fromMap(const {'opponentName': 'Somebody'}),
        isNull,
      );
    });

    test('a challenge call and a fixture call are not confused', () {
      final c = call(target: target);
      expect(c.isForChallenge, isTrue);
      expect(c.isForFixture, isFalse);
    });
  });

  group('who a call is addressed to', () {
    test('an open call asks the whole club', () {
      final c = call();
      expect(c.isTargeted, isFalse);
      expect(c.isAddressedTo('uid_anyone'), isTrue);
      expect(post().isAddressedTo('uid_anyone'), isTrue);
    });

    test('a named call asks only the people it names', () {
      final c = call(invitedUids: const ['uid_a', 'uid_b']);
      expect(c.isTargeted, isTrue);
      expect(c.isAddressedTo('uid_a'), isTrue);
      expect(c.isAddressedTo('uid_c'), isFalse);
    });

    test('the author is always addressed, named or not', () {
      // A captain who picks twelve players and is not one of them still has to
      // be able to find their own call. They are the one waiting on the
      // answers.
      final p = post(
        authorUid: 'uid_captain',
        invitedUids: const ['uid_a', 'uid_b'],
      );
      expect(p.isAddressedTo('uid_captain'), isTrue);
      expect(p.isAddressedTo('uid_c'), isFalse);
    });

    test('the audience survives the wire', () {
      final restored = MatchCall.fromMap(
        call(invitedUids: const ['uid_a', 'uid_b']).toMap(),
      );
      expect(restored!.invitedUids, ['uid_a', 'uid_b']);
      expect(restored.isAddressedTo('uid_b'), isTrue);
      expect(restored.isAddressedTo('uid_z'), isFalse);
    });

    test('an ordinary notice with no match is addressed to everyone', () {
      // Naming an audience is a property of a match call. A club notice has
      // always gone to the whole board and must keep doing so.
      const notice = Announcement(
        id: 'n1',
        orgId: 'org_village',
        authorUid: 'uid_captain',
        authorName: 'Captain',
        title: 'Ground booked',
        content: '',
      );
      expect(notice.isAddressedTo('uid_anyone'), isTrue);
    });
  });

  group('a targeted call is addressing, not access control', () {
    test('it is still a match RSVP that anybody could answer', () {
      // The announcement stays readable by the club, and `firestore.rules`
      // still lets any active member vote. What the audience changes is whose
      // dashboard it lands on and whose phone it pushes — deliberately, so a
      // member who hears about the match can go to the board and put their
      // hand up rather than being locked out of their own club's fixture.
      final p = post(target: target, invitedUids: const ['uid_a']);
      expect(p.isMatchRsvp, isTrue);
      expect(p.poll!.options, Rsvp.options);
    });
  });
}
