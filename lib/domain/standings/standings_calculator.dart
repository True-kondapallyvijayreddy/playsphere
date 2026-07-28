import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import '../scoring/scoring_registry.dart';

/// Computes a league table from played fixtures.
///
/// Ported from the pre-Firebase prototype's `StandingsCalculatorService`,
/// which had the ordering rules right — points, then score difference, then
/// wins — and was lost when the app was rebuilt on Firebase. Rewritten against
/// the current [Fixture] and [Standing] models and against per-competition
/// points configuration rather than a separate config entity.
///
/// ## Why this is computed, not stored
///
/// A standings row is a pure function of the fixtures that produced it. Storing
/// it would mean a second write on every result, a second thing to keep in
/// step, and a table that can silently disagree with the matches it claims to
/// summarise. Deriving it means the table cannot drift, costs no extra reads —
/// the fixtures are already streamed for the match list — and needs no
/// security rule of its own.
///
/// When results become server-authoritative (a Cloud Function, per the README's
/// known gaps) this same function should run there and persist to
/// `standings/{entrantId}`, so a hostile client cannot publish a false table.
/// Until then, deriving on the client is strictly more honest than persisting
/// a number the client computed.
///
/// ## Scores
///
/// Score for/against comes from the sport's plugin via
/// [ScoringPlugin.outcome], so "score" means goals in football, sets in
/// badminton and runs in cricket — whatever that sport counts. This is why the
/// fixture carries its own frozen `scoringConfig`: without it a volleyball
/// match would be totted up under badminton's rules.
class StandingsCalculator {
  const StandingsCalculator();

  /// Builds the table for [competition] from [fixtures].
  ///
  /// [entrants] fixes the rows: every entrant appears even with no matches
  /// played, because a table that hides the team who has not played yet reads
  /// as though they were never entered.
  List<Standing> compute({
    required Competition competition,
    required List<Entrant> entrants,
    required List<Fixture> fixtures,
  }) {
    final rows = <String, _Row>{
      for (final e in entrants)
        e.id: _Row(entrantId: e.id, displayName: e.displayName),
    };

    for (final fixture in fixtures) {
      // Only decided matches count. A live or abandoned match must not move
      // the table — an abandoned game is not a draw, and treating it as one
      // silently awards a point nobody earned.
      if (!fixture.status.isResulted) continue;

      final a = rows[fixture.entrantAId];
      final b = rows[fixture.entrantBId];
      // A fixture against a bye, or one whose entrant was withdrawn after the
      // draw, has no row to credit. Skip rather than inventing one.
      if (a == null || b == null) continue;

      a.played++;
      b.played++;

      if (fixture.isDraw) {
        a.drawn++;
        b.drawn++;
        a.points += competition.pointsForDraw;
        b.points += competition.pointsForDraw;
      } else if (fixture.winnerEntrantId == a.entrantId) {
        a.won++;
        b.lost++;
        a.points += competition.pointsForWin;
        b.points += competition.pointsForLoss;
      } else if (fixture.winnerEntrantId == b.entrantId) {
        b.won++;
        a.lost++;
        b.points += competition.pointsForWin;
        a.points += competition.pointsForLoss;
      } else {
        // Resulted but with no recorded winner and not flagged a draw. Count
        // the appearance and nothing else rather than guessing an outcome.
        continue;
      }

      final outcome = ScoringRegistry.resolve(fixture.scoringPluginKey)
          .outcome(fixture.scoreState, fixture.scoringContext());
      a.scoreFor += outcome.scoreForA;
      a.scoreAgainst += outcome.scoreForB;
      b.scoreFor += outcome.scoreForB;
      b.scoreAgainst += outcome.scoreForA;
    }

    final table = rows.values.toList()
      ..sort((x, y) {
        // Points, then score difference, then wins — the ordering used by
        // effectively every league. Falling back to name keeps the order
        // stable when two rows are genuinely identical, so the table does not
        // reshuffle itself between rebuilds.
        final byPoints = y.points.compareTo(x.points);
        if (byPoints != 0) return byPoints;
        final byDiff = y.difference.compareTo(x.difference);
        if (byDiff != 0) return byDiff;
        final byWins = y.won.compareTo(x.won);
        if (byWins != 0) return byWins;
        return x.displayName.toLowerCase().compareTo(y.displayName.toLowerCase());
      });

    return [
      for (var i = 0; i < table.length; i++) table[i].toStanding(rank: i + 1),
    ];
  }
}

class _Row {
  _Row({required this.entrantId, required this.displayName});

  final String entrantId;
  final String displayName;

  int played = 0;
  int won = 0;
  int drawn = 0;
  int lost = 0;
  int points = 0;
  int scoreFor = 0;
  int scoreAgainst = 0;

  int get difference => scoreFor - scoreAgainst;

  Standing toStanding({required int rank}) => Standing(
        entrantId: entrantId,
        displayName: displayName,
        played: played,
        won: won,
        drawn: drawn,
        lost: lost,
        points: points,
        scoreFor: scoreFor,
        scoreAgainst: scoreAgainst,
        rank: rank,
      );
}
