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

  // --- Exclusive scoring control (the pen) ------------------------------
  //
  // `scorerUids` says who MAY score. These three say who IS scoring, on
  // which device, and how that changes hands. See `Fixture.activeScorerUid`
  // for why the two are different questions.

  /// Hands exclusive scoring control to [scorerUid].
  ///
  /// Called by an owner or admin. Writes the grant and the eligibility in one
  /// update so there is no window in which somebody holds the pen for a match
  /// they are not allowed to score — a window a security rule would reject
  /// them in, on the ball they were handed the pen for.
  ///
  /// The device is deliberately NOT set here: the organizer granting from
  /// their own phone must not claim the pen onto it. The holder's first pad
  /// claims it (see [claimPenDevice]).
  ///
  /// Reassignment is the same operation. An owner moving the pen from one
  /// official to another calls this with the new uid, and the previous
  /// holder's pad drops to the live view on its next frame — from the same
  /// fixture listener it was already rendering the score from, so it happens
  /// mid-match without either person reloading anything.
  Future<void> grantPen({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String scorerUid,
    required String byUid,
  }) async {
    await Refs.fixture(orgId, compId, fixtureId).update({
      'activeScorerUid': scorerUid,
      // Cleared, not carried: the new holder is on their own device, and a
      // stale id here would lock them out of the pad they are standing at.
      'activeScorerDeviceId': null,
      'penGrantedByUid': byUid,
      'penGrantedAt': FieldValue.serverTimestamp(),
      'scorerUids': FieldValue.arrayUnion([scorerUid]),
    });
  }

  /// The pad claiming exclusive control for [scorerUid] on [deviceId].
  ///
  /// Covers both halves of "who is scoring on what": an unheld pen is claimed
  /// outright by the first eligible person to open the pad, and a pen already
  /// held by this person is pinned to whichever device they are actually
  /// standing at.
  ///
  /// A transaction, which is the one place in the whole scoring path that
  /// earns one. Everything else is last-writer-wins on a field a single role
  /// writes; this is two pads racing to become THE pad, and a plain update
  /// would let the loser's claim land second and quietly move the match to a
  /// screen nobody is looking at.
  ///
  /// [takeOver] is the deliberate version — "score on this device instead" —
  /// and is the only way to move a claim without an organizer. It never
  /// crosses accounts: taking the pen from another PERSON is [grantPen], and
  /// only an organizer may call that.
  Future<void> claimPen({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String scorerUid,
    required String deviceId,
    required String byUid,
    bool takeOver = false,
  }) async {
    final ref = Refs.fixture(orgId, compId, fixtureId);
    await Refs.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw const NotFoundException('That match is gone.');
      final fixture = Fixture.fromDoc(snap);

      if (fixture.penIsHeld && fixture.activeScorerUid != scorerUid) {
        throw const ValidationException(
          'Someone else has scoring control of this match. An admin can '
          'reassign it.',
        );
      }

      final claimed = fixture.activeScorerDeviceId;
      final deviceIsFree = claimed == null || claimed.isEmpty;
      if (fixture.penIsHeld && claimed == deviceId) return;
      if (!deviceIsFree && claimed != deviceId && !takeOver) {
        throw const ValidationException(
          'This match is already being scored on another device.',
        );
      }

      tx.update(ref, {
        'activeScorerUid': scorerUid,
        'activeScorerDeviceId': deviceId,
        if (!fixture.penIsHeld) ...{
          'penGrantedByUid': byUid,
          'penGrantedAt': FieldValue.serverTimestamp(),
        },
        'scorerUids': FieldValue.arrayUnion([scorerUid]),
      });
    });
  }

  /// Releases the pen so anyone eligible can pick it up.
  ///
  /// Leaves `scorerUids` alone: the person is still allowed to score this
  /// match, they are just not the one doing it at this moment.
  Future<void> releasePen({
    required String orgId,
    required String compId,
    required String fixtureId,
  }) async {
    await Refs.fixture(orgId, compId, fixtureId).update({
      'activeScorerUid': null,
      'activeScorerDeviceId': null,
      'penGrantedByUid': null,
      'penGrantedAt': null,
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
