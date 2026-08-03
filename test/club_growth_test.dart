import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/announcement.dart';
import 'package:playsphere/core/models/club_file.dart';
import 'package:playsphere/core/router/app_router.dart';

/// Step 3 of the flow: growing a club.
///
/// Invite by link and QR, polls, files and a gallery — the things a club uses
/// to become a group of people rather than a row in a database.
void main() {
  group('invite links', () {
    test('a join link carries the code', () {
      expect(Routes.joinWithCode('ABC234'), '/orgs/join?code=ABC234');
    });

    test('a code with awkward characters survives the round trip', () {
      final link = Routes.joinWithCode('A B&C');
      final code = Uri.parse(link).queryParameters['code'];
      expect(code, 'A B&C');
    });

    test('the shareable invite is absolute', () {
      // What goes in a WhatsApp message or a QR code. A relative path would
      // resolve against nothing on the receiving phone.
      final url = Routes.inviteUrl('ABC234');
      expect(Uri.parse(url).hasScheme, isTrue);
      expect(url, endsWith('/orgs/join?code=ABC234'));
    });
  });

  group('club polls', () {
    Poll poll({Map<String, int> votes = const {}, bool closed = false}) => Poll(
          options: const ['Ground A', 'Ground B', "Can't make it"],
          votes: votes,
          closed: closed,
        );

    test('counts each option', () {
      final p = poll(votes: {'u1': 0, 'u2': 0, 'u3': 1});
      expect(p.countFor(0), 2);
      expect(p.countFor(1), 1);
      expect(p.countFor(2), 0);
      expect(p.totalVotes, 3);
    });

    test('reports what a given member chose', () {
      final p = poll(votes: {'u1': 2});
      expect(p.voteOf('u1'), 2);
      expect(p.voteOf('nobody'), isNull);
    });

    test('shares sum to one across the options that were chosen', () {
      final p = poll(votes: {'u1': 0, 'u2': 1, 'u3': 1, 'u4': 1});
      expect(p.shareFor(0), closeTo(0.25, 1e-9));
      expect(p.shareFor(1), closeTo(0.75, 1e-9));
      expect(p.shareFor(2), 0);
    });

    test('an empty poll divides by zero nowhere', () {
      final p = poll();
      expect(p.shareFor(0), 0);
      expect(p.totalVotes, 0);
    });

    test('one member holds exactly one vote', () {
      // The votes map is keyed by uid, so changing your mind replaces your
      // answer — it can never add a second.
      final p = poll(votes: {'u1': 0});
      final changed = Poll(options: p.options, votes: {...p.votes, 'u1': 2});
      expect(changed.totalVotes, 1);
      expect(changed.voteOf('u1'), 2);
    });

    test('an announcement without options is not a poll', () {
      const plain = Announcement(
        id: 'a1',
        orgId: 'o1',
        authorUid: 'u1',
        authorName: 'Admin',
        title: 'Ground is wet',
        content: 'No play today.',
      );
      expect(plain.isPoll, isFalse);
      expect(plain.toCreate()['poll'], isNull);
    });

    test('a poll with fewer than two options does not deserialise', () {
      // A question with one answer is not a question.
      expect(Poll.fromMap({'options': <String>[]}), isNull);
      expect(Poll.fromMap(null), isNull);
    });

    test('a poll round-trips through the wire', () {
      final back = Poll.fromMap(
        Map<String, dynamic>.from(poll(votes: {'u1': 1}, closed: true).toMap()),
      );
      expect(back?.options.length, 3);
      expect(back?.voteOf('u1'), 1);
      expect(back?.closed, isTrue);
    });
  });

  group('club files', () {
    ClubFile file(int bytes) => ClubFile(
          id: 'f1',
          orgId: 'o1',
          name: 'Fixtures list',
          url: 'https://example.test/f1',
          storagePath: 'clubFiles/o1/u1/f1',
          uploaderUid: 'u1',
          uploaderName: 'Admin',
          sizeBytes: bytes,
        );

    test('sizes read as something a person understands', () {
      expect(file(512).readableSize, '512 B');
      expect(file(2048).readableSize, '2 KB');
      expect(file(3 * 1024 * 1024).readableSize, '3.0 MB');
    });

    test('an unknown size shows nothing rather than "0 B"', () {
      expect(file(0).readableSize, '');
    });

    test('the storage path is carried so the bytes can be removed with it', () {
      // Without it a deleted file leaves its object behind, billed forever.
      expect(file(1).toCreate()['storagePath'], 'clubFiles/o1/u1/f1');
    });
  });
}
