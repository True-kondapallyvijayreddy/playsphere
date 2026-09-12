import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One member of an INVITED club saying "put me in the side"
/// (`orgs/{orgId}/seasonInterest/{hostOrgId}_{tournamentId}_{uid}`).
///
/// ## Why a member of an invited club cannot simply register
///
/// A cross-club invitation is addressed to a CLUB. The host asked
/// Test_school1 to bring a side; they did not open their season to
/// Test_school1's four hundred members individually. If every member could
/// press Register on the host's draw, the club would arrive as forty unrelated
/// entries, the host's field would be unplayable, and the one person who is
/// accountable for who represents the club — the club's owner — would find out
/// afterwards.
///
/// So the entry is the owner's to make, and this is what everybody else gets
/// instead: a signal, recorded, that they are available. It commits nobody. It
/// is not a registration and it never becomes one on its own; the owner reads
/// the list, picks the side, and enters the club as a team. See
/// [TournamentInvite] for the club-to-club half of the same conversation.
///
/// ## Why it is stored under the INVITED club, not the host
///
/// It is the invited club's internal business — who is available for the trip
/// — and the host has no need and no right to read it. Nesting it under the
/// invited club means the rules are the ordinary ones the club already has
/// (its members write their own, its organizers read them all), needs no
/// cross-tenant grant, and leaves nothing behind at the host if the club
/// declines.
class SeasonInterest {
  const SeasonInterest({
    required this.id,
    required this.orgId,
    required this.hostOrgId,
    required this.tournamentId,
    required this.uid,
    required this.displayName,
    this.tournamentName,
    this.photoUrl,
    this.note,
    this.createdAt,
  });

  /// `hostOrgId_tournamentId_uid` — deterministic, so pressing the button
  /// twice from two devices cannot leave two rows for one person, and
  /// withdrawing is a delete of a document whose id the client already knows.
  final String id;

  /// The invited club this person is a member of, and whose side they want a
  /// place in. The document's parent, repeated here so a collection-group
  /// read can be filtered without walking the path.
  final String orgId;

  /// The club RUNNING the season, which is not [orgId] — that is what makes
  /// this an invitation rather than an ordinary entry.
  final String hostOrgId;

  final String tournamentId;

  /// Denormalized so the owner's list reads without one cross-tenant fetch
  /// per row. The invited club often cannot read the host's tournament
  /// document at all, so this is not merely a saving — see [TournamentInvite].
  final String? tournamentName;

  final String uid;
  final String displayName;
  final String? photoUrl;

  /// The member's own line to the owner: "available all three Sundays",
  /// "only if it is the U-16s". Optional, and the part that usually decides
  /// it.
  final String? note;

  final DateTime? createdAt;

  static String idFor({
    required String hostOrgId,
    required String tournamentId,
    required String uid,
  }) =>
      '${hostOrgId}_${tournamentId}_$uid';

  factory SeasonInterest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return SeasonInterest(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      hostOrgId: Fs.str(d['hostOrgId']),
      tournamentId: Fs.str(d['tournamentId']),
      tournamentName: Fs.strOrNull(d['tournamentName']),
      uid: Fs.str(d['uid']),
      displayName: Fs.str(d['displayName'], 'A member'),
      photoUrl: Fs.strOrNull(d['photoUrl']),
      note: Fs.strOrNull(d['note']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'hostOrgId': hostOrgId,
        'tournamentId': tournamentId,
        'tournamentName': tournamentName,
        'uid': uid,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
