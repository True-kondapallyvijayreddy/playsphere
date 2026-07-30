import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// Top-level CricHeroes-style "Looking For" post (`lookingForPosts/{postId}`).
class LookingForPost {
  const LookingForPost({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.type,
    required this.sportId,
    required this.description,
    this.orgId,
    this.district,
    this.mandal,
    this.contactPhone,
    this.status = 'open',
    this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorName;

  /// 'player', 'team', 'scorer', 'umpire', 'ground'
  final String type;

  final String sportId;
  final String description;
  final String? orgId;
  final String? district;
  final String? mandal;
  final String? contactPhone;
  final String status;
  final DateTime? createdAt;

  factory LookingForPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return LookingForPost(
      id: doc.id,
      authorUid: Fs.str(d['authorUid']),
      authorName: Fs.str(d['authorName'], 'Sports Person'),
      type: Fs.str(d['type'], 'player'),
      sportId: Fs.str(d['sportId'], 'cricket'),
      description: Fs.str(d['description']),
      orgId: Fs.strOrNull(d['orgId']),
      district: Fs.strOrNull(d['district']),
      mandal: Fs.strOrNull(d['mandal']),
      contactPhone: Fs.strOrNull(d['contactPhone']),
      status: Fs.str(d['status'], 'open'),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'authorUid': authorUid,
        'authorName': authorName,
        'type': type,
        'sportId': sportId,
        'description': description,
        'orgId': orgId,
        'district': district,
        'mandal': mandal,
        'contactPhone': contactPhone,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
