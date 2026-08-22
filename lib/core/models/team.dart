import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';
import 'firestore_codec.dart';

/// A squad with an identity of its own, at `teams/{teamId}`.
///
/// ## Why this is top-level and not `orgs/{orgId}/teams`
///
/// Rule 4 — *a team is independent of club* — is the whole reason this
/// collection exists. Four friends who play together are a team; they may
/// never join a club, and the product must not require them to. Nesting the
/// collection under an org would make the club a mandatory parent in the
/// document path, which is exactly the constraint the rule forbids, and no
/// amount of a nullable `clubId` field can undo a path that already demands
/// one. [SubGroup] is the club-scoped concept and stays where it is.
///
/// ## Why event teams live here too
///
/// The spec models `Team` (§100) and `EventTeam` (§101) as separate shapes.
/// They are one collection here, separated by [TeamType.event], because §21
/// says an event team "need not become a permanent team" — *need not*, not
/// *cannot* — and §22 requires its record to survive the competition as
/// history. Two collections make promotion a copy-and-repoint migration and
/// force every downstream reader (career statistics, match history, entrant
/// links) to handle two shapes for the same idea. One collection makes
/// promotion a field change and gives those readers a single shape. The cost
/// is two fields that only mean something for one type, documented below.
///
/// ## Why the roster is a list on the document
///
/// A roster is small — the largest squad in the sports this product covers is
/// tens of people, not thousands — and it is read every single time a team is
/// displayed. A subcollection would turn every team card into a second query.
/// If a team ever needs per-member data beyond membership (a shirt number, a
/// join date), that is the point to promote it, and [memberUids] stays as the
/// index the queries use.
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.sportId,
    required this.type,
    required this.createdByUid,
    this.clubId,
    this.captainUid,
    this.managerUid,
    this.memberUids = const [],
    this.status = TeamStatus.active,
    this.competitionId,
    this.baseTeamId,
    this.photoUrl,
    this.homeArea,
    this.joinCode,
    this.createdAt,
  });

  final String id;

  /// The team's current name.
  ///
  /// Deliberately mutable, and deliberately NOT what history is keyed on:
  /// Rule 31 says a record must not disappear because a team was renamed, so
  /// every competition an entry is made in snapshots the name it used that
  /// day onto its own `Entrant`, and points back here with `teamId` for
  /// continuity. Renaming this changes what the team is called from now on,
  /// and changes nothing about what it was called in 2024.
  final String name;

  final String sportId;
  final TeamType type;

  /// Who created the document. Never reassigned — the security rules freeze
  /// it — because it is the fallback authority on a team whose captain has
  /// left and whose club is null, and an editable owner field is an
  /// account-takeover waiting to happen.
  final String createdByUid;

  /// The club this team plays for, or null for an independent team.
  ///
  /// Invariant, enforced by [validationError] and by the security rules:
  /// non-null exactly when [type] is [TeamType.permanent] — [TeamType.event]
  /// may go either way, since a club can raise an event team and so can a
  /// group of friends.
  final String? clubId;

  final String? captainUid;
  final String? managerUid;

  /// The roster. Order is not meaningful; membership is.
  final List<String> memberUids;

  final TeamStatus status;

  /// The competition this team was raised for. Meaningful only when [type] is
  /// [TeamType.event] — see the class note on why it sits on the shared shape.
  final String? competitionId;

  /// The permanent team an event team was drawn from, when it was.
  ///
  /// Lets "Warriors A" in one tournament be connected to "Warriors" without
  /// claiming to *be* it — the two have different rosters, which is the
  /// entire reason the event team was raised.
  final String? baseTeamId;

  final String? photoUrl;

  /// Free-text locality ("Gachibowli"), for the team discovery the spec asks
  /// for in §12. Text rather than a geohash because a team has no coordinates
  /// of its own — it plays wherever its next fixture is — and the honest
  /// version of "nearby teams" is the area its members say they play in.
  final String? homeArea;

  /// The code a captain reads out so friends can find this team, or null for
  /// a team nobody joins by asking — a club squad is picked from the club's
  /// roster, and an event team is picked for one tournament.
  ///
  /// ## Why the code is not what authorizes joining
  ///
  /// `firestore.rules` opens every team document to any signed-in reader, so
  /// a code stored on the document is knowledge anybody could obtain. It is a
  /// *lookup key* — the answer to "which of the eleven teams called Warriors
  /// is my one" — and nothing more. What actually admits somebody is the
  /// captain approving a [TeamJoinRequest], which is also what makes the
  /// roster consented on both sides: the player asked, and the captain said
  /// yes.
  final String? joinCode;

  final DateTime? createdAt;

  /// Everyone who can act for this team, in one place.
  ///
  /// The captain and manager are not required to appear in [memberUids] — a
  /// manager frequently does not play — so callers that need "is this person
  /// involved at all" must not ask the roster alone.
  Set<String> get involvedUids => {
        createdByUid,
        if (captainUid != null) captainUid!,
        if (managerUid != null) managerUid!,
        ...memberUids,
      };

  bool get isIndependent => clubId == null;

  /// Whether this team can still be picked for something new.
  bool get isSelectable => status == TeamStatus.active;

  /// Why this team is not valid, or null if it is.
  ///
  /// Returned as a message rather than thrown so the repository can reject a
  /// bad write before it costs a round trip, and a form can show the same
  /// sentence without a try/catch. The security rules enforce the same
  /// invariants server-side — this is the courteous half of the check, not
  /// the authoritative one.
  String? get validationError {
    if (name.trim().isEmpty) return 'A team needs a name.';
    if (sportId.isEmpty) return 'A team needs a sport.';
    if (createdByUid.isEmpty) return 'A team needs an owner.';
    if (type.requiresClub && clubId == null) {
      return 'A club team must belong to a club.';
    }
    if (type.forbidsClub && clubId != null) {
      return 'An independent team cannot belong to a club.';
    }
    if (type == TeamType.event && competitionId == null) {
      return 'An event team must name the competition it was created for.';
    }
    if (type != TeamType.event && competitionId != null) {
      return 'Only an event team belongs to a single competition.';
    }
    // A duplicate in the roster double-counts a player in every squad-size
    // check and in any statistic derived from the list.
    if (memberUids.toSet().length != memberUids.length) {
      return 'That player is already in this team.';
    }
    return null;
  }

  Team copyWith({
    String? name,
    String? captainUid,
    String? managerUid,
    List<String>? memberUids,
    TeamStatus? status,
    String? photoUrl,
    String? homeArea,
    String? joinCode,
    TeamType? type,
    String? clubId,
    bool clearCompetitionId = false,
  }) =>
      Team(
        id: id,
        name: name ?? this.name,
        sportId: sportId,
        type: type ?? this.type,
        createdByUid: createdByUid,
        clubId: clubId ?? this.clubId,
        captainUid: captainUid ?? this.captainUid,
        managerUid: managerUid ?? this.managerUid,
        memberUids: memberUids ?? this.memberUids,
        status: status ?? this.status,
        competitionId: clearCompetitionId ? null : competitionId,
        baseTeamId: baseTeamId,
        photoUrl: photoUrl ?? this.photoUrl,
        homeArea: homeArea ?? this.homeArea,
        joinCode: joinCode ?? this.joinCode,
        createdAt: createdAt,
      );

  /// This event team as a permanent one (§21: it *may* become permanent).
  ///
  /// Becomes [TeamType.independent] when there is no club to belong to, which
  /// is the pairing [validationError] requires — promoting a club-less squad
  /// to `permanent` would produce a document that cannot be saved.
  Team promotedToPersistent() => copyWith(
        type: clubId == null ? TeamType.independent : TeamType.permanent,
        clearCompetitionId: true,
      );

  factory Team.fromDoc(Map<String, dynamic> d, String docId) => Team(
        id: docId,
        name: Fs.str(d['name'], 'Team'),
        sportId: Fs.str(d['sportId']),
        type: TeamType.fromWire(Fs.strOrNull(d['type'])),
        createdByUid: Fs.str(d['createdByUid']),
        clubId: Fs.strOrNull(d['clubId']),
        captainUid: Fs.strOrNull(d['captainUid']),
        managerUid: Fs.strOrNull(d['managerUid']),
        memberUids: Fs.strList(d['memberUids']),
        status: TeamStatus.fromWire(Fs.strOrNull(d['status'])),
        competitionId: Fs.strOrNull(d['competitionId']),
        baseTeamId: Fs.strOrNull(d['baseTeamId']),
        photoUrl: Fs.strOrNull(d['photoUrl']),
        homeArea: Fs.strOrNull(d['homeArea']),
        joinCode: Fs.strOrNull(d['joinCode']),
        createdAt: Fs.dateOrNull(d['createdAt']),
      );

  factory Team.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Team.fromDoc(doc.data() ?? const {}, doc.id);

  Map<String, Object?> toCreate() => {
        'name': name.trim(),
        'sportId': sportId,
        'type': type.wire,
        'createdByUid': createdByUid,
        'clubId': clubId,
        'captainUid': captainUid,
        'managerUid': managerUid,
        'memberUids': memberUids,
        'status': status.wire,
        'competitionId': competitionId,
        'baseTeamId': baseTeamId,
        'photoUrl': photoUrl,
        'homeArea': homeArea,
        'joinCode': joinCode,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// A code a person can read off a phone screen and type without asking
  /// which character that is.
  ///
  /// Same alphabet as `Organization.generateInviteCode`, and for the same
  /// reason: no O/0, no I/1/l. Six characters from 31 is about 900 million
  /// combinations, which is not a security boundary and does not need to be
  /// — see [joinCode].
  static String generateJoinCode([Random? random]) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rng = random ?? Random.secure();
    return List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)])
        .join();
  }
}
