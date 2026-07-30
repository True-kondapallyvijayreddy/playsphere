import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// Top-level inter-club challenge (`challenges/{challengeId}`).
///
/// Unblocks cross-club matches (school-vs-school, village-vs-village) by placing
/// challenges outside single-tenant org boundaries.
class Challenge {
  const Challenge({
    required this.id,
    required this.fromOrgId,
    required this.toOrgId,
    required this.fromOrgName,
    required this.toOrgName,
    required this.sportId,
    required this.status,
    this.proposedSlots = const [],
    this.venue,
    this.createdFixtureId,
    this.createdAt,
  });

  final String id;
  final String fromOrgId;
  final String toOrgId;
  final String fromOrgName;
  final String toOrgName;
  final String sportId;

  /// 'pending', 'accepted', 'declined', 'rescheduled'
  final String status;

  final List<DateTime> proposedSlots;
  final String? venue;
  final String? createdFixtureId;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  factory Challenge.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Challenge(
      id: doc.id,
      fromOrgId: Fs.str(d['fromOrgId']),
      toOrgId: Fs.str(d['toOrgId']),
      fromOrgName: Fs.str(d['fromOrgName'], 'Challenging Club'),
      toOrgName: Fs.str(d['toOrgName'], 'Opponent Club'),
      sportId: Fs.str(d['sportId'], 'cricket'),
      status: Fs.str(d['status'], 'pending'),
      proposedSlots: Fs.dateList(d['proposedSlots']),
      venue: Fs.strOrNull(d['venue']),
      createdFixtureId: Fs.strOrNull(d['createdFixtureId']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'fromOrgId': fromOrgId,
        'toOrgId': toOrgId,
        'fromOrgName': fromOrgName,
        'toOrgName': toOrgName,
        'sportId': sportId,
        'status': status,
        'proposedSlots': proposedSlots.map(Fs.ts).toList(),
        'venue': venue,
        'createdFixtureId': createdFixtureId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
