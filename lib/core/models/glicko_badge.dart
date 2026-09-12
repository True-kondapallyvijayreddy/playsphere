import 'firestore_codec.dart';

/// The Overall PlaySphere Glicko as it travels — a handful of numbers
/// denormalised onto `users/{uid}` so that a roster, a team sheet, a
/// tournament entry list or a player card can put a competitive standing
/// beside a name without opening anybody's ratings subcollection.
///
/// ## Why a separate, smaller thing than the composite itself
///
/// `OverallGlicko` is the full computation: every sport, its confidence, its
/// recency, its rank weight, and the arithmetic that turns them into one
/// number. A profile shows all of that, because a profile is where somebody
/// asks "why is my number what it is", and it can afford to — it has already
/// loaded the rating documents to draw the per-sport cards.
///
/// This is the travelling copy. It carries what fits beside a name and nothing
/// else. Keeping it deliberately thin is the point: the field lives on a
/// document that half the app loads, and an unbounded per-sport map on it would
/// grow with every sport a person ever tries.
///
/// Written only by `functions/overall_glicko.js`; `firestore.rules` freezes it
/// against every client write. A competitive standing a person can type into
/// their own profile is not a rating.
class GlickoBadge {
  const GlickoBadge({
    required this.overall,
    required this.provisional,
    required this.sports,
    required this.sportCount,
    this.computedAt,
  });

  /// The composite, rounded, on the Glicko scale.
  final int overall;

  /// True while there is not yet enough play behind the number for it to be
  /// stated plainly. Every surface that shows [overall] must show this too —
  /// see [OverallGlicko.isProvisional].
  final bool provisional;

  /// The top few sports by rating, strongest first. Display only: the
  /// authoritative per-sport ratings are the rating documents.
  final Map<String, int> sports;

  /// How many sports the composite was actually built from, which is often
  /// more than [sports] holds. Lets a card say "and 2 more" honestly.
  final int sportCount;

  final DateTime? computedAt;

  /// Sports beyond the ones listed in [sports].
  int get hiddenSportCount =>
      (sportCount - sports.length).clamp(0, sportCount);

  /// This person's rating in one named sport, or null if the travelling copy
  /// does not carry it.
  ///
  /// Null does NOT mean unrated — [sports] holds only the top few — so a
  /// caller that wants a number regardless should fall back to [overall]
  /// rather than treating this as "has never played". A roster for a sport
  /// somebody plays as their fourth is the case that makes this matter: the
  /// honest thing to show there is the overall standing, not a blank.
  ///
  /// Rating keys are collapsed to base sports server-side, so `chess` answers
  /// for `chess:blitz` too. The colon is the only separator to strip — sport
  /// ids like `table_tennis` contain underscores of their own.
  int? ratingFor(String sportId) => sports[sportId.split(':').first];

  /// Null when the map is absent or malformed, which is the ordinary state for
  /// anybody who has not played a rated match. Callers render null as "no
  /// rating yet", never as a number — 1500 is a real position on this scale
  /// and claiming it for someone with no results is a statement nothing
  /// supports.
  static GlickoBadge? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final overall = raw['overall'];
    if (overall is! num) return null;

    final rawSports = raw['sports'];
    // Re-sorted here, and it has to be. The server writes these in rank order,
    // but a Firestore map is not an ordered structure — it comes back off the
    // wire keyed alphabetically — so "strongest first" would have quietly
    // become "alphabetically first" on every card in the app, which reads as
    // a bug in the rating rather than in the decoding.
    final entries = <MapEntry<String, int>>[
      if (rawSports is Map)
        for (final e in rawSports.entries)
          if (e.value is num)
            MapEntry(e.key.toString(), (e.value as num).round()),
    ]..sort((a, b) {
        final byRating = b.value.compareTo(a.value);
        return byRating != 0 ? byRating : a.key.compareTo(b.key);
      });
    final sports = Map<String, int>.fromEntries(entries);

    return GlickoBadge(
      overall: overall.round(),
      // Absent means absent, not false: an old document written before the
      // flag existed should read as provisional rather than silently claim a
      // confidence nothing measured.
      provisional: raw['provisional'] != false,
      sports: sports,
      sportCount: (raw['sportCount'] as num?)?.toInt() ?? sports.length,
      computedAt: Fs.dateOrNull(raw['computedAt']),
    );
  }
}
