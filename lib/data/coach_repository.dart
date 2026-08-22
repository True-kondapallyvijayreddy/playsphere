import '../core/firebase/firestore_refs.dart';
import '../core/models/coach.dart';
import 'org_repository.dart' show guard, guardStream;

/// Listing yourself as a coach, and finding one.
///
/// Deliberately shaped like [GroundRepository]: the same token search, the
/// same "a browse is a future, a page you sit on is a stream" split. Somebody
/// looking for a coach and somebody looking for a pitch are doing the same
/// thing — searching a public directory of local supply — and two different
/// search mechanisms for one job would be two things to get wrong.
class CoachRepository {
  const CoachRepository();

  // --- The coach's own listing -------------------------------------------

  /// Creates or replaces this person's listing.
  ///
  /// One method rather than a register/update pair, because the document id
  /// is the uid: there is no id to hand back, and "have I already got one?"
  /// is a question the caller should not have to answer before saving. The
  /// merge keeps `createdAt` and `isVerified` — which a client may not write
  /// anyway — intact on a re-save.
  Future<void> saveMyProfile(CoachProfile profile, {required bool isNew}) =>
      guard(() async {
        final ref = Refs.coach(profile.uid);
        if (isNew) {
          await ref.set(profile.toCreate());
        } else {
          await ref.update(profile.toUpdate());
        }
      });

  /// One coach's listing, or null if they have never made one.
  Stream<CoachProfile?> watchCoach(String uid) => guardStream(
        () => Refs.coach(uid).snapshots().map(
              (d) => d.exists ? CoachProfile.fromDoc(d) : null,
            ),
      );

  // --- Finding one --------------------------------------------------------

  /// Coaches for a sport, most recently listed first.
  ///
  /// A stream rather than a future, unlike [searchCoaches]: this is the list
  /// behind a sport, which a person arrives at and reads, and it is one
  /// indexed query rather than a merge of several.
  ///
  /// `isActive` is pinned in the query, not filtered afterwards, because a
  /// delisted coach must never be paged through into view — a person who has
  /// switched their listing off has withdrawn consent to be contacted, and
  /// "we fetched them and hid them" is the wrong side of that line.
  Stream<List<CoachProfile>> watchCoachesForSport(
    String sportId, {
    int limit = 20,
  }) =>
      guardStream(
        () => Refs.coaches
            .where('isActive', isEqualTo: true)
            .where('sportIds', arrayContains: sportId)
            .limit(limit)
            .snapshots()
            .map((s) => s.docs.map(CoachProfile.fromDoc).toList()),
      );

  /// Finds coaches by any words somebody might type — a name, an area, a
  /// sport, a certification — narrowed by sport.
  ///
  /// The mechanism is `GroundRepository.searchGrounds`', for the reason given
  /// there: Firestore has no full-text index, so one `array-contains` on the
  /// longest word typed does the narrowing and every other word is checked in
  /// Dart against that small set. Longest as a proxy for rarest.
  ///
  /// There is no legacy second query here, unlike the ground search. Nothing
  /// was ever written to this collection before `searchTokens` existed, so
  /// there is no older listing shape to keep findable.
  Future<List<CoachProfile>> searchCoaches({
    String keywords = '',
    String? sportId,
    bool acceptingOnly = false,
    int limit = 60,
  }) =>
      guard(() async {
        final words = CoachProfile.tokenize([keywords]);

        var query = Refs.coaches.where('isActive', isEqualTo: true);
        if (words.isEmpty) {
          // No words, but a sport — "show me the cricket coaches", which is
          // where the sport hub lands. Without this the search would open
          // empty and make the sport question look pointless.
          if (sportId == null) return const <CoachProfile>[];
          query = query.where('sportIds', arrayContains: sportId);
        } else {
          final anchor = words.reduce((a, b) => b.length > a.length ? b : a);
          query = query.where('searchTokens', arrayContains: anchor);
        }

        final snap = await query.limit(limit).get();

        final matching = <CoachProfile>[];
        for (final doc in snap.docs) {
          final c = CoachProfile.fromDoc(doc);
          // Every word has to match, not only the anchor. Recomputed from
          // the model rather than read back off the document, so the test
          // applied here is the same one that produced the stored array.
          final tokens = c.searchTokens.toSet();
          if (!words.every(tokens.contains)) continue;
          // Applied in Dart when words were typed, because Firestore permits
          // only one `array-contains` per query and the words already spent
          // it. An empty `sportIds` is not "every sport" here — see
          // `CoachProfile.sportIds`.
          if (sportId != null && !c.coaches(sportId)) continue;
          if (acceptingOnly && !c.acceptingStudents) continue;
          matching.add(c);
        }

        // Verified first, then the ones actually taking students, then the
        // more experienced. A parent scrolling this list is choosing who to
        // ring, and those are the three things that decide it.
        matching.sort((a, b) {
          if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
          if (a.acceptingStudents != b.acceptingStudents) {
            return a.acceptingStudents ? -1 : 1;
          }
          return b.yearsExperience.compareTo(a.yearsExperience);
        });
        return matching;
      });
}
