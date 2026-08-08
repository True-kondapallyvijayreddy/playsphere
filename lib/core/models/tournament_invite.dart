import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One club asking another to bring a side to its tournament
/// (`tournamentInvites/{inviteId}`).
///
/// ## Why this is not the public link
///
/// A tournament already has a public link, and that link is the right tool for
/// a poster, a WhatsApp group or a parent who wants to follow the scores. It is
/// the wrong tool for the thing an organizer actually needs, which is to reach
/// eleven named clubs and know which of them have answered. A link that has
/// been sent cannot be listed, cannot be counted, and cannot tell you that the
/// school two mandals over never saw it.
///
/// So an invitation is a document. It names both clubs, it reaches the invited
/// club's organizers as a notification rather than as a message somebody has to
/// notice, and it carries a status the host can read back: who was asked, who
/// said yes, who has not replied. That list is the difference between running
/// an open tournament and hoping.
///
/// ## Why it is top-level, like a challenge
///
/// It belongs to two tenants at once. Nested under the host club, the invited
/// club could not read it — the org rules would refuse a stranger — and nesting
/// a copy under each is two documents that can disagree about the same answer.
/// `challenges` solved this exact problem the same way, and an invitation is
/// the same shape of thing: a negotiation between two clubs, owned by neither.
class TournamentInvite {
  const TournamentInvite({
    required this.id,
    required this.tournamentId,
    required this.tournamentName,
    required this.fromOrgId,
    required this.fromOrgName,
    required this.toOrgId,
    required this.toOrgName,
    required this.status,
    this.message,
    this.startDate,
    this.endDate,
    this.invitedBy,
    this.createdAt,
    this.respondedAt,
  });

  final String id;

  /// The host's tournament. With [fromOrgId] this is the pair that addresses
  /// the public tournament page, which is where an invited club is sent —
  /// they are not members of the host and the org-scoped screen is closed to
  /// them.
  final String tournamentId;

  /// Denormalized so a list of invitations reads without one cross-tenant
  /// fetch per row — the invited club cannot read the host's tournament
  /// document through the org rules anyway, so this is not merely a saving.
  final String tournamentName;

  final String fromOrgId;
  final String fromOrgName;
  final String toOrgId;
  final String toOrgName;

  /// 'pending', 'accepted', 'declined', 'withdrawn'.
  ///
  /// Answers are recorded rather than deleted, for the reason a challenge
  /// records them: a host who can see "declined" knows to ask somebody else,
  /// and a host who sees nothing cannot tell a refusal from a club that never
  /// opened the app.
  final String status;

  /// The line the host writes to this club. Optional, and usually the part
  /// that gets a reply: "bring your U-14s, we are short two teams".
  final String? message;

  /// Copied off the tournament at the moment of invitation, so the invited
  /// club sees the dates in the notification and in the list without reading
  /// across the tenant boundary.
  final DateTime? startDate;
  final DateTime? endDate;

  final String? invitedBy;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isWithdrawn => status == 'withdrawn';

  bool isIncomingFor(String orgId) => orgId == toOrgId;

  /// The other club's name from [orgId]'s point of view, so one row renders
  /// the same whether you sent the invitation or received it.
  String otherNameFor(String orgId) =>
      orgId == fromOrgId ? toOrgName : fromOrgName;

  /// The host may take an invitation back only while it is unanswered. Once a
  /// club has accepted, they have put a date in their calendar on the strength
  /// of it, and revoking that is a conversation rather than a button.
  bool canBeWithdrawnBy(String orgId) => isPending && orgId == fromOrgId;

  factory TournamentInvite.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return TournamentInvite(
      id: doc.id,
      tournamentId: Fs.str(d['tournamentId']),
      tournamentName: Fs.str(d['tournamentName'], 'A tournament'),
      fromOrgId: Fs.str(d['fromOrgId']),
      fromOrgName: Fs.str(d['fromOrgName'], 'A club'),
      toOrgId: Fs.str(d['toOrgId']),
      toOrgName: Fs.str(d['toOrgName'], 'A club'),
      status: Fs.str(d['status'], 'pending'),
      message: Fs.strOrNull(d['message']),
      startDate: Fs.dateOrNull(d['startDate']),
      endDate: Fs.dateOrNull(d['endDate']),
      invitedBy: Fs.strOrNull(d['invitedBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      respondedAt: Fs.dateOrNull(d['respondedAt']),
    );
  }

  Map<String, Object?> toCreate() => {
        'tournamentId': tournamentId,
        'tournamentName': tournamentName,
        'fromOrgId': fromOrgId,
        'fromOrgName': fromOrgName,
        'toOrgId': toOrgId,
        'toOrgName': toOrgName,
        'status': status,
        'message': message,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'invitedBy': invitedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
