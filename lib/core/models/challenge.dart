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
    this.message,
    this.entryFeeRupees = 0,
    this.counterSlots = const [],
    this.counterVenue,
    this.counterMessage,
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

  /// A note from the challenging club — "Shall we play at 7pm on the 26th?".
  ///
  /// Written once, at creation, and immutable afterwards. A challenge is a
  /// record of what was offered, and a message the issuer could rewrite after
  /// the fact would make it evidence of nothing.
  final String? message;

  /// What each side pays into the match pot, in whole rupees. Zero means a
  /// friendly, which is the overwhelming majority.
  ///
  /// Rupees rather than paise, unlike `Competition.entryFeeRupees`'s
  /// neighbours in billing — this is a figure two clubs agree between
  /// themselves and settle in cash at the ground, not something the platform
  /// collects.
  final int entryFeeRupees;

  // --- The counter-offer ---------------------------------------------------
  //
  // A challenge used to have two answers: yes and no. In practice the common
  // answer is "yes, but not then" — and with no way to express it the
  // receiving club had to decline and issue a fresh challenge back, which
  // lost the thread and read to the first club as a refusal.
  //
  // Only the club that *received* the challenge may write these, and only
  // while it is still pending. See `firestore.rules`.

  /// Dates the receiving club proposes instead of [proposedSlots].
  final List<DateTime> counterSlots;

  /// A different ground, where the receiving club cannot host at the one
  /// offered. Null means the original [venue] stands.
  final String? counterVenue;

  /// The receiving club's note explaining the counter.
  final String? counterMessage;

  bool get isCountered => status == 'countered';

  /// True when [orgId] may answer a counter-offer — the club that issued the
  /// original challenge, now on the receiving end of the negotiation.
  bool canAnswerCounterAs(String orgId) => isCountered && orgId == fromOrgId;

  /// True when [orgId] may counter — the challenged club, while the offer is
  /// still open. A club cannot counter its own challenge, and cannot counter
  /// one it has already answered.
  bool canCounterAs(String orgId) => isPending && orgId == toOrgId;

  /// The slots actually on the table right now.
  ///
  /// Once countered, the counter-offer's dates are the live proposal and the
  /// original's are history — a screen showing both would ask the challenging
  /// club to agree to a date nobody is offering any more.
  List<DateTime> get liveSlots =>
      isCountered && counterSlots.isNotEmpty ? counterSlots : proposedSlots;

  /// The ground currently on the table, by the same reasoning.
  String? get liveVenue => isCountered ? (counterVenue ?? venue) : venue;

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
      message: Fs.strOrNull(d['message']),
      entryFeeRupees: Fs.integer(d['entryFeeRupees']),
      counterSlots: Fs.dateList(d['counterSlots']),
      counterVenue: Fs.strOrNull(d['counterVenue']),
      counterMessage: Fs.strOrNull(d['counterMessage']),
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
        'message': message,
        'entryFeeRupees': entryFeeRupees,
        // The counter fields are written empty at creation rather than
        // omitted, so `firestore.rules` can hold them unchanged on every
        // update except the counter itself — a field that does not exist
        // cannot be compared against.
        'counterSlots': const <Object?>[],
        'counterVenue': null,
        'counterMessage': null,
      };

  /// The receiving club's counter-offer, as a partial update.
  ///
  /// Deliberately narrow: it writes the status and the three counter fields
  /// and nothing else, so a counter can never quietly rewrite the sport, the
  /// entry fee or the original offer it is answering.
  static Map<String, Object?> counterUpdate({
    required List<DateTime> slots,
    String? venue,
    String? note,
  }) =>
      {
        'status': 'countered',
        'counterSlots': slots.map(Fs.ts).toList(),
        'counterVenue': venue,
        'counterMessage': note,
      };
}
