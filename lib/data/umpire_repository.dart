import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/models/match_official.dart';
import '../core/models/umpire_profile.dart';

/// Manages registration of multi-sport umpires/referees, search/querying,
/// and assigning officials to fixtures with optional scoring permissions.
class UmpireRepository {
  const UmpireRepository();

  /// Self-service or manager registration of an umpire profile.
  Future<void> registerUmpire(UmpireProfile profile) async {
    await Refs.umpire(profile.uid).set(
      profile.toMap(),
      SetOptions(merge: true),
    );
  }

  /// Fetches an umpire's profile by UID.
  Future<UmpireProfile?> fetchUmpire(String uid) async {
    final doc = await Refs.umpire(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UmpireProfile.fromMap(doc.data()!);
  }

  /// Fetches all active umpires certified to officiate a specific sport.
  Future<List<UmpireProfile>> fetchUmpiresForSport(String sportId) async {
    final snap = await Refs.umpires
        .where('sports', arrayContains: sportId)
        .where('isAvailable', isEqualTo: true)
        .get();
    return snap.docs.map((d) => UmpireProfile.fromMap(d.data())).toList();
  }

  /// Checks if an official is already assigned to a live or overlapping match.
  Future<void> checkOfficialAvailability({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String officialUid,
    required String officialName,
    DateTime? scheduledAt,
  }) async {
    final snap = await Refs.fixtures(orgId, compId).get();
    final fixtures = snap.docs.map(Fixture.fromDoc).toList();

    for (final fix in fixtures) {
      if (fix.id == fixtureId) continue;
      final isAssigned = fix.officials.any((o) => o.uid == officialUid);
      if (!isAssigned) continue;

      if (fix.isLive) {
        throw ValidationException(
          '$officialName is currently officiating a LIVE match (${fix.entrantAName} vs ${fix.entrantBName})',
        );
      }

      if (scheduledAt != null && fix.scheduledAt != null) {
        final diff = fix.scheduledAt!.difference(scheduledAt).abs();
        if (diff < const Duration(hours: 2)) {
          throw ValidationException(
            'Time clash: $officialName is already assigned to ${fix.entrantAName} vs ${fix.entrantBName}',
          );
        }
      }
    }
  }

  /// Assigns an official to a fixture and optionally grants scoring access
  /// by adding their UID to `fixture.scorerUids`.
  Future<void> assignOfficialToFixture({
    required String orgId,
    required String compId,
    required String fixtureId,
    required MatchOfficial official,
    bool grantScoringAccess = true,
  }) async {
    final fixRef = Refs.fixture(orgId, compId, fixtureId);
    final doc = await fixRef.get();
    if (!doc.exists) return;

    final fixture = Fixture.fromDoc(doc);

    // Validate that official is not already officiating a live or overlapping match
    await checkOfficialAvailability(
      orgId: orgId,
      compId: compId,
      fixtureId: fixtureId,
      officialUid: official.uid,
      officialName: official.name,
      scheduledAt: fixture.scheduledAt,
    );
    final existingOfficials = List<MatchOfficial>.from(fixture.officials);

    final idx = existingOfficials.indexWhere((o) => o.uid == official.uid);
    if (idx >= 0) {
      existingOfficials[idx] = official;
    } else {
      existingOfficials.add(official);
    }

    final updatedScorers = List<String>.from(fixture.scorerUids);
    if (grantScoringAccess && !updatedScorers.contains(official.uid)) {
      updatedScorers.add(official.uid);
    }

    await fixRef.update({
      'officials': MatchOfficial.listTo(existingOfficials),
      'scorerUids': updatedScorers,
      // Naming an official advances the match's readiness — §7's
      // SCHEDULED -> OFFICIALS ASSIGNED. Only ever forwards, and never past
      // `ready`: declaring a match ready is the organizer's deliberate act in
      // the Match Center, not a side effect of filling one of several slots.
      if (fixture.readiness == MatchReadiness.scheduled)
        'readiness': MatchReadiness.officialsAssigned.wire,
    });
  }

  /// Removes an official from a match, and their scoring access with them.
  ///
  /// The counterpart to [assignOfficialToFixture], and its absence was a real
  /// gap: an umpire assigned by mistake, or one who cannot make it, could
  /// only be replaced by assigning somebody else — which left the first one
  /// still holding the pen on a match they are not officiating.
  Future<void> removeOfficialFromFixture({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String officialUid,
  }) async {
    final fixRef = Refs.fixture(orgId, compId, fixtureId);
    final doc = await fixRef.get();
    if (!doc.exists) return;

    final fixture = Fixture.fromDoc(doc);
    final remaining =
        fixture.officials.where((o) => o.uid != officialUid).toList();

    await fixRef.update({
      'officials': MatchOfficial.listTo(remaining),
      // Scoring access goes with the role. Leaving it behind would mean an
      // official removed from a match could still write its score, which is
      // the one thing removing them was meant to stop.
      'scorerUids': fixture.scorerUids.where((u) => u != officialUid).toList(),
      // Back to `scheduled` once the last official is gone, so the Match
      // Center stops claiming a panel that no longer exists.
      if (remaining.isEmpty &&
          fixture.readiness == MatchReadiness.officialsAssigned)
        'readiness': MatchReadiness.scheduled.wire,
    });
  }

  /// Hands somebody the pen for one match — §6.
  ///
  /// Separate from [assignOfficialToFixture] because a scorer is not
  /// necessarily an official. The doc lists an official scorer, a team
  /// scorer, the organizer and a remote scorer as four ways to fill the role,
  /// and at grassroots level it is routinely a captain or a parent on the
  /// boundary. All four are the same fact to the model — a uid that may write
  /// this match's score — so this takes a person rather than a category.
  ///
  /// No availability check, unlike an umpire: one person can legitimately
  /// score two matches on adjacent courts, and blocking that would be
  /// inventing a rule the sport does not have.
  Future<void> assignScorer({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String scorerUid,
  }) async {
    await Refs.fixture(orgId, compId, fixtureId).update({
      'scorerUids': FieldValue.arrayUnion([scorerUid]),
    });
  }

  /// Takes the pen back.
  ///
  /// `arrayRemove` rather than a read-modify-write: two organizers editing
  /// the panel at once would otherwise each write a list computed from what
  /// they read, and the later write would silently restore whoever the
  /// earlier one removed.
  Future<void> removeScorer({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String scorerUid,
  }) async {
    await Refs.fixture(orgId, compId, fixtureId).update({
      'scorerUids': FieldValue.arrayRemove([scorerUid]),
    });
  }

  /// An official confirming a submitted result — §23's VERIFY step.
  ///
  /// Only reachable for a match the scorer left `awaiting_approval`, and
  /// `firestore.rules` is what actually enforces that only an organizer may
  /// write `finalized`. Guarded here too so the caller gets a sentence rather
  /// than a permission error.
  Future<void> finalizeResult({
    required String orgId,
    required String compId,
    required String fixtureId,
  }) async {
    final fixRef = Refs.fixture(orgId, compId, fixtureId);
    final doc = await fixRef.get();
    if (!doc.exists) return;

    final fixture = Fixture.fromDoc(doc);
    if (!fixture.status.isResulted) {
      throw const ValidationException(
        'This match has no result to verify yet.',
      );
    }
    if (fixture.resultState != MatchResultState.awaitingApproval) {
      throw const ValidationException(
        'This result is not waiting for approval.',
      );
    }
    await fixRef.update({'resultState': MatchResultState.finalized.wire});
  }

  /// The organizer's explicit "this match is good to go" — §7's READY.
  ///
  /// Deliberately not enforced anywhere: a club's Sunday game has no
  /// organizer to press it, and blocking scoring on a state nobody set would
  /// stop exactly the grassroots matches this product exists for. It is a
  /// signal to everyone looking at the fixture, not a gate.
  Future<void> setMatchReadiness({
    required String orgId,
    required String compId,
    required String fixtureId,
    required MatchReadiness readiness,
  }) async {
    await Refs.fixture(orgId, compId, fixtureId)
        .update({'readiness': readiness.wire});
  }
}
