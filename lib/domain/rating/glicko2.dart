import 'dart:math' as math;

/// A player's rating in one sport.
///
/// Glicko-2 rather than Elo, per the spec, and the reason is grassroots
/// reality rather than sophistication: Elo tells you a number, Glicko-2 tells
/// you how much to believe it. A player who has played twice has a wildly
/// uncertain rating, and Elo cannot express that — it moves them the same
/// amount as someone with two hundred games, so early results whipsaw the
/// table and nobody trusts it. The rating deviation models that uncertainty,
/// converges fast on few games, and grows again when someone stops playing.
class Rating {
  const Rating({
    this.rating = defaultRating,
    this.deviation = defaultDeviation,
    this.volatility = defaultVolatility,
    this.gamesPlayed = 0,
    this.updatedAt,
  });

  /// Glickman's defaults for an unrated player.
  static const double defaultRating = 1500;
  static const double defaultDeviation = 350;
  static const double defaultVolatility = 0.06;

  final double rating;

  /// How uncertain that rating is. Reported to users as a confidence band of
  /// roughly ±2·deviation rather than as a bare number.
  final double deviation;

  final double volatility;
  final int gamesPlayed;

  /// When the server last settled this rating, as it stamps on every write in
  /// `onMatchSettled`.
  ///
  /// Read-only here — [toMap] does not emit it, because nothing on the client
  /// writes a rating any more and a client-supplied "last settled" time would
  /// be a claim about the server's own bookkeeping. It exists so
  /// [OverallGlickoEngine] has a recency signal for a sport that moved a
  /// rating without writing a career line, which is exactly what a rated
  /// walkover does.
  final DateTime? updatedAt;

  /// A rating stops being provisional once it is known well enough to be
  /// worth showing without a caveat. 110 is a common threshold and matches
  /// roughly a dozen games at this scale.
  bool get isProvisional => deviation > 110;

  /// The interval a player's true strength most likely sits in.
  (double low, double high) get confidenceInterval =>
      (rating - 2 * deviation, rating + 2 * deviation);

  /// Human band, because a raw number means nothing to someone who has just
  /// played their first match. The spec asks for tiers by default with the
  /// number available on the profile.
  String get tier => switch (rating) {
        < 1200 => 'Beginner',
        < 1400 => 'Developing',
        < 1600 => 'Club',
        < 1800 => 'Strong',
        < 2000 => 'District',
        < 2200 => 'State',
        _ => 'Elite',
      };

  Rating copyWith({
    double? rating,
    double? deviation,
    double? volatility,
    int? gamesPlayed,
    DateTime? updatedAt,
  }) =>
      Rating(
        rating: rating ?? this.rating,
        deviation: deviation ?? this.deviation,
        volatility: volatility ?? this.volatility,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'rating': rating,
        'deviation': deviation,
        'volatility': volatility,
        'gamesPlayed': gamesPlayed,
      };

  /// [updatedAt] is passed in already decoded rather than read from [d], for
  /// the reason `CareerStats.fromMap` does the same with its own timestamp:
  /// this file is pure domain and knows nothing about Firestore's `Timestamp`.
  factory Rating.fromMap(Map<String, dynamic>? d, {DateTime? updatedAt}) {
    if (d == null) return Rating(updatedAt: updatedAt);
    double num_(Object? v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    return Rating(
      rating: num_(d['rating'], defaultRating),
      deviation: num_(d['deviation'], defaultDeviation),
      volatility: num_(d['volatility'], defaultVolatility),
      gamesPlayed: (d['gamesPlayed'] as num?)?.toInt() ?? 0,
      updatedAt: updatedAt,
    );
  }
}

/// One result to rate against.
class RatingGame {
  const RatingGame({
    required this.opponent,
    required this.score,
    this.weight = 1.0,
  });

  final Rating opponent;

  /// 1 win, 0.5 draw, 0 loss.
  final double score;

  /// How much this result should count.
  ///
  /// A team sport cannot move eleven ratings by the team's result alone —
  /// that rates the side, not the player. The caller weights each player's
  /// share by their contribution (cricket MVP points, minutes played), so a
  /// substitute who came on for five minutes is not credited with the win as
  /// heavily as the player who scored.
  final double weight;
}

/// Glicko-2, following Glickman's published algorithm.
///
/// Ratings are updated in *rating periods* rather than per match. Doing it per
/// match makes the order of results inside a weekend change the outcome, which
/// is indefensible when a club plays four games on a Sunday.
class Glicko2 {
  const Glicko2({this.systemConstant = 0.5});

  /// Glickman's τ. Constrains how much volatility can move; smaller is more
  /// conservative. 0.3–1.2 is the sane range and 0.5 suits amateur sport,
  /// where genuine step changes in ability are rarer than upsets.
  final double systemConstant;

  static const double _scale = 173.7178; // Glicko → Glicko-2 scale factor
  static const double _epsilon = 0.000001;

  double _g(double phi) => 1 / math.sqrt(1 + 3 * phi * phi / (math.pi * math.pi));

  double _e(double mu, double muJ, double phiJ) =>
      1 / (1 + math.exp(-_g(phiJ) * (mu - muJ)));

  /// Applies one rating period's worth of results.
  ///
  /// With no games the rating is unchanged but the deviation GROWS: a player
  /// who has not played for months is genuinely less predictable, and a
  /// system that pretends otherwise lets a stale rating sit at the top of a
  /// leaderboard indefinitely.
  Rating rate(Rating player, List<RatingGame> games) {
    final mu = (player.rating - Rating.defaultRating) / _scale;
    final phi = player.deviation / _scale;
    final sigma = player.volatility;

    if (games.isEmpty) {
      final phiStar = math.sqrt(phi * phi + sigma * sigma);
      return player.copyWith(
        deviation: math.min(phiStar * _scale, Rating.defaultDeviation),
      );
    }

    // Estimated variance of the player's rating, from the games alone.
    var vInv = 0.0;
    var deltaSum = 0.0;
    for (final game in games) {
      final muJ = (game.opponent.rating - Rating.defaultRating) / _scale;
      final phiJ = game.opponent.deviation / _scale;
      final g = _g(phiJ);
      final e = _e(mu, muJ, phiJ);
      vInv += game.weight * g * g * e * (1 - e);
      deltaSum += game.weight * g * (game.score - e);
    }
    if (vInv <= 0) return player;

    final v = 1 / vInv;
    final delta = v * deltaSum;

    final sigmaPrime = _newVolatility(
      phi: phi,
      sigma: sigma,
      v: v,
      delta: delta,
    );

    final phiStar = math.sqrt(phi * phi + sigmaPrime * sigmaPrime);
    final phiPrime = 1 / math.sqrt(1 / (phiStar * phiStar) + 1 / v);
    final muPrime = mu + phiPrime * phiPrime * deltaSum;

    return Rating(
      rating: muPrime * _scale + Rating.defaultRating,
      deviation: phiPrime * _scale,
      volatility: sigmaPrime,
      gamesPlayed: player.gamesPlayed + games.length,
    );
  }

  /// Illinois-variant regula falsi, as Glickman specifies. Iterative because
  /// the volatility equation has no closed form.
  double _newVolatility({
    required double phi,
    required double sigma,
    required double v,
    required double delta,
  }) {
    final a = math.log(sigma * sigma);
    final tau = systemConstant;

    double f(double x) {
      final ex = math.exp(x);
      final phi2 = phi * phi;
      final num = ex * (delta * delta - phi2 - v - ex);
      final den = 2 * math.pow(phi2 + v + ex, 2);
      return num / den - (x - a) / (tau * tau);
    }

    var bigA = a;
    double bigB;
    if (delta * delta > phi * phi + v) {
      bigB = math.log(delta * delta - phi * phi - v);
    } else {
      var k = 1;
      while (f(a - k * tau) < 0 && k < 100) {
        k++;
      }
      bigB = a - k * tau;
    }

    var fA = f(bigA);
    var fB = f(bigB);
    var guard = 0;
    while ((bigB - bigA).abs() > _epsilon && guard < 200) {
      final c = bigA + (bigA - bigB) * fA / (fB - fA);
      final fC = f(c);
      if (fC * fB <= 0) {
        bigA = bigB;
        fA = fB;
      } else {
        fA = fA / 2;
      }
      bigB = c;
      fB = fC;
      guard++;
    }
    return math.exp(bigA / 2);
  }

  /// Guards against a single result moving a rating implausibly far, which is
  /// the signature of a fabricated match rather than a genuine upset.
  static bool isImplausibleSwing(Rating before, Rating after,
          {double threshold = 80}) =>
      (after.rating - before.rating).abs() > threshold;
}
