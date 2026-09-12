import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
import '../core/models/team.dart';
import '../core/models/team_join_request.dart';
import 'media_uploader.dart';
import 'org_repository.dart' show guard, guardStream;

/// Reads and writes for `teams/{teamId}`.
///
/// Every write validates through [Team.validationError] before it leaves the
/// device. That is not the security boundary — `firestore.rules` enforces the
/// same invariants and is the one that counts — but a caller that gets a
/// sentence back instead of a `permission-denied` can show it to the person
/// who typed the form, and a rejected write costs no round trip.
class TeamRepository {
  const TeamRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the crest upload against a fake bucket.
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

  // --- Reads ------------------------------------------------------------

  Stream<Team?> watchTeam(String teamId) => guardStream(
        () => Refs.team(teamId).snapshots().map(
              (d) => d.exists ? Team.fromSnapshot(d) : null,
            ),
      );

  Future<Team?> getTeam(String teamId) => guard(() async {
        final doc = await Refs.team(teamId).get();
        return doc.exists ? Team.fromSnapshot(doc) : null;
      });

  /// Active teams this person is on the roster of.
  ///
  /// Sorted client-side. The query already filters on an array and an
  /// equality, and adding `orderBy('name')` would need a further composite
  /// index for a list that is realistically a handful of documents — sorting
  /// those in memory is cheaper than the index it would otherwise cost.
  Stream<List<Team>> watchMyTeams(String uid) => guardStream(
        () => Refs.teamsForMember(uid).snapshots().map(_toSortedTeams),
      );

  Stream<List<Team>> watchClubTeams(String orgId) => guardStream(
        () => Refs.teamsForClub(orgId).snapshots().map(_toSortedTeams),
      );

  Stream<List<Team>> watchCompetitionTeams(String compId) => guardStream(
        () => Refs.teamsForCompetition(compId).snapshots().map(_toSortedTeams),
      );

  static List<Team> _toSortedTeams(QuerySnapshot<Map<String, dynamic>> snap) {
    final teams = snap.docs.map(Team.fromSnapshot).toList();
    teams.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return teams;
  }

  // --- Writes -----------------------------------------------------------

  /// Creates a team and returns its id.
  ///
  /// [createdByUid] is put on the roster and made captain unless the caller
  /// says otherwise. A team of nobody is not a useful document, and the
  /// person creating it is on it in every case the product actually has —
  /// including a club admin raising a squad, who is a club member either way.
  Future<String> createTeam({
    required String name,
    required String sportId,
    required String createdByUid,
    required TeamType type,
    String? clubId,
    String? captainUid,
    String? managerUid,
    List<String> memberUids = const [],
    String? competitionId,
    String? baseTeamId,
    String? homeArea,
    String? joinCode,
  }) =>
      guard(() async {
        final roster = <String>{createdByUid, ...memberUids}.toList();
        final team = Team(
          id: '',
          name: name,
          sportId: sportId,
          type: type,
          createdByUid: createdByUid,
          clubId: clubId,
          captainUid: captainUid ?? createdByUid,
          managerUid: managerUid,
          memberUids: roster,
          competitionId: competitionId,
          baseTeamId: baseTeamId,
          homeArea: homeArea,
          joinCode: joinCode,
        );
        final problem = team.validationError;
        if (problem != null) throw ValidationException(problem);

        final ref = await Refs.teams.add(team.toCreate());
        return ref.id;
      });

  /// Raises an event team for one competition, optionally from a base team.
  ///
  /// This is §21's flow: a club with sixty-four cricketers enters a tournament
  /// that allows eighteen. [memberUids] is the selected eighteen, and
  /// [baseTeamId] records which permanent squad they were drawn from without
  /// claiming the event team *is* that squad — the rosters differ, which is
  /// the whole reason this document exists.
  Future<String> createEventTeam({
    required String name,
    required String sportId,
    required String createdByUid,
    required String competitionId,
    required List<String> memberUids,
    String? clubId,
    String? baseTeamId,
    String? captainUid,
  }) =>
      createTeam(
        name: name,
        sportId: sportId,
        createdByUid: createdByUid,
        type: TeamType.event,
        clubId: clubId,
        captainUid: captainUid,
        memberUids: memberUids,
        competitionId: competitionId,
        baseTeamId: baseTeamId,
      );

  /// Raises a team that belongs to no club.
  ///
  /// The flow the club-scoped [createTeam] cannot serve: five friends from
  /// five different clubs entering a tournament as one side. No capability is
  /// checked and no org is named, because there is no org — Rule 4 says a
  /// team does not need a club, and requiring one to create a team is the
  /// exact constraint that rule forbids.
  ///
  /// The creator is the captain and the only member. Everybody else arrives
  /// through [requestToJoin] and [approveJoinRequest], which is what makes
  /// the roster consented at both ends rather than a list of uids somebody
  /// typed in.
  Future<String> createIndependentTeam({
    required String name,
    required String sportId,
    required String createdByUid,
    String? homeArea,
  }) =>
      createTeam(
        name: name,
        sportId: sportId,
        createdByUid: createdByUid,
        type: TeamType.independent,
        captainUid: createdByUid,
        homeArea: homeArea,
        joinCode: Team.generateJoinCode(),
      );

  /// Independent teams playing one sport.
  Stream<List<Team>> watchIndependentTeams(String sportId) => guardStream(
        () => Refs.independentTeamsForSport(sportId)
            .snapshots()
            .map(_toSortedTeams),
      );

  /// The team a shared code points at, or null.
  ///
  /// Uppercased before the query for the same reason `findByInviteCode`
  /// does it: codes get typed by hand off a phone screen and half of those
  /// arrive lowercase.
  Future<Team?> findByJoinCode(String code) => guard(() async {
        if (code.trim().isEmpty) return null;
        final snap = await Refs.teamsByJoinCode(code).get();
        if (snap.docs.isEmpty) return null;
        return Team.fromSnapshot(snap.docs.first);
      });

  // --- Crest --------------------------------------------------------------

  /// Gives a team its own crest.
  ///
  /// `Team.photoUrl` has been read by the team list, the team page and the
  /// career profile since teams were added, and written by nothing — three
  /// screens rendering a field no form could set. This is that form's other
  /// half.
  ///
  /// Deliberately not routed through [Team.validationError] and `updateTeam`:
  /// that path rewrites the whole document, and a crest change must not be
  /// able to disturb a roster. One field, one write.
  ///
  /// Authority is the same one that governs every other team edit —
  /// `teamRuns()` in `firestore.rules`, meaning the captain, the manager or
  /// the creator. The uid in the path is only what Cloud Storage can check.
  Future<String> uploadTeamCrest({
    required String teamId,
    required String uid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'teams/$teamId/logo',
          uid: uid,
          bytes: bytes,
          contentType: contentType,
        );
        await Refs.team(teamId).update({'photoUrl': url});
        return url;
      });

  /// Goes back to the generated crest.
  Future<void> removeTeamCrest(String teamId) =>
      guard(() => Refs.team(teamId).update({'photoUrl': null}));

  // --- Joining ------------------------------------------------------------

  /// Asks a team to be let on.
  ///
  /// Keyed by the requester's uid, so asking twice replaces rather than
  /// queueing a second row for the captain to decline twice.
  Future<void> requestToJoin({
    required String teamId,
    required String uid,
    required String displayName,
    String? photoUrl,
    String? message,
  }) =>
      guard(
        () => Refs.teamJoinRequest(teamId, uid).set(
          TeamJoinRequest(
            uid: uid,
            displayName: displayName,
            photoUrl: photoUrl,
            message: message,
          ).toCreate(),
        ),
      );

  /// Withdraws a request, or declines one.
  ///
  /// The same call for both: a declined request and a withdrawn one leave the
  /// database in the identical state, and keeping a tombstone would mean
  /// storing "this captain said no to this player" — a record that helps
  /// nobody and that the player can see.
  Future<void> cancelJoinRequest({
    required String teamId,
    required String uid,
  }) =>
      guard(() => Refs.teamJoinRequest(teamId, uid).delete());

  /// Lets somebody on, and clears their request, atomically.
  ///
  /// A batch because the two halves are one decision. Adding the player and
  /// failing to clear the request leaves a captain approving somebody who is
  /// already on the team; clearing the request and failing to add them loses
  /// the ask entirely, and the player has no way to know it happened.
  ///
  /// `arrayUnion` rather than a read-modify-write for the roster, so two
  /// captains approving two players in the same moment both land.
  Future<void> approveJoinRequest({
    required String teamId,
    required String uid,
  }) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.update(Refs.team(teamId), {
          'memberUids': FieldValue.arrayUnion([uid]),
        });
        batch.delete(Refs.teamJoinRequest(teamId, uid));
        await batch.commit();
      });

  /// Who is waiting on this team's captain.
  ///
  /// Bounded like the team queries themselves, and for the same reason: this
  /// is a live listener, so the client holds and is re-billed for the whole
  /// result on every change. A popular independent team's join queue is
  /// unbounded in principle — a shared join code reaches whoever it reaches —
  /// and a captain works through a queue from the top rather than scrolling to
  /// the end of it.
  Stream<List<TeamJoinRequest>> watchJoinRequests(String teamId) => guardStream(
        () => Refs.teamJoinRequests(teamId)
            .limit(Refs.teamQueryLimit)
            .snapshots()
            .map(
              (s) => s.docs.map(TeamJoinRequest.fromDoc).toList(),
            ),
      );

  /// Whether this person has already asked to join this team.
  Stream<bool> watchHasRequested({
    required String teamId,
    required String uid,
  }) =>
      guardStream(
        () => Refs.teamJoinRequest(teamId, uid).snapshots().map((d) => d.exists),
      );

  /// Renames a team, or changes its captain, manager, photo or area.
  ///
  /// Does not touch the roster — see [addMember] and [removeMember], which
  /// use atomic array operations so two people editing a squad at once cannot
  /// overwrite each other's changes.
  Future<void> updateTeamDetails({
    required String teamId,
    String? name,
    String? captainUid,
    String? managerUid,
    String? photoUrl,
    String? homeArea,
  }) =>
      guard(() async {
        if (name != null && name.trim().isEmpty) {
          throw const ValidationException('A team needs a name.');
        }
        await Refs.team(teamId).update({
          if (name != null) 'name': name.trim(),
          if (captainUid != null) 'captainUid': captainUid,
          if (managerUid != null) 'managerUid': managerUid,
          if (photoUrl != null) 'photoUrl': photoUrl,
          if (homeArea != null) 'homeArea': homeArea,
        });
      });

  /// Adds a player to the roster.
  ///
  /// `arrayUnion` rather than a read-modify-write: two selectors adding two
  /// different players at the same moment must both land, and it makes adding
  /// somebody already on the roster a no-op instead of a duplicate.
  Future<void> addMember({
    required String teamId,
    required String uid,
  }) =>
      guard(
        () => Refs.team(teamId).update({
          'memberUids': FieldValue.arrayUnion([uid]),
        }),
      );

  /// Removes a player from the roster.
  ///
  /// Clears the captaincy if the captain is the one leaving, in the same
  /// write: a team pointing at a captain who is no longer on it renders as a
  /// squad led by somebody absent, and leaving the two to separate writes
  /// means a crash between them makes that state permanent.
  Future<void> removeMember({
    required String teamId,
    required String uid,
  }) =>
      guard(() async {
        final team = await getTeam(teamId);
        if (team == null) throw const NotFoundException();
        await Refs.team(teamId).update({
          'memberUids': FieldValue.arrayRemove([uid]),
          if (team.captainUid == uid) 'captainUid': null,
          if (team.managerUid == uid) 'managerUid': null,
        });
      });

  /// Archives a team. There is deliberately no delete.
  ///
  /// Rule 31: the matches this team played, and every career statistic
  /// derived from them, point at this document. Deleting it would break the
  /// traceability chain Rule 16 requires, so a disbanded team is hidden, not
  /// removed.
  Future<void> archiveTeam(String teamId) => guard(
        () => Refs.team(teamId).update({'status': TeamStatus.archived.wire}),
      );

  Future<void> restoreTeam(String teamId) => guard(
        () => Refs.team(teamId).update({'status': TeamStatus.active.wire}),
      );

  /// Turns an event team into a lasting one (§21).
  ///
  /// Reads first because the target type depends on whether the team has a
  /// club — [Team.promotedToPersistent] picks `permanent` or `independent` so
  /// the type/club invariant holds either way.
  Future<void> promoteEventTeam(String teamId) => guard(() async {
        final team = await getTeam(teamId);
        if (team == null) throw const NotFoundException();
        if (team.type != TeamType.event) {
          throw const ValidationException('That team is already permanent.');
        }
        final promoted = team.promotedToPersistent();
        final problem = promoted.validationError;
        if (problem != null) throw ValidationException(problem);
        await Refs.team(teamId).update({
          'type': promoted.type.wire,
          'competitionId': null,
        });
      });
}
