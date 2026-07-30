import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
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
    });
  }
}
