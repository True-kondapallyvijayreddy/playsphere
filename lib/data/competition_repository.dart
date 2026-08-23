import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/chunked_batch.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/competition.dart';
import '../core/models/organization.dart';
import '../core/models/dispute.dart';
import '../core/models/enums.dart';
import '../core/models/firestore_codec.dart';
import '../core/models/fixture.dart';
import '../core/models/group_entry.dart';
import '../core/models/match_player.dart';
import '../core/models/scoring_request.dart';
import '../core/models/squad_entry.dart';
import '../core/models/team.dart';
import '../core/models/venue.dart' as venue_model;
import '../core/sync/uuid_v7.dart';
import '../domain/draw/fixture_generator.dart';
import '../domain/draw/match_scheduler.dart';
import '../domain/draw/tournament_scheduler.dart';
import '../domain/draw/schedule_shift.dart';
import '../domain/draw/seeding.dart';
import '../domain/draw/swiss_pairing.dart';
import '../domain/rating/glicko2.dart';
import '../domain/tournament/entrant_promoter.dart';
import '../domain/tournament/house_roster.dart';
import '../domain/tournament/team_partitioner.dart';
import 'media_uploader.dart';
import 'rating_service.dart';
import '../domain/standings/standings_calculator.dart';
import '../domain/scoring/scoring_plugin.dart';
import '../domain/scoring/scoring_registry.dart';
import 'org_repository.dart' show guard, guardStream;

/// Specification for forming a team from a player pool or draft.
class TeamDraftSpec {
  const TeamDraftSpec({
    required this.name,
    required this.memberUids,
    this.captainUid,
    this.houseName,
  });

  final String name;
  final List<String> memberUids;
  final String? captainUid;
  final String? houseName;
}

class CompetitionRepository {
  const CompetitionRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the banner upload against a fake bucket.
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

  // --- Branding ---------------------------------------------------------

  /// Puts artwork across the top of an event's page.
  ///
  /// Optional in every sense: `PsBanner` already paints generated art from
  /// the event's sport, so this replaces a working default rather than
  /// filling a hole. That is the point — an organizer who skips it must not
  /// end up with a page that looks broken, or the field becomes a required
  /// one in practice and events stop being quick to create.
  ///
  /// Writes the one field rather than going through `Competition.toUpdate`,
  /// which rewrites the schedule, the entry rules and the fee alongside it.
  ///
  /// `firestore.rules` gates this on `canManageCompetitions(orgId)` and
  /// refuses it outright once the event is completed — a finished event is a
  /// historical record, artwork included.
  Future<String> uploadEventBanner({
    required String orgId,
    required String compId,
    required String uid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'competitions/$compId/banner',
          uid: uid,
          bytes: bytes,
          contentType: contentType,
          // Banners are 1600px and full-bleed, so they earn more headroom
          // than a 512px crest does.
          maxMegabytes: 6,
        );
        await Refs.competition(orgId, compId).update({'bannerUrl': url});
        return url;
      });

  /// Goes back to the generated banner.
  Future<void> removeEventBanner({
    required String orgId,
    required String compId,
  }) =>
      guard(
        () => Refs.competition(orgId, compId).update({'bannerUrl': null}),
      );

  /// Failures from a write that was applied to the local cache and returned
  /// to the caller *before* the server acknowledged it — every method below
  /// marked "not awaited". Mirrors `ScoringService.writeFailures`: with
  /// offline persistence on, awaiting a Firestore write never completes
  /// while offline, so match-day setup screens cannot afford to await these
  /// the way the rest of this repository still awaits reads and simple
  /// admin writes. A screen that wants to tell an organizer "that didn't
  /// save" listens here instead of relying on a thrown exception.
  ///
  /// Static, not an instance field, so the class can stay `const` — every
  /// call site constructs a fresh `CompetitionRepository()` and they must
  /// all observe the same failures.
  static final StreamController<AppException> _writeFailures =
      StreamController<AppException>.broadcast();

  static Stream<AppException> get writeFailures => _writeFailures.stream;

  /// Same translation `ScoringService._translateWriteFailure` applies —
  /// duplicated rather than shared because the two repositories have no
  /// common base and the mapping is a handful of lines, not a reason to
  /// invent one.
  static AppException _translateWriteFailure(Object error) {
    if (error is! FirebaseException) {
      return const ValidationException('That could not be saved.');
    }
    return switch (error.code) {
      'permission-denied' => const PermissionDeniedException(),
      'already-exists' => const ConflictException(),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      _ => ValidationException(error.message ?? 'That could not be saved.'),
    };
  }

  // --- Reads ------------------------------------------------------------

  Stream<List<Competition>> watchCompetitions(
    String orgId, {
    CompetitionStatus? status,
  }) {
    Query<Map<String, dynamic>> q = Refs.competitions(orgId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    // By the date the event happens, most recent first — not by when it was
    // typed in. See [Competition.sortDate]; the dashboard orders on the same
    // key, so the two lists cannot disagree about what "latest" means.
    return guardStream(
      () => q.snapshots().map(
            (snap) => snap.docs.map(Competition.fromDoc).toList()
              ..sort((a, b) => b.sortDate.compareTo(a.sortDate)),
          ),
    );
  }

  Stream<Competition?> watchCompetition(String orgId, String compId) =>
      guardStream(
        () => Refs.competition(orgId, compId).snapshots().map(
              (doc) => doc.exists ? Competition.fromDoc(doc) : null,
            ),
      );

  Stream<List<Registration>> watchRegistrations(
    String orgId,
    String compId, {
    RegistrationStatus? status,
  }) {
    Query<Map<String, dynamic>> q = Refs.registrations(orgId, compId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    return guardStream(
      () => q.snapshots().map(
            (snap) => snap.docs.map(Registration.fromDoc).toList(),
          ),
    );
  }

  Stream<List<Entrant>> watchEntrants(String orgId, String compId) =>
      guardStream(
        () => Refs.entrants(orgId, compId).snapshots().map(
              (snap) => snap.docs.map(Entrant.fromDoc).toList(),
            ),
      );

  /// Every match in one competition.
  ///
  /// [canManage] is not a convenience — it decides which QUERY is sent, and
  /// sending the wrong one is a permission error rather than a wrong answer.
  /// `firestore.rules` opens a draft fixture only to whoever can manage the
  /// competition, and Firestore rejects a list it cannot prove is allowed
  /// instead of quietly filtering it. So a member has to pin `isDraft`
  /// themselves; an organizer must NOT, or they would stop seeing the drafts
  /// they are in the middle of editing.
  ///
  /// Callers pass what the permission matrix says (see `fixturesProvider`),
  /// never a guess. Passing `true` without the capability does not grant
  /// anything — the rule still refuses — it just turns a filtered list into a
  /// denied one.
  Stream<List<Fixture>> watchFixtures(
    String orgId,
    String compId, {
    bool canManage = false,
  }) =>
      guardStream(
        () {
          final Query<Map<String, dynamic>> q = canManage
              ? Refs.fixtures(orgId, compId)
              : Refs.fixtures(orgId, compId).where('isDraft', isEqualTo: false);
          return q.snapshots().map(
                (snap) => snap.docs.map(Fixture.fromDoc).toList()
                  ..sort((a, b) {
                    final r = a.round.compareTo(b.round);
                    return r != 0 ? r : a.matchIndex.compareTo(b.matchIndex);
                  }),
              );
        },
      );

  /// Live matches across an entire organization — powers the spectator
  /// "what's on right now" screen that remote viewers land on.
  Stream<List<Fixture>> watchLiveFixtures(String orgId) {
    return guardStream(
      () => Refs.allFixturesQuery
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: FixtureStatus.live.wire)
          .snapshots()
          .map((snap) => snap.docs.map(Fixture.fromDoc).toList()),
    );
  }

  /// Fixtures a specific person is assigned to score.
  Stream<List<Fixture>> watchMyScoringAssignments(String uid) {
    return guardStream(
      () => Refs.allFixturesQuery
          .where('scorerUids', arrayContains: uid)
          .where('status', whereIn: [
            FixtureStatus.scheduled.wire,
            FixtureStatus.live.wire,
          ])
          .snapshots()
          .map((snap) => snap.docs.map(Fixture.fromDoc).toList()),
    );
  }

  // --- Competition lifecycle -------------------------------------------

  /// Creates a competition, offline included.
  ///
  /// Genuinely fully possible offline: `.doc()` generates the id
  /// client-side with no network round trip, and a fresh `.set()` needs no
  /// prior read. The write is deliberately NOT awaited — see
  /// `ScoringService.submit`'s comment for why: with offline persistence
  /// enabled, an awaited Firestore write does not complete until the server
  /// acknowledges it, and offline that is never, which would hang
  /// "Saving..." for the rest of the time the organizer has no signal. The
  /// local cache write lands at once, so `watchCompetition`/
  /// `watchCompetitions` show the new competition immediately; a failure
  /// once connectivity returns is reported on [writeFailures] instead of by
  /// throwing here.
  Future<String> createCompetition(Competition competition) => guard(() async {
        final ref = Refs.competitions(competition.orgId).doc();
        unawaited(
          ref.set(competition.toCreate()).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
        return ref.id;
      });

  Future<void> updateCompetition(Competition competition) => guard(
        () => Refs.competition(competition.orgId, competition.id)
            .update(competition.toUpdate()),
      );

  Future<void> setStatus({
    required String orgId,
    required String compId,
    required CompetitionStatus status,
  }) =>
      guard(() => Refs.competition(orgId, compId).update({
            'status': status.wire,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  /// Calls an event off, on the record, and tells everybody who had entered.
  ///
  /// ## Why cancelling is not deleting
  ///
  /// The obvious implementation is a delete. It is the wrong one twice over.
  ///
  /// An event that has been played has results hanging off it — fixtures,
  /// scorecards, ratings already settled, career stats already rolled up. A
  /// delete either orphans all of that or cascades through it, and a player's
  /// lifelong record (§2.5) is not something an organizer's stray tap should
  /// be able to punch a hole in.
  ///
  /// Even for an event with nothing played, the people who registered are owed
  /// an explanation, and a deleted document cannot deliver one. So this is a
  /// state transition that keeps the document, keeps the entry list, and keeps
  /// [reason] where the notification and the event page can both read it.
  ///
  /// [reason] is required and refused when blank — see
  /// [Competition.cancelReason] for why that is the point rather than
  /// friction. The push itself is sent by the `onEventCancelled` Cloud
  /// Function watching this transition, so it reaches people whose phones are
  /// off and does not depend on this client staying alive.
  Future<void> cancelCompetition({
    required String orgId,
    required String compId,
    required String reason,
    required String byUid,
  }) =>
      guard(() async {
        final text = reason.trim();
        if (text.isEmpty) {
          throw const ValidationException(
            'Give a reason. Everyone who entered will be told, and an event '
            'that disappears without one reads as a fault in the app.',
          );
        }
        if (text.length > 500) {
          throw const ValidationException('Keep the reason under 500 characters.');
        }

        final snap = await Refs.competition(orgId, compId).get();
        if (!snap.exists) throw const NotFoundException('That event is gone.');
        final existing = Competition.fromDoc(snap);
        if (existing.status == CompetitionStatus.cancelled) {
          throw const ValidationException('This event is already cancelled.');
        }
        if (existing.status == CompetitionStatus.completed) {
          throw const ValidationException(
            'This event has already been played. Cancelling it now would '
            'erase results that count towards people\'s records.',
          );
        }

        await Refs.competition(orgId, compId).update({
          'status': CompetitionStatus.cancelled.wire,
          'cancelReason': text,
          'cancelledBy': byUid,
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Puts one event on hold, reversibly.
  ///
  /// The event-level twin of `TournamentRepository.suspendTournament`, and it
  /// exists for the case that one does not cover: a season where the kho-kho
  /// ground is gone but the badminton is fine. Pausing the season would stop
  /// four sports to stop one.
  ///
  /// [reason] is required for the reason [cancelCompetition] documents.
  Future<void> suspendCompetition({
    required String orgId,
    required String compId,
    required String reason,
    required String byUid,
  }) =>
      guard(() async {
        final text = reason.trim();
        if (text.isEmpty) {
          throw const ValidationException(
            'Give a reason. Everyone who entered will see it, and an event '
            'that stops without one reads as a fault in the app.',
          );
        }
        if (text.length > 500) {
          throw const ValidationException(
            'Keep the reason under 500 characters.',
          );
        }

        final snap = await Refs.competition(orgId, compId).get();
        if (!snap.exists) throw const NotFoundException('That event is gone.');
        final existing = Competition.fromDoc(snap);
        if (existing.isSuspended) {
          throw const ValidationException('This event is already on hold.');
        }
        if (existing.status == CompetitionStatus.cancelled) {
          throw const ValidationException(
            'This event was cancelled. Pausing it now would change nothing.',
          );
        }
        if (existing.status == CompetitionStatus.completed) {
          throw const ValidationException(
            'This event has been played. There is nothing left to pause.',
          );
        }

        await Refs.competition(orgId, compId).update({
          'isSuspended': true,
          'suspendReason': text,
          'suspendedBy': byUid,
          'suspendedAt': FieldValue.serverTimestamp(),
          // False even when the season above is itself suspended: this was
          // the organizer's own decision about this event, and resuming the
          // season must not undo it. See `Competition.suspendedBySeason`.
          'suspendedBySeason': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Brings one paused event back.
  ///
  /// Refuses when the season above it is what paused it — resuming a single
  /// event under a suspended season would put one draw back on a calendar the
  /// rest of the season has vacated, and entries would open for a competition
  /// whose courts are not booked. Resume the season instead, and this comes
  /// back with it.
  ///
  /// The check is on `suspendedBySeason` from the freshly-read document rather
  /// than on anything the caller passes, because the caller is usually the
  /// event page, which holds a `Competition` and no `Tournament` at all.
  Future<void> resumeCompetition({
    required String orgId,
    required String compId,
    required String byUid,
  }) =>
      guard(() async {
        final snap = await Refs.competition(orgId, compId).get();
        if (!snap.exists) throw const NotFoundException('That event is gone.');
        final existing = Competition.fromDoc(snap);
        if (!existing.isSuspended) {
          throw const ValidationException('This event is not on hold.');
        }
        if (existing.suspendedBySeason) {
          throw const ValidationException(
            'The season this event belongs to is on hold. Resume the season '
            'and this event comes back with it.',
          );
        }

        await Refs.competition(orgId, compId).update({
          'isSuspended': false,
          'suspendReason': null,
          'suspendedBy': null,
          'suspendedAt': null,
          'suspendedBySeason': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Sends a note about an event to everyone who entered it, without changing
  /// anything about the event.
  ///
  /// The half of Feature #15 that is not cancellation: "the ground is soft,
  /// bring studs", "we start at 7 not 8". Organizers were sending these on
  /// WhatsApp to a group that never contains everyone who registered, so the
  /// two people who found the event through the app never heard.
  ///
  /// Stored on the competition rather than sent directly, for the same reason
  /// as [cancelCompetition]: the Cloud Function delivers it, and the note
  /// stays readable on the event page afterwards for anyone who missed the
  /// push.
  Future<void> noteToEntrants({
    required String orgId,
    required String compId,
    required String note,
    required String byUid,
  }) =>
      guard(() async {
        final text = note.trim();
        if (text.isEmpty) {
          throw const ValidationException('Write something to send.');
        }
        if (text.length > 500) {
          throw const ValidationException('Keep the note under 500 characters.');
        }

        await Refs.competition(orgId, compId).update({
          'organizerNote': {
            'text': text,
            'byUid': byUid,
            'at': FieldValue.serverTimestamp(),
            // Bumped so the Cloud Function can tell a NEW note from an edit to
            // the competition that happens to carry the old one along.
            'seq': FieldValue.increment(1),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  // --- Global discovery -------------------------------------------------

  /// Every event on the platform that is open for outside entries.
  ///
  /// ## Why this exists as its own read
  ///
  /// Every other list in the product answers "what is happening in MY club",
  /// which is right for a member and useless for the thing clubs actually
  /// need: finding a tournament to enter. A district badminton open exists in
  /// one club's tenant, and until now the only people who could see it were
  /// that club's own members — who are the one group that does not need to
  /// discover it.
  ///
  /// The filters are applied in Dart rather than in the query, and that is a
  /// deliberate trade. Firestore allows one range and a limited number of
  /// equalities per composite index; sport, state, district, category and
  /// date-window in every combination is a combinatorial explosion of indexes
  /// nobody will maintain. What the QUERY pins down is the pair that actually
  /// bounds the result set — open to outsiders, still accepting entries — and
  /// that is a few hundred documents nationally, not a few hundred thousand.
  /// Filtering those in memory is instant and costs one index.
  ///
  /// `openToNonMembers == true` is also the security boundary, not just a
  /// filter: the collection-group rule refuses any query that does not pin it,
  /// so this cannot be widened by accident into reading private draws.
  Stream<List<Competition>> watchGlobalEvents({int limit = 200}) => guardStream(
        () => Refs.allCompetitionsQuery
            .where('openToNonMembers', isEqualTo: true)
            .where('status', whereIn: [
              CompetitionStatus.registrationOpen.wire,
              CompetitionStatus.registrationClosed.wire,
            ])
            .orderBy('startDate')
            .limit(limit)
            .snapshots()
            .map((s) => s.docs.map(Competition.fromDoc).toList()),
      );

  /// Matches your clubmates are playing right now, wherever they are playing
  /// them.
  ///
  /// ## The gap this fills
  ///
  /// Every live list in the product is scoped to a club's own competitions, so
  /// a member turning out for a district side, a college team or a friend's
  /// club vanished from their own club's view entirely. The people most likely
  /// to want to follow that match — the clubmates who know them — were the
  /// only ones who could not.
  ///
  /// ## Why it is capped, and why the cap is where it is
  ///
  /// `arrayContainsAny` takes at most 30 values, so this can watch 30 people,
  /// not a club of four hundred. That is a real limit and it is stated rather
  /// than hidden: [memberUids] should be the clubmates worth following — the
  /// caller passes the most recently active — and the screen says how many it
  /// is watching.
  ///
  /// The alternative shapes are worse. A fan-out of one listener per member is
  /// four hundred listeners on a ₹8k phone. A denormalized "my clubmates are
  /// playing" collection is a write amplification on the hottest document in
  /// the product, paid on every ball of every match. A capped query costs one
  /// listener and one index, and is honest about what it covers.
  ///
  /// Privacy comes free: the collection-group fixture rule already requires
  /// the host org to be readable, so a clubmate playing inside a private club
  /// you do not belong to simply does not appear.
  Stream<List<Fixture>> watchClubmateLiveFixtures({
    required List<String> memberUids,
    int limit = 30,
  }) {
    final watching = memberUids.take(limit).toList();
    if (watching.isEmpty) return Stream.value(const []);

    return guardStream(
      () => Refs.allFixturesQuery
          .where('playerUids', arrayContainsAny: watching)
          .where('status', isEqualTo: FixtureStatus.live.wire)
          .snapshots()
          .map((s) {
        final now = DateTime.now();
        return s.docs
            .map(Fixture.fromDoc)
            // Same activity test as everywhere else: a scoreboard nobody has
            // touched in six hours is not a match anyone should be told to
            // watch (Bug #1 / #15).
            .where((f) => f.isLiveAt(now))
            .toList();
      }),
    );
  }

  // --- Group entries ----------------------------------------------------

  Stream<List<GroupEntry>> watchGroupEntries({
    required String orgId,
    required String compId,
  }) =>
      guardStream(
        () => Refs.groupEntries(orgId, compId).snapshots().map(
              (s) => s.docs.map(GroupEntry.fromDoc).toList()
                ..sort((a, b) => (a.createdAt ?? DateTime(0))
                    .compareTo(b.createdAt ?? DateTime(0))),
            ),
      );

  /// Every squad still waiting on [uid] to answer, across every club.
  ///
  /// The other half of a group entry, and the half that was missing: the
  /// leader proposes and the app told the people they named nothing at all.
  /// The invitation sat on the event's own page, which is a page somebody who
  /// has not entered has no reason to open — so a group could sit in
  /// `forming` forever while five people waited for each other.
  ///
  /// Filtered to `forming` in the query rather than in Dart because the read
  /// rule and the index are both keyed on it, and because a settled group is
  /// not a question. Documents written before [GroupEntry.orgId] existed carry
  /// no path on them and are skipped: a row that cannot be opened or answered
  /// is worse than a row that is not shown.
  Stream<List<GroupEntry>> watchSquadInvites(String uid) => guardStream(
        () => Refs.allGroupEntriesQuery
            .where('memberUids', arrayContains: uid)
            .where('status', isEqualTo: GroupEntryStatus.forming.wire)
            .snapshots()
            .map(
              (s) => [
                for (final doc in s.docs)
                  if (GroupEntry.fromDoc(doc) case final g
                      when g.orgId.isNotEmpty && g.compId.isNotEmpty && g.awaits(uid))
                    g,
              ]..sort((a, b) => (b.createdAt ?? DateTime(0))
                  .compareTo(a.createdAt ?? DateTime(0))),
            ),
      );

  /// Proposes a group entry. Everyone named still has to agree.
  ///
  /// Deliberately does NOT create any registrations. A group that reaches the
  /// field before its members have accepted is a group of people who did not
  /// choose to be there, and withdrawing them afterwards would already have
  /// moved the event's counters.
  Future<String> createGroupEntry({
    required String orgId,
    required String compId,
    required String name,
    required String leaderUid,
    required String leaderName,
    required Map<String, String> members,

    /// What the group is entering. Copied onto the document so the people
    /// being invited can see what they are being asked to play in without
    /// first reading the competition — see [GroupEntry.orgId].
    String competitionName = '',
  }) =>
      guard(() async {
        final groupName = name.trim();
        if (groupName.isEmpty) {
          throw const ValidationException('Give the group a name.');
        }

        // The leader is a member of their own group. Adding them here rather
        // than asking the caller to remember means a group of five is five
        // everywhere it is counted.
        final all = {leaderUid: leaderName, ...members};
        if (all.length < 2) {
          throw const ValidationException(
            'A group needs at least one other person. To enter on your own, '
            'register as an individual.',
          );
        }

        final ref = Refs.groupEntries(orgId, compId).doc();
        await ref.set(
          GroupEntry(
            id: ref.id,
            orgId: orgId,
            compId: compId,
            competitionName: competitionName,
            name: groupName,
            leaderUid: leaderUid,
            leaderName: leaderName,
            memberUids: all.keys.toList(),
            memberNames: all,
            status: GroupEntryStatus.forming,
          ).toCreate(),
        );
        return ref.id;
      });

  /// A named member accepting or declining their place.
  ///
  /// This write is what proves the person is a member of the club at all —
  /// `firestore.rules` only lets an active member make it, and only about
  /// themselves. That is how "a group may contain only club members" is
  /// enforced without the rules having to walk a list, which they cannot do:
  /// a non-member can be named and can never accept, so a complete group is a
  /// group of members by construction.
  ///
  /// Moving the group to `pending_approval` once the last person accepts is
  /// done here rather than by a trigger, because the accepting client already
  /// holds the document and the transition is a pure function of it. A stale
  /// client cannot force it early: the rules re-check that every uid in
  /// `memberUids` is in `acceptedUids` before allowing the status to move.
  Future<void> answerGroupInvite({
    required String orgId,
    required String compId,
    required String groupId,
    required String uid,
    required bool accept,
  }) =>
      guard(() async {
        final ref = Refs.groupEntry(orgId, compId, groupId);

        await Refs.db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) {
            throw const NotFoundException('That group is gone.');
          }
          final group = GroupEntry.fromDoc(snap);

          if (group.status != GroupEntryStatus.forming) {
            throw const ValidationException(
              'This group has already been settled.',
            );
          }
          if (!group.memberUids.contains(uid)) {
            throw const ValidationException('You are not in this group.');
          }

          if (!accept) {
            // One decline ends it. The alternative is a leader waiting
            // indefinitely on somebody who has already said no, and a field
            // slot held open for a group that cannot be completed.
            tx.update(ref, {
              'declinedUids': FieldValue.arrayUnion([uid]),
              'status': GroupEntryStatus.withdrawn.wire,
            });
            return;
          }

          final accepted = {...group.acceptedUids, uid};
          final complete = group.memberUids.every(accepted.contains);

          tx.update(ref, {
            'acceptedUids': FieldValue.arrayUnion([uid]),
            if (complete) 'status': GroupEntryStatus.pendingApproval.wire,
          });
        });
      });

  /// The organizer's decision on a complete group.
  ///
  /// Approving writes one registration per member, in the same batch as the
  /// status change. Separate writes would let a group be marked approved while
  /// half its members never reached the entry list — and the half that did
  /// would be holding slots the organizer never agreed to give them.
  ///
  /// Every member lands `confirmed`: the organizer has just looked at the
  /// group as a whole and said yes, and putting some of them into a queue
  /// afterwards would split exactly the thing that was approved for being
  /// together.
  Future<void> decideGroupEntry({
    required String orgId,
    required String compId,
    required String groupId,
    required bool approve,
    required String byUid,
    String? note,
  }) =>
      guard(() async {
        final snap = await Refs.groupEntry(orgId, compId, groupId).get();
        if (!snap.exists) {
          throw const NotFoundException('That group is gone.');
        }
        final group = GroupEntry.fromDoc(snap);

        if (group.status != GroupEntryStatus.pendingApproval) {
          throw const ValidationException(
            'This group is still waiting on its own members.',
          );
        }

        final batch = Refs.db.batch();
        batch.update(Refs.groupEntry(orgId, compId, groupId), {
          'status': approve
              ? GroupEntryStatus.approved.wire
              : GroupEntryStatus.rejected.wire,
          'decidedBy': byUid,
          if (note != null && note.trim().isNotEmpty)
            'decisionNote': note.trim(),
        });

        if (approve) {
          for (final uid in group.memberUids) {
            batch.set(
              Refs.registration(orgId, compId, uid),
              Registration(
                uid: uid,
                displayName: group.nameFor(uid),
                status: RegistrationStatus.confirmed,
                // The group's name, so the draw shows "Ravi's XI" rather than
                // five unrelated individuals who happen to have entered.
                teamName: group.name,
              ).toCreate(status: RegistrationStatus.confirmed),
            );
          }
          batch.update(Refs.competition(orgId, compId), {
            'confirmedCount': FieldValue.increment(group.size),
            'entrantCount': FieldValue.increment(group.size),
          });
        }

        await batch.commit();
      });

  // --- Registration -----------------------------------------------------

  /// Registers [user], refusing when they do not meet the category rules.
  ///
  /// The eligibility check runs before the write and returns the specific
  /// reason. Silently accepting an ineligible entry and discovering it at
  /// medal time is how school meets end in arguments.
  /// Registers [user] and returns what actually happened to them.
  ///
  /// ## Why this is a transaction and not a `set`
  ///
  /// "The first thirteen people who register are the team" is a promise about
  /// a count, and a count is exactly what a client cannot be trusted with.
  /// Two people tapping Register at the same moment on the thirteenth slot
  /// both read "12 confirmed" and both write themselves in, and the organizer
  /// arrives at the ground with fourteen players and no way to say which one
  /// was late.
  ///
  /// So the decision — confirmed, waitlisted, or an application — is made
  /// inside a Firestore transaction that reads the competition's counters and
  /// writes the registration and the incremented counter together. Firestore
  /// aborts and retries the transaction if the competition document changed
  /// underneath it, which is what turns first-come into a real ordering
  /// rather than a race. `firestore.rules` enforces the same arithmetic
  /// independently, so a client bypassing this method entirely still cannot
  /// confirm itself into a full or approval-gated event.
  ///
  /// ## What this costs
  ///
  /// Transactions do not work offline — they need a round trip to see a
  /// consistent read. Registering therefore requires signal, unlike scoring,
  /// which must not. That trade is deliberate and the right way round:
  /// registration happens on a phone at home in the days before the match,
  /// scoring happens on a ground with no bars. A caller offline gets a
  /// [NetworkException] telling them to try when they have signal, which is
  /// honest, rather than a local write that silently invents a slot that was
  /// taken hours ago.
  Future<RegistrationStatus> register({
    required Competition competition,
    required AppUser user,
    String? houseName,
    String? partnerUid,
    String? partnerName,
    bool isSoloDoubles = false,
    String? teamName,
  }) =>
      guard(() async {
        if (competition.isSuspended) {
          throw ValidationException(
            'This event is on hold'
            '${competition.suspendReason == null ? '' : ' — ${competition.suspendReason}'}'
            '. Entries reopen when the organizer resumes it.',
          );
        }
        if (!competition.registrationIsOpen) {
          throw const ValidationException(
            'Entries are closed for this competition.',
          );
        }

        final eligibility = competition.category.check(
          user,
          competitionStart: competition.startDate,
        );
        if (!eligibility.isEligible) {
          throw ValidationException(
            'Not eligible for ${competition.category.label}. '
            '${eligibility.reason}',
          );
        }

        final compRef = Refs.competition(competition.orgId, competition.id);
        final regRef =
            Refs.registration(competition.orgId, competition.id, user.uid);

        return Refs.db.runTransaction<RegistrationStatus>(
          (tx) async {
            // Re-read rather than trusting the [competition] argument: it came
            // from a snapshot listener and may be seconds stale, which on a
            // last-slot race is the whole question.
            final compSnap = await tx.get(compRef);
            if (!compSnap.exists) {
              throw const ValidationException('That event no longer exists.');
            }
            final fresh = Competition.fromDoc(compSnap);

            if (!fresh.registrationIsOpen) {
              throw const ValidationException(
                'Entries closed while you were registering.',
              );
            }

            // Re-registering after withdrawing is allowed and lands at the
            // back of whatever queue now exists — but a live registration
            // must not be able to double-count itself into two slots.
            final existing = await tx.get(regRef);
            if (existing.exists) {
              final current = Registration.fromDoc(existing);
              if (current.status.occupiesSlot) {
                throw const ValidationException(
                  'You have already registered for this event.',
                );
              }
            }

            final outcome = fresh.outcomeOfRegisteringNow;

            if (outcome == RegistrationStatus.waitlisted &&
                !fresh.waitlistEnabled) {
              throw const ValidationException('This event is full.');
            }

            final position = outcome == RegistrationStatus.waitlisted
                ? fresh.waitlistCount + 1
                : null;

            tx.set(
              regRef,
              Registration(
                uid: user.uid,
                displayName: user.displayName,
                photoUrl: user.photoUrl,
                status: outcome,
                houseName: houseName,
                partnerUid: partnerUid,
                partnerName: partnerName,
                isSoloDoubles: isSoloDoubles,
                teamName: teamName,
              ).toCreate(
                status: outcome,
                waitlistPosition: position,
                houseName: houseName,
                partnerUid: partnerUid,
                partnerName: partnerName,
                isSoloDoubles: isSoloDoubles,
              ),
            );

            // Only the counter that the outcome belongs to moves, and only by
            // one. An approval-model registration moves neither: it does not
            // hold a slot until an organizer confirms it, and counting it
            // would let a queue of applications close a field nobody was
            // admitted to.
            if (outcome == RegistrationStatus.confirmed) {
              tx.update(compRef, {
                'confirmedCount': FieldValue.increment(1),
              });
            } else if (outcome == RegistrationStatus.waitlisted) {
              tx.update(compRef, {
                'waitlistCount': FieldValue.increment(1),
              });
            }

            return outcome;
          },
        );
      });

  /// Enters a whole TEAM into an event, as one entry.
  ///
  /// ## Why this is not [register] with a team name typed into it
  ///
  /// [register] enters the person who pressed the button. For a group sport
  /// that is the wrong unit and has always been: a cricket tournament's field
  /// is a list of sides, and the eleven people in one of them are not eleven
  /// entries competing against each other. The product could already express
  /// a side (`TeamEntryMode.preformedTeam` groups confirmed registrations by
  /// a typed `teamName`) and the cost of doing it that way is everything a
  /// string costs: two members of one club spelling it differently field two
  /// teams, nobody can answer "have Hyderabad CC entered?" with a single
  /// read, and a squad has to be reassembled by hand for every event it plays.
  ///
  /// So the entry is the team document. One write, keyed on the team's id, so
  /// entering twice is idempotent rather than duplicating the side; the roster
  /// is snapshotted onto it, because who was registered is a fact about this
  /// event and the team's own roster will keep moving.
  ///
  /// ## What it deliberately does not check
  ///
  /// Age and gender categories. [Competition.category] is a rule about a
  /// PERSON, and applying it to a team means either refusing the whole side
  /// because one player is a year too old — with no way to substitute them —
  /// or silently entering an ineligible player. Both are worse than the
  /// organizer checking a squad list, which is what happens at a real event.
  /// The squad is written onto the entry precisely so they can.
  Future<RegistrationStatus> registerTeam({
    required Competition competition,
    required Team team,
    required String byUid,
  }) =>
      guard(() async {
        if (competition.isSuspended) {
          throw ValidationException(
            'This event is on hold'
            '${competition.suspendReason == null ? '' : ' — ${competition.suspendReason}'}'
            '. Entries reopen when the organizer resumes it.',
          );
        }
        if (!competition.registrationIsOpen) {
          throw const ValidationException(
            'Entries are closed for this competition.',
          );
        }
        if (team.sportId != competition.sportId) {
          throw ValidationException(
            '${team.name} is a ${SportCatalog.byId(team.sportId).name} team '
            'and this is a ${competition.sportName} event.',
          );
        }
        if (team.memberUids.isEmpty) {
          throw ValidationException(
            '${team.name} has nobody in it yet. Add the squad before '
            'entering them.',
          );
        }

        final compRef = Refs.competition(competition.orgId, competition.id);
        final regRef =
            Refs.registration(competition.orgId, competition.id, team.id);

        return Refs.db.runTransaction<RegistrationStatus>((tx) async {
          // Same re-read as [register], for the same reason: the last slot is
          // decided by what is true at commit time, not by what the caller's
          // snapshot said.
          final compSnap = await tx.get(compRef);
          if (!compSnap.exists) {
            throw const ValidationException('That event no longer exists.');
          }
          final fresh = Competition.fromDoc(compSnap);
          if (!fresh.registrationIsOpen) {
            throw const ValidationException(
              'Entries closed while you were registering.',
            );
          }

          final existing = await tx.get(regRef);
          if (existing.exists &&
              Registration.fromDoc(existing).status.occupiesSlot) {
            throw ValidationException(
              '${team.name} is already entered in this event.',
            );
          }

          final outcome = fresh.outcomeOfRegisteringNow;
          if (outcome == RegistrationStatus.waitlisted &&
              !fresh.waitlistEnabled) {
            throw const ValidationException('This event is full.');
          }
          final position = outcome == RegistrationStatus.waitlisted
              ? fresh.waitlistCount + 1
              : null;

          tx.set(
            regRef,
            Registration(
              // The doc id, and on a team row that is the team's id. See
              // [Registration.teamId].
              uid: team.id,
              displayName: team.name,
              photoUrl: team.photoUrl,
              status: outcome,
              teamName: team.name,
              teamId: team.id,
              memberUids: team.memberUids,
              registeredByUid: byUid,
            ).toCreate(status: outcome, waitlistPosition: position),
          );

          if (outcome == RegistrationStatus.confirmed) {
            tx.update(compRef, {'confirmedCount': FieldValue.increment(1)});
          } else if (outcome == RegistrationStatus.waitlisted) {
            tx.update(compRef, {'waitlistCount': FieldValue.increment(1)});
          }
          return outcome;
        });
      });

  /// Puts members into the field directly — the organizer's picks in a hybrid
  /// event, and the "final changes" an admin makes at the ground.
  ///
  /// These are confirmed on creation and marked [Registration.preselected],
  /// and they consume the reserved slots rather than the open ones: an
  /// organizer filling their 8 must not eat into the 5 that were advertised
  /// as open. That is why this increments nothing — [Competition.openSlots]
  /// already excludes the reserved block, so a preselected entrant is outside
  /// the count that first-come registration competes over.
  Future<void> preselect({
    required Competition competition,
    required List<AppUser> players,
    required String byUid,
  }) =>
      guard(() async {
        if (players.isEmpty) return;

        final ineligible = <String>[];
        for (final p in players) {
          final check = competition.category.check(
            p,
            competitionStart: competition.startDate,
          );
          if (!check.isEligible) {
            ineligible.add('${p.displayName}: ${check.reason}');
          }
        }
        if (ineligible.isNotEmpty) {
          throw ValidationException(
            'Not eligible for ${competition.category.label} — '
            '${ineligible.join('; ')}',
          );
        }

        final batch = Refs.db.batch();
        for (final p in players) {
          final data = Registration(
            uid: p.uid,
            displayName: p.displayName,
            photoUrl: p.photoUrl,
            status: RegistrationStatus.confirmed,
          ).toCreate(
            status: RegistrationStatus.confirmed,
            preselected: true,
          );
          data['decidedBy'] = byUid;
          batch.set(
            Refs.registration(competition.orgId, competition.id, p.uid),
            data,
          );
        }

        // Every id is known client-side, so this is applied to the local cache
        // immediately and not awaited — an organizer naming a squad at the
        // ground gets an instant list. Failures surface on [writeFailures].
        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
      });

  /// An organizer's verdict on a registration.
  ///
  /// Moves the confirmed counter with the decision, because the counter is
  /// what capacity is enforced against: confirming an application without
  /// incrementing it would let an organizer admit twenty people into a
  /// thirteen-slot event and never be told.
  /// An organizer's verdict on a registration.
  ///
  /// Moves the confirmed counter with the decision, because the counter is
  /// what capacity is enforced against: confirming an application without
  /// incrementing it would let an organizer admit twenty people into a
  /// thirteen-slot event and never be told.
  Future<void> decideRegistration({
    required String orgId,
    required String compId,
    required String uid,
    required RegistrationStatus status,
    required String decidedByUid,
    String? note,
  }) =>
      guard(() => _moveRegistration(
            orgId: orgId,
            compId: compId,
            uid: uid,
            after: status,
            extraFields: {
              'decidedBy': decidedByUid,
              'eligibilityNote': note,
              'decidedAt': FieldValue.serverTimestamp(),
            },
          ));

  /// A player pulling out.
  ///
  /// The interesting case is a *confirmed* player pulling out, because that
  /// re-opens a slot — and the flow says the waitlist exists precisely for
  /// this moment. The first reserve is promoted in the same transaction, so
  /// there is never a window where the event is a player short and nobody has
  /// been told they are in.
  Future<void> withdraw({
    required String orgId,
    required String compId,
    required String uid,
  }) =>
      guard(() => _moveRegistration(
            orgId: orgId,
            compId: compId,
            uid: uid,
            after: RegistrationStatus.withdrawn,
          ));

  /// The one path that changes a registration's status.
  ///
  /// Every such change has to move the competition's counters in step with
  /// it, because those counters are what capacity is enforced against — in
  /// the client here, and independently in `firestore.rules`. Three
  /// near-copies of this arithmetic would drift until the counters stopped
  /// meaning anything.
  ///
  /// ## Reads first, then writes
  ///
  /// Firestore transactions require every read to happen before the first
  /// write, so the read phase below is unconditional. That is the API's
  /// shape, not caution.
  ///
  /// ## Why promotion is a second transaction
  ///
  /// When a confirmed player drops out, the first reserve takes their slot.
  /// It is tempting to do both in one transaction, and it does not work:
  /// security rules evaluate a write against the state *before* the
  /// transaction, so at the moment the promotion is checked the event is
  /// still full — the very condition the rule refuses to promote into. The
  /// withdrawal has to commit first for the slot to become provably free.
  ///
  /// The gap between the two is milliseconds, and if the app dies inside it
  /// the result is an event one player short with a reserve still queued —
  /// visible, and fixable by an organizer in one tap. The failure mode of
  /// the alternative is a double-booked slot, which is not.
  Future<void> _moveRegistration({
    required String orgId,
    required String compId,
    required String uid,
    required RegistrationStatus after,
    Map<String, Object?> extraFields = const {},
  }) async {
    final compRef = Refs.competition(orgId, compId);
    final regRef = Refs.registration(orgId, compId, uid);

    final freedASlot = await Refs.db.runTransaction<bool>((tx) async {
      // ---- reads -------------------------------------------------------
      final regSnap = await tx.get(regRef);
      if (!regSnap.exists) {
        throw const ValidationException('That registration is gone.');
      }

      final before = Registration.fromDoc(regSnap).status;
      if (before == after) return false;

      // ---- decide ------------------------------------------------------
      var confirmedDelta = 0;
      var waitlistDelta = 0;
      if (before == RegistrationStatus.confirmed) confirmedDelta -= 1;
      if (after == RegistrationStatus.confirmed) confirmedDelta += 1;
      if (before == RegistrationStatus.waitlisted) waitlistDelta -= 1;
      if (after == RegistrationStatus.waitlisted) waitlistDelta += 1;

      // ---- writes ------------------------------------------------------
      tx.update(regRef, {
        ...extraFields,
        'status': after.wire,
        // Leaving the queue by any route makes the position meaningless, and
        // a stale "3rd reserve" on a confirmed player is how a scorer ends up
        // reading the wrong list at the ground.
        if (after != RegistrationStatus.waitlisted) 'waitlistPosition': null,
      });

      if (confirmedDelta != 0 || waitlistDelta != 0) {
        tx.update(compRef, {
          if (confirmedDelta != 0)
            'confirmedCount': FieldValue.increment(confirmedDelta),
          if (waitlistDelta != 0)
            'waitlistCount': FieldValue.increment(waitlistDelta),
        });
      }

      return confirmedDelta < 0;
    });

    if (freedASlot) {
      await _promoteFirstReserve(orgId, compId, justLeft: uid);
    }
  }

  /// Pulls the first reserve into a slot that has just been freed.
  ///
  /// Deliberately forgiving: a promotion that cannot happen — because the
  /// queue is empty, because the reserve withdrew in the meantime, or
  /// because an organizer refilled the slot first — is not an error in the
  /// withdrawal that triggered it. The player who pulled out has pulled out
  /// either way, and failing their action because someone else's row moved
  /// would be the wrong thing to tell them.
  Future<void> _promoteFirstReserve(
    String orgId,
    String compId, {
    required String justLeft,
  }) async {
    try {
      final next = await _firstWaitlisted(orgId, compId, exclude: justLeft);
      if (next == null) return;

      final compRef = Refs.competition(orgId, compId);
      final nextRef = Refs.registration(orgId, compId, next.uid);

      await Refs.db.runTransaction((tx) async {
        final nextSnap = await tx.get(nextRef);
        final compSnap = await tx.get(compRef);
        if (!nextSnap.exists || !compSnap.exists) return;

        // Re-verified inside the transaction: the query that chose this
        // candidate ran before it, and they may have withdrawn since.
        if (Registration.fromDoc(nextSnap).status !=
            RegistrationStatus.waitlisted) {
          return;
        }

        final comp = Competition.fromDoc(compSnap);
        final open = comp.openSlots;
        // The slot has to genuinely exist. An organizer who over-admitted
        // past capacity should not have the overflow topped back up by the
        // waitlist.
        if (open != null && comp.confirmedCount >= open) return;

        tx.update(nextRef, {
          'status': RegistrationStatus.confirmed.wire,
          'waitlistPosition': null,
          'promotedFromWaitlistAt': FieldValue.serverTimestamp(),
        });
        tx.update(compRef, {
          'confirmedCount': FieldValue.increment(1),
          'waitlistCount': FieldValue.increment(-1),
        });
      });
    } catch (error) {
      _writeFailures.add(_translateWriteFailure(error));
    }
  }


  /// The registration at the front of the waitlist, if there is one.
  ///
  /// Ordered by [Registration.waitlistPosition] rather than creation time so
  /// that the queue an entrant was shown — "you are 2nd reserve" — is the
  /// queue that is actually honoured.
  Future<Registration?> _firstWaitlisted(
    String orgId,
    String compId, {
    String? exclude,
  }) async {
    final snap = await Refs.registrations(orgId, compId)
        .where('status', isEqualTo: RegistrationStatus.waitlisted.wire)
        .orderBy('waitlistPosition')
        .limit(2)
        .get();

    for (final doc in snap.docs) {
      if (doc.id == exclude) continue;
      return Registration.fromDoc(doc);
    }
    return null;
  }


  /// Freezes the confirmed field into entrants and closes registration.
  ///
  /// Registration and entrant are separate on purpose: this is the moment the
  /// starting field is fixed, so a late application cannot appear inside a
  /// bracket that is already being played.
  /// Freezes the confirmed field into entrants and closes registration —
  /// what still requires connectivity, and what does not.
  ///
  /// The read below is the part that cannot be made fully offline-honest.
  /// When offline, Firestore serves this query from whatever this device
  /// has already cached — typically populated by the registrations list
  /// screen's own listener before an organizer ever reaches this button, so
  /// the common case (one organizer, one phone, reviewing then locking the
  /// field at the ground) works. But it is not the same guarantee being
  /// online gives: a registration confirmed moments ago on a *different*
  /// device, never synced to this one, is invisible to this read and will
  /// be silently excluded from the field. There is no way to close that gap
  /// without a connection — a device cannot learn about a write it has
  /// never seen. If completeness across every device matters more than
  /// being able to lock the field right now, this action should wait for
  /// signal.
  ///
  /// The write, once the entrant list is decided, has no such limitation:
  /// every entrant id (`doc(reg.uid)`) is already known client-side, so it
  /// is applied to the local cache and NOT awaited — the count this method
  /// returns is correct the instant the batch is built, regardless of when
  /// the server acknowledges it. A failure is reported on [writeFailures].
  /// Closes entries and converts registrations into official draw entrants.
  /// Handles individual entrants, school house squads, doubles pairs, and preformed teams.
  Future<int> lockFieldAndCreateEntrants({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final compDoc = await Refs.competition(orgId, compId).get();
        final comp = compDoc.exists ? Competition.fromDoc(compDoc) : null;

        final snap = await Refs.registrations(orgId, compId)
            .where('status', isEqualTo: RegistrationStatus.confirmed.wire)
            .get();

        if (snap.docs.isEmpty) {
          throw const ValidationException(
            'At least two confirmed entries are needed before you can close '
            'entries and make a draw.',
          );
        }

        final batch = Refs.db.batch();
        int finalEntrantCount = 0;

        // The promotion rules live in `EntrantPromoter` so they can be
        // tested without a database. Everything this method still does is the
        // part that genuinely needs Firestore: read the confirmed list, write
        // the field it resolves to.
        final promotion = const EntrantPromoter().promote(
          mode: comp?.teamEntryMode ?? TeamEntryMode.individual,
          confirmed: snap.docs.map(Registration.fromDoc).toList(),
        );
        if (!promotion.isReady) {
          throw ValidationException(promotion.problems.join('\n'));
        }
        for (final entrant in promotion.entrants) {
          batch.set(
            Refs.entrants(orgId, compId).doc(entrant.id),
            entrant.toMap(),
          );
        }
        finalEntrantCount = promotion.entrants.length;

        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.registrationClosed.wire,
          'entrantCount': finalEntrantCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
        return finalEntrantCount;
      });

  /// Writes an entrant list straight onto a competition, bypassing
  /// registration entirely.
  ///
  /// ## Why this exists next to `lockFieldAndCreateEntrants`
  ///
  /// That one is the tournament path: people register, an organizer closes
  /// entries, and `EntrantPromoter` turns confirmed registrations into
  /// entrants with all the waitlist and squad rules that implies. It is
  /// correct and it is not what a Sunday club needs.
  ///
  /// A match availability call has already done the asking. Ten people said
  /// they were free; there is no registration to close, no waitlist to
  /// promote, and no approval to wait for — the field is simply those ten.
  /// Routing that through the registration machinery would mean writing ten
  /// registrations in order to immediately read them back and delete them.
  ///
  /// Refuses once fixtures exist, for the same reason
  /// [replaceEntrantsWithSquads] does: a fixture stores the entrant ids it is
  /// between, so replacing entrants underneath a draw leaves matches pointing
  /// at nothing.
  Future<void> seedEntrants({
    required String orgId,
    required String compId,
    required List<Entrant> entrants,
  }) =>
      guard(() async {
        if (entrants.isEmpty) {
          throw const ValidationException(
            'A competition needs at least one entrant.',
          );
        }
        final fixtures = await Refs.fixtures(orgId, compId).limit(1).get();
        if (fixtures.docs.isNotEmpty) {
          throw const ValidationException(
            'This event already has matches. Clear the draw before changing '
            'who is in it.',
          );
        }

        final batch = Refs.db.batch();
        for (final entrant in entrants) {
          batch.set(Refs.entrants(orgId, compId).doc(entrant.id), entrant.toMap());
        }
        batch.update(Refs.competition(orgId, compId), {
          'entrantCount': entrants.length,
          'status': CompetitionStatus.registrationClosed.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // Awaited, unlike the scoring path. Nobody is standing at a crease
        // waiting for this — an organizer is watching a spinner on a setup
        // screen, and the very next thing that happens is a draw generated
        // FROM these entrants. Firing and forgetting would race the draw
        // against the field it is drawn from.
        await batch.commit();
      });

  /// Forms custom squads or drafts from the solo player pool.
  ///
  /// Replaces the entrant list wholesale, which is why it refuses to run once
  /// fixtures exist: a fixture stores the entrant ids it is between, so
  /// deleting an entrant a scheduled match points at leaves that match
  /// referring to nothing, and there is no safe way to guess which new squad
  /// inherited the old one's place. [generateDraw] guards its own regenerate
  /// for the same reason; this path was reachable without any such check.
  ///
  /// The commit is deliberately not awaited, matching
  /// [lockFieldAndCreateEntrants]: every id written here is known
  /// client-side, so the count is correct the moment the batch is built and
  /// the organizer is not made to wait on a round trip at the ground. A
  /// failure surfaces on [writeFailures].
  Future<int> formTeamsFromPool({
    required String orgId,
    required String compId,
    required List<TeamDraftSpec> teams,
  }) =>
      guard(() async {
        if (teams.length < 2) {
          throw const ValidationException(
            'At least two teams are required to make a draw.',
          );
        }

        final existingFixtures = await Refs.fixtures(orgId, compId).get();
        if (existingFixtures.docs.isNotEmpty) {
          final anyScored = existingFixtures.docs
              .map(Fixture.fromDoc)
              .any((f) => f.lastSeq > 0 || f.hasResult);
          throw ValidationException(
            anyScored
                ? 'Some matches in this competition already have scores. '
                    'Squads cannot be re-formed once results exist.'
                : 'A draw has already been made for this competition. '
                    'Clear the existing fixtures before re-forming squads.',
          );
        }

        final batch = Refs.db.batch();
        final existingEntrants = await Refs.entrants(orgId, compId).get();
        for (final doc in existingEntrants.docs) {
          batch.delete(doc.reference);
        }

        for (var i = 0; i < teams.length; i++) {
          final t = teams[i];
          final entrantId =
              'team_${i + 1}_${DateTime.now().millisecondsSinceEpoch % 10000}';
          batch.set(
            Refs.entrants(orgId, compId).doc(entrantId),
            Entrant(
              id: entrantId,
              displayName: t.name,
              entrantType: EntrantType.team,
              memberUids: t.memberUids,
              uid: t.captainUid ?? (t.memberUids.isNotEmpty ? t.memberUids.first : null),
            ).toMap(),
          );
        }

        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.registrationClosed.wire,
          'entrantCount': teams.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
        return teams.length;
      });

  // --- Houses and groups -------------------------------------------------

  /// Saves the organizer's house/group list, carrying the students already
  /// registered under the old names across with it.
  ///
  /// ## Why this is not `updateCompetition` with a new `presetHouses`
  ///
  /// A registration records the house a student PICKED, by name — see
  /// [Registration.houseName]. Nothing links it back to a house id, because
  /// there is no house id: the list on the competition is a list of strings.
  /// So writing a corrected list on its own quietly strands everyone who
  /// entered under the old spelling. Thirty students who chose "Red Hosue"
  /// stay attached to "Red Hosue" while the competition now offers "Red
  /// House", and the team builder drops all thirty into the unassigned pool
  /// with no indication of why.
  ///
  /// [plan] carries the rename map the editor derived from what the organizer
  /// actually edited, and this replays it over the registrations in the same
  /// write as the competition update. A rename therefore moves people; only a
  /// deletion loses them, which is what a deletion means.
  ///
  /// Deleted houses are deliberately NOT reassigned. Picking a house for
  /// somebody is the organizer's call at the team builder, with the names in
  /// front of them — not something to guess here.
  ///
  /// Not awaited, for the reason the rest of this file is not: with offline
  /// persistence on, a commit's future does not complete until the server
  /// acknowledges, and an organizer fixing house names in a school hall with
  /// no signal must not be left watching a spinner. Failures surface on
  /// [writeFailures].
  Future<void> saveHouses({
    required String orgId,
    required String compId,
    required HouseRosterPlan plan,
    TeamEntryMode? entryMode,
  }) =>
      guard(() async {
        if (!plan.isValid) {
          throw ValidationException(plan.error!);
        }

        final batch = ChunkedBatch(Refs.db);

        if (plan.renames.isNotEmpty) {
          // One query per renamed house rather than a full scan of the
          // registrations: a rename touches one house's students, and an
          // event with a thousand entries should not be read in full because
          // somebody fixed a typo.
          for (final entry in plan.renames.entries) {
            final affected = await Refs.registrations(orgId, compId)
                .where('houseName', isEqualTo: entry.key)
                .get();
            for (final doc in affected.docs) {
              batch.update(doc.reference, {'houseName': entry.value});
            }
          }
        }

        batch.update(Refs.competition(orgId, compId), {
          'presetHouses': plan.names,
          if (entryMode != null) 'teamEntryMode': entryMode.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
      });

  /// How many confirmed entries sit in each house right now, including the
  /// ones whose house is no longer on the list.
  ///
  /// The editor shows this beside every row because the number is what makes
  /// a deletion a real decision: "Remove Red House" and "Remove Red House and
  /// its 30 students" are different taps, and the organizer can only tell
  /// which one they are making if the count is on screen.
  static Map<String, int> houseCounts(List<Registration> registrations) {
    final counts = <String, int>{};
    for (final r in registrations) {
      if (r.status != RegistrationStatus.confirmed) continue;
      final h = r.houseName;
      if (h == null || h.isEmpty) continue;
      counts[h] = (counts[h] ?? 0) + 1;
    }
    return counts;
  }

  /// What auto-placing the field into houses would do, without doing it.
  ///
  /// Preview and apply are two calls on purpose. Placing three hundred
  /// students is not a tap an organizer should make blind, and the number that
  /// decides whether they make it — how many the club's roster actually knows
  /// enough about — is only knowable by doing the whole calculation. So the
  /// calculation runs first and the write happens only if they say yes.
  ///
  /// [members] is the hosting club's roster. An entrant who is not in it is an
  /// outsider — an open event's guest from another club — and is reported
  /// rather than placed: this club's houses are not facts about other clubs'
  /// players. See [HouseAssigner].
  static HousePlacementPreview previewHousePlacement({
    required List<Registration> registrations,
    required List<Membership> members,
    required List<String> houses,
  }) {
    final byUid = {for (final m in members) m.uid: m};
    final onList = {for (final h in houses) h.trim().toLowerCase()};

    final placements = <String, String>{};
    final unplaced = <String>[];
    final outsiders = <String>[];
    final alreadyPlaced = <String>[];

    for (final r in registrations) {
      if (r.status != RegistrationStatus.confirmed) continue;

      // A house the organizer put them in by hand, or one they picked
      // themselves at registration, is a decision already made. Bulk actions
      // do not overrule decisions.
      final current = r.houseName?.trim();
      if (current != null &&
          current.isNotEmpty &&
          onList.contains(current.toLowerCase())) {
        alreadyPlaced.add(r.displayName);
        continue;
      }

      final member = byUid[r.uid];
      if (member == null) {
        outsiders.add(r.displayName);
        continue;
      }

      final house = HouseAssigner.assign(member.grouping, houses);
      if (house == null) {
        unplaced.add(r.displayName);
      } else {
        placements[r.uid] = house;
      }
    }

    return HousePlacementPreview(
      placements: placements,
      unplaced: unplaced,
      outsiders: outsiders,
      alreadyPlaced: alreadyPlaced,
    );
  }

  /// Writes the placements a [previewHousePlacement] worked out.
  ///
  /// Chunked, because a school's field is routinely larger than a Firestore
  /// batch, and not awaited for the reason every other bulk write here is not
  /// — see [saveHouses].
  Future<int> applyHousePlacement({
    required String orgId,
    required String compId,
    required HousePlacementPreview preview,
  }) =>
      guard(() async {
        if (preview.placements.isEmpty) return 0;

        final batch = ChunkedBatch(Refs.db);
        for (final e in preview.placements.entries) {
          batch.update(
            Refs.registration(orgId, compId, e.key),
            {'houseName': e.value},
          );
        }

        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
        return preview.placements.length;
      });

  // --- Draw -------------------------------------------------------------

  /// One Glicko-2 rating per entrant, whatever shape the entrant is.
  ///
  /// An individual resolves to their own rating for this sport. A TEAM
  /// resolves to its members' ratings combined by [combineTeamRating] — until
  /// that existed this method's predecessor simply skipped every team, which
  /// meant a club league, a school tournament and any other team event fell
  /// through to the generator's `Random(42)` fallback no matter how much was
  /// known about the players in it.
  ///
  /// Reads are issued per member and are cheap: a rating document is a handful
  /// of numbers, Firestore serves them from cache once warm, and this runs
  /// once per draw rather than once per match.
  Future<Map<String, Rating>> _ratingsForEntrants({
    required List<Entrant> entrants,
    required String sportId,
  }) async {
    const service = RatingService();
    final ratings = <String, Rating>{};

    for (final e in entrants) {
      if (e.withdrawn) continue;

      final solo = e.soloUid;
      if (solo != null) {
        ratings[e.id] = await service.getRating(solo, sportId);
        continue;
      }

      if (e.memberUids.isEmpty) continue;
      final members = <Rating>[
        for (final uid in e.memberUids) await service.getRating(uid, sportId),
      ];
      final combined = combineTeamRating(members);
      if (combined != null) ratings[e.id] = combined;
    }

    return ratings;
  }

  /// Generates and persists the fixture list.
  ///
  /// Refuses to run once a match has been scored: regenerating a draw
  /// underneath results already entered would orphan them, and there is no
  /// safe automatic reconciliation.
  ///
  /// The `anyScored` guard just below is a genuine safety check — a
  /// regenerate deletes every existing fixture, scored or not — and offline
  /// it is only as complete as what this device has cached, exactly like
  /// the read in [lockFieldAndCreateEntrants] above. On the device that has
  /// been scoring the competition throughout (the realistic case this
  /// offline mode is built for) that is everything relevant. Against a
  /// result entered from a second device that never synced to this one
  /// before going offline, it is not, and there is no local fix for that —
  /// only a connection closes the gap. This method does not attempt to
  /// detect that case and refuse; it trusts the same cache the rest of the
  /// screen is already showing the organizer.
  ///
  /// The write that follows has no such limitation — every fixture id comes
  /// from a client-side `.doc()` — so it is applied to the local cache and
  /// NOT awaited; the count returned is final the moment the batch is
  /// built, and a failure is reported on [writeFailures].
  Future<DrawOutcome> generateDraw({
    required Competition competition,
    required List<Entrant> entrants,

    /// Who holds the pen on every fixture the draw writes.
    ///
    /// Almost always EMPTY, and that is the considered default rather than an
    /// oversight. It used to be the organizer who pressed "Make the draw",
    /// stamped onto all thirty-eight matches — which reads as an assignment
    /// and is not one: nobody stands at four courts at once. The roster it
    /// produced was a lie the whole event then had to work around, and it hid
    /// the real question ("who is actually scoring court 3 at 11:40?") behind
    /// a name that was already there.
    ///
    /// An unassigned match is not an unscorable one. An organizer may score
    /// any match in their own club — `firestore.rules` branch (a) and
    /// `ScoringScreen` both allow it, and opening the pad puts their name on
    /// that one match. Officials and scorers are then named per match, after
    /// the draw, when the organizer knows who turned up. See
    /// `UmpireRepository.assignScorer` and the Match Center officials card.
    List<String> defaultScorerUids = const [],
  }) =>
      guard(() async {
        final orgId = competition.orgId;
        final compId = competition.id;

        final existing = await Refs.fixtures(orgId, compId).get();
        final anyScored = existing.docs
            .map(Fixture.fromDoc)
            .any((f) => f.lastSeq > 0 || f.hasResult);
        if (anyScored) {
          throw const ValidationException(
            'Some matches already have scores. Clear those results before '
            'regenerating the draw.',
          );
        }

        // The readiness gate. `validateDrawReadiness` was written with unit
        // tests but never called from anywhere, so a competition could reach
        // a bracket with students still sitting unassigned in the draft pool
        // and squads too short to field a side. Green tests for a gate that
        // does not run are worse than no gate: they read as assurance.
        //
        // It belongs here rather than in the team builder because the builder
        // is one of several ways a field gets decided (a house split and a
        // doubles pairing both bypass it), and this is the one point every
        // one of them has to pass through.
        final confirmedRegs = await Refs.registrations(orgId, compId)
            .where('status', isEqualTo: RegistrationStatus.confirmed.wire)
            .get();
        final readiness = const TeamPartitioner().validateDrawReadiness(
          competition: competition,
          entrants: entrants,
          confirmedRegistrations:
              confirmedRegs.docs.map(Registration.fromDoc).toList(),
        );
        if (!readiness.isReady) {
          throw ValidationException(readiness.reasons.join('\n'));
        }

        // Every parameter the generator accepts is passed. Until this call
        // carried them, a groups+knockout draw silently took the fallback of
        // roughly four per group with two qualifiers each no matter what the
        // organizer chose, because there was no way to say otherwise and no
        // field to say it in.
        final draw = competition.drawConfig;

        // Seeds from the ratings the product already computes, when the
        // organizer asked for it. Until this existed, `Entrant.seed` was a
        // hand-typed integer and the generator fell back to `Random(42)` when
        // nobody had one — so an unseeded 38-player draw was a raffle, while
        // Glicko-2 sat computed and ignored in the next folder.
        var field = entrants;
        List<SeedVerdict> seeding = const [];
        if (draw.seedFromRatings) {
          final ratings = await _ratingsForEntrants(
            entrants: entrants,
            sportId: competition.sportId,
          );
          final result = const SeedingPolicy()
              .assign(entrants: entrants, ratings: ratings);
          seeding = result.verdicts;
          final byId = result.seedsByEntrant;
          field = [
            for (final e in entrants) e.withSeed(byId[e.id]),
          ];
        }

        final planned = const FixtureGenerator().generate(
          format: competition.format,
          entrants: field,
          shuffleSeed: draw.shuffleSeed,
          doubleRoundRobin: draw.doubleRoundRobin,
          bracketReset: draw.bracketReset,
          groupSize: draw.groupSize,
          numGroups: draw.numGroups,
          qualifiersPerGroup: draw.qualifiersPerGroup,
          method: DrawMethod.fromWire(draw.method),
          useGroups: draw.useGroups,
        );
        if (planned.isEmpty) {
          throw const ValidationException(
            'Not enough entrants to make a draw.',
          );
        }

        final sport = SportCatalog.byId(competition.sportId);
        // The organizer's edits layered over the sport preset, resolved once
        // for the whole draw so every fixture in it is created under one set
        // of rules.
        final effectiveConfig = competition.effectiveScoringConfig(sport.config);

        // ---- Pass 1: decide what is actually being written. ----
        //
        // Byes and dead branches are not matches. Everything else is,
        // INCLUDING placeholders whose entrants are still unknown — a
        // quarter-final exists as soon as the draw does, and dropping it is
        // what previously left groups+knockout with no knockout stage. See
        // `SlotFill` for the full history of that bug.
        final kept = <PlannedFixture>[
          for (final p in planned)
            if (p.isPlayable) p,
        ];
        if (kept.isEmpty) {
          throw const ValidationException(
            'Not enough entrants to make a draw.',
          );
        }

        // ---- Pass 2: allocate ids only for what survives. ----
        //
        // Allocating for every planned fixture and writing only some is what
        // produced dangling `feedsWinnerToFixtureId` values pointing at
        // documents that were never created. When one of those matches
        // finished, the advancement `batch.update()` hit a missing document,
        // Firestore rejected the batch, and the SCORE was lost with it. Ids
        // now exist only for documents that will exist, and a pointer at
        // anything else resolves to null rather than to a lie.
        final refByPlannedIndex = <int, DocumentReference<Map<String, dynamic>>>{
          for (final p in kept) p.matchIndex: Refs.fixtures(orgId, compId).doc(),
        };
        String? idFor(int? plannedIndex) =>
            plannedIndex == null ? null : refByPlannedIndex[plannedIndex]?.id;

        // Identifies this draw, so a partial write is detectable and
        // repairable — see `ChunkedBatch` for why atomicity cannot be
        // promised across chunks.
        final drawId = UuidV7.generate();

        // Resolve the picked venues into court names. Done here rather than
        // inside `_planSchedule` so that method stays a pure function of what
        // it is given, and so the reads happen once.
        final venueCourtNames = <String>[];
        for (final venueId in competition.scheduleConfig.venueIds) {
          final vDoc = await Refs.venue(orgId, venueId).get();
          if (!vDoc.exists) continue;
          final venue = venue_model.Venue.fromDoc(vDoc);
          if (venue.isArchived) continue;
          for (final court in venue.usableCourts) {
            venueCourtNames.add(court.name);
          }
        }

        // Turn the draw into a timetable before writing it. Every fixture used
        // to be stamped with `competition.startDate`, so a 38-entrant draw
        // told all 38 entrants to arrive at the same minute — which is not a
        // schedule, and is why tournaments that start at ten finish at eleven.
        final timetable = _planSchedule(kept, competition, venueCourtNames);

        final batch = ChunkedBatch(Refs.db);

        // Clear any previous unscored draw so regenerating does not leave
        // stale fixtures behind alongside the new ones.
        for (final doc in existing.docs) {
          batch.delete(doc.reference);
        }

        for (final p in kept) {
          final ref = refByPlannedIndex[p.matchIndex]!;
          final fixture = Fixture(
            id: ref.id,
            orgId: orgId,
            compId: compId,
            entrantAId: p.entrantA?.id ?? '',
            entrantBId: p.entrantB?.id ?? '',
            entrantAName: p.entrantA?.displayName ?? 'To be decided',
            entrantBName: p.entrantB?.displayName ?? 'To be decided',
            // An individual event never fills a line-up, so this is the only
            // record of who is actually playing. Null for a team entrant and
            // for a knockout slot still waiting on a qualifier — both fill in
            // later, from `_maybeAdvanceWinner` and `promoteGroupQualifiers`.
            entrantAUid: p.entrantA?.soloUid,
            entrantBUid: p.entrantB?.soloUid,
            // Auto-populate lineups from registered entrants so the scoring
            // screen does not block with "Set the line-ups first" when the
            // players are already known. For solo entrants this is the player
            // themselves; team lineups are filled at match-start from the
            // entrant's member list (names require a read we avoid here).
            lineupA: p.entrantA?.soloUid != null
                ? [MatchPlayer(id: p.entrantA!.soloUid!, name: p.entrantA!.displayName, uid: p.entrantA!.soloUid)]
                : const [],
            lineupB: p.entrantB?.soloUid != null
                ? [MatchPlayer(id: p.entrantB!.soloUid!, name: p.entrantB!.displayName, uid: p.entrantB!.soloUid)]
                : const [],
            status: FixtureStatus.scheduled,
            sourceType: competition.matchSource,
            sourceId: competition.matchSourceId,
            round: p.round,
            matchIndex: p.matchIndex,
            roundLabel: p.roundLabel,
            venue: competition.venue,
            scheduledAt: timetable.startAt[p.matchIndex] ?? competition.startDate,
            courtId: timetable.courtId[p.matchIndex],
            tournamentId: competition.tournamentId,
            scorerUids: defaultScorerUids,
            scoringPluginKey: competition.scoringPluginKey,
            sportId: competition.sportId,
            rulesetVersion: competition.rulesetVersion,
            // Frozen here so every surface that renders this match reads the
            // rules it was actually played under, without a second read.
            scoringConfig: effectiveConfig,
            scoreState: ScoringRegistry.resolve(competition.scoringPluginKey)
                .initialState(_contextFor(p, effectiveConfig)),
            feedsWinnerToFixtureId: idFor(p.feedsWinnerToIndex),
            feedsWinnerToSlot: p.feedsWinnerToSlot,
            // The rest of the draw's wiring, which the generator has always
            // produced and this method used to drop on the floor. Without
            // `groupId` no group table can be computed, so no qualifier can
            // ever be resolved and a groups+knockout draw sits at "To be
            // decided" forever; without `feedsLoserTo*` the losers bracket is
            // written and nobody arrives in it.
            feedsLoserToFixtureId: idFor(p.feedsLoserToIndex),
            feedsLoserToSlot: p.feedsLoserToSlot,
            bracket: p.bracket,
            groupId: p.groupId,
            qualifierA: p.qualifierA,
            qualifierB: p.qualifierB,
          );

          batch.set(ref, fixture.toCreate());
        }

        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.scheduled.wire,
          'fixtureCount': kept.length,
          'drawId': drawId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Not awaited, for the same reason every match-day write here is not:
        // the local cache already holds all of it, and awaiting would hang
        // until a server answered. A rejection surfaces on [writeFailures].
        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        // Seeds are persisted onto the entrants so the published seeding list
        // and the bracket cannot disagree, and so regenerating after a
        // withdrawal starts from the same ranking rather than recomputing one
        // that has drifted.
        if (seeding.isNotEmpty) {
          final seedBatch = Refs.db.batch();
          for (final v in seeding) {
            seedBatch.update(
              Refs.entrants(orgId, compId).doc(v.entrantId),
              {'seed': v.seed},
            );
          }
          unawaited(seedBatch.commit().catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }));
        }

        return DrawOutcome(
          planned: planned.length,
          written: kept.length,
          chunks: batch.chunkCount,
          drawId: drawId,
          seeding: seeding,
          // The scheduler already worked out which matches it could not place —
          // no court free inside the day, a rest gap it could not honour — and
          // this method computed the list and dropped it on the floor. The
          // organizer was told "38 matches created" and left to discover at the
          // ground that six of them had a provisional time and no court.
          scheduleProblems: timetable.problems,
        );
      });

  /// Pairs and writes the next Swiss round from the results of the one just
  /// finished.
  ///
  /// ## The bug this exists for
  ///
  /// Swiss is a selectable format, and `generateDraw` produced exactly one
  /// round of it — `FixtureGenerator._swissFirstRound`, which is all that can
  /// be drawn up front because rounds two onward pair by standing and there
  /// are no standings before a ball is bowled. `SwissPairing.nextSwissRound`
  /// was written to build those rounds, was covered by four tests, and was
  /// called from nowhere in `lib/`. So an organizer who picked Swiss got one
  /// round of fixtures and no way to produce a second: the event dead-ended
  /// with the field half-ranked and the app offering no button that would
  /// move it forward.
  ///
  /// ## Why this is additive, and [generateDraw] is not
  ///
  /// `generateDraw` clears the previous draw before writing, because
  /// regenerating a bracket means replacing it. That is exactly wrong here —
  /// every earlier round holds played results, and those results are the only
  /// input this pairing has. Nothing is deleted; the new round is appended
  /// with `matchIndex` continuing past the highest already written, so ids
  /// stay unique across the whole event.
  Future<SwissRoundOutcome> generateNextSwissRound({
    required Competition competition,
    required List<Entrant> entrants,
    List<String> defaultScorerUids = const [],
  }) =>
      guard(() async {
        final orgId = competition.orgId;
        final compId = competition.id;

        if (competition.format != CompetitionFormat.swiss) {
          throw const ValidationException(
            'Only a Swiss event pairs a new round from the last one.',
          );
        }

        // A withdrawal mid-event removes that entrant from every later
        // round, which is the whole reason pairing is done per round rather
        // than drawn up front.
        final active = [for (final e in entrants) if (!e.withdrawn) e];
        if (active.length < 2) {
          throw const ValidationException(
            'Not enough entrants left to pair another round.',
          );
        }

        final all = (await Refs.fixtures(orgId, compId).get())
            .docs
            .map(Fixture.fromDoc)
            .toList();
        if (all.isEmpty) {
          throw const ValidationException(
            'Make the draw first — there is no round one to pair from.',
          );
        }

        final currentRound =
            all.fold<int>(1, (hi, f) => f.round > hi ? f.round : hi);

        const swiss = SwissPairing();
        final totalRounds = swiss.recommendedRoundCount(
          active.length,
          override: competition.drawConfig.swissRounds,
        );
        if (currentRound >= totalRounds) {
          throw ValidationException(
            'This event runs $totalRounds ${totalRounds == 1 ? 'round' : 'rounds'} '
            'and round $currentRound was the last one.',
          );
        }

        // Pairing by standing is only meaningful once the standings are
        // final. Pairing off a half-played round would seed the next one from
        // a table that changes an hour later — and the fixtures would already
        // have been written by then.
        final pending = all
            .where((f) => f.round == currentRound && !f.hasResult)
            .length;
        if (pending > 0) {
          throw ValidationException(
            '$pending ${pending == 1 ? 'match' : 'matches'} in round '
            '$currentRound still ${pending == 1 ? 'needs' : 'need'} a result. '
            'Finish the round before pairing the next one.',
          );
        }

        // Scores come from the competition's own points model, via the same
        // calculator that renders the standings table — so the order this
        // pairs by is the order the organizer is looking at on screen, not a
        // second opinion computed a different way.
        final table = const StandingsCalculator().compute(
          competition: competition,
          entrants: active,
          fixtures: all,
        );
        final pointsById = {
          for (final row in table) row.entrantId: row.points.toDouble(),
        };

        // Who has already sat a round out. Derived from the fixtures rather
        // than stored — see [SwissPairing.byeRecipients] for why.
        final entrantIdsByRound = <int, Set<String>>{};
        for (var r = 1; r <= currentRound; r++) {
          entrantIdsByRound[r] = {
            for (final f in all.where((f) => f.round == r)) ...[
              if (f.entrantAId.isNotEmpty) f.entrantAId,
              if (f.entrantBId.isNotEmpty) f.entrantBId,
            ],
          };
        }
        final byeReceivers = swiss.byeRecipients(
          activeEntrantIds: [for (final e in active) e.id],
          entrantIdsByRound: entrantIdsByRound,
        );

        final playedPairs = <EntrantPair>{
          for (final f in all)
            if (f.entrantAId.isNotEmpty && f.entrantBId.isNotEmpty)
              EntrantPair(f.entrantAId, f.entrantBId),
        };

        final nextRound = currentRound + 1;
        final planned = swiss.nextSwissRound(
          standings: [
            for (final e in active)
              SwissStanding(
                entrant: e,
                score: pointsById[e.id] ?? 0,
                hadBye: byeReceivers.contains(e.id),
              ),
          ],
          playedPairs: playedPairs,
          round: nextRound,
          shuffleSeed: competition.drawConfig.shuffleSeed,
        );

        // The bye is in `planned` but is not a match, so it never reaches the
        // database — same rule the first round is written under.
        final kept = [for (final p in planned) if (p.isPlayable) p];
        if (kept.isEmpty) {
          throw const ValidationException(
            'Nothing left to pair — every remaining entrant has played '
            'everyone else.',
          );
        }

        final sport = SportCatalog.byId(competition.sportId);
        final effectiveConfig =
            competition.effectiveScoringConfig(sport.config);

        final venueCourtNames = <String>[];
        for (final venueId in competition.scheduleConfig.venueIds) {
          final vDoc = await Refs.venue(orgId, venueId).get();
          if (!vDoc.exists) continue;
          final venue = venue_model.Venue.fromDoc(vDoc);
          if (venue.isArchived) continue;
          for (final court in venue.usableCourts) {
            venueCourtNames.add(court.name);
          }
        }

        // `_planSchedule` lays a round out from the competition's own start
        // date, which is correct for a draw made before the event and wrong
        // for a round paired during it — round four would be timetabled for
        // the morning of day one, in the past. So the shape it produces is
        // kept (court allocation, spacing, rest gaps) and the whole block is
        // shifted to begin after the last match already on the books.
        final timetable = _planSchedule(kept, competition, venueCourtNames);
        final shift = _swissRoundOffset(
          planned: timetable.startAt.values,
          previous: all,
          competition: competition,
        );

        final offset =
            all.fold<int>(-1, (hi, f) => f.matchIndex > hi ? f.matchIndex : hi) +
                1;

        final batch = ChunkedBatch(Refs.db);
        final drawId = UuidV7.generate();

        for (final p in kept) {
          final ref = Refs.fixtures(orgId, compId).doc();
          final startAt = timetable.startAt[p.matchIndex];
          final fixture = Fixture(
            id: ref.id,
            orgId: orgId,
            compId: compId,
            entrantAId: p.entrantA?.id ?? '',
            entrantBId: p.entrantB?.id ?? '',
            entrantAName: p.entrantA?.displayName ?? 'To be decided',
            entrantBName: p.entrantB?.displayName ?? 'To be decided',
            entrantAUid: p.entrantA?.soloUid,
            entrantBUid: p.entrantB?.soloUid,
            lineupA: p.entrantA?.soloUid != null
                ? [
                    MatchPlayer(
                      id: p.entrantA!.soloUid!,
                      name: p.entrantA!.displayName,
                      uid: p.entrantA!.soloUid,
                    )
                  ]
                : const [],
            lineupB: p.entrantB?.soloUid != null
                ? [
                    MatchPlayer(
                      id: p.entrantB!.soloUid!,
                      name: p.entrantB!.displayName,
                      uid: p.entrantB!.soloUid,
                    )
                  ]
                : const [],
            status: FixtureStatus.scheduled,
            sourceType: competition.matchSource,
            sourceId: competition.matchSourceId,
            round: p.round,
            // Continues past every index already written, so the ids stay
            // unique across rounds rather than colliding with round one's.
            matchIndex: offset + p.matchIndex,
            roundLabel: p.roundLabel,
            venue: competition.venue,
            scheduledAt: startAt == null
                ? competition.startDate
                : startAt.add(shift),
            courtId: timetable.courtId[p.matchIndex],
            tournamentId: competition.tournamentId,
            scorerUids: defaultScorerUids,
            scoringPluginKey: competition.scoringPluginKey,
            sportId: competition.sportId,
            rulesetVersion: competition.rulesetVersion,
            scoringConfig: effectiveConfig,
            scoreState: ScoringRegistry.resolve(competition.scoringPluginKey)
                .initialState(_contextFor(p, effectiveConfig)),
            // Swiss has no bracket wiring: nobody advances anywhere, every
            // entrant simply plays again next round.
          );
          batch.set(ref, fixture.toCreate());
        }

        batch.update(Refs.competition(orgId, compId), {
          'fixtureCount': all.length + kept.length,
          'drawId': drawId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Not awaited, for the same reason every match-day write here is not:
        // the local cache already holds all of it, and awaiting would hang
        // until a server answered. A rejection surfaces on [writeFailures].
        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return SwissRoundOutcome(
          round: nextRound,
          totalRounds: totalRounds,
          written: kept.length,
          byeEntrantName: _swissByeName(planned),
          scheduleProblems: timetable.problems,
        );
      });

  /// How far to push a freshly paired Swiss round so it starts after the
  /// matches already on the books rather than at the competition's own start
  /// date.
  ///
  /// Returns [Duration.zero] when there is nothing to move — no planned
  /// times, or a previous round that somehow finishes after the new one is
  /// already timetabled for, in which case the layout is left alone rather
  /// than dragged backwards.
  Duration _swissRoundOffset({
    required Iterable<DateTime> planned,
    required List<Fixture> previous,
    required Competition competition,
  }) {
    if (planned.isEmpty) return Duration.zero;

    final firstPlanned = planned.reduce((a, b) => a.isBefore(b) ? a : b);

    DateTime? lastExisting;
    for (final f in previous) {
      final at = f.scheduledAt;
      if (at == null) continue;
      if (lastExisting == null || at.isAfter(lastExisting)) lastExisting = at;
    }
    if (lastExisting == null) return Duration.zero;

    final cfg = competition.scheduleConfig;
    final resumeAt = lastExisting.add(
      Duration(minutes: cfg.matchMinutes + cfg.changeoverMinutes),
    );
    if (!resumeAt.isAfter(firstPlanned)) return Duration.zero;
    return resumeAt.difference(firstPlanned);
  }

  /// The entrant sitting this Swiss round out, if the field is odd.
  ///
  /// Read off the planned round rather than recomputed, so the name reported
  /// to the organizer is the one the pairing actually chose.
  String? _swissByeName(List<PlannedFixture> planned) {
    for (final p in planned) {
      if (p.entrantA != null && p.entrantB == null) {
        return p.entrantA!.displayName;
      }
      if (p.entrantB != null && p.entrantA == null) {
        return p.entrantB!.displayName;
      }
    }
    return null;
  }

  /// Generates a draft schedule against placeholder teams — "Team A", "Team
  /// B", … — before real entrants exist, so an organizer can lay out rounds,
  /// pick venues and times, and line up officials ahead of registration
  /// instead of waiting for it to close.
  ///
  /// Runs the exact same [FixtureGenerator] [generateDraw] does, over
  /// synthetic entrants, so the bracket an organizer plans against — round
  /// robin, knockout, or groups feeding a knockout — is shaped by the same
  /// engine that will draw the real one. All that is asked for here is how
  /// many teams to plan for and, for a groups format, how many a group
  /// holds.
  ///
  /// Deliberately leaves the competition's `status` and `fixtureCount`
  /// untouched: this is a preview, not a milestone in the event's lifecycle.
  /// Analytics and the tournament progress bar both read one of those two, so
  /// leaving them alone is what stops a draft schedule inflating either.
  /// Every fixture this writes carries [Fixture.isDraft], which is what the
  /// rest of the app reads to leave placeholders out of anything it counts,
  /// schedules a spectator against, or offers to reschedule in bulk.
  ///
  /// Refused under the same guard as [generateDraw] — nothing here is
  /// regenerated over a match that already has a score — and for the same
  /// reason: on the ordinary path this only ever runs before real entrants
  /// exist, so there should be nothing to protect, but a competition an
  /// organizer somehow scored by hand must still not be silently wiped.
   /// The identities a draft match must not double-book.
  ///
  /// Real accounts where there are any — a person entered in three events is
  /// the clash the tournament scheduler exists to catch, and only a uid can
  /// see that across draws. A team entered by typing a name into the
  /// registration form has no accounts behind it at all, and for that case the
  /// entrant ids stand in: they cannot catch a player turning out for two
  /// clubs, but they do stop one team being put on two courts at once, which
  /// is the failure an organizer notices from across the hall.
  ///
  /// Never empty, which matters more than what is in it: the scheduler treats
  /// a match with no identities as one it cannot safely place, so an empty set
  /// is the difference between a timetable and a list of matches with no times
  /// on them.
  static Set<String> _clashKeysFor(PlannedFixture p) {
    final uids = <String>{
      if (p.entrantA?.soloUid case final uid?) uid,
      if (p.entrantB?.soloUid case final uid?) uid,
      ...?p.entrantA?.memberUids,
      ...?p.entrantB?.memberUids,
    };
    if (uids.isNotEmpty) return uids;
    return <String>{
      if (p.entrantA?.id case final id?) id,
      if (p.entrantB?.id case final id?) id,
    };
  }

  /// Re-orders a field into the order the entries arrived in.
  ///
  /// The timestamp lives on the REGISTRATION, not on the entrant document the
  /// registration was turned into, so this reads the registrations and sorts
  /// by them. Matched on the entrant's own id first and its uid second, which
  /// covers both shapes the two collections take: `lockFieldAndCreateEntrants`
  /// keys an individual's entrant document by their uid, while a team entrant
  /// carries its own id and the uid of nobody.
  ///
  /// Anyone with no registration to date keeps their existing relative order
  /// and sits BEHIND everyone who has one. That is the honest reading of an
  /// organizer's direct pick or a document written before the field was
  /// timestamped: it is not evidence of having entered first.
  Future<List<Entrant>> _inRegistrationOrder(
    String orgId,
    String compId,
    List<Entrant> entrants,
  ) async {
    if (entrants.length < 2) return entrants;

    final snap = await Refs.registrations(orgId, compId).get();
    final enteredAt = <String, DateTime>{};
    for (final doc in snap.docs) {
      final at = Fs.dateOrNull(doc.data()['createdAt']);
      if (at != null) enteredAt[doc.id] = at;
    }
    if (enteredAt.isEmpty) return entrants;

    DateTime? whenFor(Entrant e) =>
        enteredAt[e.id] ?? (e.uid == null ? null : enteredAt[e.uid!]);

    final indexed = [
      for (var i = 0; i < entrants.length; i++) (index: i, entrant: entrants[i]),
    ]..sort((a, b) {
        final ta = whenFor(a.entrant);
        final tb = whenFor(b.entrant);
        if (ta != null && tb != null) {
          final byTime = ta.compareTo(tb);
          if (byTime != 0) return byTime;
        } else if (ta != null) {
          return -1;
        } else if (tb != null) {
          return 1;
        }
        return a.index.compareTo(b.index);
      });

    return [for (final e in indexed) e.entrant];
  }

 Future<DrawOutcome> generateDraftSchedule({
    required Competition competition,
    required int teamCount,

    /// How many GROUPS the field is split into — not how many teams are in
    /// each one.
    ///
    /// It used to be the other way round, and the two are not interchangeable
    /// from the organizer's chair. "32 teams, 4" has to mean four groups of
    /// eight, because four is the number of tables that appear on the wall;
    /// read as a group *size* the same input silently produced eight groups of
    /// four, which is a different tournament with twice as many standings to
    /// follow. The count is also the number the organizer is actually choosing
    /// between — two groups or four — while the size is the consequence, so it
    /// is the count that belongs in the parameter and the size that belongs in
    /// the summary line.
    ///
    /// Null lets [GroupBounds] pick. Ignored unless the draw is grouped.
    int? numGroups,

    /// Entrants who have actually registered, placed into the draw ahead of
    /// any placeholder.
    ///
    /// The case this exists for: entries are open, ten people have signed up,
    /// the field is capped at thirty-two, and the organizer needs a timetable
    /// *now* — venues booked, officials rostered, a programme to hand out.
    /// Planning against thirty-two anonymous "Team A" placeholders throws away
    /// the ten names already known; waiting for the field to fill means
    /// planning nothing until the week of the event. Seeding the real ten and
    /// leaving twenty-two open slots is what an organizer does on paper, and
    /// it is what this does.
    ///
    /// Withdrawn entrants are dropped rather than given a slot. Order is the
    /// caller's — registration order on the ordinary path.
    List<Entrant> seedWith = const [],
  }) =>
      guard(() async {
        final orgId = competition.orgId;
        final compId = competition.id;

        final existing = await Refs.fixtures(orgId, compId).get();
        final anyScored = existing.docs
            .map(Fixture.fromDoc)
            .any((f) => f.lastSeq > 0 || f.hasResult);
        if (anyScored) {
          throw const ValidationException(
            'Some matches already have scores. Clear those results before '
            'generating a new schedule.',
          );
        }

        var real = [
          for (final e in seedWith)
            if (!e.withdrawn) e,
        ];
        if (real.isEmpty) {
          final eSnap = await Refs.entrants(orgId, compId).get();
          real = [
            for (final doc in eSnap.docs)
              if (!Entrant.fromDoc(doc).withdrawn) Entrant.fromDoc(doc),
          ];
          if (real.isEmpty) {
            final rSnap = await Refs.registrations(orgId, compId).get();
            real = [
              for (final doc in rSnap.docs)
                if (doc.data()['status'] == RegistrationStatus.confirmed.name ||
                    doc.data()['status'] == RegistrationStatus.pending.name)
                  Entrant(
                    id: doc.id,
                    displayName: (doc.data()['displayName'] as String?)?.isNotEmpty == true
                        ? doc.data()['displayName'] as String
                        : 'Player ${doc.id.length > 4 ? doc.id.substring(0, 4) : doc.id}',
                    entrantType: competition.entrantType,
                    uid: doc.id,
                  ),
            ];
          }
        }
        // ── Who is in, and in what order ──────────────────────────────
        //
        // FIRST COME, FIRST IN. When more people have entered than the
        // organizer planned a bracket for, the ones who entered first take the
        // places. That is what a club does at the gate and it is the only rule
        // an organizer can defend to the eleventh team without an argument:
        // the alternative — whoever Firestore happened to return first — is
        // arbitrary and looks like favouritism.
        //
        // Entrant documents carry no timestamp of their own, so the order
        // comes from the REGISTRATIONS they were created from. Anyone without
        // a registration to date (an organizer's direct pick, a legacy
        // document) keeps their existing relative position, after the dated
        // ones rather than ahead of them.
        real = await _inRegistrationOrder(orgId, compId, real);

        // A field already larger than the plan is not an error — the
        // organizer asked for a smaller bracket than the entry list, and the
        // extra entrants simply do not fit in it. Taking the first
        // [teamCount] keeps the draw the size that was asked for.
        final entered = real.length > teamCount ? real.sublist(0, teamCount) : real;

        // ── Where each of them sits in the bracket ────────────────────
        //
        // Registration order decides WHO is in. It must not decide who plays
        // whom: seeding the field by the minute people happened to sign up is
        // how the two strongest sides meet in round one and the final is
        // played at ten in the morning.
        //
        // So the entered field is ordered by the rating the product already
        // computes — Glicko-2, combined across a team's members by
        // `combineTeamRating` — and everyone it cannot speak for keeps
        // registration order behind them. Open slots go last, which puts them
        // at the bottom of a bracket where they behave exactly like the byes
        // they are.
        //
        // The order is then written onto `Entrant.seed` for every position,
        // because that is the only channel `FixtureGenerator` reads: left
        // unseeded it falls back to `Random(42)` and scatters the real
        // entrants in among the open slots.
        final ratings = await _ratingsForEntrants(
          entrants: entered,
          sportId: competition.sportId,
        );
        final verdicts =
            const SeedingPolicy().assign(entrants: entered, ratings: ratings);
        final seedByEntrant = verdicts.seedsByEntrant;

        final byRating = [
          for (var i = 0; i < entered.length; i++) (index: i, entrant: entered[i]),
        ]..sort((a, b) {
            final sa = seedByEntrant[a.entrant.id];
            final sb = seedByEntrant[b.entrant.id];
            if (sa != null && sb != null) return sa.compareTo(sb);
            // A rated player ahead of an unrated one — not because they are
            // better, but because a seed is a position the bracket protects
            // and an unknown cannot be given one.
            if (sa != null) return -1;
            if (sb != null) return 1;
            return a.index.compareTo(b.index);
          });

        final placeholders = <Entrant>[
          for (var i = 0; i < byRating.length; i++)
            byRating[i].entrant.withSeed(i + 1),
          for (var i = entered.length; i < teamCount; i++)
            Entrant(
              id: 'draft_$i',
              // Two vocabularies, because they answer different questions. A
              // draw with nobody in it yet is a shape, and "Team A vs Team B"
              // reads as one. A draw with ten real names in it has gaps, and
              // a gap wants to be called a gap — "Open slot 11" next to ten
              // people, not another "Team K" competing with them for the eye.
              displayName: entered.isEmpty
                  ? 'Team ${_draftTeamLabel(i)}'
                  : 'Open slot ${i + 1}',
              entrantType: competition.entrantType,
              seed: i + 1,
            ),
        ];

        /// Whether a planned side is somebody real, as opposed to an open slot
        /// the organizer is still waiting to fill.
        final enteredIds = {for (final e in entered) e.id};

        // The competition's own draw settings, not a fresh set of defaults.
        //
        // This call used to hardcode two qualifiers and never pass
        // `useGroups` at all, so a knockout that an organizer had explicitly
        // split into groups came back as a flat bracket: the sheet asked them
        // about groups, and the generator was never told there were any.
        final draw = competition.drawConfig;
        final planned = const FixtureGenerator().generate(
          format: competition.format,
          entrants: placeholders,
          useGroups: draw.useGroups,
          numGroups: numGroups ?? draw.numGroups,
          groupSize: numGroups == null ? draw.groupSize : null,
          qualifiersPerGroup: draw.qualifiersPerGroup,
          doubleRoundRobin: draw.doubleRoundRobin,
        );
        final kept = <PlannedFixture>[
          for (final p in planned)
            if (p.isPlayable) p,
        ];
        if (kept.isEmpty) {
          throw const ValidationException(
            'Not enough teams to plan a schedule — try a higher number.',
          );
        }

        final refByPlannedIndex = <int, DocumentReference<Map<String, dynamic>>>{
          for (final p in kept) p.matchIndex: Refs.fixtures(orgId, compId).doc(),
        };
        String? idFor(int? plannedIndex) =>
            plannedIndex == null ? null : refByPlannedIndex[plannedIndex]?.id;

        final sport = SportCatalog.byId(competition.sportId);
        final effectiveConfig = competition.effectiveScoringConfig(sport.config);

        // ── Court & time-slot allocation ──────────────────────────────
        // Build courts from ScheduleConfig venues (or ad-hoc names) and
        // compute time slots so every draft fixture gets a real court and
        // start time instead of the blanket competition.startDate.
        final sc = competition.scheduleConfig;
        final courtRefs = <CourtRef>[];

        if (sc.usesVenues) {
          for (final vid in sc.venueIds) {
            final vDoc = await Refs.venue(orgId, vid).get();
            if (!vDoc.exists) continue;
            final v = venue_model.Venue.fromDoc(vDoc);
            for (final c in v.usableCourts) {
              courtRefs.add(CourtRef(
                venueId: v.id,
                venueName: v.name,
                courtId: c.id,
                courtName: c.name,
              ));
            }
          }
        } else if (sc.courts.isNotEmpty) {
          for (var i = 0; i < sc.courts.length; i++) {
            courtRefs.add(CourtRef(
              venueId: 'adhoc',
              venueName: competition.venue ?? '',
              courtId: 'court_$i',
              courtName: sc.courts[i],
            ));
          }
        }

        // Build the placement map: matchIndex → (court, scheduledAt).
        // Falls back gracefully when no courts/venues are configured.
        final placements = <int, Placement>{};
        if (courtRefs.isNotEmpty && competition.startDate != null) {
          final startDate = competition.startDate!;
          final endDate = competition.endDate ?? startDate;
          final dayCount = endDate.difference(startDate).inDays + 1;

          final slots = TournamentScheduler.buildSlots(
            firstDay: startDate,
            dayCount: dayCount,
            openHour: sc.dayStartHour,
            closeHour: sc.dayEndHour,
            slotMinutes: sc.slotMinutes,
          );

          // ONLY the matches that can actually be played get a court and a
          // time, and that is the point of a draft rather than a limitation
          // of it.
          //
          // A match against "Open slot 7" is not a fixture, it is a gap with a
          // shape. Giving it 9:40 on court 2 books a court nobody will use,
          // pushes a match between two teams who ARE entered into the
          // afternoon, and prints a programme with half its lines undated in
          // the wrong half. Real-versus-real first is what an organizer does
          // with a whiteboard: put down the games you can run, leave the rest
          // as slots to fill as people enter.
          //
          // The remaining matches are simply left without a placement. They
          // are not reported as scheduling problems because they are not
          // problems — [generateDraftSchedule] returns no `scheduleProblems`
          // for this reason, unlike [generateDraw], where an unplaced match is
          // a real one with nowhere to go.
          final schedulable = <SchedulableMatch>[
            for (final p in kept)
              if (enteredIds.contains(p.entrantA?.id) &&
                  enteredIds.contains(p.entrantB?.id))
                SchedulableMatch(
                  compId: compId,
                  matchIndex: p.matchIndex,
                  round: p.round,
                  // Member uids as well as the solo one. A team entrant has no
                  // `soloUid` at all, so keyed on that alone every match in a
                  // club league, a school tournament or any other team event
                  // arrived at the scheduler with nobody in it — and a match
                  // with no players is one the scheduler refuses to place,
                  // which is why a team draft schedule came back with no
                  // courts and no times on any of it.
                  playerUids: _clashKeysFor(p),
                  isGroupStage: p.groupId != null,
                  matchMinutes: sc.matchMinutes,
                ),
          ];

          final result = const TournamentScheduler().schedule(
            matches: schedulable,
            courts: courtRefs,
            slots: slots,
            minRestBetweenMatches: Duration(minutes: sc.restGapMinutes),
          );

          for (final entry in result.placements.entries) {
            // Key is "compId#matchIndex" — extract matchIndex.
            final parts = entry.key.split('#');
            if (parts.length == 2) {
              final idx = int.tryParse(parts[1]);
              if (idx != null) placements[idx] = entry.value;
            }
          }
        }

        final batch = ChunkedBatch(Refs.db);

        // Clear any previous draft (or unscored real draw — the guard above
        // already refused if anything in it was scored) so regenerating does
        // not leave stale fixtures sitting alongside the new ones.
        for (final doc in existing.docs) {
          batch.delete(doc.reference);
        }

        for (final p in kept) {
          final ref = refByPlannedIndex[p.matchIndex]!;
          final placement = placements[p.matchIndex];
          final fixture = Fixture(
            id: ref.id,
            orgId: orgId,
            compId: compId,
            entrantAId: p.entrantA?.id ?? '',
            entrantBId: p.entrantB?.id ?? '',
            entrantAName: p.entrantA?.displayName ?? 'To be decided',
            entrantBName: p.entrantB?.displayName ?? 'To be decided',
            // An individual event never fills a line-up, so this is the only
            // record of who is actually playing. Null for a team entrant and
            // for a knockout slot still waiting on a qualifier — both fill in
            // later, from `_maybeAdvanceWinner` and `promoteGroupQualifiers`.
            entrantAUid: p.entrantA?.soloUid,
            entrantBUid: p.entrantB?.soloUid,
            status: FixtureStatus.scheduled,
            sourceType: competition.matchSource,
            sourceId: competition.matchSourceId,
            round: p.round,
            matchIndex: p.matchIndex,
            roundLabel: p.roundLabel,
            venue: placement?.court.venueName ?? competition.venue,
            courtId: placement?.court.courtId,
            scheduledAt: placement?.window.start ?? competition.startDate,
            tournamentId: competition.tournamentId,
            scoringPluginKey: competition.scoringPluginKey,
            sportId: competition.sportId,
            rulesetVersion: competition.rulesetVersion,
            scoringConfig: effectiveConfig,
            scoreState: ScoringRegistry.resolve(competition.scoringPluginKey)
                .initialState(_contextFor(p, effectiveConfig)),
            feedsWinnerToFixtureId: idFor(p.feedsWinnerToIndex),
            feedsWinnerToSlot: p.feedsWinnerToSlot,
            feedsLoserToFixtureId: idFor(p.feedsLoserToIndex),
            feedsLoserToSlot: p.feedsLoserToSlot,
            bracket: p.bracket,
            groupId: p.groupId,
            qualifierA: p.qualifierA,
            qualifierB: p.qualifierB,
            isDraft: true,
          );
          batch.set(ref, fixture.toCreate());
        }

        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return DrawOutcome(
          planned: planned.length,
          written: kept.length,
          chunks: batch.chunkCount,
          drawId: UuidV7.generate(),
        );
      });

  /// "Team A", "Team B", … "Team Z", "Team AA" — spreadsheet-style, so
  /// running out of single letters degrades to something still readable
  /// instead of a number nobody can place in the bracket by eye.
  static String _draftTeamLabel(int index) {
    var n = index;
    var label = '';
    do {
      label = String.fromCharCode(65 + n % 26) + label;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return label;
  }

  /// Converts every draft fixture into a real, published fixture and sets the
  /// competition status to [CompetitionStatus.scheduled].
  ///
  /// This is the one-tap "Lock & Publish" action an organizer triggers when
  /// the draft timetable looks right and they want participants to see it.
  /// Until this runs, draft fixtures are invisible to everyone outside the
  /// organizer team.
  Future<void> publishDraftSchedule({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final snap = await Refs.fixtures(orgId, compId).get();
        final drafts = snap.docs
            .map(Fixture.fromDoc)
            .where((f) => f.isDraft)
            .toList();

        if (drafts.isEmpty) {
          throw const ValidationException(
            'There is no draft schedule to publish.',
          );
        }

        final batch = ChunkedBatch(Refs.db);
        for (final f in drafts) {
          batch.update(
            Refs.fixtures(orgId, compId).doc(f.id),
            {'isDraft': false},
          );
        }
        // Flip the competition into the "scheduled" state so public feeds,
        // notifications, and the club portal all pick it up.
        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.scheduled.name,
          'fixtureCount': drafts.length,
        });

        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
      });

  /// Counts how much of a draw actually reached the server.
  ///
  /// Exists because [ChunkedBatch] gives up cross-chunk atomicity, and the
  /// honest response to that is a way to detect a partial write rather than a
  /// comment asserting it will not happen. Compares the fixtures carrying
  /// [drawId] against the count recorded on the competition.
  Future<({int expected, int found, bool complete})> verifyDraw({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final comp = await Refs.competition(orgId, compId).get();
        final expected = (comp.data()?['fixtureCount'] as num?)?.toInt() ?? 0;
        final drawId = comp.data()?['drawId'] as String?;
        if (drawId == null) {
          return (expected: expected, found: expected, complete: true);
        }
        final snap = await Refs.fixtures(orgId, compId)
            .where('drawId', isEqualTo: drawId)
            .count()
            .get();
        final found = snap.count ?? 0;
        return (
          expected: expected,
          found: found,
          complete: found >= expected,
        );
      });

  /// Creates a one-off match and the competition that holds it, together.
  ///
  /// The club's own internal game, and one player against another. Both were
  /// impossible to express before: a fixture lives under a competition, and
  /// the only route to a competition ran through registration and a draw. So
  /// a Sunday side-versus-side, or two friends on a badminton court, had to
  /// be staged as a tournament of two — six screens before the first serve,
  /// which on a ground is the same as not being possible.
  ///
  /// One batch, so a competition can never exist without its match. The
  /// fixture is created `live` rather than `scheduled` and the creator is its
  /// scorer, because the entire point of the path is that the next tap after
  /// this one is a score.
  ///
  /// Returns the new fixture's ids so the caller can open the pad on it.
  Future<({String compId, String fixtureId})> createQuickMatch({
    required String orgId,
    required String name,
    required SportSpec sport,
    required CompetitionCategory category,
    required String sideAName,
    required String sideBName,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
    required String createdByUid,
    String? venue,
    DateTime? startsAt,
    Map<String, dynamic>? scoringConfig,
  }) =>
      guard(() async {
        if (lineupA.isEmpty || lineupB.isEmpty) {
          throw const ValidationException(
            'Both sides need at least one player before the match can start.',
          );
        }

        final compRef = Refs.competitions(orgId).doc();
        final fixtureRef = Refs.fixtures(orgId, compRef.id).doc();
        final config = scoringConfig ?? sport.config;

        // Entrant ids are the fixture's own two sides rather than references
        // to registration documents, because a quick match has no
        // registrations to point at. They only have to be stable and distinct
        // within the match — the standings calculator and the award both key
        // on them, and neither cares what they spell.
        const entrantAId = 'side_a';
        const entrantBId = 'side_b';

        final competition = Competition(
          id: compRef.id,
          orgId: orgId,
          name: name,
          sportId: sport.id,
          sportName: sport.name,
          archetype: sport.archetype,
          entrantType: lineupA.length > 1 || lineupB.length > 1
              ? EntrantType.team
              : EntrantType.individual,
          format: CompetitionFormat.singleMatch,
          // Overwritten by `toCreate`, which is the single place a starting
          // status is decided. Passed here only because the field is required.
          status: CompetitionStatus.inProgress,
          category: category,
          scoringPluginKey: sport.pluginKey,
          venue: venue,
          startDate: startsAt ?? DateTime.now(),
          // Nobody registers for a match that already has both team sheets.
          participationModel: ParticipationModel.approval,
          entrantCount: 2,
          fixtureCount: 1,
          createdBy: createdByUid,
        );

        final fixture = Fixture(
          id: fixtureRef.id,
          orgId: orgId,
          compId: compRef.id,
          entrantAId: entrantAId,
          entrantBId: entrantBId,
          entrantAName: sideAName,
          entrantBName: sideBName,
          // Scheduled until somebody scores something. Nobody has to remember
          // to start it: the first accepted action flips it to live, in
          // `ScoringService.apply`.
          //
          // This used to open `live` on the argument that the person setting
          // it up is already standing on the court. But a match that is set
          // up and not yet under way is exactly what "Live now" must not
          // contain — a fixture created for a game starting in an hour, or
          // one abandoned during setup, sat in every follower's live list
          // showing 0-0 with nothing happening. Live means a scorecard has
          // started.
          status: FixtureStatus.scheduled,
          // §12 — a quick match is the archetypal standalone game: no
          // tournament above it and nobody to answer to.
          sourceType: MatchSource.singleMatch,
          sourceId: compRef.id,
          roundLabel: 'Match',
          venue: venue,
          scheduledAt: startsAt ?? DateTime.now(),
          scorerUids: [createdByUid],
          scoringPluginKey: sport.pluginKey,
          sportId: sport.id,
          scoringConfig: config,
          lineupA: lineupA,
          lineupB: lineupB,
          scoreState: ScoringRegistry.resolve(sport.pluginKey).initialState(
            ScoringContext(
              entrantAName: sideAName,
              entrantBName: sideBName,
              config: config,
              lineupA: lineupA,
              lineupB: lineupB,
            ),
          ),
          // No `startedAt`. It contradicted the `scheduled` status three lines
          // above and the comment explaining why that status is deliberate: a
          // match that has been set up has not started. `ScoringService.submit`
          // stamps it on the first accepted action, which is the moment it
          // becomes true.
        );

        final batch = Refs.db.batch();
        batch.set(compRef, competition.toCreate());
        batch.set(fixtureRef, fixture.toCreate());

        // Not awaited, for the same reason every other match-day write in
        // this file is not: with offline persistence on, a Firestore commit
        // does not complete until the server acknowledges it, and a club
        // ground has no signal. The local cache takes the write immediately,
        // so the pad opens on a real fixture either way; a rejection once
        // connectivity returns arrives on [writeFailures].
        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return (compId: compRef.id, fixtureId: fixtureRef.id);
      });

  /// Pulls an entrant out of a draw that has already been made, and resolves
  /// every match they had left.
  ///
  /// ## Why this is not the same as [withdraw]
  ///
  /// [withdraw] moves a *registration* before the draw exists: the field is
  /// still open, a reserve is promoted, and nobody has been drawn against
  /// anybody. Once the draw is made there is no slot to give back — there are
  /// fixtures, some of them days away, each with a real opponent who is
  /// entitled to a result rather than a match that silently never happens.
  ///
  /// Before this existed a team that dropped out mid-tournament left their
  /// remaining fixtures sitting as `scheduled` forever. The league table
  /// counted matches nobody would ever play, the knockout bracket waited on a
  /// winner who would never be decided, and an organizer's only recourse was
  /// to open each one and force a walkover by hand.
  ///
  /// ## What it does not touch
  ///
  /// Anything already played or in progress. A completed match is history and
  /// a live one has a scorer standing over it; withdrawing later does not
  /// unmake either. Only fixtures that have not had a single event are
  /// resolved, which is also what makes this safe to run at any point.
  ///
  /// A fixture whose *other* side is still unknown is skipped rather than
  /// awarded — there is nobody to award it to yet. It resolves naturally when
  /// the opponent arrives and this is run again, or when a later concession
  /// reaches it.
  Future<WithdrawalOutcome> withdrawEntrant({
    required String orgId,
    required String compId,
    required String entrantId,
    String? note,
  }) =>
      guard(() async {
        final snap = await Refs.fixtures(orgId, compId).get();
        final fixtures = snap.docs.map(Fixture.fromDoc).toList();

        final batch = Refs.db.batch();
        var conceded = 0;
        var skipped = 0;

        for (final f in fixtures) {
          final isTheirs =
              f.entrantAId == entrantId || f.entrantBId == entrantId;
          if (!isTheirs) continue;
          // Played, playing, or already resolved — not ours to rewrite.
          if (f.status != FixtureStatus.scheduled || f.lastSeq > 0) continue;

          final opponentId =
              f.entrantAId == entrantId ? f.entrantBId : f.entrantAId;
          if (opponentId.isEmpty) {
            skipped++;
            continue;
          }
          final opponentName =
              f.entrantAId == entrantId ? f.entrantBName : f.entrantAName;
          // Carried forward with the id it belongs to. Read off this fixture
          // rather than looked up again: the beneficiary is already one of
          // these two sides, so the answer is in hand.
          final opponentUid =
              f.entrantAId == entrantId ? f.entrantBUid : f.entrantAUid;

          batch.update(Refs.fixture(orgId, compId, f.id), {
            'status': FixtureStatus.walkover.wire,
            // Conceded, not walkover: the difference is that the entrant left
            // the competition rather than missing this one match, and a
            // scorecard weeks later should say which.
            'resultType': MatchResultType.conceded.wire,
            'winnerEntrantId': opponentId,
            'isDraw': false,
            // The wire token, not a sentence — the same convention
            // `ScoringService.setFixtureOutcome` documents at length. A
            // persisted English phrase would freeze one scorer's language onto
            // the document and show it to a Telugu spectator forever; the UI
            // translates the token at render time.
            'summary': MatchResultType.conceded.wire,
            'resultNote': note ?? 'Opponent withdrew from the competition.',
            'completedAt': FieldValue.serverTimestamp(),
          });
          conceded++;

          // Carry the beneficiary forward, exactly as a played result would.
          // Without this a concession in a quarter-final leaves the semi-final
          // permanently waiting on a winner who has already been decided.
          if (f.feedsWinnerToFixtureId != null &&
              f.feedsWinnerToSlot != null) {
            final slot = f.feedsWinnerToSlot == 'a' ? 'A' : 'B';
            batch.update(
              Refs.fixture(orgId, compId, f.feedsWinnerToFixtureId!),
              {
                'entrant${slot}Id': opponentId,
                'entrant${slot}Name': opponentName,
                'entrant${slot}Uid': opponentUid,
                // `playerUids` is a stored summary of a derived getter, so a
                // slot filled after the fixture was written has to extend it
                // here or the promoted player's own match list never learns
                // they are in the next round. arrayUnion, not a rewrite: the
                // opposite slot may already hold somebody.
                if (opponentUid != null)
                  'playerUids': FieldValue.arrayUnion([opponentUid]),
              },
            );
          }
        }

        // `set(merge: true)`, not `update`.
        //
        // An `update` on a document that does not exist fails, and in a batch
        // it takes every other write with it — so a competition whose entrant
        // documents were never created (a challenge fixture names clubs
        // directly, and a quick match names sides) would lose the whole
        // concession, silently, along with every walkover it had just awarded.
        batch.set(
          Refs.entrants(orgId, compId).doc(entrantId),
          {'withdrawn': true},
          SetOptions(merge: true),
        );

        // Not awaited — same reason as every other match-day write here.
        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return WithdrawalOutcome(
          matchesConceded: conceded,
          matchesWaiting: skipped,
        );
      });

  /// Fills the knockout phase of a groups+knockout draw from the group tables.
  ///
  /// This is the step that was missing entirely. The generator has always
  /// produced a fully-shaped knockout bracket alongside the groups, with each
  /// slot tagged by the table position that will fill it ("winner of Group B"),
  /// and nothing has ever read those tags — so the quarter-finals of every
  /// groups+knockout tournament ever drawn in this app read "To be decided"
  /// permanently, and organizers did the promotion on paper.
  ///
  /// ## Only complete groups promote
  ///
  /// A group is resolved only once every one of its matches has a result. Half
  /// a group has a leader, not a winner, and writing that leader into a
  /// quarter-final would stick: nothing downstream would move them back out
  /// when the last group match reversed the table.
  ///
  /// ## Safe to call repeatedly
  ///
  /// Idempotent by construction — a slot that already holds a real entrant is
  /// skipped, so this can run on every result without needing to know whether
  /// it has run before. That matters because the natural trigger is "a group
  /// match finished", which fires many times for the same group.
  Future<QualifierOutcome> resolveQualifiers({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final compDoc = await Refs.competition(orgId, compId).get();
        if (!compDoc.exists) {
          throw const NotFoundException('That competition no longer exists.');
        }
        final competition = Competition.fromDoc(compDoc);

        final fixtureSnap = await Refs.fixtures(orgId, compId).get();
        final fixtures = fixtureSnap.docs.map(Fixture.fromDoc).toList();

        final entrantSnap = await Refs.entrants(orgId, compId).get();
        final entrants = entrantSnap.docs.map(Entrant.fromDoc).toList();

        const calculator = StandingsCalculator();
        final tables = calculator.computeGroups(
          competition: competition,
          entrants: entrants,
          fixtures: fixtures,
        );

        final complete = <String, List<Standing>>{
          for (final entry in tables.entries)
            if (calculator.isGroupComplete(entry.key, fixtures))
              entry.key: entry.value,
        };

        // A standing carries an entrant id and a display name, not an account.
        // The entrants are already loaded above for the tables, so resolving
        // the promoted player's uid costs nothing more than this map.
        final soloUidByEntrantId = <String, String>{
          for (final e in entrants)
            if (e.soloUid != null) e.id: e.soloUid!,
        };

        final batch = Refs.db.batch();
        var resolved = 0;
        final waiting = <String>{};

        for (final fixture in fixtures) {
          final updates = <String, Object?>{};
          // Both slots of one fixture can resolve in the same pass, so the
          // promoted accounts are gathered before the single arrayUnion below.
          // Writing `playerUids` inside `fill` would let the second slot's
          // union silently replace the first's.
          final promotedUids = <String>[];

          void fill(String slot, QualifierSource? source, String existingId) {
            if (source == null || existingId.isNotEmpty) return;
            final table = complete[source.groupId];
            if (table == null) {
              waiting.add(source.groupId);
              return;
            }
            // A group with fewer finishers than the draw expects to promote
            // — an entrant withdrew before a ball was played. Leaving the
            // slot unresolved is right: the organizer has to decide whether
            // to give a bye or reshape the bracket, and a silent wrong name
            // in a quarter-final is worse than an empty one.
            if (source.position > table.length) return;
            final standing = table[source.position - 1];
            updates['entrant${slot}Id'] = standing.entrantId;
            updates['entrant${slot}Name'] = standing.displayName;
            final soloUid = soloUidByEntrantId[standing.entrantId];
            updates['entrant${slot}Uid'] = soloUid;
            if (soloUid != null) promotedUids.add(soloUid);
          }

          fill('A', fixture.qualifierA, fixture.entrantAId);
          fill('B', fixture.qualifierB, fixture.entrantBId);

          if (promotedUids.isNotEmpty) {
            updates['playerUids'] = FieldValue.arrayUnion(promotedUids);
          }

          if (updates.isEmpty) continue;
          batch.update(Refs.fixture(orgId, compId, fixture.id), updates);
          resolved++;
        }

        if (resolved > 0) {
          // Not awaited, for the reason every match-day write here is not:
          // the local cache has it already and awaiting would hang offline.
          unawaited(batch.commit().catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }));
        }

        return QualifierOutcome(
          slotsResolved: resolved,
          groupsComplete: complete.keys.toList()..sort(),
          groupsPending: waiting.toList()..sort(),
        );
      });

  /// Turns a generated draw into "which court, what time" for every fixture.
  ///
  /// ## Why placeholders get a time too
  ///
  /// [MatchScheduler] deliberately skips a fixture whose entrants are not both
  /// known — you cannot check a rest gap for a player you cannot name, and a
  /// semi-final has no players until the quarter-finals are played. But an
  /// organizer publishing a schedule still has to tell people roughly when to
  /// come back, and every federation solves this the same way: a placeholder
  /// carries a **"not before" time**, derived from when its feeder round is
  /// expected to finish. So this method schedules what it can properly, then
  /// gives every remaining round a provisional start one slot after the
  /// latest match of the round before it.
  ///
  /// Group matches are scheduled ahead of knockout matches regardless of round
  /// number, because a groups+knockout draw numbers both from 1 and the
  /// knockout phase cannot begin until every group has finished.
  ({Map<int, DateTime> startAt, Map<int, String> courtId, List<String> problems})
      _planSchedule(
    List<PlannedFixture> kept,
    Competition competition,
    List<String> venueCourts,
  ) {
    final cfg = competition.scheduleConfig;
    final start = competition.startDate;

    // Without courts or a start date there is nothing to lay out against, so
    // every fixture keeps the competition's own start time.
    //
    // Falling back is right; falling back SILENTLY was not. `problems` was
    // returned empty here, so the draw sheet reported a schedule generated
    // without complaint and the organizer got a draw where every match began
    // at the same minute on no court — indistinguishable, on screen, from one
    // the solver had thought about. The two reasons are separated because the
    // fix differs: one is a venue, the other is a date.
    if (start == null) {
      return (
        startAt: {},
        courtId: {},
        problems: const [
          'No start date, so no match could be given a time. Set the '
              'competition dates and generate the draw again.',
        ],
      );
    }
    if (!cfg.hasCourts) {
      return (
        startAt: {},
        courtId: {},
        problems: const [
          'No courts, so every match is listed at the competition start time '
              'and none has a court. Add a venue with courts — or type court '
              'names in the draw setup — and generate again.',
        ],
      );
    }

    // Court names come from real venue documents when the organizer picked
    // venues, and from typed text when they did not. Only the names differ
    // here — a single draw does not care that two events share a hall,
    // because it is the only draw there is. Cross-event contention is
    // `TournamentRepository.generateSchedule`'s problem, and it is why a
    // venue has to be an entity rather than a string.
    final courtNames = cfg.usesVenues
        ? [
            for (final v in venueCourts) v,
          ]
        : cfg.courts;
    // Venues were named but none of them yielded a usable court — every one
    // archived, or every court marked unavailable. Distinct from "no courts
    // configured" above and worth saying so: the organizer did the setup, and
    // what they need to hear is that the setup no longer resolves to anything.
    if (courtNames.isEmpty) {
      return (
        startAt: {},
        courtId: {},
        problems: const [
          'The selected venues have no usable courts, so no match could be '
              'given a court or a time. Mark a court available, or pick a '
              'different venue.',
        ],
      );
    }

    final venues = [
      for (final name in courtNames) Venue(id: name, name: name, capacity: 1),
    ];

    // Enough slots that the draw fits even if every match needs its own,
    // spilling onto later days at the configured day boundaries. Capped so a
    // misconfiguration (one court, thousand-entrant field) cannot spin here.
    final perDay =
        ((cfg.dayEndHour - cfg.dayStartHour) * 60) ~/ cfg.slotMinutes;
    final slots = <TimeSlot>[];
    if (perDay > 0) {
      final daysNeeded =
          ((kept.length / (venues.length * perDay)).ceil()).clamp(1, 30);
      for (var day = 0; day < daysNeeded; day++) {
        var cursor = DateTime(
          start.year,
          start.month,
          start.day + day,
          cfg.dayStartHour,
        );
        for (var i = 0; i < perDay; i++) {
          final end = cursor.add(Duration(minutes: cfg.matchMinutes));
          slots.add(TimeSlot(start: cursor, end: end));
          cursor = cursor.add(Duration(minutes: cfg.slotMinutes));
        }
      }
    }

    // Group matches first, then by round, then by draw position — the order
    // the scheduler fills slots in, and therefore the order matches are
    // played. A later round must never take an earlier court than the round
    // that feeds it.
    final ordered = [...kept]..sort((a, b) {
        final phase = (a.bracket == Bracket.group ? 0 : 1)
            .compareTo(b.bracket == Bracket.group ? 0 : 1);
        if (phase != 0) return phase;
        final round = a.round.compareTo(b.round);
        if (round != 0) return round;
        return a.matchIndex.compareTo(b.matchIndex);
      });

    final result = const MatchScheduler().schedule(
      fixtures: ordered,
      venues: venues,
      slots: slots,
      minRestBetweenMatches: Duration(minutes: cfg.restGapMinutes),
    );

    final startAt = <int, DateTime>{};
    final courtId = <int, String>{};
    for (final s in result.scheduled) {
      startAt[s.fixture.matchIndex] = s.slot.start;
      courtId[s.fixture.matchIndex] = s.venue.id;
    }

    // "Not before" times for everything still unplaced. Walk the rounds in
    // playing order; each round with no real placement starts one slot after
    // the latest time anything before it is due to finish.
    var watermark = startAt.values.isEmpty
        ? DateTime(start.year, start.month, start.day, cfg.dayStartHour)
        : startAt.values.reduce((a, b) => a.isAfter(b) ? a : b);

    for (final p in ordered) {
      if (startAt.containsKey(p.matchIndex)) {
        final placed = startAt[p.matchIndex]!;
        if (placed.isAfter(watermark)) watermark = placed;
        continue;
      }
      watermark = watermark.add(Duration(minutes: cfg.slotMinutes));
      startAt[p.matchIndex] = watermark;
      // No court: a provisional match has not been given one, and inventing
      // one would have an organizer holding a court empty for a match that
      // might be an hour late.
    }

    return (
      startAt: startAt,
      courtId: courtId,
      problems: [
        for (final u in result.unscheduled) '${u.fixture.roundLabel}: ${u.reason}',
      ],
    );
  }

  /// The context a freshly-planned fixture's opening state is built from.
  ///
  /// [config] is the competition's EFFECTIVE rules, not the sport's raw
  /// preset. The two used to be the same thing, and the opening state was
  /// therefore built from a 20-over default even for an event the organizer
  /// had set to 8 — the fixture's stored `scoringConfig` said 8 and the state
  /// beside it had already been shaped for 20.
  ScoringContext _contextFor(
    PlannedFixture p,
    Map<String, dynamic> config,
  ) =>
      ScoringContext(
        entrantAName: p.entrantA?.displayName ?? 'A',
        entrantBName: p.entrantB?.displayName ?? 'B',
        config: config,
      );

  Future<void> assignScorers({
    required String orgId,
    required String compId,
    required String fixtureId,
    required List<String> scorerUids,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            'scorerUids': scorerUids,
          }));

  // --- Asking to score --------------------------------------------------

  /// Raises a hand to score [fixture].
  ///
  /// Awaited, unlike the scoring writes in this file: this one is not part of
  /// a match in progress, the person is standing still looking at a button,
  /// and "your request has been sent" is a claim we should only make once the
  /// server has it. Re-requesting overwrites the caller's own document —
  /// `scoringRequests/{uid}` — so a double tap cannot produce two rows in
  /// somebody's approval queue.
  Future<void> requestToScore({
    required Fixture fixture,
    required String uid,
    required String displayName,
    String? note,
  }) =>
      guard(() => Refs.scoringRequest(
            fixture.orgId,
            fixture.compId,
            fixture.id,
            uid,
          ).set(
            ScoringRequest(
              uid: uid,
              orgId: fixture.orgId,
              compId: fixture.compId,
              fixtureId: fixture.id,
              displayName: displayName,
              matchLabel: '${fixture.entrantAName} v ${fixture.entrantBName}',
              status: ScoringRequestStatus.pending,
              note: note,
            ).toCreate(),
          ));

  /// Grants the request and adds the person to the match's scorers, in one
  /// batch.
  ///
  /// Atomic on purpose. Split into two writes, a failure between them leaves
  /// either an approved request by someone the fixture will still reject, or
  /// a scorer with no record of who let them in — and the second is the one
  /// that matters when a result is disputed months later.
  Future<void> approveScoringRequest({
    required ScoringRequest request,
    required String decidedByUid,
  }) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.update(
          Refs.fixture(request.orgId, request.compId, request.fixtureId),
          {
            'scorerUids': FieldValue.arrayUnion([request.uid]),
            // Approving "let me score this" hands over control, not just
            // eligibility. Granting the second without the first was the old
            // behaviour and it read as a yes that did nothing: the person was
            // added to a list, the pad still belonged to whoever had it, and
            // the only visible result of the approval was that nothing
            // changed. See `Fixture.activeScorerUid`.
            'activeScorerUid': request.uid,
            // The new holder claims their own device when they open the pad.
            'activeScorerDeviceId': null,
            'penGrantedByUid': decidedByUid,
            'penGrantedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.update(
          Refs.scoringRequest(
            request.orgId,
            request.compId,
            request.fixtureId,
            request.uid,
          ),
          {
            'status': ScoringRequestStatus.approved.wire,
            'decidedBy': decidedByUid,
            'decidedAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
      });

  Future<void> declineScoringRequest({
    required ScoringRequest request,
    required String decidedByUid,
  }) =>
      guard(() => Refs.scoringRequest(
            request.orgId,
            request.compId,
            request.fixtureId,
            request.uid,
          ).update({
            'status': ScoringRequestStatus.declined.wire,
            'decidedBy': decidedByUid,
            'decidedAt': FieldValue.serverTimestamp(),
          }));

  /// This person's own request for one match, so the button can say "asked"
  /// rather than offering to ask again.
  Stream<ScoringRequest?> watchMyScoringRequest({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String uid,
  }) =>
      guardStream(
        () => Refs.scoringRequest(orgId, compId, fixtureId, uid)
            .snapshots()
            .map((d) => d.exists ? ScoringRequest.fromDoc(d) : null),
      );

  /// Everyone waiting on an answer from [orgId].
  Stream<List<ScoringRequest>> watchPendingScoringRequests(String orgId) =>
      guardStream(
        () => Refs.allScoringRequestsQuery
            .where('orgId', isEqualTo: orgId)
            .where('status', isEqualTo: ScoringRequestStatus.pending.wire)
            .snapshots()
            .map((s) => s.docs.map(ScoringRequest.fromDoc).toList()),
      );

  /// Records who is playing, per side.
  ///
  /// Set before the first ball. The scoring engines refuse a delivery that
  /// names nobody, so this is what makes a match scorable at all for any sport
  /// that tracks players — including the very first match of a competition,
  /// created and started without ever having had signal.
  ///
  /// Genuinely fully possible offline: unlike the two methods above, this
  /// needs no prior read and no server-derived value — the line-up is
  /// exactly what the scorer just entered. Deliberately NOT awaited, for the
  /// same reason as everywhere else in this file: an awaited Firestore write
  /// does not complete until the server acknowledges it, and awaiting this
  /// one is what used to hang "Saving..." on a ground with no signal and
  /// make it impossible to ever record who's playing, which in turn made it
  /// impossible to score anything at all offline. The local cache write
  /// lands immediately, so this device's own fixture listener shows the
  /// line-up at once; a failure is reported on [writeFailures].
  // --- Squad calls: a club opening its own side to its own members -------

  /// Everyone who has put their hand up for a side.
  Stream<List<SquadEntry>> watchSquadEntries(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      guardStream(
        () => Refs.squadEntries(orgId, compId, fixtureId)
            .orderBy('createdAt')
            .snapshots()
            .map((s) => s.docs.map(SquadEntry.fromDoc).toList()),
      );

  /// A club opening (or closing) its own side to its own members.
  ///
  /// This is the half of the flow's step 6 that was missing: "XYZ Club selects
  /// players **or opens registration**". Until now the challenged club's admin
  /// had to name every player by hand, which is the same chasing-people-over-
  /// WhatsApp problem that participation models solved at the event level —
  /// just one level down, where a challenge actually lives.
  Future<void> setSquadCall({
    required Fixture fixture,
    required String forOrgId,
    required bool open,
    int? capacity,
    bool waitlistEnabled = true,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }
        if (fixture.squadLockedFor(
          side == 'a' ? fixture.entrantAId : fixture.entrantBId,
        )) {
          throw const ValidationException(
            'That squad is locked. Reopen it before changing the call.',
          );
        }

        final existing = fixture.squadCallFor(side);
        final call = SquadCall(
          open: open,
          capacity: capacity,
          // Counters are carried across rather than reset: closing and
          // reopening a call must not forget who already has a place.
          confirmed: existing.confirmed,
          waitlisted: existing.waitlisted,
          waitlistEnabled: waitlistEnabled,
        );

        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
            side == 'a' ? 'squadCallA' : 'squadCallB': call.toMap(),
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// A member registering for their own club's side.
  ///
  /// Transactional for the same reason competition registration is: "the first
  /// eleven of our members who register are playing" is a promise about a
  /// count, and two people tapping at once on the last place both read ten.
  /// `firestore.rules` enforces the same arithmetic independently.
  ///
  /// Which side the member joins is derived from the club they belong to, not
  /// passed in — a member of ABC cannot register for XYZ's eleven.
  Future<RegistrationStatus> joinSquad({
    required Fixture fixture,
    required String forOrgId,
    required AppUser user,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'You are not in either club playing this match.',
          );
        }

        final fixRef =
            Refs.fixture(fixture.orgId, fixture.compId, fixture.id);
        final entryRef = Refs.squadEntry(
          fixture.orgId,
          fixture.compId,
          fixture.id,
          user.uid,
        );

        return Refs.db.runTransaction<RegistrationStatus>((tx) async {
          final fixSnap = await tx.get(fixRef);
          if (!fixSnap.exists) {
            throw const ValidationException('That match no longer exists.');
          }
          final fresh = Fixture.fromDoc(fixSnap);
          final call = fresh.squadCallFor(side);

          if (fresh.squadLockedFor(
            side == 'a' ? fresh.entrantAId : fresh.entrantBId,
          )) {
            throw const ValidationException(
              'That squad has been locked in already.',
            );
          }
          if (!call.acceptsEntries) {
            throw const ValidationException(
              'Registration is not open for this side.',
            );
          }

          final existing = await tx.get(entryRef);
          if (existing.exists &&
              SquadEntry.fromDoc(existing).status.occupiesSlot) {
            throw const ValidationException(
              'You have already put your name down.',
            );
          }

          final outcome = call.outcomeOfJoiningNow;
          if (outcome == RegistrationStatus.waitlisted &&
              !call.waitlistEnabled) {
            throw const ValidationException('This side is full.');
          }

          tx.set(
            entryRef,
            SquadEntry(
              uid: user.uid,
              displayName: user.displayName,
              photoUrl: user.photoUrl,
              side: side,
              orgId: forOrgId,
              status: outcome,
              waitlistPosition: outcome == RegistrationStatus.waitlisted
                  ? call.waitlisted + 1
                  : null,
            ).toCreate(),
          );

          final field = side == 'a' ? 'squadCallA' : 'squadCallB';
          tx.update(fixRef, {
            if (outcome == RegistrationStatus.confirmed)
              '$field.confirmed': FieldValue.increment(1)
            else
              '$field.waitlisted': FieldValue.increment(1),
          });

          return outcome;
        });
      });

  /// A member pulling out of a squad they had registered for.
  ///
  /// Frees the place, then promotes the first reserve in a second
  /// transaction — for exactly the reason competition withdrawal does: the
  /// rules evaluate a write against pre-transaction state, so the slot is only
  /// provably free once the withdrawal has committed.
  Future<void> leaveSquad({
    required Fixture fixture,
    required String uid,
  }) =>
      guard(() async {
        final fixRef =
            Refs.fixture(fixture.orgId, fixture.compId, fixture.id);
        final entryRef = Refs.squadEntry(
          fixture.orgId,
          fixture.compId,
          fixture.id,
          uid,
        );

        final freedAPlace = await Refs.db.runTransaction<String?>((tx) async {
          final snap = await tx.get(entryRef);
          if (!snap.exists) return null;
          final entry = SquadEntry.fromDoc(snap);
          if (entry.status == RegistrationStatus.withdrawn) return null;

          final field = entry.side == 'a' ? 'squadCallA' : 'squadCallB';

          tx.update(entryRef, {
            'status': RegistrationStatus.withdrawn.wire,
            'waitlistPosition': null,
          });
          tx.update(fixRef, {
            if (entry.status == RegistrationStatus.confirmed)
              '$field.confirmed': FieldValue.increment(-1)
            else if (entry.status == RegistrationStatus.waitlisted)
              '$field.waitlisted': FieldValue.increment(-1),
          });

          return entry.status == RegistrationStatus.confirmed
              ? entry.side
              : null;
        });

        if (freedAPlace != null) {
          await _promoteFirstReserveIntoSquad(
            fixture: fixture,
            side: freedAPlace,
            justLeft: uid,
          );
        }
      });

  /// Pulls the first reserve into a squad place that has just been freed.
  ///
  /// Forgiving by design: a promotion that cannot happen is not a failure of
  /// the withdrawal that triggered it. The member who pulled out has pulled
  /// out either way.
  Future<void> _promoteFirstReserveIntoSquad({
    required Fixture fixture,
    required String side,
    required String justLeft,
  }) async {
    try {
      final snap = await Refs.squadEntries(
        fixture.orgId,
        fixture.compId,
        fixture.id,
      )
          .where('side', isEqualTo: side)
          .where('status', isEqualTo: RegistrationStatus.waitlisted.wire)
          .orderBy('waitlistPosition')
          .limit(2)
          .get();

      SquadEntry? next;
      for (final doc in snap.docs) {
        if (doc.id == justLeft) continue;
        next = SquadEntry.fromDoc(doc);
        break;
      }
      if (next == null) return;

      final fixRef = Refs.fixture(fixture.orgId, fixture.compId, fixture.id);
      final nextRef = Refs.squadEntry(
        fixture.orgId,
        fixture.compId,
        fixture.id,
        next.uid,
      );

      await Refs.db.runTransaction((tx) async {
        final nextSnap = await tx.get(nextRef);
        final fixSnap = await tx.get(fixRef);
        if (!nextSnap.exists || !fixSnap.exists) return;
        if (SquadEntry.fromDoc(nextSnap).status !=
            RegistrationStatus.waitlisted) {
          return;
        }

        final call = Fixture.fromDoc(fixSnap).squadCallFor(side);
        if (call.isFull) return;

        final field = side == 'a' ? 'squadCallA' : 'squadCallB';
        tx.update(nextRef, {
          'status': RegistrationStatus.confirmed.wire,
          'waitlistPosition': null,
          'promotedFromWaitlistAt': FieldValue.serverTimestamp(),
        });
        tx.update(fixRef, {
          '$field.confirmed': FieldValue.increment(1),
          '$field.waitlisted': FieldValue.increment(-1),
        });
      });
    } catch (error) {
      _writeFailures.add(_translateWriteFailure(error));
    }
  }

  /// Turns the members who registered into the actual team sheet, and locks it.
  ///
  /// The moment a squad call becomes a squad. Everyone confirmed becomes a
  /// [MatchPlayer] on that side, in the order they registered, which is the
  /// order they were promised places in.
  Future<void> lockSquadFromEntries({
    required Fixture fixture,
    required String forOrgId,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }

        final snap = await Refs.squadEntries(
          fixture.orgId,
          fixture.compId,
          fixture.id,
        )
            .where('side', isEqualTo: side)
            .where('status', isEqualTo: RegistrationStatus.confirmed.wire)
            .get();

        final entries = snap.docs.map(SquadEntry.fromDoc).toList()
          ..sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null || bt == null) return 0;
            return at.compareTo(bt);
          });

        if (entries.isEmpty) {
          throw const ValidationException(
            'Nobody has registered for this side yet.',
          );
        }

        await setSideLineup(
          fixture: fixture,
          forOrgId: forOrgId,
          lineup: [
            for (final e in entries)
              MatchPlayer(id: e.uid, name: e.displayName, uid: e.uid),
          ],
          lock: true,
        );
      });

  /// One club naming its own players in an inter-club match.
  ///
  /// ## Why this exists next to [setLineups]
  ///
  /// [setLineups] writes both squads at once, which is right for an internal
  /// competition where one club's organizers run everything. It is wrong for
  /// a challenge match, where two clubs that do not answer to each other each
  /// pick their own side — and until now the visiting club could not name a
  /// single player, because the fixture lives under the *hosting* club and
  /// every write path required authority there. "ABC challenges XYZ, XYZ
  /// picks its team" simply did not work.
  ///
  /// A challenge fixture stores the two clubs' own ids as its entrant ids
  /// (see `CommunityRepository.acceptChallenge`), so which side a club may
  /// touch is answerable from the fixture alone — here, and independently in
  /// `firestore.rules`, which is what stops one club from picking the other's
  /// team.
  ///
  /// [lock] is the flow's "lock its final squad": the club declaring it has
  /// finished picking. A locked side can only be reopened by the club that
  /// locked it.
  ///
  /// Not awaited, for the same reason as [setLineups] — an admin naming a
  /// squad at the ground gets an instant list, and a failure arrives on
  /// [writeFailures].
  Future<void> setSideLineup({
    required Fixture fixture,
    required String forOrgId,
    required List<MatchPlayer> lineup,
    bool? lock,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }

        final isA = side == 'a';
        if (fixture.squadLockedFor(isA ? fixture.entrantAId : fixture.entrantBId) &&
            lock != false) {
          throw const ValidationException(
            'That squad is locked. Reopen it before making changes.',
          );
        }

        // `playerUids` summarises BOTH sides and is what the rules consult
        // when a scorer settles ratings onto a player's profile, so it has to
        // be recomputed from this side's new list plus the other side's
        // existing one — writing only this side's uids would strip the
        // opponent's players out of the match they played in.
        final other = isA ? fixture.lineupB : fixture.lineupA;
        final playerUids = <String>{
          for (final p in [...lineup, ...other])
            if (p.uid != null) p.uid!,
          // Individual entrants are named on the entrant document, never in a
          // line-up. Recomputing from the two sheets alone would erase them
          // from a fixture that has both shapes — a club team against a lone
          // qualifier — the moment the club edited its own squad.
          ...fixture.entrantUids,
        }.toList();

        final update = <String, Object?>{
          isA ? 'lineupA' : 'lineupB': MatchPlayer.listTo(lineup),
          'playerUids': playerUids,
        };
        if (lock != null) {
          update[isA ? 'squadLockedA' : 'squadLockedB'] = lock;
        }

        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id)
              .update(update)
              .catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// One club naming which of its TEAMS is playing this match.
  ///
  /// ## Why naming a team is not the same as naming a line-up
  ///
  /// [setSideLineup] writes a list of people. That is all a challenge match
  /// could ever hold, and it is why the side of an inter-club fixture was the
  /// one place in the product where a squad was anonymous: the eleven names
  /// went onto the fixture and nowhere else, so the match never appeared on
  /// any team's record and the team a club had just assembled off an
  /// availability call could not be used at all.
  ///
  /// This writes the POINTER as well as the people — `teamAId`/`teamBId`
  /// alongside the line-up it implies. The line-up is still written, because
  /// the scoring engine names players and knows nothing about teams; the
  /// pointer is what makes the match belong to the team afterwards.
  ///
  /// ## Why it can be called again
  ///
  /// Because sides change. A club may swap the whole team for a different one
  /// (the B team travelling instead of the A team is an ordinary Saturday),
  /// or re-sync the line-up after adding a player to the team's roster.
  /// Naming a team does not lock anything — [setSideLineup] with `lock: true`
  /// is still how a club says it has finished picking, and a locked side is
  /// refused here for exactly the same reason it is refused there.
  ///
  /// Passing a null [team] clears the pointer and leaves the line-up alone:
  /// a club going back to picking individuals, having named a team by
  /// mistake, should not silently lose the names it already had.
  Future<void> setSideTeam({
    required Fixture fixture,
    required String forOrgId,
    required Team? team,
    List<MatchPlayer> lineup = const [],
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }
        final isA = side == 'a';

        if (fixture.squadLockedFor(isA ? fixture.entrantAId : fixture.entrantBId)) {
          throw const ValidationException(
            'That squad is locked. Reopen it before changing the team.',
          );
        }
        if (fixture.status == FixtureStatus.completed) {
          throw const ValidationException(
            'This match is over. Its team sheet is part of the result.',
          );
        }
        // A team belongs to one sport, and a side made of hockey players
        // cannot contest a cricket match. Checked here rather than only in
        // the picker so no other caller can route around it.
        // Only when the fixture actually states a sport. `Fixture.sportId` is
        // null on documents written before it existed, and refusing every
        // team on a fixture that never said what it was would block the flow
        // on old data rather than protect anything.
        if (team != null &&
            fixture.sportId != null &&
            team.sportId != fixture.sportId) {
          throw ValidationException(
            '${team.name} is a ${team.sportId} team, and this match is '
            '${fixture.sportId}.',
          );
        }

        final update = <String, Object?>{
          isA ? 'teamAId' : 'teamBId': team?.id,
          isA ? 'teamAName' : 'teamBName': team?.name,
        };

        // Same reasoning as `setSideLineup`: `playerUids` summarises BOTH
        // sides and the rules read it when a scorer settles ratings, so it
        // has to be rebuilt from this side's new list plus the other side's
        // existing one rather than overwritten with this side alone.
        if (lineup.isNotEmpty) {
          final other = isA ? fixture.lineupB : fixture.lineupA;
          update[isA ? 'lineupA' : 'lineupB'] = MatchPlayer.listTo(lineup);
          update['playerUids'] = <String>{
            for (final p in [...lineup, ...other])
              if (p.uid != null) p.uid!,
            ...fixture.entrantUids,
          }.toList();
        }

        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id)
              .update(update)
              .catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// Names both team sheets at once, for the host-managed case.
  ///
  /// Takes the whole [fixture] rather than its three ids because
  /// `playerUids` cannot be rebuilt from the line-ups alone — see the note on
  /// [Fixture.entrantAUid]. Passing the ids separately is what made it
  /// possible to write a summary that quietly dropped an individual entrant.
  Future<void> setLineups({
    required Fixture fixture,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
  }) =>
      guard(() async {
        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
            'lineupA': MatchPlayer.listTo(lineupA),
            'lineupB': MatchPlayer.listTo(lineupB),
            // Written in the same update as the line-ups it summarises.
            // `firestore.rules` reads it to decide whether a scorer settling
            // a match may write ratings and career stats onto a given
            // player's profile — see the ratings/career_stats rules — and it
            // cannot reach inside the lineup maps to work that out itself.
            'playerUids': <String>{
              for (final p in [...lineupA, ...lineupB])
                if (p.uid != null) p.uid!,
              ...fixture.entrantUids,
            }.toList(),
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// Records the toss, and who chose what.
  ///
  /// Cricket needs it to know which side bats first; every other sport uses it
  /// to decide who starts. It is written onto the fixture and into the frozen
  /// scoring config, because "who batted first" is part of how the match reads
  /// forever after and must not be recomputed later from anything mutable.
  ///
  /// Genuinely fully possible offline, for the same reason as [setLineups]:
  /// no prior read, nothing server-derived. Not awaited, for the same
  /// reason — see that method's comment.
  /// Records the toss and what the winner took.
  ///
  /// [startingSide] is who plays first, worked out from the choice rather
  /// than assumed — see `TossDialog._startingSide`. It is written for every
  /// sport, because "who served first" and "who raided first" are as much a
  /// part of a scorecard as "who batted first".
  ///
  /// [decidesBatting] gates the one key that is cricket's alone. The dialog
  /// used to write `battingFirst` for all thirteen sports, so a badminton
  /// fixture carried a frozen ruleset asserting which side batted.
  ///
  /// ## Why the opening state is rebuilt here
  ///
  /// Writing `battingFirst` into the config is not enough on its own, and for a
  /// long time that is all this did. An engine reads its rules at
  /// `initialState`, which runs ONCE — when the draw is generated, or when a
  /// quick match is created — long before anybody tosses a coin. Cricket's
  /// opening innings was therefore built from a config with no `battingFirst`
  /// in it, defaulted to side A, and stayed there: side B could win the toss
  /// and elect to bat and the scorecard would still open with side A batting,
  /// carrying that error through the innings break, the target, the result and
  /// every net run rate the match fed.
  ///
  /// So the config and the state it determines are written together. Safe
  /// because this is only ever reachable before the first ball — the fixture
  /// still has `lastSeq == 0`, which is also the exact condition
  /// `firestore.rules` allows a scorer to write a line-up or a toss under. Once
  /// a delivery exists there is a log to honour and the opening state is no
  /// longer ours to rewrite.
  Future<void> recordToss({
    required Fixture fixture,
    required String wonByEntrantId,
    required String decision,
    required String startingSide,
    required bool decidesBatting,
    required Map<String, dynamic> scoringConfig,
  }) =>
      guard(() async {
        if (fixture.lastSeq > 0) {
          throw const ValidationException(
            'This match has already started. The toss cannot be changed once '
            'a ball has been scored.',
          );
        }

        final config = <String, dynamic>{
          ...scoringConfig,
          'startingSide': startingSide,
          if (decidesBatting) 'battingFirst': startingSide,
        };

        final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
        final rebuiltState = plugin.initialState(
          ScoringContext(
            entrantAName: fixture.entrantAName,
            entrantBName: fixture.entrantBName,
            config: config,
            lineupA: fixture.lineupA,
            lineupB: fixture.lineupB,
          ),
        );

        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
            'tossWonByEntrantId': wonByEntrantId,
            'tossDecision': decision,
            'scoringConfig': config,
            'scoreState': rebuiltState,
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  // --- Disputes ---------------------------------------------------------

  Stream<List<Dispute>> watchDisputes({
    required String orgId,
    required String compId,
    required String fixtureId,
  }) =>
      guardStream(
        () => Refs.disputes(orgId, compId, fixtureId).snapshots().map(
              (snap) => snap.docs.map(Dispute.fromDoc).toList()
                ..sort((a, b) => (b.raisedAt ?? DateTime(0))
                    .compareTo(a.raisedAt ?? DateTime(0))),
            ),
      );

  /// Raises a protest against a result.
  ///
  /// The event log is append-only and the scorer is locked, which makes the
  /// record tamper-proof but not right: a scorer can press the wrong button
  /// and a player can be a year too old for the category. Without a path to
  /// say so, that argument happens on WhatsApp and the app becomes the thing
  /// people argue about rather than the thing that settles it.
  ///
  /// Refused outside the protest window. A bracket cannot advance while an
  /// earlier match might still be overturned, and a tournament where last
  /// week's quarter-final can be reopened has no results at all.
  Future<String> raiseDispute({
    required Fixture fixture,
    required String raisedByUid,
    required String raisedByName,
    required DisputeReason reason,
    String? detail,
    String? entrantId,
  }) =>
      guard(() async {
        if (!fixture.hasResult) {
          throw const ValidationException(
            'There is no result to dispute yet.',
          );
        }
        if (!withinProtestWindow(fixture.completedAt)) {
          throw const ValidationException(
            'The protest window for this match has closed.',
          );
        }

        final ref = Refs.disputes(
          fixture.orgId,
          fixture.compId,
          fixture.id,
        ).doc();

        final dispute = Dispute(
          id: ref.id,
          orgId: fixture.orgId,
          compId: fixture.compId,
          fixtureId: fixture.id,
          raisedByUid: raisedByUid,
          raisedByName: raisedByName,
          entrantId: entrantId,
          reason: reason,
          status: DisputeStatus.open,
          detail: detail,
        );

        final batch = Refs.db.batch();
        batch.set(ref, dispute.toCreate());
        // The fixture carries the flag so a bracket, a standings table and a
        // spectator card can all see a result is under protest from the one
        // document they already read.
        //
        // `openDisputeId` is not decoration. `firestore.rules` cannot run a
        // query, so a member flagging a finished match has to NAME the protest
        // that justifies it — the rule then reads that document (via
        // `getAfter`, since it is created in this same batch) and checks the
        // caller really did raise it. Without it the only branches that admit
        // this write require organizer authority, which meant the protest flow
        // was denied to every competitor it was built for.
        batch.update(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id),
          {
            'status': FixtureStatus.disputed.wire,
            'openDisputeId': ref.id,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
        return ref.id;
      });

  /// A referee's decision on a protest.
  ///
  /// [upheld] false leaves the result exactly as it was and returns the
  /// fixture to completed. True marks it for correction — the actual
  /// correction is a reversal event through the scoring pad, because the log
  /// is append-only and a referee overwriting a score directly would be the
  /// one write in the product that cannot be audited.
  Future<void> resolveDispute({
    required Dispute dispute,
    required String refereeUid,
    required bool upheld,
    required String note,
  }) =>
      guard(() async {
        if (refereeUid == dispute.raisedByUid) {
          throw const ValidationException(
            'A protest cannot be decided by the person who raised it.',
          );
        }
        if (note.trim().isEmpty) {
          throw const ValidationException(
            'Say why. A decision without a reason is not a decision anybody '
            'can accept.',
          );
        }

        final batch = Refs.db.batch();
        batch.update(
          Refs.disputes(dispute.orgId, dispute.compId, dispute.fixtureId)
              .doc(dispute.id),
          {
            'status': (upheld ? DisputeStatus.upheld : DisputeStatus.rejected)
                .wire,
            'resolvedByUid': refereeUid,
            'resolutionNote': note.trim(),
            'resolvedAt': FieldValue.serverTimestamp(),
          },
        );
        batch.update(
          Refs.fixture(dispute.orgId, dispute.compId, dispute.fixtureId),
          {
            // Upheld returns the match to the pad so the correction can be
            // appended as a reversal; rejected simply restores the result.
            'status': (upheld ? FixtureStatus.live : FixtureStatus.completed)
                .wire,
            // Cleared with the decision it belonged to. Left behind, it would
            // keep pointing at a settled protest — and every later read of the
            // fixture would say a decided match was still under one.
            'openDisputeId': null,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
      });

  /// Swaps who is playing one match — the organizer's override on the DRAW,
  /// as [rescheduleFixture] is their override on the timetable.
  ///
  /// ## Why this has to exist
  ///
  /// A draw is made days before it is played, and the ground decides
  /// otherwise: a side arrives four players short, a college bus does not
  /// turn up, two teams agree to swap so one can travel home, a walkover
  /// leaves an opponent with nobody. Until this existed the only ways out
  /// were to regenerate the entire draw — which is refused once anything has
  /// been scored, and throws away every court, time and official already
  /// assigned — or to play the match under the wrong two names and let the
  /// standings inherit the lie.
  ///
  /// ## What it refuses, and why those are not arbitrary
  ///
  ///  - **A match that has started or been played.** At `lastSeq > 0` the
  ///    entrant names are no longer a plan, they are the record of who was
  ///    on the field for every event in the log, and the ratings and career
  ///    stats settled from it hang off exactly these two ids. Changing them
  ///    afterwards does not fix a mistake, it reassigns a performance to
  ///    somebody who was not there. That case is a dispute
  ///    ([raiseDispute]), which is reviewed, not a silent edit.
  ///  - **A challenge between two clubs.** Its entrant ids ARE the two club
  ///    ids and `participantOrgIds` mirrors them; `firestore.rules` freezes
  ///    that mirror on every update, so a swap here would be denied by the
  ///    server anyway. A different opponent is a different challenge.
  ///
  /// Everything belonging to the side that left goes with it: its team sheet,
  /// its squad call and its lock. Keeping them would hand the incoming side a
  /// line-up of players who are not theirs — and `playerUids` is what the
  /// rules consult before letting a scorer settle ratings onto a profile, so
  /// a stale name there is not cosmetic.
  ///
  /// The swap is recorded on the fixture rather than applied invisibly. An
  /// organizer who changes a quarter-final's opponent will be asked why, and
  /// "the record says so" is the only answer that ends the conversation.
  Future<void> changeOpponent({
    required Fixture fixture,
    required String side,
    required Entrant entrant,
    required String byUid,
    String? reason,
  }) =>
      guard(() async {
        if (side != 'a' && side != 'b') {
          throw const ValidationException('A match has two sides, a and b.');
        }
        if (fixture.lastSeq > 0 || fixture.hasResult) {
          throw const ValidationException(
            'This match has already been played. Raise a dispute to have the '
            'result reviewed — the two sides on a played match are part of '
            'its record.',
          );
        }
        if (fixture.participantOrgIds != null) {
          throw const ValidationException(
            'This is a challenge between two clubs, so the two clubs are the '
            'match. Cancel it and challenge the other club instead.',
          );
        }
        if (entrant.withdrawn) {
          throw const ValidationException(
            'That entrant has withdrawn from this event.',
          );
        }

        final isA = side == 'a';

        // `firestore.rules` (`lockedSquadsRespected`) freezes a locked side's
        // line-up AND its lock together, and only the club that locked it may
        // reopen it. So this is not a client-side nicety standing in for a
        // server check — the write would be refused, and a sentence here is
        // better than a permission error at the ground.
        if (isA ? fixture.squadLockedA : fixture.squadLockedB) {
          throw const ValidationException(
            'That side has locked its squad. Reopen it before changing who is '
            'playing.',
          );
        }

        final opposingId = isA ? fixture.entrantBId : fixture.entrantAId;
        if (entrant.id == opposingId) {
          throw const ValidationException(
            'A side cannot play itself.',
          );
        }

        final outgoingId = isA ? fixture.entrantAId : fixture.entrantBId;
        final outgoingName = isA ? fixture.entrantAName : fixture.entrantBName;

        // Recomputed from the side that STAYS plus whoever the incoming
        // entrant is. Same reasoning as `setSideLineup`: this list is the
        // settlement gate, and rebuilding it from one side alone would strip
        // the opponent out of their own match.
        final keptLineup = isA ? fixture.lineupB : fixture.lineupA;
        final keptSoloUid = isA ? fixture.entrantBUid : fixture.entrantAUid;
        final playerUids = <String>{
          for (final p in keptLineup) ...[if (p.uid != null) p.uid!],
          if (keptSoloUid != null && keptSoloUid.isNotEmpty) keptSoloUid,
          if (entrant.soloUid case final uid?) uid,
        }.toList();

        final update = <String, Object?>{
          isA ? 'entrantAId' : 'entrantBId': entrant.id,
          isA ? 'entrantAName' : 'entrantBName': entrant.displayName,
          isA ? 'entrantAUid' : 'entrantBUid': entrant.soloUid,
          isA ? 'lineupA' : 'lineupB': const <Object?>[],
          isA ? 'squadCallA' : 'squadCallB': const SquadCall().toMap(),
          isA ? 'squadLockedA' : 'squadLockedB': false,
          'playerUids': playerUids,
          'opponentChanges': FieldValue.arrayUnion([
            {
              'side': side,
              'fromId': outgoingId,
              'fromName': outgoingName,
              'toId': entrant.id,
              'toName': entrant.displayName,
              'byUid': byUid,
              // Not `serverTimestamp()`: Firestore refuses a sentinel inside
              // an array element. The clock is the organizer's phone, which
              // is what every other match-day timestamp on this document is
              // written from anyway.
              'at': Timestamp.fromDate(DateTime.now()),
              if (reason != null && reason.trim().isNotEmpty)
                'reason': reason.trim(),
            },
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Not awaited — the same offline reasoning as every other match-day
        // write in this file. An organizer standing on a ground with no
        // signal gets the new name at once, and a failure surfaces on
        // [writeFailures].
        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id)
              .update(update)
              .catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// Moves one match. The organizer's override on everything the scheduler
  /// decided — a court that flooded, two players who asked to swap, a
  /// referee's call. [courtId] is here because a schedule that can move a
  /// match in time but not across the hall is only half an override.
  Future<void> rescheduleFixture({
    required String orgId,
    required String compId,
    required String fixtureId,
    DateTime? scheduledAt,
    String? venue,
    String? courtId,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            if (scheduledAt != null)
              'scheduledAt': Timestamp.fromDate(scheduledAt),
            if (venue != null) 'venue': venue,
            if (courtId != null) 'courtId': courtId,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  /// Pulls a scheduled match forward and plays it now.
  ///
  /// ## Why this is a write and not just a navigation
  ///
  /// A match set for next Tuesday that is actually played today is not a
  /// scheduled match that happened to start early — it is a match played on a
  /// different day, possibly with a different ball, possibly with a side that
  /// had to borrow a player. Sending the organizer straight to the scoring pad
  /// records none of that: the fixture keeps insisting it is due on Tuesday,
  /// every "running late" calculation reads it as three days overdue, and the
  /// agreement the two captains actually made exists nowhere.
  ///
  /// So this does three things in one write:
  ///
  ///  - moves `scheduledAt` to now, which is what makes the match honest to
  ///    every screen that sorts, groups or flags by it;
  ///  - stores [checks] — the sport's own pre-match questions and how they
  ///    were answered — under `startedEarly`, so "we agreed the same eleven"
  ///    is answerable three weeks later;
  ///  - records who agreed to it and when.
  ///
  /// Refused once a ball has been bowled. At that point the match is not being
  /// started, it is being rewritten, and the scheduled time it was played
  /// against is part of the record.
  Future<void> startMatchEarly({
    required Fixture fixture,
    required Map<String, bool> checks,
    required String byUid,
    String? note,
  }) =>
      guard(() async {
        if (fixture.lastSeq > 0) {
          throw const ValidationException(
            'This match has already started.',
          );
        }
        if (fixture.hasResult) {
          throw const ValidationException(
            'This match has already been played.',
          );
        }

        final now = DateTime.now();
        await Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
          'scheduledAt': Timestamp.fromDate(now),
          'startedEarly': {
            'originalScheduledAt': fixture.scheduledAt == null
                ? null
                : Timestamp.fromDate(fixture.scheduledAt!),
            'byUid': byUid,
            'at': Timestamp.fromDate(now),
            'checks': checks,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  /// Moves the remaining schedule of one standalone event.
  ///
  /// The tournament-level equivalent lives on `TournamentRepository`; this is
  /// for a club's own afternoon, which is the common case and has no
  /// tournament above it to shift from.
  Future<ShiftPlan> shiftSchedule({
    required String orgId,
    required String compId,
    Duration? by,
    DateTime? newStart,
    DateTime? from,
  }) =>
      guard(() async {
        if (by == null && newStart == null) {
          throw const ValidationException(
            'Say either a new start time or how long to move by.',
          );
        }

        final snap = await Refs.fixtures(orgId, compId).get();
        final fixtures = snap.docs.map(Fixture.fromDoc).toList();

        final plan = newStart != null
            ? ScheduleShift.planNewStart(
                fixtures: fixtures,
                newStart: newStart,
              )
            : ScheduleShift.plan(fixtures: fixtures, by: by!, from: from);

        if (plan.isEmpty) return plan;

        final batch = ChunkedBatch(Refs.db);
        for (final entry in plan.moves.entries) {
          batch.update(Refs.fixture(orgId, compId, entry.key), {
            'scheduledAt': Timestamp.fromDate(entry.value),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return plan;
      });
}

/// What a draw generation actually did.
///
/// Replaces a bare `int`, which could not distinguish "703 matches created"
/// from "703 matches planned, an unknown number written, and the batch may
/// have been rejected on the way". The organizer is shown a number that was
/// true at the moment it was produced; these fields are what make it true.
/// What one press of "pair the next Swiss round" produced.
///
/// Separate from [DrawOutcome] because the two answer different questions. A
/// draw reports on a whole bracket built at once — how much of it was
/// padding, what got seeded. A Swiss round reports on one round appended to
/// an event already underway, where the things an organizer needs to hear are
/// which round this is, how many are left, and who is sitting out.
class SwissRoundOutcome {
  const SwissRoundOutcome({
    required this.round,
    required this.totalRounds,
    required this.written,
    this.byeEntrantName,
    this.scheduleProblems = const [],
  });

  /// The round just created — 2 for the first press, and so on.
  final int round;

  /// How many rounds this event runs in total, so the organizer can be told
  /// "round 3 of 5" rather than left to guess when it ends.
  final int totalRounds;

  /// Matches written. Excludes the bye, which is not a match.
  final int written;

  /// Who sits this round out, on an odd field. Null when the field is even.
  ///
  /// Surfaced deliberately: the bye is the one thing about a Swiss round that
  /// is not visible on the fixture list, because it is the absence of a
  /// fixture. An organizer who is not told will be asked by the player.
  final String? byeEntrantName;

  /// Matches the scheduler could not place on a real court at a real time.
  final List<String> scheduleProblems;

  bool get hasScheduleProblems => scheduleProblems.isNotEmpty;

  /// Whether this was the last round the event will run.
  bool get isFinalRound => round >= totalRounds;
}

class DrawOutcome {
  const DrawOutcome({
    required this.planned,
    required this.written,
    required this.chunks,
    required this.drawId,
    this.seeding = const [],
    this.scheduleProblems = const [],
  });

  /// Matches the scheduler could not place on a real court at a real time, and
  /// why — "Semi-final 1: no court free before the day ends".
  ///
  /// These fixtures still exist and still carry a provisional "not before"
  /// time; what they do not have is a court. Reported rather than swallowed
  /// because the alternative is an organizer discovering it at the venue.
  final List<String> scheduleProblems;

  bool get hasScheduleProblems => scheduleProblems.isNotEmpty;

  /// Fixtures the generator produced, including byes and dead branches.
  final int planned;

  /// Fixtures handed to Firestore — the number of real matches.
  final int written;

  /// How many batches it took. More than one means the write is not atomic
  /// and `verifyDraw` is worth running.
  final int chunks;

  final String drawId;

  /// Who was seeded and why, when the draw seeded from ratings. Empty when the
  /// organizer set seeds by hand. Shown to the organizer so a player asking
  /// "why am I not seeded?" gets an answer rather than a shrug.
  final List<SeedVerdict> seeding;

  bool get isAtomic => chunks <= 1;

  /// How many planned fixtures were byes or dead branches. Worth surfacing:
  /// a large number on a non-knockout format usually means the field size is
  /// awkward rather than that anything went wrong.
  int get skipped => planned - written;
}

/// What pulling an entrant out of a live draw actually resolved.
class WithdrawalOutcome {
  const WithdrawalOutcome({
    required this.matchesConceded,
    required this.matchesWaiting,
  });

  /// Fixtures awarded to the opponent.
  final int matchesConceded;

  /// Fixtures skipped because the other side is not yet known — a knockout
  /// placeholder further down the bracket. Reported rather than hidden so an
  /// organizer knows to run this again once the bracket fills.
  final int matchesWaiting;
}

/// What one pass of [CompetitionRepository.resolveQualifiers] achieved.
///
/// Reports pending groups as well as resolved slots because "nothing happened"
/// has two very different meanings to an organizer — every qualifier is
/// already in place, or Group C still has two matches to play — and a bare
/// count cannot tell them apart.
class QualifierOutcome {
  const QualifierOutcome({
    required this.slotsResolved,
    required this.groupsComplete,
    required this.groupsPending,
  });

  /// Knockout fixtures that gained at least one entrant on this pass.
  final int slotsResolved;

  final List<String> groupsComplete;

  /// Groups a knockout slot is still waiting on.
  final List<String> groupsPending;

  bool get isFullyResolved => groupsPending.isEmpty;
}
