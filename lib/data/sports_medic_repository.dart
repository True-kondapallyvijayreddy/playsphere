import '../core/firebase/firestore_refs.dart';
import '../core/models/sports_medic.dart';
import 'org_repository.dart' show guard, guardStream;

/// Listing yourself as a sports doctor or physiotherapist, and finding one.
///
/// Deliberately the same shape as `CoachRepository` — one anchor word in an
/// `array-contains`, the rest of the words checked in Dart, verified first in
/// the sort. Somebody looking for a physio and somebody looking for a coach
/// are performing the same act on the same kind of collection, and two search
/// mechanisms for one job would be two things to get wrong.
///
/// What differs is the ranking and one refusal. See [searchMedics].
class SportsMedicRepository {
  const SportsMedicRepository();

  // --- The practitioner's own listing -------------------------------------

  /// Creates or replaces this person's listing.
  ///
  /// One method rather than register/update, because the document id is the
  /// uid: there is no id to hand back, and "have I got one already?" is not a
  /// question the caller should have to answer before saving.
  Future<void> saveMyProfile(
    SportsMedicProfile profile, {
    required bool isNew,
  }) =>
      guard(() async {
        final ref = Refs.sportsMedic(profile.uid);
        if (isNew) {
          await ref.set(profile.toCreate());
        } else {
          await ref.update(profile.toUpdate());
        }
      });

  /// One practitioner's listing, or null if they have never made one.
  Stream<SportsMedicProfile?> watchMedic(String uid) => guardStream(
        () => Refs.sportsMedic(uid).snapshots().map(
              (d) => d.exists ? SportsMedicProfile.fromDoc(d) : null,
            ),
      );

  // --- Finding one --------------------------------------------------------

  /// Practitioners in one city, most useful first.
  ///
  /// The city is queried on `cityKey` rather than filtered in Dart, because
  /// "who is in Warangal" is the question this directory exists to answer and
  /// it must not degrade into reading the whole collection as the directory
  /// grows.
  Stream<List<SportsMedicProfile>> watchMedicsInCity(
    String city, {
    int limit = 40,
  }) =>
      guardStream(
        () => Refs.sportsMedics
            .where('isActive', isEqualTo: true)
            .where('cityKey', isEqualTo: city.trim().toLowerCase())
            .limit(limit)
            .snapshots()
            .map((s) => s.docs.map(SportsMedicProfile.fromDoc).toList()),
      );

  /// Finds practitioners by any words somebody might type — a name, a clinic,
  /// an area, a qualification — narrowed by role, sport and consultation mode.
  ///
  /// ## Why an empty query returns nothing
  ///
  /// Same rule as the coach and ground searches: reading a whole collection to
  /// fill a screen nobody has addressed is the unbounded query this design
  /// exists to avoid. The one softening is [role] — "show me every physio" is
  /// a real question with a bounded answer, so a role on its own is enough to
  /// run a search even with no words typed.
  ///
  /// ## Why the sport filter does not exclude generalists
  ///
  /// `SportsMedicProfile.treats` returns true for an empty `sportIds`. An
  /// orthopaedic surgeon who has not ticked "kabaddi" still fixes the knee a
  /// kabaddi player tore, and hiding them from a kabaddi player would be the
  /// directory withholding the right answer on a technicality. This is the
  /// opposite of the coach rule, on purpose — see `SportsMedicProfile`.
  Future<List<SportsMedicProfile>> searchMedics({
    String keywords = '',
    SportsMedicRole? role,
    String? sportId,
    String? city,
    ConsultationMode? mode,
    bool acceptingOnly = false,
    int limit = 60,
  }) =>
      guard(() async {
        final words = SportsMedicProfile.tokenizeQuery(keywords);

        var query = Refs.sportsMedics.where('isActive', isEqualTo: true);

        if (words.isNotEmpty) {
          // Longest word as a proxy for rarest — Firestore allows one
          // `array-contains` per query, so it is spent on the word most
          // likely to narrow hardest.
          final anchor = words.reduce((a, b) => b.length > a.length ? b : a);
          query = query.where('searchTokens', arrayContains: anchor);
        } else if (city != null && city.trim().isNotEmpty) {
          // No words but a city: the equality filter narrows on the server,
          // which is what makes "every physio in Warangal" affordable.
          query = query.where('cityKey', isEqualTo: city.trim().toLowerCase());
        } else if (role == null) {
          // Nothing asked at all.
          return const <SportsMedicProfile>[];
        }

        final snap = await query.limit(limit).get();

        final cityKey = city?.trim().toLowerCase();
        final matching = <SportsMedicProfile>[];
        for (final doc in snap.docs) {
          final m = SportsMedicProfile.fromDoc(doc);
          // Every word has to match, not only the anchor. Recomputed from the
          // model rather than read off the document, so the test applied here
          // is the one that produced the stored array.
          final tokens = m.searchTokens.toSet();
          if (!words.every(tokens.contains)) continue;
          if (role != null && m.role != role) continue;
          if (sportId != null && !m.treats(sportId)) continue;
          if (cityKey != null && cityKey.isNotEmpty && m.cityKey != cityKey) {
            continue;
          }
          if (mode != null && !m.offers(mode)) continue;
          if (acceptingOnly && !m.acceptingNewPatients) continue;
          matching.add(m);
        }

        // Verified first, then the ones actually taking patients, then the
        // more experienced. Somebody scrolling this list is deciding who to
        // ring about an injury, and those are the three facts that decide it.
        matching.sort((a, b) {
          if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
          if (a.acceptingNewPatients != b.acceptingNewPatients) {
            return a.acceptingNewPatients ? -1 : 1;
          }
          return b.experienceYears.compareTo(a.experienceYears);
        });
        return matching;
      });
}
