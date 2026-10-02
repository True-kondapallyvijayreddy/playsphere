import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// A player asking to move houses, at
/// `orgs/{orgId}/competitions/{compId}/houseTransferRequests/{uid}` —
/// TC-CLUB-003.
///
/// ## Why this exists instead of just letting a player pick a new house
///
/// [Registration.houseName] is the organizer's own placement, run through
/// house standings and the team builder — see `HouseRoster`. Letting a
/// player rewrite it directly would let one self-service tap undo a
/// balanced split the organizer (or [CompetitionRepository.applyHousePlacement])
/// deliberately built. So a request is not a house change: it is a note on
/// the organizer's queue, applied only through the same manual-transfer path
/// TC-ADM-029 already uses, and only when the organizer has turned this on
/// for the event in the first place — off by default, since most events
/// never want it.
///
/// ## Why the document id is the requester's uid
///
/// One outstanding request per player, same reasoning as [TeamJoinRequest]:
/// asking twice replaces rather than queueing a second row, and "have I
/// already asked?" is a `get` rather than a query.
class HouseTransferRequest {
  const HouseTransferRequest({
    required this.uid,
    required this.displayName,
    required this.fromHouse,
    required this.toHouse,
    this.note,
    this.createdAt,
  });

  /// Also the document id.
  final String uid;

  final String displayName;

  /// The house on their registration when they asked — kept even though it
  /// can be read off the registration, so the organizer's queue shows what
  /// changed without a second read.
  final String fromHouse;

  final String toHouse;

  /// "My cousin is in Blue House and I'd like to be with him." Optional; a
  /// bare request with no reason is still a valid one.
  final String? note;

  final DateTime? createdAt;

  factory HouseTransferRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return HouseTransferRequest(
      uid: doc.id,
      displayName: Fs.str(d['displayName'], 'Player'),
      fromHouse: Fs.str(d['fromHouse']),
      toHouse: Fs.str(d['toHouse']),
      note: Fs.strOrNull(d['note']),
      createdAt: Fs.dateOrNull(d['createdAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'uid': uid,
        'displayName': displayName,
        'fromHouse': fromHouse,
        'toHouse': toHouse,
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
