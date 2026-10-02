import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// The club telling a member they have been picked
/// (`orgs/{orgId}/seasonNominations/{hostOrgId}_{tournamentId}_{compId}_{uid}`).
///
/// ## Why selection and entry are two documents
///
/// For a TEAM draw the club's selection IS the entry: the side is the unit
/// that competes, the organizer assembles it, and one registration carries all
/// eleven names. For a SINGLES draw it cannot be. Entering a singles draw is
/// a commitment by the player to be somewhere on a Sunday, and
/// `firestore.rules` is right to refuse a secretary who tries to make it on
/// their behalf — the club cannot consent for them, and an entry nobody agreed
/// to is a walkover waiting to happen.
///
/// So the club's half of the decision gets a document of its own. It says: we
/// picked you, for this draw, in this season. `onSeasonNominated` in
/// functions/nominations.js turns it into a notification with the link, and
/// the player's own registration — if they make one — is a separate act on
/// the host's event, exactly as it was before.
///
/// The mirror image of [SeasonInterest], and stored beside it under the
/// invited club for the same reasons: it is the club's internal business, the
/// host has no need to read it, and it needs no cross-tenant grant.
class SeasonNomination {
  const SeasonNomination({
    required this.id,
    required this.orgId,
    required this.hostOrgId,
    required this.tournamentId,
    required this.compId,
    required this.uid,
    required this.nominatedByUid,
    this.compName,
    this.tournamentName,
    this.clubName,
    this.createdAt,
  });

  /// `hostOrgId_tournamentId_compId_uid` — deterministic, so nominating the
  /// same person for the same draw twice rewrites one row rather than sending
  /// them a second notification.
  final String id;

  /// The club doing the picking. The document's parent.
  final String orgId;

  final String hostOrgId;
  final String tournamentId;

  /// The draw they were picked for. A season has several, and "you have been
  /// selected" without saying for what is not a message anybody can act on.
  final String compId;

  final String uid;
  final String nominatedByUid;

  /// Denormalized for the notification, which is composed by a trigger that
  /// often cannot read the host's documents on the club's behalf.
  final String? compName;
  final String? tournamentName;
  final String? clubName;

  final DateTime? createdAt;

  static String idFor({
    required String hostOrgId,
    required String tournamentId,
    required String compId,
    required String uid,
  }) =>
      '${hostOrgId}_${tournamentId}_${compId}_$uid';

  factory SeasonNomination.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return SeasonNomination(
      id: doc.id,
      orgId: Fs.str(d['orgId']),
      hostOrgId: Fs.str(d['hostOrgId']),
      tournamentId: Fs.str(d['tournamentId']),
      compId: Fs.str(d['compId']),
      uid: Fs.str(d['uid']),
      nominatedByUid: Fs.str(d['nominatedByUid']),
      compName: Fs.strOrNull(d['compName']),
      tournamentName: Fs.strOrNull(d['tournamentName']),
      clubName: Fs.strOrNull(d['clubName']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'orgId': orgId,
        'hostOrgId': hostOrgId,
        'tournamentId': tournamentId,
        'compId': compId,
        'uid': uid,
        'nominatedByUid': nominatedByUid,
        'compName': compName,
        'tournamentName': tournamentName,
        'clubName': clubName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
