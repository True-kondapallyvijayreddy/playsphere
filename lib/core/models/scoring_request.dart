import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// Where a scoring request stands.
///
/// Answered requests are kept rather than deleted: an admin needs to be able
/// to see that they already turned someone down, and a match whose scorer is
/// later disputed needs a record of who asked to hold the pen and who granted
/// it.
enum ScoringRequestStatus {
  pending('pending'),
  approved('approved'),
  declined('declined');

  const ScoringRequestStatus(this.wire);

  final String wire;

  static ScoringRequestStatus fromWire(String? value) =>
      ScoringRequestStatus.values.firstWhere(
        (s) => s.wire == value,
        orElse: () => ScoringRequestStatus.pending,
      );
}

/// Somebody asking to be allowed to score one match.
///
/// The gap this closes: the only route into a fixture's `scorerUids` was an
/// admin pushing someone in from the match list, and that list only offers
/// members who already hold the Judge / Scorer role. On a village ground the
/// admin is frequently not present and often not the person who knows the
/// sport — so the umpire who turned up, or a club-mate with a phone, had no
/// way to volunteer. This lets them raise a hand; the admin still decides.
///
/// Stored at
/// `orgs/{orgId}/competitions/{compId}/fixtures/{fixtureId}/scoringRequests/{uid}`.
class ScoringRequest {
  const ScoringRequest({
    required this.uid,
    required this.orgId,
    required this.compId,
    required this.fixtureId,
    required this.displayName,
    required this.status,
    this.matchLabel = '',
    this.note,
    this.decidedBy,
    this.createdAt,
    this.decidedAt,
  });

  /// Also the document id.
  final String uid;

  final String orgId;
  final String compId;
  final String fixtureId;

  /// Denormalized so the admin's list renders from one query instead of a
  /// profile fetch per row — the same reason `members` carries it.
  final String displayName;

  /// "Blue House v Red House". Denormalized for the same reason: the approval
  /// card has to say which match without reading the fixture it hangs under.
  final String matchLabel;

  final ScoringRequestStatus status;

  /// Optional free text — "I am the umpire today", "coach asked me to".
  final String? note;

  final String? decidedBy;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get isPending => status == ScoringRequestStatus.pending;
  bool get isApproved => status == ScoringRequestStatus.approved;
  bool get isDeclined => status == ScoringRequestStatus.declined;

  factory ScoringRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ScoringRequest(
      uid: doc.id,
      orgId: Fs.str(d['orgId']),
      compId: Fs.str(d['compId']),
      fixtureId: Fs.str(d['fixtureId']),
      displayName: Fs.str(d['displayName'], 'A member'),
      matchLabel: Fs.str(d['matchLabel']),
      status: ScoringRequestStatus.fromWire(Fs.strOrNull(d['status'])),
      note: Fs.strOrNull(d['note']),
      decidedBy: Fs.strOrNull(d['decidedBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      decidedAt: Fs.dateOrNull(d['decidedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'orgId': orgId,
        'compId': compId,
        'fixtureId': fixtureId,
        'displayName': displayName,
        'matchLabel': matchLabel,
        'status': status.wire,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
