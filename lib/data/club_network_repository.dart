import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/club_thread.dart';
import '../core/models/organization.dart';
import 'org_repository.dart' show guard, guardStream;

/// The club owners' network: one club's owner talking to another's.
///
/// ## What this is for
///
/// Everything else in the product connects a club to its own members. Nothing
/// connected a club to the club down the road, and that is the relationship
/// grassroots sport actually runs on — a school looking for a fixture, an
/// academy with three spare slots in a tournament, a village club that wants
/// to know who else plays leather-ball cricket within an hour's drive. That
/// conversation currently happens in a WhatsApp group somebody's uncle
/// administers, and the season it produces never reaches the app.
///
/// So: a directory of clubs filterable by sport and by place (reusing
/// `DiscoveryRepository` — the search that already exists, rather than a
/// second one that disagrees with it), and a thread per pair of clubs, with
/// seasons and events attachable to a message so an invitation is one tap to
/// open rather than a pasted link.
///
/// ## Why the entitlement is checked on SENDING and not on reading
///
/// This is a paid-plan feature: reaching every other club on the platform is
/// exactly the kind of thing a ₹999 club plan should buy, and it is the first
/// thing in the product that is worth money to an organizer rather than to a
/// player. But a paywall that lets a club RECEIVE a fixture offer and then
/// refuses to let it answer is not a paywall, it is a broken inbox — the club
/// that paid is the one left waiting. So:
///
///  * reading a conversation is open to both clubs' owners, always;
///  * opening a NEW conversation needs an active club plan;
///  * replying inside a thread that already exists stays open, plan or no
///    plan — a conversation, once started, belongs to both clubs.
///
/// `firestore.rules` enforces all three. The checks here exist to fail fast
/// with a message a person can act on, never as the security boundary.
class ClubNetworkRepository {
  const ClubNetworkRepository();

  /// The longest a single message may be.
  ///
  /// Bounded for the same reason the membership introduction is: this is a
  /// display payload rendered in a bubble, and the only real risk is somebody
  /// pasting a season's entire rulebook into an inbox. Mirrored in
  /// `firestore.rules`.
  static const maxMessageLength = 2000;

  /// Every conversation one club is part of, from its own inbox.
  Stream<List<ClubThread>> watchThreads(String orgId) => guardStream(
        () => Refs.threadsForClub(orgId).snapshots().map(
              (snap) => [
                for (final d in snap.docs)
                  ClubThread.fromDoc(d, myOrgId: orgId),
              ],
            ),
      );

  /// One club's row for one conversation. Emits null until it exists — a
  /// conversation is created by its first message, not by opening the screen.
  Stream<ClubThread?> watchThread({
    required String orgId,
    required String threadId,
  }) =>
      guardStream(
        () => Refs.clubInboxRow(orgId, threadId).snapshots().map(
              (doc) =>
                  doc.exists ? ClubThread.fromDoc(doc, myOrgId: orgId) : null,
            ),
      );

  /// The conversation itself, oldest first.
  ///
  /// Queried newest-first — that is the half worth holding a listener over —
  /// and reversed here, because a conversation reads downwards.
  Stream<List<ClubMessage>> watchMessages(String threadId) => guardStream(
        () => Refs.clubMessageHistory(threadId).snapshots().map(
              (snap) => [
                for (final d in snap.docs.reversed) ClubMessage.fromDoc(d),
              ],
            ),
      );

  /// Sends a message on behalf of [from] to [to], creating both clubs' inbox
  /// rows if this is the first thing either has ever said.
  ///
  /// One batch, three writes: the message, and a summary row on each side.
  /// They have to land together, or an inbox shows a preview of a message
  /// that is not there — which on a phone that loses signal mid-send is a
  /// conversation that looks answered and is not.
  ///
  /// A batch and not a transaction, deliberately. A transaction needs the
  /// network, and the owner typing this is as likely to be standing at a
  /// ground with one bar as sitting at a desk; a batch goes into the same
  /// offline queue every other write in the product uses and lands when the
  /// signal does. Nothing here needs a read-modify-write: every field is
  /// either overwritten wholesale or is a server timestamp, so a first send
  /// and a hundredth are the same write, and two clubs writing to each other
  /// for the first time in the same second cannot collide.
  ///
  /// The one asymmetry between the two rows is the point of the whole shape:
  /// the sender marks its OWN row read, and does not touch the recipient's
  /// marker. `firestore.rules` enforces that — a sender who could stamp the
  /// recipient's marker could deliver a fixture offer that never shows as
  /// unread.
  Future<String> sendMessage({
    required Organization from,
    required Organization to,
    required String senderUid,
    required String senderName,
    String text = '',
    ThreadShare? share,
  }) =>
      guard(() async {
        final body = text.trim();
        if (body.isEmpty && share == null) {
          throw ArgumentError('A message needs words or something shared.');
        }

        final threadId = ClubThread.idFor(from.id, to.id);
        final pair = ClubThread.pairOf(from.id, to.id);
        final messageRef = Refs.clubMessages(threadId).doc();

        final message = ClubMessage(
          id: messageRef.id,
          senderOrgId: from.id,
          senderUid: senderUid,
          senderName: senderName,
          text: body.length > maxMessageLength
              ? body.substring(0, maxMessageLength)
              : body,
          share: share,
        );
        final preview = message.preview;

        final batch = Refs.db.batch();

        batch.set(
          Refs.clubInboxRow(from.id, threadId),
          {
            'orgIds': pair,
            'otherOrgId': to.id,
            'otherOrgName': to.name,
            'otherOrgLogoUrl': to.logoUrl,
            'lastMessage': preview,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastSenderOrgId': from.id,
            // The sender has by definition read everything in the thread,
            // including what they just wrote. Without this their own send
            // would mark it unread for them the moment the server stamps it.
            'lastReadAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        batch.set(
          Refs.clubInboxRow(to.id, threadId),
          {
            'orgIds': pair,
            'otherOrgId': from.id,
            'otherOrgName': from.name,
            'otherOrgLogoUrl': from.logoUrl,
            'lastMessage': preview,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastSenderOrgId': from.id,
          },
          SetOptions(merge: true),
        );

        batch.set(messageRef, {
          'senderOrgId': message.senderOrgId,
          'senderUid': message.senderUid,
          'senderName': message.senderName,
          'text': message.text,
          if (share != null) 'share': share.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        await batch.commit();
        return threadId;
      });

  /// Marks a conversation read for [orgId], as of now.
  ///
  /// Not awaited by its caller and deliberately silent: this is housekeeping
  /// behind a screen somebody opened to read, and a failed read marker must
  /// never surface as an error over the conversation they came for. The next
  /// visit writes it again.
  Future<void> markRead({
    required String threadId,
    required String orgId,
  }) =>
      guard(() => Refs.clubInboxRow(orgId, threadId).set(
            {'lastReadAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          ));
}
