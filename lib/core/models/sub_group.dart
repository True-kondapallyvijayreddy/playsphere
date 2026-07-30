import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// A sub-team, age group, or gender subgroup inside a club.
class SubGroup {
  const SubGroup({
    required this.id,
    required this.orgId,
    required this.name,
    this.sportId,
    this.ageGroup,
    this.gender,
    this.memberUids = const [],
    this.createdAt,
  });

  final String id;
  final String orgId;
  final String name;
  final String? sportId;
  final String? ageGroup;
  final String? gender;
  final List<String> memberUids;
  final DateTime? createdAt;

  factory SubGroup.fromDoc(Map<String, dynamic> d, String docId) => SubGroup(
        id: docId,
        orgId: Fs.str(d['orgId']),
        name: Fs.str(d['name'], 'Sub-Group'),
        sportId: Fs.strOrNull(d['sportId']),
        ageGroup: Fs.strOrNull(d['ageGroup']),
        gender: Fs.strOrNull(d['gender']),
        memberUids: Fs.strList(d['memberUids']),
        createdAt: Fs.dateOrNull(d['createdAt']),
      );

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'name': name,
        'sportId': sportId,
        'ageGroup': ageGroup,
        'gender': gender,
        'memberUids': memberUids,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
