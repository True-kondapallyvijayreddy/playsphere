import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/announcement.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/organization.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/community/widgets/match_rsvp_card.dart';
import 'package:playsphere/features/home/home_providers.dart';

/// Match availability calls: the model, and the clash rule.
///
/// The clash rule is the part worth pinning hardest. It is enforced twice —
/// once in `clashesFor` here, and once in `onMatchRsvp` in functions/index.js
/// — and the two have to agree. A client that warns about a clash the server
/// does not notice, or the reverse, is worse than having neither.
void main() {
  Announcement call({
    required String id,
    required DateTime when,
    Map<String, int> votes = const {},
    String title = 'Sunday game',
    int maxPlayers = 0,
    String sportId = 'cricket',
  }) =>
      Announcement(
        id: id,
        orgId: 'org1',
        authorUid: 'organizer',
        authorName: 'Captain',
        title: title,
        content: '',
        poll: Poll(options: Rsvp.options, votes: votes),
        match: MatchCall(
          sportId: sportId,
          matchDate: when,
          venue: 'Gymkhana',
          maxPlayers: maxPlayers,
        ),
      );

  final sunday6pm = DateTime(2026, 8, 23, 18);

  group('a match call is a poll with four extra facts', () {
    test('it is only an RSVP when it has BOTH the match and the poll', () {
      expect(call(id: 'a', when: sunday6pm).isMatchRsvp, isTrue);

      // A notice ABOUT a match is not a call for availability, and must not
      // draw voting buttons that write nowhere.
      const notice = Announcement(
        id: 'b',
        orgId: 'org1',
        authorUid: 'u',
        authorName: 'Captain',
        title: 'Ground booked',
        content: '',
      );
      expect(notice.isMatchRsvp, isFalse);
    });

    test('it survives a round trip through Firestore', () {
      final original = call(
        id: 'a',
        when: sunday6pm,
        maxPlayers: 22,
        votes: const {'u1': Rsvp.yes, 'u2': Rsvp.no},
      );
      final restored = Announcement.fromDoc(
        Map<String, dynamic>.from(original.toCreate())
          // `toCreate` writes a server sentinel for createdAt, which only the
          // server resolves; everything else must come back as it went in.
          ..remove('createdAt'),
        'a',
      );

      expect(restored.isMatchRsvp, isTrue);
      expect(restored.match!.sportId, 'cricket');
      expect(restored.match!.matchDate, sunday6pm);
      expect(restored.match!.maxPlayers, 22);
      expect(restored.poll!.voteOf('u1'), Rsvp.yes);
      expect(restored.poll!.voteOf('u2'), Rsvp.no);
    });

    test('a call with no kick-off degrades to a plain poll', () {
      final broken = Announcement.fromDoc(const {
        'orgId': 'org1',
        'title': 'Match',
        'poll': {'options': Rsvp.options},
        'match': {'sportId': 'cricket'},
      }, 'a');
      expect(broken.match, isNull);
      expect(broken.isMatchRsvp, isFalse);
      // The poll still works — the question is answerable even though the
      // card cannot draw a date.
      expect(broken.isPoll, isTrue);
    });
  });

  group('surplus', () {
    test('more yeses than seats is a surplus', () {
      final c = call(id: 'a', when: sunday6pm, maxPlayers: 4);
      expect(c.match!.hasSurplus(4), isFalse);
      expect(c.match!.hasSurplus(10), isTrue);
    });

    test('no target is never a surplus, however many turn up', () {
      // Zero means "as many as show up". Offering to split an open invitation
      // into a tournament because eight people answered is inventing a
      // problem the organizer did not have.
      final c = call(id: 'a', when: sunday6pm);
      expect(c.match!.hasSurplus(30), isFalse);
    });
  });

  group('the roster', () {
    test('names come back grouped by answer, and sorted', () {
      final c = call(id: 'a', when: sunday6pm, votes: const {
        'zara': Rsvp.yes,
        'anil': Rsvp.yes,
        'bina': Rsvp.maybe,
        'chetan': Rsvp.no,
      });
      // Sorted, so a card does not reshuffle its roster on every snapshot.
      expect(c.poll!.votersFor(Rsvp.yes), ['anil', 'zara']);
      expect(c.poll!.votersFor(Rsvp.maybe), ['bina']);
      expect(c.poll!.countFor(Rsvp.yes), 2);
    });
  });

  group('clashes', () {
    test('two yeses within the window clash', () {
      final a = call(id: 'a', when: sunday6pm, votes: const {'me': Rsvp.yes});
      final b = call(
        id: 'b',
        when: sunday6pm.add(const Duration(hours: 1)),
        title: 'Badminton',
        votes: const {'me': Rsvp.yes},
      );
      expect(
        clashesFor(candidate: a, against: [a, b], uid: 'me').single.id,
        'b',
      );
    });

    test('a match far enough away does not clash', () {
      final a = call(id: 'a', when: sunday6pm, votes: const {'me': Rsvp.yes});
      final b = call(
        id: 'b',
        when: sunday6pm.add(const Duration(hours: 5)),
        votes: const {'me': Rsvp.yes},
      );
      expect(clashesFor(candidate: a, against: [a, b], uid: 'me'), isEmpty);
    });

    test('a maybe is not a promise and never clashes', () {
      // Warning somebody off a match they have not committed to is how a
      // useful alert becomes one people learn to dismiss.
      final a = call(id: 'a', when: sunday6pm, votes: const {'me': Rsvp.yes});
      final b = call(
        id: 'b',
        when: sunday6pm,
        votes: const {'me': Rsvp.maybe},
      );
      expect(clashesFor(candidate: a, against: [a, b], uid: 'me'), isEmpty);
    });

    test('somebody else being double-booked is not my clash', () {
      final a = call(id: 'a', when: sunday6pm, votes: const {'me': Rsvp.yes});
      final b = call(
        id: 'b',
        when: sunday6pm,
        votes: const {'someone_else': Rsvp.yes},
      );
      expect(clashesFor(candidate: a, against: [a, b], uid: 'me'), isEmpty);
    });

    test('a call never clashes with itself', () {
      final a = call(id: 'a', when: sunday6pm, votes: const {'me': Rsvp.yes});
      expect(clashesFor(candidate: a, against: [a], uid: 'me'), isEmpty);
    });

    test('the window matches the one the Cloud Function enforces', () {
      // functions/index.js hard-codes CLASH_WINDOW_MS = 3 * 60 * 60 * 1000.
      // These two are one rule implemented twice and must not drift.
      expect(kClashWindow, const Duration(hours: 3));
    });

    test('the yes index matches the one the Cloud Function reads', () {
      // functions/index.js hard-codes RSVP_YES = 0. The index is stored in
      // every vote, so a mismatch silently reads Maybe as In.
      expect(Rsvp.yes, 0);
      expect(Rsvp.options.first, 'In');
    });
  });

  Widget harness({
    required String uid,
    required String authorUid,
    bool canOrganize = true,
    ChallengeCallTarget? forChallenge,
    FixtureCallTarget? forFixture,
  }) {
    final announcement = Announcement(
      id: 'a1',
      orgId: 'org1',
      authorUid: authorUid,
      authorName: 'Captain Ravi',
      title: 'Sunday game',
      content: '',
      poll: const Poll(
        options: Rsvp.options,
        votes: {'p1': Rsvp.yes, 'p2': Rsvp.yes},
      ),
      match: MatchCall(
        sportId: 'cricket',
        matchDate: DateTime.now().add(const Duration(days: 2)),
        venue: 'Gymkhana',
        forChallenge: forChallenge,
        forFixture: forFixture,
      ),
    );

    return ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        organizationProvider.overrideWith(
          (ref, id) => Stream.value(
            const Organization(
              id: 'org1',
              name: 'Nizampet High School',
              orgType: OrgType.school,
              visibility: OrgVisibility.public,
              ownerUid: 'owner',
              inviteCode: 'ABC234',
            ),
          ),
        ),
        orgMembersProvider.overrideWith(
          (ref, id) => Stream.value(const <Membership>[]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            // `canOrganize` is the club-level capability the screens pass
            // in. It defaults to true here so that most cases below differ
            // only in authorship — which is the whole point.
            child: MatchRsvpCard(
              announcement: announcement,
              canOrganize: canOrganize,
            ),
          ),
        ),
      ),
    );
  }

  // Who may call a match OFF, as against who may run it.
  //
  // The rule the card enforces: drafting the sides is any organizer's, but
  // editing and cancelling belong to the person who put the call out. Before
  // this, every admin in the club saw "Cancel match" on every admin's call —
  // and cancelling deletes the call and its whole discussion.
  group('only the author can call a match off', () {


    /// The card starts collapsed, so anything past the vote row needs a tap.
    Future<void> expand(WidgetTester tester) async {
      await tester.tap(find.textContaining('Who is in'));
      await tester.pumpAndSettle();
    }

    testWidgets('the author gets Edit and Cancel, behind their own menu',
        (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'me'));
      await tester.pump();

      final menu = find.byTooltip('Your call');
      expect(menu, findsOneWidget);

      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Edit call'), findsOneWidget);
      expect(find.text('Cancel match'), findsOneWidget);
    });

    testWidgets('another admin gets no menu at all', (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'someone_else'));
      await tester.pump();

      expect(find.byTooltip('Your call'), findsNothing);
      expect(find.text('Cancel match'), findsNothing);
      expect(find.text('Edit call'), findsNothing);
    });

    testWidgets('and is told whose call it is when they look', (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'someone_else'));
      await tester.pump();
      await expand(tester);

      expect(
        find.textContaining('only they can edit or cancel it'),
        findsOneWidget,
      );
    });

    testWidgets('everybody else still answers it', (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'someone_else'));
      await tester.pump();

      // The vote row is never behind the expand — it is the one thing every
      // recipient of the card has to do. The buttons carry the running tally
      // alongside the word.
      expect(find.text('In 2'), findsOneWidget);
      expect(find.text('Maybe 0'), findsOneWidget);
      expect(find.text('Out 0'), findsOneWidget);
    });

    testWidgets('an admin who is not the author can still make the teams',
        (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'someone_else'));
      await tester.pump();

      // Collapsed, one tap from the card. Drafting the sides is the whole
      // reason the call exists.
      expect(find.text('Make teams'), findsOneWidget);
    });

    testWidgets('a plain member is offered neither', (tester) async {
      await tester.pumpWidget(
        harness(uid: 'me', authorUid: 'someone_else', canOrganize: false),
      );
      await tester.pump();

      expect(find.text('Make teams'), findsNothing);
      expect(find.byTooltip('Your call'), findsNothing);
      expect(find.text('In 2'), findsOneWidget);
    });
  });


  // The three reasons a call gets put out, and the three different next steps
  // they lead to. Getting this wrong is not cosmetic: offering "Make teams" on
  // a challenge call builds a second, private match that the club being
  // challenged is not in and nobody is expecting.
  group('what happens once the answers are in', () {
    testWidgets('a club\'s own game deals the yeses into two sides',
        (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'me'));
      await tester.pump();

      expect(find.text('Make teams'), findsOneWidget);
      expect(find.text('Open challenge'), findsNothing);
    });

    testWidgets('a challenge call goes to the challenge board instead',
        (tester) async {
      await tester.pumpWidget(harness(
        uid: 'me',
        authorUid: 'me',
        forChallenge: const ChallengeCallTarget(
          challengeId: 'ch1',
          opponentName: 'Kompally Sports Academy',
        ),
      ));
      await tester.pump();

      expect(find.text('Open challenge'), findsOneWidget);
      // The wrong button must be gone, not merely deprioritised.
      expect(find.text('Make teams'), findsNothing);
    });

    testWidgets('a call for a fixture that exists goes to that match',
        (tester) async {
      await tester.pumpWidget(harness(
        uid: 'me',
        authorUid: 'me',
        forFixture: const FixtureCallTarget(
          orgId: 'org1',
          compId: 'comp1',
          fixtureId: 'fx1',
          side: 'A',
        ),
      ));
      await tester.pump();

      expect(find.text('Open match'), findsOneWidget);
      expect(find.text('Make teams'), findsNothing);
    });

    testWidgets('and neither is offered a way to split its own side',
        (tester) async {
      await tester.pumpWidget(harness(
        uid: 'me',
        authorUid: 'me',
        forChallenge: const ChallengeCallTarget(
          challengeId: 'ch1',
          opponentName: 'Kompally Sports Academy',
        ),
      ));
      await tester.pump();
      await tester.tap(find.textContaining('Who is in'));
      await tester.pumpAndSettle();

      expect(find.text('Mini-tournament instead'), findsNothing);
      expect(
        find.textContaining('is your side for this challenge'),
        findsOneWidget,
      );
    });
  });

  // "Show me four or five at once." A member in three clubs during a busy week
  // has five of these waiting, and a card they have to scroll past to reach the
  // next one is a card they answer late.
  group('the card is compact enough to stack', () {
    testWidgets('a collapsed call fits four to five on a phone screen',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(uid: 'me', authorUid: 'me'),
      );
      await tester.pump();

      final height = tester.getSize(find.byType(MatchRsvpCard)).height;
      // 800pt is roughly what a phone leaves for the list once the app bar and
      // the system insets have taken theirs. Four has to fit; the budget is
      // set at five so that ordinary drift is caught before it costs a card.
      expect(height, lessThanOrEqualTo(800 / 4));
      expect(height, greaterThan(100), reason: 'a card this short is broken');
    });

    testWidgets('expanding one reveals the detail it was hiding',
        (tester) async {
      await tester.pumpWidget(harness(uid: 'me', authorUid: 'me'));
      await tester.pump();

      // Collapsed: no roster, no discussion.
      expect(find.textContaining('Discussion'), findsNothing);

      final collapsed = tester.getSize(find.byType(MatchRsvpCard)).height;
      await tester.tap(find.textContaining('Who is in'));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(MatchRsvpCard)).height,
        greaterThan(collapsed),
      );
      expect(find.text('Your call.'), findsOneWidget);
    });
  });
}
