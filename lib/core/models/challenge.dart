import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// One contest inside a challenge — a sport, played in one particular
/// arrangement.
///
/// ## Why a challenge needed more than a sport id
///
/// A challenge carried exactly one `sportId`, which made it possible to say
/// "we challenge you at cricket" and nothing else. That is not how clubs
/// challenge each other. A village club messaging another proposes a
/// Saturday and a list: table tennis singles, badminton doubles, and a
/// leather-ball cricket match. Sending three separate challenges gets three
/// separate negotiations, three separate accept taps, and no way to say the
/// three are one fixture list on one afternoon.
///
/// [sideFormatId] is what makes "TT singles" different from "TT doubles"
/// without inventing a second sport. It is a `SideFormat.id` from the scoring
/// registry, and its `configOverrides` are what the engine actually reads —
/// so a doubles leg is scored with doubles service rotation because the leg
/// said so, not because somebody remembered to set it later.
class ChallengeLeg {
  const ChallengeLeg({
    required this.sportId,
    required this.sportName,
    required this.sideFormatId,
    required this.sideFormatName,
  });

  final String sportId;
  final String sportName;
  final String sideFormatId;
  final String sideFormatName;

  /// "Table tennis · Doubles". What the receiving club reads in the list.
  String get label => '$sportName · $sideFormatName';

  static ChallengeLeg fromMap(Map<String, dynamic> m) => ChallengeLeg(
        sportId: Fs.str(m['sportId'], 'cricket'),
        sportName: Fs.str(m['sportName'], 'Cricket'),
        sideFormatId: Fs.str(m['sideFormatId']),
        sideFormatName: Fs.str(m['sideFormatName']),
      );

  Map<String, Object?> toMap() => {
        'sportId': sportId,
        'sportName': sportName,
        'sideFormatId': sideFormatId,
        'sideFormatName': sideFormatName,
      };

  @override
  bool operator ==(Object other) =>
      other is ChallengeLeg &&
      other.sportId == sportId &&
      other.sideFormatId == sideFormatId;

  @override
  int get hashCode => Object.hash(sportId, sideFormatId);
}

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
    this.legs = const [],
    this.proposedSlots = const [],
    this.venue,
    this.createdFixtureId,
    this.createdCompId,
    this.hostOrgId,
    this.createdTournamentId,
    this.agreedSlot,
    this.createdAt,
  });

  final String id;
  final String fromOrgId;
  final String toOrgId;
  final String fromOrgName;
  final String toOrgName;
  /// The FIRST leg's sport, kept as a plain field.
  ///
  /// Redundant with `legs.first.sportId` and deliberately still written. Every
  /// challenge created before [legs] existed has only this, and the list rows,
  /// the notification and the accept path all have to keep working for those
  /// documents without a migration. [resolvedLegs] is what code should read.
  final String sportId;

  /// Every contest in this challenge. Empty on documents written before
  /// multi-sport challenges existed — use [resolvedLegs].
  final List<ChallengeLeg> legs;

  /// The legs to actually play, however old the document is.
  ///
  /// A pre-[legs] challenge resolves to a single leg built from [sportId] with
  /// the sport's default arrangement, which is exactly what it always meant.
  List<ChallengeLeg> resolvedLegs(String Function(String) sportNameOf) =>
      legs.isNotEmpty
          ? legs
          : [
              ChallengeLeg(
                sportId: sportId,
                sportName: sportNameOf(sportId),
                sideFormatId: '',
                sideFormatName: '',
              ),
            ];

  bool get isMultiSport => legs.length > 1;

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

  /// For a multi-sport challenge: the tournament grouping every leg's
  /// competition, so both clubs open one fixture list rather than hunting for
  /// three unrelated events. Null for a single-sport challenge, which needs no
  /// container.
  final String? createdTournamentId;

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
      legs: [
        for (final raw in (d['legs'] is List ? d['legs'] as List : const []))
          if (raw is Map) ChallengeLeg.fromMap(Map<String, dynamic>.from(raw)),
      ],
      proposedSlots: Fs.dateList(d['proposedSlots']),
      venue: Fs.strOrNull(d['venue']),
      createdFixtureId: Fs.strOrNull(d['createdFixtureId']),
      createdCompId: Fs.strOrNull(d['createdCompId']),
      hostOrgId: Fs.strOrNull(d['hostOrgId']),
      createdTournamentId: Fs.strOrNull(d['createdTournamentId']),
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
        'legs': legs.map((l) => l.toMap()).toList(),
        'proposedSlots': proposedSlots.map(Fs.ts).toList(),
        'venue': venue,
        'createdFixtureId': createdFixtureId,
        'createdCompId': createdCompId,
        'hostOrgId': hostOrgId,
        'createdTournamentId': createdTournamentId,
        'agreedSlot': Fs.ts(agreedSlot),
        'createdAt': FieldValue.serverTimestamp(),
      };
}
