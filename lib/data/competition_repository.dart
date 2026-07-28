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

  Future<String> createCompetition(Competition competition) => guard(() async {
        final ref = Refs.competitions(competition.orgId).doc();
        await ref.set(competition.toCreate());
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

        await batch.commit();
        return snap.docs.length;
      });

  // --- Draw -------------------------------------------------------------

  /// Generates and persists the fixture list.
  ///
  /// Refuses to run once a match has been scored: regenerating a draw
  /// underneath results already entered would orphan them, and there is no
  /// safe automatic reconciliation.
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

        await batch.commit();
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
  /// that tracks players.
  Future<void> setLineups({
    required String orgId,
    required String compId,
    required String fixtureId,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            'lineupA': MatchPlayer.listTo(lineupA),
            'lineupB': MatchPlayer.listTo(lineupB),
          }));

  /// Records the toss, and who chose what.
  ///
  /// Cricket needs it to know which side bats first; every other sport uses it
  /// to decide who starts. It is written onto the fixture and into the frozen
  /// scoring config, because "who batted first" is part of how the match reads
  /// forever after and must not be recomputed later from anything mutable.
  Future<void> recordToss({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String wonByEntrantId,
    required String decision,
    required String battingFirstSide,
    required Map<String, dynamic> scoringConfig,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            'tossWonByEntrantId': wonByEntrantId,
            'tossDecision': decision,
            'scoringConfig': {
              ...scoringConfig,
              'battingFirst': battingFirstSide,
            },
          }));

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
