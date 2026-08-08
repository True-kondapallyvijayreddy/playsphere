import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/notifications/notification_model.dart';
import 'org_repository.dart' show guard, guardStream;

/// The durable half of a notification, backing the in-app inbox.
///
/// `NotificationService` (in `core/notifications/`) only ever sees a message
/// while the app is open to receive it — foreground, or the one that launched
/// it. Everything sent while a phone was asleep, or already dismissed from
/// the tray, was gone for good, and a member with no organizer capabilities
/// — who never sees anything on the Notifications screen's action-item lists
/// — had nothing there at all. `sendToUsers` in `functions/index.js` writes
/// one of these alongside every push it sends, so this screen has something
/// to read regardless of whether the push itself was ever seen.
class NotificationRepository {
  const NotificationRepository();

  /// The most recent notifications sent to this person, newest first.
  ///
  /// Capped at 50: this is a phone screen, not an archive, and a member of a
  /// long-running club could otherwise be streaming thousands of documents on
  /// every cold start.
  Stream<List<AppNotification>> watchFeed(String uid, {int limit = 50}) {
    return guardStream(
      () => Refs.notifications(uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(_fromDoc).toList()),
    );
  }

  AppNotification _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return AppNotification.fromDataPayload(
      data,
      id: doc.id,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    ).copyWith(read: data['read'] == true);
  }

  /// Marks one notification read — called the moment its card is tapped, not
  /// in a batch on screen exit, so a person who taps one and leaves is not
  /// shown it as unread again next time they open the app.
  Future<void> markRead(String uid, String id) => guard(
        () => Refs.notification(uid, id).update({
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Marks everything currently unread as read, for the "clear" action.
  Future<void> markAllRead(String uid, List<String> unreadIds) => guard(
        () async {
          if (unreadIds.isEmpty) return;
          final batch = Refs.db.batch();
          for (final id in unreadIds) {
            batch.update(Refs.notification(uid, id), {
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        },
      );
}
