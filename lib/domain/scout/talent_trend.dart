/// Improvement over time — the signal talent *discovery* runs on, as opposed
/// to the signal talent *search* runs on.
///
/// ## Why a rating percentile was never enough
///
/// `ScoutRepository.searchCandidates` answers "who is good at cricket in this
/// district", ranked by rating percentile. That finds the players everybody
/// already knows about. §6 of the product vision asks for something else: the
/// player nobody has noticed yet, whose results are *climbing*. A percentile
/// cannot express that — it is a snapshot, and a snapshot has no direction.
///
/// The distinction matters most for exactly the population the platform
/// exists to reach. A fifteen-year-old in a village who has gone from losing
/// every match to beating the district's established players is, on a
/// percentile leaderboard, still somewhere in the middle — indistinguishable
/// from a player who has sat in the middle for three years. On a *trend*
/// leaderboard she is first.
///
/// ## Why this file is pure
///
/// Everything here is arithmetic over plain values with an injected `now`.
/// No Firestore, no clock, no I/O. The scheduled function that builds the
/// public boards (`functions/talent.js`) reimplements the same formula in
/// JavaScript, and `test/talent_trend_test.dart` pins the numbers both sides
/// must produce — see [RisingSignal] for why that duplication is deliberate
/// rather than something to factor away.
library;

import '../rating/glicko2.dart' show Rating;

/// One reading of a player's rating, taken the moment a match settled.
///
/// These come from the bounded trail written onto the rating document by
/// `onMatchSettled` (see `functions/index.js`). They are deliberately *not* a
/// full event log: a career's worth of rating changes is a real collection
/// with real cost, and the only question the boards ask is "how much has this
/// moved lately", which a short trail answers exactly.
class RatingSnapshot {
  const RatingSnapshot({required this.rating, required this.at});

  final double rating;
  final DateTime at;

  Map<String, Object?> toMap() => {
        'r': rating,
        't': at.toUtc().toIso8601String(),
      };

  /// Decodes a trail entry. Tolerant of a missing or malformed row because
  /// the trail is written by a Cloud Function and read by a client that may
  /// be older than it: an unreadable entry should cost one data point, never
  /// a crashed discovery feed.
  static RatingSnapshot? fromMap(Object? raw) {
    if (raw is! Map) return null;
    // Pattern-matched rather than cast: a trail row is written by a Cloud
    // Function and read by a client that may be older or newer than it, and
    // `as num?` throws on a wrongly-typed value instead of returning null —
    // which would take down the whole discovery feed for one bad row.
    final rating = raw['r'];
    if (rating is! num) return null;
    final at = raw['t'];
    final parsed = at is String ? DateTime.tryParse(at) : null;
    if (parsed == null) return null;
    return RatingSnapshot(rating: rating.toDouble(), at: parsed);
  }
}

/// A player's recent rating readings, oldest first.
///
/// ## The bound, and what it costs
///
/// `onMatchSettled` keeps the most recent [maxLength] snapshots and drops the
/// rest. For a player who plays weekly that is roughly five months of
/// history, comfortably longer than the 90-day window the boards use. For a
/// player in a daily league it is three weeks, and a 90-day delta measured
/// against a trail that only reaches back three weeks is measuring three
/// weeks — [deltaOver] reports [TrendSpan.truncated] when that happens rather
/// than quietly presenting the shorter interval as the full window.
class RatingTrail {
  const RatingTrail(this.snapshots);

  static const empty = RatingTrail([]);

  /// How many snapshots the trail keeps. Mirrored by `TRAIL_LENGTH` in
  /// `functions/index.js` — the two must agree, and `talent_trend_test.dart`
  /// is where that agreement is asserted.
  static const maxLength = 24;

  /// Oldest first. The last element is the player's current rating.
  final List<RatingSnapshot> snapshots;

  bool get isEmpty => snapshots.isEmpty;

  static RatingTrail fromList(Object? raw) {
    if (raw is! List) return empty;
    final parsed = <RatingSnapshot>[];
    for (final e in raw) {
      final snap = RatingSnapshot.fromMap(e);
      if (snap != null) parsed.add(snap);
    }
    parsed.sort((a, b) => a.at.compareTo(b.at));
    return RatingTrail(parsed);
  }

  /// How many snapshots fall strictly inside [window] measured back from
  /// [now] — that is, how many matches contributed to the delta.
  int matchesWithin(Duration window, {required DateTime now}) {
    final cutoff = now.subtract(window);
    return snapshots.where((s) => s.at.isAfter(cutoff)).length;
  }

  /// The rating change across [window], and how trustworthy that interval is.
  ///
  /// ## Where the baseline comes from
  ///
  /// The correct baseline is the last reading taken *before* the window
  /// opened: anchoring on the first reading *inside* it would silently
  /// discard the gain from the first match of the window, which for a player
  /// with four matches in ninety days throws away a quarter of the signal.
  ///
  /// When no such reading exists the trail simply does not reach back far
  /// enough, and the honest baseline is the oldest snapshot held. That case
  /// returns [TrendSpan.truncated] so a caller can tell "improved 80 points
  /// over 90 days" from "improved 80 points over as much of 90 days as we can
  /// see", which are different claims.
  RatingDelta deltaOver(Duration window, {required DateTime now}) {
    if (snapshots.isEmpty) {
      return const RatingDelta(points: 0, matches: 0, span: TrendSpan.absent);
    }
    final cutoff = now.subtract(window);
    final latest = snapshots.last;

    RatingSnapshot? baseline;
    for (final s in snapshots) {
      if (s.at.isAfter(cutoff)) break;
      baseline = s;
    }

    final span = baseline == null ? TrendSpan.truncated : TrendSpan.full;
    // With no pre-window reading, the oldest snapshot we hold is the baseline
    // — and it is itself inside the window, so it must not also be counted as
    // one of the matches that moved the rating away from it.
    final anchor = baseline ?? snapshots.first;
    final matches = snapshots.where((s) => s.at.isAfter(anchor.at)).length;

    return RatingDelta(
      points: latest.rating - anchor.rating,
      matches: matches,
      span: span,
    );
  }
}

/// How much of the requested window a [RatingDelta] actually covers.
enum TrendSpan {
  /// The trail reached back past the start of the window. The delta means
  /// what it says.
  full,

  /// The trail begins inside the window — the delta covers a shorter
  /// interval than asked for. Still real, just not the whole period.
  truncated,

  /// No snapshots at all. Nothing can be said about direction.
  absent,
}

/// A rating change over some interval, with the sample behind it.
class RatingDelta {
  const RatingDelta({
    required this.points,
    required this.matches,
    required this.span,
  });

  /// Glicko points gained (positive) or lost (negative).
  final double points;

  /// Matches that contributed. Never counts the baseline reading itself.
  final int matches;

  final TrendSpan span;
}

/// The ranked "is this player rising" number, and everything that went into
/// it.
///
/// ## The formula, and why each term is there
///
/// ```
/// score = ratingDelta × confidence
/// confidence = matches / (matches + shrinkage)
/// ```
///
/// **`ratingDelta` and not the rating itself.** A board ranked on rating is
/// the leaderboard that already exists. Ranking on the change is what makes
/// this discovery rather than a second view of the same list — and it is what
/// lets an unknown player outrank an established one, which is the entire
/// point.
///
/// **`confidence`, because two matches prove nothing.** Glicko will happily
/// move a provisional player 200 points for beating one strong opponent, and
/// without a sample-size term that single upset would top every board in the
/// state. Shrinking by `matches / (matches + k)` costs a heavy sample almost
/// nothing (12 matches keeps 80% of the delta at `k = 3`) while cutting a
/// one-match spike to a quarter. It is the standard small-sample shrinkage,
/// chosen over a hard minimum alone because a cliff at "5 matches" would make
/// a player's board position lurch the moment they hit it.
///
/// [minMatches] is *also* applied, as an eligibility gate rather than a
/// weight: below it, [eligible] is false and the player is left off the board
/// entirely. Shrinkage handles the ranking; the gate handles the claim. Being
/// named on a public "rising talent" board is a statement about somebody, and
/// three matches is the floor at which the platform is willing to make it.
///
/// **Deviation is reported, not multiplied in.** Glicko's RD already governs
/// how far a rating moves per match, so folding it into the score would
/// penalise uncertainty twice. It is surfaced as [provisional] so a scout
/// reading the board can see the difference between a settled climb and a
/// volatile one.
///
/// ## Why the same maths also lives in JavaScript
///
/// `functions/talent.js` computes these boards server-side, because the
/// alternative is every client scanning every player in a district — which
/// `firestore.rules` correctly refuses to allow. So the formula exists twice,
/// once here and once there. That is a real duplication and it is the lesser
/// evil: the alternative is a client that cannot explain its own leaderboard.
/// `test/talent_trend_test.dart` fixes the expected outputs for a set of
/// inputs, and `functions/talent.js` carries the same table in a comment, so
/// a change to one that is not mirrored in the other fails a test rather than
/// producing two subtly different rankings.
class RisingSignal {
  const RisingSignal({
    required this.delta,
    required this.score,
    required this.confidence,
    required this.eligible,
    required this.provisional,
  });

  /// Sample-size shrinkage constant. See the class doc.
  static const shrinkage = 3.0;

  /// Fewest matches in the window before a player may be *named* on a board.
  static const minMatches = 3;

  /// Above this Glicko RD a rating is still finding its level, and the climb
  /// is flagged [provisional] on the board rather than presented as settled.
  /// Glicko's default RD for an unrated player is 350; a player with a couple
  /// of dozen results sits well under 100.
  static const provisionalDeviation = 110.0;

  /// The default measurement window. Ninety days is long enough for a club
  /// player who plays fortnightly to register six results, and short enough
  /// that "rising" still means "now" rather than "at some point last year".
  static const window = Duration(days: 90);

  final RatingDelta delta;

  /// The ranked number. Positive means improving; a board keeps only the top
  /// slice of these.
  final double score;

  /// `matches / (matches + shrinkage)`, in 0..1.
  final double confidence;

  /// Whether this player may appear on a board at all.
  final bool eligible;

  /// Whether the underlying rating is still unsettled ([provisionalDeviation]).
  final bool provisional;

  /// Computes the signal for one player in one sport.
  ///
  /// [rating] supplies only the current deviation — the *level* deliberately
  /// plays no part in the score, for the reason given in the class doc.
  factory RisingSignal.from({
    required RatingTrail trail,
    required Rating rating,
    required DateTime now,
    Duration window = RisingSignal.window,
  }) {
    final delta = trail.deltaOver(window, now: now);
    final confidence = delta.matches / (delta.matches + shrinkage);
    return RisingSignal(
      delta: delta,
      score: delta.points * confidence,
      confidence: confidence,
      eligible: delta.matches >= minMatches && delta.points > 0,
      provisional: rating.deviation > provisionalDeviation,
    );
  }
}

/// A club's form over the same window the player boards use.
///
/// ## Why this is win rate and not a rating
///
/// Players carry a Glicko rating, so the new information about a player is
/// the *change* in it. Clubs carry no rating at all — nothing in the product
/// rates a team — so win rate has to serve as both the level and, compared
/// against the club's own history, the direction.
///
/// That is why [score] blends the two terms where [RisingSignal] uses one:
///
/// ```
/// score = confidence × (recentWinRate + momentum)
/// momentum = recentWinRate − lifetimeWinRate
/// ```
///
/// The vision asks for two different clubs to be findable here. One is the
/// remote village team that has quietly won 27 of 32 — dominant, with no
/// upward trend to show because it was always dominant. The other is the club
/// that has just turned a corner. `recentWinRate` finds the first, `momentum`
/// finds the second, and summing them lets a club qualify on either. A pure
/// momentum score would rank the first club at zero, which is the outcome the
/// donation and sponsorship features exist to prevent.
///
/// A club with no matches outside the window has `lifetimeWinRate ==
/// recentWinRate` and therefore zero momentum, ranking purely on dominance.
/// That is correct: a brand-new club has no trend, only a record.
class TeamFormSignal {
  const TeamFormSignal({
    required this.matchesInWindow,
    required this.winsInWindow,
    required this.lifetimeMatches,
    required this.lifetimeWins,
    required this.recentWinRate,
    required this.lifetimeWinRate,
    required this.momentum,
    required this.confidence,
    required this.score,
    required this.eligible,
  });

  /// Clubs play far less often than the players in them — an inter-club
  /// challenge is a weekend event, not a weekly one — so the floor is lower
  /// than [RisingSignal.minMatches] would be over the same period.
  static const minMatches = 3;

  /// Same shrinkage role as [RisingSignal.shrinkage], on the same reasoning.
  static const shrinkage = 2.0;

  final int matchesInWindow;
  final int winsInWindow;
  final int lifetimeMatches;
  final int lifetimeWins;

  /// 0..1.
  final double recentWinRate;
  final double lifetimeWinRate;

  /// `recentWinRate − lifetimeWinRate`. Negative for a club in decline.
  final double momentum;

  final double confidence;
  final double score;
  final bool eligible;

  factory TeamFormSignal.from({
    required int matchesInWindow,
    required int winsInWindow,
    required int lifetimeMatches,
    required int lifetimeWins,
  }) {
    final recent = matchesInWindow == 0 ? 0.0 : winsInWindow / matchesInWindow;
    // Falls back to the recent rate rather than to zero when there is no
    // history at all: a zero lifetime rate for a club that has never played
    // outside the window would manufacture a large positive momentum out of
    // an absence of data, ranking every new club above every established one.
    final lifetime =
        lifetimeMatches == 0 ? recent : lifetimeWins / lifetimeMatches;
    final confidence = matchesInWindow / (matchesInWindow + shrinkage);
    final momentum = recent - lifetime;
    return TeamFormSignal(
      matchesInWindow: matchesInWindow,
      winsInWindow: winsInWindow,
      lifetimeMatches: lifetimeMatches,
      lifetimeWins: lifetimeWins,
      recentWinRate: recent,
      lifetimeWinRate: lifetime,
      momentum: momentum,
      confidence: confidence,
      score: confidence * (recent + momentum),
      eligible: matchesInWindow >= minMatches,
    );
  }
}
