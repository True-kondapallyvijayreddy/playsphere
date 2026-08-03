/// How a league separates two teams level on points.
///
/// The chain is configuration, not code, because it genuinely differs by
/// sport and by league: cricket goes to net run rate, football to goal
/// difference, a Swiss chess event to Buchholz, and a school league may
/// simply want head-to-head first. §9 asks for exactly this.
enum Tiebreak {
  /// Result between the tied teams. Applied first in most federation rules.
  headToHead('head_to_head', 'Head to head'),

  /// Net run rate — cricket only.
  netRunRate('net_run_rate', 'Net run rate'),

  /// Goals/points for minus against.
  scoreDifference('score_difference', 'Score difference'),

  /// Goals/points scored, ignoring those conceded.
  scoreFor('score_for', 'Score for'),

  wins('wins', 'Wins'),

  /// Sum of the scores of everyone a team has played — the standard Swiss
  /// tiebreak, and the one §9 names for large chess and table-tennis fields.
  buchholz('buchholz', 'Buchholz'),

  /// Sum of the scores of the opponents a team actually beat, plus half for
  /// those it drew. Discriminates better than Buchholz at the top of a table.
  sonnebornBerger('sonneborn_berger', 'Sonneborn-Berger'),

  /// Fewest matches played — used where a table is shown mid-season.
  fewestPlayed('fewest_played', 'Fewest played'),

  /// Rank the tied teams by a table built from **only the matches they played
  /// against each other**, recursing if that still leaves some of them level.
  ///
  /// This is FIBA's and FIVB's rule and it is genuinely different from
  /// [headToHead], which only compares two rows. When three teams tie, "who
  /// beat whom" has no answer as a pairwise question — A beat B, B beat C, C
  /// beat A — and the sport's actual rule is to build a mini-league of those
  /// three and separate them inside it. Applying a flat chain over the full
  /// table instead gives a different, wrong answer.
  miniLeague('mini_league', 'Results between tied teams'),

  /// Sets won ÷ sets lost. Volleyball's second criterion, after match points
  /// and before points ratio.
  ///
  /// A ratio, not a difference: 3 sets to 0 across two matches is a better
  /// record than 30 to 27, and a difference cannot tell them apart.
  setsRatio('sets_ratio', 'Sets ratio'),

  /// Points won ÷ points lost, across every set played. Volleyball's third
  /// criterion, and the one that usually settles it.
  pointsRatio('points_ratio', 'Points ratio'),

  /// Last resort so the order is stable rather than arbitrary.
  name('name', 'Name');

  const Tiebreak(this.wire, this.label);

  final String wire;
  final String label;

  static Tiebreak fromWire(String? w) => Tiebreak.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => Tiebreak.scoreDifference,
      );

  /// The chain a sport uses unless the competition names its own.
  static List<Tiebreak> defaultsFor(String sportId) => switch (sportId) {
        'cricket' => const [
            Tiebreak.headToHead,
            Tiebreak.netRunRate,
            Tiebreak.wins,
            Tiebreak.name,
          ],
        'chess' => const [
            Tiebreak.buchholz,
            Tiebreak.sonnebornBerger,
            Tiebreak.headToHead,
            Tiebreak.name,
          ],
        // FIVB: match points, then sets ratio, then points ratio, then the
        // results between the tied teams.
        'volleyball' => const [
            Tiebreak.setsRatio,
            Tiebreak.pointsRatio,
            Tiebreak.miniLeague,
            Tiebreak.name,
          ],
        // FIBA classifies a tie from the matches among the tied teams only,
        // recursively, before anything else.
        'basketball' => const [
            Tiebreak.miniLeague,
            Tiebreak.scoreDifference,
            Tiebreak.scoreFor,
            Tiebreak.name,
          ],
        _ => const [
            Tiebreak.headToHead,
            Tiebreak.scoreDifference,
            Tiebreak.scoreFor,
            Tiebreak.wins,
            Tiebreak.name,
          ],
      };

  /// Parses a stored chain, falling back to the sport's default when the
  /// competition has not configured one.
  static List<Tiebreak> parse(Object? stored, String sportId) {
    if (stored is! List) return defaultsFor(sportId);
    final parsed = stored
        .whereType<String>()
        .map((s) => Tiebreak.values.where((t) => t.wire == s))
        .expand((e) => e)
        .toList();
    if (parsed.isEmpty) return defaultsFor(sportId);
    // Always terminate on something total, so sorting is deterministic.
    if (parsed.last != Tiebreak.name) parsed.add(Tiebreak.name);
    return parsed;
  }
}
