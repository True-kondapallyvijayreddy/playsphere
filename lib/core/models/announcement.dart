import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// A post board update / notice inside a club (`orgs/{orgId}/announcements/{announcementId}`).
class Announcement {
  const Announcement({
    required this.id,
    required this.orgId,
    required this.authorUid,
    required this.authorName,
    required this.title,
    required this.content,
    this.isPinned = false,
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String authorUid;
  final String authorName;
  final String title;
  final String content;
  final bool isPinned;
  final DateTime? createdAt;

  factory Announcement.fromDoc(Map<String, dynamic> d, String docId) =>
      Announcement(
        id: docId,
        orgId: Fs.str(d['orgId']),
        authorUid: Fs.str(d['authorUid']),
        authorName: Fs.str(d['authorName'], 'Admin'),
        title: Fs.str(d['title']),
        content: Fs.str(d['content']),
        isPinned: Fs.boolean(d['isPinned']),
        createdAt: Fs.dateOrNull(d['createdAt']),
      );

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'authorUid': authorUid,
        'authorName': authorName,
        'title': title,
        'content': content,
        'isPinned': isPinned,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
