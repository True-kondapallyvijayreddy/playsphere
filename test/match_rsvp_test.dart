import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/announcement.dart';
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
}
