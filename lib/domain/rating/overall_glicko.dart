import 'dart:math' as math;

import 'glicko2.dart';

/// The Overall PlaySphere Glicko — one number for how strong a person is as a
/// competitor, across every sport they play.
///
/// ## What this is, and what it deliberately is not
///
/// A Glicko rating is only meaningful *inside* one competitive domain. 1842 in
/// cricket and 1618 in badminton were produced by two disjoint populations
/// playing two different games; there is no match anybody could play that would
/// reconcile them, so there is no rating period in which they could be updated
/// together. Anything that folds them into a single figure is an index, not a
/// rating, and this file is careful to say so: the output is a **composite
/// rendered on the Glicko scale**, not a Glicko rating with a wider scope. The
/// per-sport numbers in `users/{uid}/ratings/{ratingKey}` remain the only
/// authoritative ratings PlaySphere has.
///
/// The reason to render it on the 1500-centred scale anyway — rather than as
/// the 0–100 figure [CrossSportIndex] produces — is that it has to sit beside
/// the sport ratings on the same profile and be read without a decoder ring.
/// "Vijay Reddy · Glicko 1716" above "Cricket 1842 · Badminton 1618" is legible
/// at a glance. "Vijay Reddy · Index 71" next to those same numbers is not.
///
/// The two coexist on purpose. [CrossSportIndex] answers "where does this
/// person stand relative to everyone else", which needs the population of every
/// rated player and therefore a server-side aggregate. This answers "how strong
/// is this person", which needs nothing but their own rating documents — so it
/// can be computed on the client from data the profile has already loaded, and
/// on the server in the same pass that settles a match.
///
/// ## Why not an average
///
/// A mean of 2000 in cricket and 1000 in badminton is 1500, which describes
/// neither. Worse, it makes taking up a second sport a punishment: a district-
/// level cricketer who plays four games of volleyball for fun would watch their
/// headline number fall. Nobody would play the second sport twice.
///
/// So three things shape the blend, in this order:
///
/// 1. **Strength order.** Sports are ranked by rating and each successive one
///    counts [rankDecay] as much as the one above it. A person's competitive
///    identity is led by what they are best at; the rest colours it in.
/// 2. **Confidence.** Each sport's say in the blend is scaled by how much its
///    own rating is believed — Glicko's rating deviation, which is the whole
///    reason Glicko-2 was chosen over Elo — and by how recently it was earned.
/// 3. **Evidence.** The finished blend is pulled back toward 1500 by how many
///    rated matches actually stand behind it. This is the guard the product
///    needs most: without it, one lucky win against a strong opponent would
///    mint a headline number on a profile that a scout might act on.
///
/// ## Worked example
///
/// A player rated 1842 cricket, 1618 badminton, 1497 football, 1325 volleyball,
/// all established (RD 60, ~40 matches each, all played recently):
///
/// | rank | sport      | rating | weight            |
/// |------|------------|--------|-------------------|
/// | 1    | cricket    | 1842   | 0.829 × 1         |
/// | 2    | badminton  | 1618   | 0.829 × 0.45      |
/// | 3    | football   | 1497   | 0.829 × 0.45²     |
/// | 4    | volleyball | 1325   | 0.829 × 0.45³     |
///
/// giving a weighted mean of 1717, which — 160 matches deep — is not shrunk at
/// all. **Overall 1717.** The same player after two cricket matches and nothing
/// else would read far lower, and be flagged provisional.
///
/// `test/overall_glicko_test.dart` pins both.
class OverallGlicko {
  const OverallGlicko({
    required this.overall,
    required this.components,
    required this.evidenceWeight,
    required this.effectiveMatches,
  });

  /// The composite, on the Glicko scale.
  final double overall;

  /// One entry per sport that had something to say, strongest first.
  final List<OverallGlickoComponent> components;

  /// 0–1, how far the blend was allowed to travel from 1500. 1 means the
  /// evidence was ample and [overall] is the blend untouched.
  final double evidenceWeight;

  /// Rated matches behind the number, after recency decay. Fractional because
  /// a season-old match counts for less than yesterday's.
  final double effectiveMatches;

  /// The sport that leads this person's competitive identity.
  OverallGlickoComponent get primary => components.first;

  /// True while the number is still being pulled meaningfully toward the 1500
  /// prior — there is not yet enough play behind it to state plainly.
  ///
  /// The UI must say so wherever it shows the number. A provisional composite
  /// on a profile a selector is reading is worse than no composite at all if
  /// it does not announce what it is.
  bool get isProvisional => evidenceWeight < provisionalEvidence;

  /// Below this, [isProvisional]. Reached at roughly fifteen effective rated
  /// matches — the point at which the shrinkage stops moving the number by
  /// more than a rounding error.
  static const double provisionalEvidence = 0.85;

  /// The same tier vocabulary the per-sport badge uses, so a profile does not
  /// speak two languages about the same scale.
  String get tier => Rating(rating: overall).tier;
}

/// What one sport contributed, kept so the profile can answer "why is my
/// number what it is" rather than presenting a bare figure.
class OverallGlickoComponent {
  const OverallGlickoComponent({
    required this.sportId,
    required this.rating,
    required this.confidence,
    required this.recency,
    required this.rankFactor,
    required this.matches,
  });

  /// The base sport — `chess`, never `chess:blitz`. See
  /// [OverallGlickoEngine.compute] for why time controls are collapsed.
  final String sportId;

  /// This sport's authoritative Glicko rating, undiscounted. What the profile
  /// shows beside the sport, and what the blend consumes.
  final double rating;

  /// 0–1, from the rating deviation.
  final double confidence;

  /// 0–1, from how long ago this sport was last played.
  final double recency;

  /// 0–1, this sport's place in the person's strength order: 1 for their best,
  /// [OverallGlickoEngine.rankDecay] for the next, and so on.
  final double rankFactor;

  /// Rated matches in this sport.
  final int matches;

  /// How much this sport steered the composite, before normalisation.
  double get weight => confidence * recency * rankFactor;
}

/// One sport's rating as the engine wants it.
class SportRatingEvidence {
  const SportRatingEvidence({
    required this.sportId,
    required this.rating,
    this.lastPlayedAt,
  });

  /// The rating key as stored — `cricket`, or `chess:blitz`. The engine
  /// collapses time controls itself; callers pass what they have.
  final String sportId;

  final Rating rating;

  /// When this sport was last played. Callers should fall back to the rating
  /// document's own `updatedAt` when there is no career record — a rated
  /// walkover moves a rating without writing a career line.
  ///
  /// Null means "no timestamp anywhere", which is a data gap rather than
  /// evidence of a long absence, and is treated as no penalty. That is the
  /// opposite of [CrossSportIndex]'s choice and deliberately so: there, a
  /// missing timestamp must never let a stale row masquerade as current form
  /// on a discovery board somebody else reads. Here the number is the
  /// person's own headline, and silently halving it because a legacy document
  /// predates a field would be a bug they could neither see nor fix.
  final DateTime? lastPlayedAt;

  /// `chess:blitz` means chess.
  ///
  /// Splits on the COLON only, and that is not a detail. Real sport ids
  /// contain underscores — `table_tennis`, `kho_kho`, `athletics_sprint`,
  /// `athletics_field` — so splitting on `_` as well would turn table tennis
  /// into `table`, which matches no sport in the catalogue, and would merge
  /// sprint and field athletics into one pool whose ratings measure two
  /// unrelated abilities. The colon is the only separator `Fixture.ratingKey`
  /// ever introduces.
  String get baseSportId => sportId.split(':').first;
}

/// Computes the [OverallGlicko] composite.
///
/// Every constant here has a mirror in `functions/overall_glicko.js`. That
/// duplication is deliberate and follows the precedent set by
/// `RisingSignal`/`risingSignal()`: this copy exists so the app can explain and
/// re-derive the number it is already showing without a round trip, and the
/// server copy exists because the composite has to be denormalised onto the
/// user document for every roster and player card that never loads a rating.
/// `test/overall_glicko_test.dart` pins the outputs both must produce.
class OverallGlickoEngine {
  const OverallGlickoEngine({
    this.recencyHalfLifeDays = defaultHalfLifeDays,
    this.rankDecay = defaultRankDecay,
    this.evidenceScale = defaultEvidenceScale,
  });

  /// Days for a sport's contribution to fall to half. 180 for the reason
  /// [CrossSportIndex] uses it: in grassroots sport an off-season gap is
  /// normal and must not read as having quit.
  static const double defaultHalfLifeDays = 180;

  /// How much each successive sport counts relative to the one above it.
  ///
  /// 0.45 rather than a rounder number because of what it produces at the top
  /// of the file: a four-sport player's composite lands a little above the
  /// midpoint between their best sport and their mean, which is where a
  /// person's own sense of "how good am I" actually sits. Lower and the
  /// composite collapses onto the best sport, making it a duplicate of a
  /// number already on the page; higher and it drifts toward the mean this
  /// whole file exists to avoid.
  static const double defaultRankDecay = 0.45;

  /// Effective matches at which the composite has travelled ~63% of the way
  /// from 1500 to its blend. See [_evidenceWeight].
  static const double defaultEvidenceScale = 8;

  final double recencyHalfLifeDays;
  final double rankDecay;
  final double evidenceScale;

  /// 0 at a brand-new rating deviation — 350, nothing is known — rising toward
  /// 1 as the deviation shrinks. Anchored to [Rating.defaultDeviation] rather
  /// than an independent constant so this cannot disagree with what
  /// `glicko2.dart` considers "we know nothing about this player".
  double confidenceFor(Rating rating) =>
      (1 - rating.deviation / Rating.defaultDeviation).clamp(0.0, 1.0);

  /// Exponential decay from the last time this sport was played.
  double recencyFor(DateTime? lastPlayedAt, DateTime asOf) {
    if (lastPlayedAt == null) return 1.0; // see SportRatingEvidence.lastPlayedAt
    final days =
        asOf.difference(lastPlayedAt).inMilliseconds / Duration.millisecondsPerDay;
    if (days <= 0) return 1.0;
    if (recencyHalfLifeDays <= 0) return 0.0;
    return math.pow(0.5, days / recencyHalfLifeDays).toDouble();
  }

  /// How far the blend is allowed to travel from the 1500 prior, given the
  /// weight of play behind it.
  ///
  /// `1 - e^(-m/scale)` rather than the `m/(m+k)` shrinkage used elsewhere in
  /// the product, because this one has to *finish*. A ratio curve is still
  /// visibly short of 1 at fifty matches, which would leave a district-level
  /// cricketer's composite permanently below their own cricket rating with no
  /// amount of play able to close the gap — the profile would look broken to
  /// exactly the people whose records are strongest. This reaches 0.98 by
  /// thirty matches and is indistinguishable from 1 thereafter, while still
  /// cutting a two-match record to about a fifth.
  double _evidenceWeight(double effectiveMatches) {
    if (effectiveMatches <= 0 || evidenceScale <= 0) return 0;
    return 1 - math.exp(-effectiveMatches / evidenceScale);
  }

  /// The composite, or null when there is nothing to compute one from.
  ///
  /// Null rather than 1500. A person who has not played a rated match has no
  /// competitive standing yet, and 1500 is a real position on this scale —
  /// mid-table, "Club" tier — which is a claim about them that no result
  /// supports. The UI renders null as an invitation to play, never as a
  /// number.
  ///
  /// ## Time controls are collapsed
  ///
  /// Chess is rated per time control (`chess:blitz`, `chess:classical`) because
  /// bullet and classical measure different skills. For the composite they are
  /// one sport: counting them as two would hand a chess player a breadth their
  /// results do not show, and would rank a second time control ahead of a real
  /// second sport. The best-evidenced reading of each base sport is the one
  /// that stands for it.
  OverallGlicko? compute({
    required List<SportRatingEvidence> entries,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();

    // Base sport -> the reading that best represents it.
    final bySport = <String, ({SportRatingEvidence e, double conf, double rec})>{};
    for (final entry in entries) {
      // No games means no evidence beyond the prior, so this sport has nothing
      // to say yet and must not vote.
      if (entry.rating.gamesPlayed == 0) continue;

      final conf = confidenceFor(entry.rating);
      final rec = recencyFor(entry.lastPlayedAt, now);
      final key = entry.baseSportId;
      final held = bySport[key];
      if (held == null || conf * rec > held.conf * held.rec) {
        bySport[key] = (e: entry, conf: conf, rec: rec);
      }
    }
    if (bySport.isEmpty) return null;

    // Strength order. Ties broken on the better-evidenced rating, then on the
    // sport id so the same inputs always produce the same list — a composite
    // that reordered between rebuilds would make the breakdown untrustworthy
    // even while the headline number stayed put.
    final ranked = bySport.values.toList()
      ..sort((a, b) {
        final byRating = b.e.rating.rating.compareTo(a.e.rating.rating);
        if (byRating != 0) return byRating;
        final byEvidence = (b.conf * b.rec).compareTo(a.conf * a.rec);
        if (byEvidence != 0) return byEvidence;
        return a.e.baseSportId.compareTo(b.e.baseSportId);
      });

    final components = <OverallGlickoComponent>[];
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    var effectiveMatches = 0.0;

    for (var i = 0; i < ranked.length; i++) {
      final r = ranked[i];
      final rankFactor = math.pow(rankDecay, i).toDouble();
      final component = OverallGlickoComponent(
        sportId: r.e.baseSportId,
        rating: r.e.rating.rating,
        confidence: r.conf,
        recency: r.rec,
        rankFactor: rankFactor,
        matches: r.e.rating.gamesPlayed,
      );
      components.add(component);
      weightedSum += component.rating * component.weight;
      weightTotal += component.weight;
      effectiveMatches += r.e.rating.gamesPlayed * r.rec;
    }

    // Every sport carried a zero weight: each is either maximally uncertain
    // (RD still at 350) or decayed to nothing. There is a record here, but
    // nothing in it is worth blending, and dividing by zero to say so is not
    // an option.
    if (weightTotal <= 0) return null;

    final blend = weightedSum / weightTotal;
    final evidence = _evidenceWeight(effectiveMatches);

    return OverallGlicko(
      overall: Rating.defaultRating + (blend - Rating.defaultRating) * evidence,
      components: components,
      evidenceWeight: evidence,
      effectiveMatches: effectiveMatches,
    );
  }
}
