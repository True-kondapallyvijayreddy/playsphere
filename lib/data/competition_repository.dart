import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/competition.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/models/match_player.dart';
import '../domain/draw/fixture_generator.dart';
import '../domain/scoring/scoring_plugin.dart';
import '../domain/scoring/scoring_registry.dart';
import 'org_repository.dart' show guard;

class CompetitionRepository {
  const CompetitionRepository();

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
    return q.snapshots().map(
          (snap) => snap.docs.map(Competition.fromDoc).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0))),
        );
  }

  Stream<Competition?> watchCompetition(String orgId, String compId) =>
      Refs.competition(orgId, compId).snapshots().map(
            (doc) => doc.exists ? Competition.fromDoc(doc) : null,
          );

  Stream<List<Registration>> watchRegistrations(
    String orgId,
    String compId, {
    RegistrationStatus? status,
  }) {
    Query<Map<String, dynamic>> q = Refs.registrations(orgId, compId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    return q.snapshots().map(
          (snap) => snap.docs.map(Registration.fromDoc).toList(),
        );
  }

  Stream<List<Entrant>> watchEntrants(String orgId, String compId) =>
      Refs.entrants(orgId, compId).snapshots().map(
            (snap) => snap.docs.map(Entrant.fromDoc).toList(),
          );

  Stream<List<Fixture>> watchFixtures(String orgId, String compId) =>
      Refs.fixtures(orgId, compId).snapshots().map(
            (snap) => snap.docs.map(Fixture.fromDoc).toList()
              ..sort((a, b) {
                final r = a.round.compareTo(b.round);
                return r != 0 ? r : a.matchIndex.compareTo(b.matchIndex);
              }),
          );

  /// Live matches across an entire organization — powers the spectator
  /// "what's on right now" screen that remote viewers land on.
  Stream<List<Fixture>> watchLiveFixtures(String orgId) {
    return Refs.allFixturesQuery
        .where('orgId', isEqualTo: orgId)
        .where('status', isEqualTo: FixtureStatus.live.wire)
        .snapshots()
        .map((snap) => snap.docs.map(Fixture.fromDoc).toList());
  }

  /// Fixtures a specific person is assigned to score.
  Stream<List<Fixture>> watchMyScoringAssignments(String uid) {
    return Refs.allFixturesQuery
        .where('scorerUids', arrayContains: uid)
        .where('status', whereIn: [
          FixtureStatus.scheduled.wire,
          FixtureStatus.live.wire,
        ])
        .snapshots()
        .map((snap) => snap.docs.map(Fixture.fromDoc).toList());
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

  // --- Registration -----------------------------------------------------

  /// Registers [user], refusing when they do not meet the category rules.
  ///
  /// The eligibility check runs before the write and returns the specific
  /// reason. Silently accepting an ineligible entry and discovering it at
  /// medal time is how school meets end in arguments.
  Future<void> register({
    required Competition competition,
    required AppUser user,
  }) =>
      guard(() async {
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

        await Refs.registration(competition.orgId, competition.id, user.uid).set(
          Registration(
            uid: user.uid,
            displayName: user.displayName,
            photoUrl: user.photoUrl,
            status: RegistrationStatus.pending,
          ).toCreate(),
        );
      });

  Future<void> decideRegistration({
    required String orgId,
    required String compId,
    required String uid,
    required RegistrationStatus status,
    required String decidedByUid,
    String? note,
  }) =>
      guard(() => Refs.registration(orgId, compId, uid).update({
            'status': status.wire,
            'decidedBy': decidedByUid,
            'eligibilityNote': note,
            'decidedAt': FieldValue.serverTimestamp(),
          }));

  Future<void> withdraw({
    required String orgId,
    required String compId,
    required String uid,
  }) =>
      guard(() => Refs.registration(orgId, compId, uid).update({
            'status': RegistrationStatus.withdrawn.wire,
          }));

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
  Future<int> lockFieldAndCreateEntrants({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final snap = await Refs.registrations(orgId, compId)
            .where('status', isEqualTo: RegistrationStatus.confirmed.wire)
            .get();

        if (snap.docs.length < 2) {
          throw const ValidationException(
            'At least two confirmed entries are needed before you can close '
            'entries and make a draw.',
          );
        }

        final batch = Refs.db.batch();
        for (final doc in snap.docs) {
          final reg = Registration.fromDoc(doc);
          batch.set(
            Refs.entrants(orgId, compId).doc(reg.uid),
            Entrant(
              id: reg.uid,
              displayName: reg.displayName,
              entrantType: EntrantType.individual,
              uid: reg.uid,
              photoUrl: reg.photoUrl,
            ).toMap(),
          );
        }
        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.registrationClosed.wire,
          'entrantCount': snap.docs.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
        return snap.docs.length;
      });

  // --- Draw -------------------------------------------------------------

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
  Future<int> generateDraw({
    required Competition competition,
    required List<Entrant> entrants,
    required List<String> defaultScorerUids,
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

        final planned = const FixtureGenerator().generate(
          format: competition.format,
          entrants: entrants,
        );
        if (planned.isEmpty) {
          throw const ValidationException(
            'Not enough entrants to make a draw.',
          );
        }

        final sport = SportCatalog.byId(competition.sportId);
        final batch = Refs.db.batch();

        // Clear any previous unscored draw so regenerating does not leave
        // stale fixtures behind alongside the new ones.
        for (final doc in existing.docs) {
          batch.delete(doc.reference);
        }

        final refs = List.generate(
          planned.length,
          (_) => Refs.fixtures(orgId, compId).doc(),
        );

        var realCount = 0;
        for (var i = 0; i < planned.length; i++) {
          final p = planned[i];
          // A bye is not a match. Recording it as one would give a free win
          // that pollutes both the league table and the player's rating.
          if (p.isBye && competition.format != CompetitionFormat.knockout) {
            continue;
          }

          final fixture = Fixture(
            id: refs[i].id,
            orgId: orgId,
            compId: compId,
            entrantAId: p.entrantA?.id ?? '',
            entrantBId: p.entrantB?.id ?? '',
            entrantAName: p.entrantA?.displayName ?? 'To be decided',
            entrantBName: p.entrantB?.displayName ?? 'To be decided',
            status: FixtureStatus.scheduled,
            round: p.round,
            matchIndex: p.matchIndex,
            roundLabel: p.roundLabel,
            venue: competition.venue,
            scheduledAt: competition.startDate,
            scorerUids: defaultScorerUids,
            scoringPluginKey: competition.scoringPluginKey,
            sportId: competition.sportId,
            rulesetVersion: competition.rulesetVersion,
            // Frozen here so every surface that renders this match reads the
            // rules it was actually played under, without a second read.
            scoringConfig: sport.config,
            scoreState: ScoringRegistry.resolve(competition.scoringPluginKey)
                .initialState(_contextFor(p, sport)),
            feedsWinnerToFixtureId: p.feedsWinnerToIndex == null
                ? null
                : refs[p.feedsWinnerToIndex!].id,
            feedsWinnerToSlot: p.feedsWinnerToSlot,
          );

          batch.set(refs[i], fixture.toCreate());
          realCount++;
        }

        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.scheduled.wire,
          'fixtureCount': realCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
        return realCount;
      });

  ScoringContext _contextFor(PlannedFixture p, SportSpec sport) =>
      ScoringContext(
        entrantAName: p.entrantA?.displayName ?? 'A',
        entrantBName: p.entrantB?.displayName ?? 'B',
        config: sport.config,
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
  Future<void> setLineups({
    required String orgId,
    required String compId,
    required String fixtureId,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
  }) =>
      guard(() async {
        unawaited(
          Refs.fixture(orgId, compId, fixtureId).update({
            'lineupA': MatchPlayer.listTo(lineupA),
            'lineupB': MatchPlayer.listTo(lineupB),
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
  Future<void> recordToss({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String wonByEntrantId,
    required String decision,
    required String battingFirstSide,
    required Map<String, dynamic> scoringConfig,
  }) =>
      guard(() async {
        unawaited(
          Refs.fixture(orgId, compId, fixtureId).update({
            'tossWonByEntrantId': wonByEntrantId,
            'tossDecision': decision,
            'scoringConfig': {
              ...scoringConfig,
              'battingFirst': battingFirstSide,
            },
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  Future<void> rescheduleFixture({
    required String orgId,
    required String compId,
    required String fixtureId,
    DateTime? scheduledAt,
    String? venue,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            if (scheduledAt != null)
              'scheduledAt': Timestamp.fromDate(scheduledAt),
            if (venue != null) 'venue': venue,
          }));
}
