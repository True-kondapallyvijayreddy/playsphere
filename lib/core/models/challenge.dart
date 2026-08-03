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
    this.createdCompId,
    this.hostOrgId,
    this.agreedSlot,
    this.createdAt,
  });

  final String id;
  final String fromOrgId;
  final String toOrgId;
  final String fromOrgName;
  final String toOrgName;
  final String sportId;

  /// 'pending', 'accepted', 'declined', 'withdrawn', 'rescheduled'
  ///
  /// `declined` is the receiving club's answer; `withdrawn` is the issuing
  /// club taking the offer back. Both are recorded rather than deleted so
  /// neither club can quietly re-run a negotiation and claim the other never
  /// responded.
  final String status;

  final List<DateTime> proposedSlots;
  final String? venue;

  /// Where the agreed match actually lives once accepted.
  ///
  /// A challenge is a negotiation; the match is a real competition and fixture
  /// under whichever club accepted. Without all three of these ids the club
  /// that *issued* the challenge has no route to the match it agreed to play —
  /// which is what "accepted" previously meant in practice.
  final String? createdFixtureId;
  final String? createdCompId;
  final String? hostOrgId;

  /// Which of [proposedSlots] the accepting club chose.
  final DateTime? agreedSlot;

  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isWithdrawn => status == 'withdrawn';

  /// True when [orgId] is the club that issued this challenge, and so the one
  /// that may take it back while it is still unanswered.
  bool isOutgoingFor(String orgId) => orgId == fromOrgId;

  /// Whether [orgId] can still withdraw. Once the other club has accepted
  /// there is a real fixture in both clubs' schedules, and unpicking that is
  /// a cancellation of a match rather than a withdrawal of an offer.
  bool canBeWithdrawnBy(String orgId) => isPending && isOutgoingFor(orgId);

  /// True once the match exists and can be opened by either club.
  bool get hasMatch =>
      createdFixtureId != null && createdCompId != null && hostOrgId != null;

  /// The opponent's name from [orgId]'s point of view, for list rows that must
  /// read the same whether you issued the challenge or received it.
  String opponentNameFor(String orgId) =>
      orgId == fromOrgId ? toOrgName : fromOrgName;

  /// True when [orgId] is the club being challenged, and therefore the one that
  /// gets to accept, decline or pick the slot.
  bool isIncomingFor(String orgId) => orgId == toOrgId;

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
      createdCompId: Fs.strOrNull(d['createdCompId']),
      hostOrgId: Fs.strOrNull(d['hostOrgId']),
      agreedSlot: Fs.dateOrNull(d['agreedSlot']),
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
        'createdCompId': createdCompId,
        'hostOrgId': hostOrgId,
        'agreedSlot': Fs.ts(agreedSlot),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
