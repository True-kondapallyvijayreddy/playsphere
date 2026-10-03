import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';
import 'tournament.dart';

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
    this.kind = SeasonKind.season,
    this.sportNames = const [],
    this.place,
    this.startDate,
    this.endDate,
    this.invitedBy,
    this.createdAt,
    this.respondedAt,
    this.declineReason,
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
  ///
  /// Since the invitations space, this is the whole letter — "Dear sports
  /// enthusiasts, we from … are conducting …" — composed by
  /// `InvitationLetter` and edited by the host. Older invitations carry only
  /// the one line, or nothing; [letter] covers both.
  final String? message;

  /// Whether the host is running a season or a one-sport tournament. Copied
  /// at invitation time for the reason [tournamentName] is.
  final SeasonKind kind;

  /// The sports on offer, copied at invitation time so the invited club can
  /// see "Cricket, Table Tennis" without reading across the tenant boundary.
  final List<String> sportNames;

  /// Where it is played — "Adibatla, Hyderabad". Free text, as the host wrote
  /// it on the invitation.
  final String? place;

  /// Copied off the tournament at the moment of invitation, so the invited
  /// club sees the dates in the notification and in the list without reading
  /// across the tenant boundary.
  final DateTime? startDate;
  final DateTime? endDate;

  final String? invitedBy;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  /// Why the invited club said no, in their words — the feedback the host
  /// needs to plan the next season (TC-CLUB-011). Null on any other answer.
  final String? declineReason;

  /// How long a club has to change a "no" — see [canChangeAnswer].
  static const changeOfMindWindow = Duration(hours: 24);

  /// A decline can be taken back for a day: a secretary who tapped "Not this
  /// time" on the wrong season, or whose committee changed its mind that
  /// evening, should not have to ask the host to re-send. After that the host
  /// has planned around the answer. `firestore.rules` holds the same window.
  bool canChangeAnswer(DateTime now) =>
      isDeclined &&
      respondedAt != null &&
      now.difference(respondedAt!) < changeOfMindWindow;

  // --- What one invitation may carry --------------------------------------
  //
  // The same numbers as `match /tournamentInvites/{inviteId}` in
  // firestore.rules. A send is one batch across every picked club, so a field
  // one character over used to refuse the WHOLE send with a bare permission
  // error. The composer's fields stop at these, the prefills are fitted to
  // them, and [fitted] shapes every value before it is written.

  /// The letter.
  static const int maxMessageLength = 2000;

  /// "Where".
  static const int maxPlaceLength = 200;

  /// The sports listed on the invitation.
  static const int maxSportNames = 30;

  /// [text] trimmed and shortened to [max] characters, cut at a word where
  /// one is near and marked with an ellipsis. Null for blank text.
  static String? fit(String? text, int max) {
    final t = text?.trim().replaceAll(RegExp(r'[ \t]+'), ' ');
    if (t == null || t.isEmpty) return null;
    if (t.length <= max) return t;
    final cut = t.substring(0, max - 1);
    final space = cut.lastIndexOf(' ');
    final head = space > max * 0.6 ? cut.substring(0, space) : cut;
    return '${head.trimRight()}…';
  }

  /// The sports list as it may be stored: blanks and repeats dropped, and at
  /// most [maxSportNames]. Past that, the last entry says how many more there
  /// are, so the invitation still says "and 6 more" rather than going quiet.
  static List<String> fitSportNames(Iterable<String> names) {
    final seen = <String>{};
    final clean = [
      for (final n in names)
        if (n.trim().isNotEmpty && seen.add(n.trim().toLowerCase())) n.trim(),
    ];
    if (clean.length <= maxSportNames) return clean;
    final shown = clean.take(maxSportNames - 1).toList();
    return [...shown, 'and ${clean.length - shown.length} more'];
  }

  /// The document id for one host/tournament/guest triple.
  ///
  /// Deterministic, and it earns that twice over. It makes inviting a club a
  /// second time overwrite the one row instead of leaving two that can
  /// disagree about the answer. And it is the only way `firestore.rules` can
  /// reach this document at all — rules cannot query, so the grant that lets
  /// an invited club's organizers enter their side into the host's draw is an
  /// `exists()` on exactly this path. Change the shape and that grant stops
  /// finding anything.
  static String idFor({
    required String fromOrgId,
    required String tournamentId,
    required String toOrgId,
  }) =>
      '${fromOrgId}_${tournamentId}_$toOrgId';

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
      kind: SeasonKind.fromWire(Fs.strOrNull(d['kind'])),
      sportNames: Fs.strList(d['sportNames']),
      place: Fs.strOrNull(d['place']),
      startDate: Fs.dateOrNull(d['startDate']),
      endDate: Fs.dateOrNull(d['endDate']),
      invitedBy: Fs.strOrNull(d['invitedBy']),
      createdAt: Fs.dateOrNull(d['createdAt']),
      respondedAt: Fs.dateOrNull(d['respondedAt']),
      declineReason: Fs.strOrNull(d['declineReason']),
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
        'kind': kind.wire,
        'sportNames': sportNames,
        'place': place,
        'startDate': Fs.ts(startDate),
        'endDate': Fs.ts(endDate),
        'invitedBy': invitedBy,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
