import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/club_thread.dart';

/// The two facts the club network is built on and cannot get wrong: that both
/// owners land in the SAME conversation, and that an unread badge means
/// something waiting from the other side.
void main() {
  group('ClubThread.idFor — one conversation, whoever taps first', () {
    test('the pair sorts, so the id is the same from either end', () {
      expect(ClubThread.idFor('bbb', 'aaa'), ClubThread.idFor('aaa', 'bbb'));
      expect(ClubThread.idFor('aaa', 'bbb'), 'aaa__bbb');
    });

    test('the id decomposes the way the security rules decompose it', () {
      // `firestore.rules` authorises a thread by splitting its document id on
      // `__` and checking the caller owns one of the halves. If that ever
      // stops matching this, every read is refused.
      final id = ClubThread.idFor('clubTwo', 'clubOne');
      final parts = id.split('__');
      expect(parts, hasLength(2));
      expect(parts.toSet(), {'clubOne', 'clubTwo'});
      expect(parts[0].compareTo(parts[1]), lessThan(0));
    });
  });

  group('ClubThread — the row a club reads', () {
    ClubThread rowFor(String myOrgId) => ClubThread(
          id: 'a__b',
          myOrgId: myOrgId,
          orgIds: const ['a', 'b'],
          otherOrgId: myOrgId == 'a' ? 'b' : 'a',
          otherOrgName: myOrgId == 'a' ? 'Beta Academy' : 'Alpha CC',
        );

    test('names the club on the other side', () {
      expect(rowFor('a').otherOrgId, 'b');
      expect(rowFor('a').otherOrgName, 'Beta Academy');
      expect(rowFor('b').otherOrgId, 'a');
    });
  });

  group('ClubThread.isUnread', () {
    final sent = DateTime(2026, 3, 1, 10);

    ClubThread rowWith({
      required String sender,
      DateTime? read,
    }) =>
        ClubThread(
          id: 'a__b',
          myOrgId: 'a',
          orgIds: const ['a', 'b'],
          otherOrgId: 'b',
          lastMessage: 'Fixture on Saturday?',
          lastMessageAt: sent,
          lastSenderOrgId: sender,
          lastReadAt: read,
        );

    test('unread for the club that has never opened it', () {
      expect(rowWith(sender: 'b').isUnread, isTrue);
    });

    test('never unread for the club that sent the last message', () {
      // Otherwise every club carries a permanent badge for its own outgoing
      // messages until it re-opens a thread it has nothing to read in.
      expect(rowWith(sender: 'a').isUnread, isFalse);
    });

    test('read once the marker is past the message', () {
      expect(
        rowWith(sender: 'b', read: sent.add(const Duration(seconds: 1)))
            .isUnread,
        isFalse,
      );
    });

    test('unread again when a newer message arrives after the marker', () {
      expect(
        rowWith(sender: 'b', read: sent.subtract(const Duration(hours: 2)))
            .isUnread,
        isTrue,
      );
    });

    test('a row with nothing in it is not unread', () {
      const empty = ClubThread(
        id: 'a__b',
        myOrgId: 'a',
        orgIds: ['a', 'b'],
        otherOrgId: 'b',
      );
      expect(empty.isUnread, isFalse);
    });
  });

  group('ClubMessage.preview — what the inbox shows as the last line', () {
    test('the words, when there are words', () {
      const m = ClubMessage(
        id: '1',
        senderOrgId: 'a',
        senderUid: 'u',
        senderName: 'Ramesh',
        text: 'Can you play Saturday?',
      );
      expect(m.preview, 'Can you play Saturday?');
    });

    test('what was shared, when a message is only an attachment', () {
      const m = ClubMessage(
        id: '1',
        senderOrgId: 'a',
        senderUid: 'u',
        senderName: 'Ramesh',
        share: ThreadShare(
          kind: ThreadShareKind.season,
          orgId: 'a',
          refId: 's1',
          title: 'Summer League',
        ),
      );
      expect(m.preview, 'Shared a season · Summer League');
      expect(m.isEmpty, isFalse);
    });

    test('a message with neither is empty and must not be sent', () {
      const m = ClubMessage(
        id: '1',
        senderOrgId: 'a',
        senderUid: 'u',
        senderName: 'Ramesh',
        text: '   ',
      );
      expect(m.isEmpty, isTrue);
      expect(m.preview, '');
    });
  });

  group('ThreadShare — the copy stored on a message', () {
    test('round-trips through the map it is written as', () {
      final share = ThreadShare(
        kind: ThreadShareKind.season,
        orgId: 'club1',
        refId: 'season1',
        title: 'District Open',
        subtitle: 'Entries open · 4 events',
        sportId: 'cricket',
        startsAt: DateTime(2026, 6, 1),
        route: '/org/club1/live-tournament/season1',
      );
      final back = ThreadShare.fromMap(
        share.toMap().map((k, v) => MapEntry(k, v as dynamic)),
      );
      expect(back!.kind, ThreadShareKind.season);
      expect(back.title, 'District Open');
      expect(back.sportId, 'cricket');
      expect(back.route, '/org/club1/live-tournament/season1');
      expect(back.startsAt, DateTime(2026, 6, 1));
    });

    test('an empty or id-less map is not a share', () {
      expect(ThreadShare.fromMap(const {}), isNull);
      expect(ThreadShare.fromMap(const {'kind': 'season'}), isNull);
    });

    test('an unrecognised kind degrades rather than throwing', () {
      // An older build reading a kind a newer one invented must still draw
      // the card, not crash the thread.
      final share = ThreadShare.fromMap(const {
        'kind': 'something_new',
        'refId': 'x',
        'orgId': 'y',
        'title': 'Whatever',
      });
      expect(share!.kind, ThreadShareKind.club);
      expect(share.title, 'Whatever');
    });
  });
}
