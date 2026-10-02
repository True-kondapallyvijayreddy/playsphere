import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// An uninvited club asking to bring a side into someone else's open season
/// (`clubRegistrationRequests/{requestId}`) — TC-CLUB-034.
///
/// ## Why this is not just entering the team directly
///
/// [Competition.openToNonMembers] already lets an individual walk straight
/// into an open SOLO event — there is nobody to ask, a person just registers.
/// A whole club bringing a persistent team is a different kind of door: the
/// host is trusting an organization it has never dealt with, not one extra
/// name in a field. So it goes through a request the host reviews, exactly as
/// the spec asks — distinct from both the direct-invite flow ([TournamentInvite]
/// is the host asking a club) and the individual open-join path.
///
/// ## Why approval sends an invitation rather than unlocking entry directly
///
/// Once the host approves, [TournamentRepository.decideClubRegistrationRequest]
/// sends the requesting club an ordinary [TournamentInvite] and marks this
/// request `approved`. That is one more tap for the requesting club — accepting
/// the invite — rather than an instant unlock, and it is a deliberate choice:
/// it means "a club may enter" is decided by exactly one code path
/// (`inviteAccepted` in firestore.rules) everywhere in the product, audited
/// once, rather than this request being a second, newer way to reach the same
/// privilege with its own rules to get right.
///
/// ## Why top-level, like [TournamentInvite]
///
/// Same reasoning: it belongs to two tenants — the host club and the
/// requesting club — and nesting it under either would make it unreadable
/// (or, nested twice, disagreeable) to the other.
class ClubRegistrationRequest {
  const ClubRegistrationRequest({
    required this.id,
    required this.tournamentId,
    required this.tournamentName,
    required this.hostOrgId,
    required this.hostOrgName,
    required this.requestingOrgId,
    required this.requestingOrgName,
    required this.viaCompId,
    required this.status,
    this.note,
    this.declineReason,
    this.requestedBy,
    this.createdAt,
    this.decidedAt,
  });

  /// `${hostOrgId}_${tournamentId}_${requestingOrgId}` — one outstanding
  /// request per club per season, same shape as [TournamentInvite.idFor].
  final String id;

  final String tournamentId;
  final String tournamentName;
  final String hostOrgId;
  final String hostOrgName;
  final String requestingOrgId;
  final String requestingOrgName;

  /// The specific open competition the requesting club found this door
  /// through — checked server-side so a request can only be filed against a
  /// season that genuinely has at least one `openToNonMembers` event.
  final String viaCompId;

  /// 'pending', 'approved', 'declined'.
  final String status;

  /// "We'd like to bring our U-17 and U-19 sides." Optional context for the
  /// host, the same courtesy [TournamentInvite.message] is in reverse.
  final String? note;

  final String? declineReason;
  final String? requestedBy;
  final DateTime? createdAt;
  final DateTime? decidedAt;

  bool get isPending => status == 'pending';

  static String idFor({
    required String hostOrgId,
    required String tournamentId,
    required String requestingOrgId,
  }) =>
      '${hostOrgId}_${tournamentId}_$requestingOrgId';

  factory ClubRegistrationRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return ClubRegistrationRequest(
      id: doc.id,
      tournamentId: Fs.str(d['tournamentId']),
      tournamentName: Fs.str(d['tournamentName']),
      hostOrgId: Fs.str(d['hostOrgId']),
      hostOrgName: Fs.str(d['hostOrgName']),
      requestingOrgId: Fs.str(d['requestingOrgId']),
      requestingOrgName: Fs.str(d['requestingOrgName']),
      viaCompId: Fs.str(d['viaCompId']),
      status: Fs.str(d['status'], 'pending'),
      note: Fs.strOrNull(d['note']),
      declineReason: Fs.strOrNull(d['declineReason']),
      requestedBy: Fs.strOrNull(d['requestedBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      decidedAt: Fs.dateOrNull(d['decidedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'tournamentId': tournamentId,
        'tournamentName': tournamentName,
        'hostOrgId': hostOrgId,
        'hostOrgName': hostOrgName,
        'requestingOrgId': requestingOrgId,
        'requestingOrgName': requestingOrgName,
        'viaCompId': viaCompId,
        'status': status,
        'note': note,
        'requestedBy': requestedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
