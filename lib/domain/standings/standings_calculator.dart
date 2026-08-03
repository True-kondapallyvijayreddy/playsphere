import '../../core/models/competition.dart';
import '../../core/models/draw_slot.dart';
import '../../core/models/fixture.dart';
import '../scoring/scoring_registry.dart';
import 'net_run_rate.dart';
import 'tiebreak.dart';

/// Computes a league table from played fixtures.
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
///
/// ## Separating teams that are level
///
/// Points alone rank almost nothing. The chain that breaks ties is per-sport
/// configuration ([Tiebreak]), because cricket separates on net run rate,
/// football on goal difference and a Swiss chess field on Buchholz — and a
/// table that applies the wrong one produces the wrong champion.
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

    // Head-to-head results, keyed "winner|loser", plus the drawn pairs.
    final headToHead = <String, int>{};
    // Which opponents each entrant has faced, for Buchholz and
    // Sonneborn-Berger.
    final opponents = <String, List<String>>{};
    final beaten = <String, List<String>>{};
    final drewWith = <String, List<String>>{};

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

      // A resulted fixture with no winner and not flagged a draw is
      // uninterpretable. Skip it entirely — crediting an appearance without an
      // outcome makes played stop equalling won + drawn + lost.
      final isDraw = fixture.isDraw;
      final aWon = fixture.winnerEntrantId == a.entrantId;
      final bWon = fixture.winnerEntrantId == b.entrantId;
      if (!isDraw && !aWon && !bWon) continue;

      a.played++;
      b.played++;

      opponents.putIfAbsent(a.entrantId, () => []).add(b.entrantId);
      opponents.putIfAbsent(b.entrantId, () => []).add(a.entrantId);

      if (isDraw) {
        a.drawn++;
        b.drawn++;
        a.points += competition.pointsForDraw;
        b.points += competition.pointsForDraw;
        drewWith.putIfAbsent(a.entrantId, () => []).add(b.entrantId);
        drewWith.putIfAbsent(b.entrantId, () => []).add(a.entrantId);
      } else if (aWon) {
        a.won++;
        b.lost++;
        a.points += competition.pointsForWin;
        b.points += competition.pointsForLoss;
        headToHead['${a.entrantId}|${b.entrantId}'] =
            (headToHead['${a.entrantId}|${b.entrantId}'] ?? 0) + 1;
        beaten.putIfAbsent(a.entrantId, () => []).add(b.entrantId);
      } else {
        b.won++;
        a.lost++;
        b.points += competition.pointsForWin;
        a.points += competition.pointsForLoss;
        headToHead['${b.entrantId}|${a.entrantId}'] =
            (headToHead['${b.entrantId}|${a.entrantId}'] ?? 0) + 1;
        beaten.putIfAbsent(b.entrantId, () => []).add(a.entrantId);
      }

      final ctx = fixture.scoringContext();
      final outcome = ScoringRegistry.resolve(fixture.scoringPluginKey)
          .outcome(fixture.scoreState, ctx);
      a.scoreFor += outcome.scoreForA;
      a.scoreAgainst += outcome.scoreForB;
      b.scoreFor += outcome.scoreForB;
      b.scoreAgainst += outcome.scoreForA;

      _accumulateNrr(fixture: fixture, ctx: ctx, a: a, b: b);
    }

    // Buchholz and Sonneborn-Berger are functions of everyone else's final
    // points, so they can only be computed once every row is complete.
    for (final row in rows.values) {
      var buchholz = 0;
      for (final id in opponents[row.entrantId] ?? const <String>[]) {
        buchholz += rows[id]?.points ?? 0;
      }
      row.buchholz = buchholz;

      var sb = 0.0;
      for (final id in beaten[row.entrantId] ?? const <String>[]) {
        sb += rows[id]?.points ?? 0;
      }
      for (final id in drewWith[row.entrantId] ?? const <String>[]) {
        sb += (rows[id]?.points ?? 0) / 2;
      }
      row.sonnebornBerger = sb;
    }

    final chain = Tiebreak.parse(
      competition.tiebreakChain,
      competition.sportId,
    );

    final table = rows.values.toList()
      ..sort((x, y) => _compare(x, y, chain, headToHead));

    return [
      for (var i = 0; i < table.length; i++) table[i].toStanding(rank: i + 1),
    ];
  }

  /// Adds one cricket fixture's innings to both entrants' running rate.
  void _accumulateNrr({
    required Fixture fixture,
    required dynamic ctx,
    required _Row a,
    required _Row b,
  }) {
    final innings = NetRunRate.inningsOf(
      scoreState: fixture.scoreState,
      ctx: ctx,
      pluginKey: fixture.scoringPluginKey,
    );
    if (innings.isEmpty) return;

    final ballsPerOver = ctx.intConfig('ballsPerOver', 6) as int;

    for (final inn in innings) {
      final batting = inn.battingSide == 'a' ? a : b;
      final bowling = inn.battingSide == 'a' ? b : a;
      final overs = inn.oversForRate(ballsPerOver);
      if (overs <= 0) continue;
      batting.nrr.addBatting(inn.runs.toDouble(), overs);
      bowling.nrr.addBowling(inn.runs.toDouble(), overs);
    }
  }

  int _compare(
    _Row x,
    _Row y,
    List<Tiebreak> chain,
    Map<String, int> headToHead,
  ) {
    // Points always come first; the chain only separates rows already level.
    final byPoints = y.points.compareTo(x.points);
    if (byPoints != 0) return byPoints;

    for (final rule in chain) {
      final cmp = switch (rule) {
        Tiebreak.headToHead => _headToHead(x, y, headToHead),
        Tiebreak.netRunRate => _compareNullableDesc(x.nrr.value, y.nrr.value),
        Tiebreak.scoreDifference => y.difference.compareTo(x.difference),
        Tiebreak.scoreFor => y.scoreFor.compareTo(x.scoreFor),
        Tiebreak.wins => y.won.compareTo(x.won),
        Tiebreak.buchholz => y.buchholz.compareTo(x.buchholz),
        Tiebreak.sonnebornBerger =>
          y.sonnebornBerger.compareTo(x.sonnebornBerger),
        // Fewest played ranks the team with games in hand higher.
        Tiebreak.fewestPlayed => x.played.compareTo(y.played),
        Tiebreak.name => x.displayName
            .toLowerCase()
            .compareTo(y.displayName.toLowerCase()),
      };
      if (cmp != 0) return cmp;
    }
    // Stable rather than arbitrary when two rows are genuinely identical, so
    // the table does not reshuffle itself between rebuilds.
    return x.displayName.toLowerCase().compareTo(y.displayName.toLowerCase());
  }

  /// One table per group, for a groups+knockout draw.
  ///
  /// A single table across such a draw is meaningless — Group A's teams have
  /// never played Group B's — and it was also all this class could produce,
  /// because the fixtures carried no group tag. That is the whole reason a
  /// groups+knockout competition could never work out who had qualified.
  ///
  /// Each group's rows are the entrants who actually appear in that group's
  /// fixtures, so an entrant is never listed in a group they were not drawn
  /// into.
  Map<String, List<Standing>> computeGroups({
    required Competition competition,
    required List<Entrant> entrants,
    required List<Fixture> fixtures,
  }) {
    final byGroup = <String, List<Fixture>>{};
    for (final f in fixtures) {
      final g = f.groupId;
      if (f.bracket != Bracket.group || g == null) continue;
      byGroup.putIfAbsent(g, () => []).add(f);
    }

    final byId = {for (final e in entrants) e.id: e};
    final tables = <String, List<Standing>>{};

    for (final entry in byGroup.entries) {
      final ids = <String>{};
      for (final f in entry.value) {
        if (f.entrantAId.isNotEmpty) ids.add(f.entrantAId);
        if (f.entrantBId.isNotEmpty) ids.add(f.entrantBId);
      }
      tables[entry.key] = compute(
        competition: competition,
        entrants: [
          for (final id in ids)
            if (byId[id] != null) byId[id]!,
        ],
        fixtures: entry.value,
      );
    }

    return tables;
  }

  /// Whether every match in [groupId] has a result.
  ///
  /// A group table is only safe to promote from once it is final. Resolving a
  /// qualifier from a half-played group would name someone who is top on
  /// Saturday morning and fourth by Saturday night — and having already been
  /// written into a quarter-final, they would stay there.
  bool isGroupComplete(String groupId, List<Fixture> fixtures) {
    final inGroup = fixtures.where(
      (f) => f.bracket == Bracket.group && f.groupId == groupId,
    );
    if (inGroup.isEmpty) return false;
    return inGroup.every((f) => f.status.isResulted);
  }

  int _headToHead(_Row x, _Row y, Map<String, int> h2h) {
    final xBeatY = h2h['${x.entrantId}|${y.entrantId}'] ?? 0;
    final yBeatX = h2h['${y.entrantId}|${x.entrantId}'] ?? 0;
    return yBeatX.compareTo(xBeatY);
  }

  /// Descending, with "no value" sorting last rather than as zero. A team
  /// with no completed innings has no net run rate; treating that as 0.000
  /// would rank it above every team with a negative one.
  int _compareNullableDesc(double? x, double? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
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
  int buchholz = 0;
  double sonnebornBerger = 0;

  final NrrTally nrr = NrrTally();

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
        netRunRate: nrr.value,
        buchholz: buchholz,
      );
}
