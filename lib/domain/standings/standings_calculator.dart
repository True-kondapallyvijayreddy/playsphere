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

    /// Replaces the competition's own tiebreak chain.
    ///
    /// Exists for exactly one caller: the mini-league in [_separate], which
    /// must run WITHOUT [Tiebreak.miniLeague] in the chain. A mini-table is
    /// already "the matches among these teams" — asking it to break its own
    /// ties by building a mini-table of the same teams from the same matches
    /// is circular by definition, and recurses until the stack gives out.
    List<Tiebreak>? chainOverride,
  }) {
    final rows = <String, _Row>{
      for (final e in entrants)
        e.id: _Row(entrantId: e.id, displayName: e.displayName),
    };

    // A DRAFT fixture may name an entrant that has no [Entrant] document,
    // because `generateDraftSchedule` lays a bracket out against placeholders
    // — "Team A", "Team B" — before registration has produced anybody real.
    // Without a row each, a draft schedule's table is empty and the preview it
    // exists to give is blank.
    //
    // Restricted to drafts, and that restriction is the whole subtlety. On a
    // PLAYED fixture an entrant id absent from the list means the opposite
    // thing: stale data — an entrant deleted, or a fixture carried over from a
    // reshaped draw — and inventing a row for it puts a competitor in the
    // table who is not in the competition. Synthesizing unconditionally made
    // `standings_test.dart`'s "a fixture naming an unknown entrant is ignored,
    // not crashed on" return a two-row table for a one-entrant event.
    //
    // `isDraft` is the right signal rather than a proxy for one: it is already
    // "what the rest of the app reads to leave placeholders out of anything it
    // counts" (see `CompetitionRepository.generateDraftSchedule`).
    for (final f in fixtures) {
      if (!f.isDraft) continue;
      if (f.entrantAId.isNotEmpty && !rows.containsKey(f.entrantAId)) {
        rows[f.entrantAId] = _Row(
          entrantId: f.entrantAId,
          displayName: f.entrantAName.isNotEmpty ? f.entrantAName : f.entrantAId,
        );
      }
      if (f.entrantBId.isNotEmpty && !rows.containsKey(f.entrantBId)) {
        rows[f.entrantBId] = _Row(
          entrantId: f.entrantBId,
          displayName: f.entrantBName.isNotEmpty ? f.entrantBName : f.entrantBId,
        );
      }
    }

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
      //
      // The result TYPE is consulted as well as the status, because the two
      // say different things: a walkover is a completed fixture that awards
      // points to the side who turned up, and a no-show is a completed
      // fixture that awards nothing to anyone. `status.isResulted` alone
      // could not tell them apart.
      if (!fixture.countsForStandings) continue;

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
      } else {
        // The margin is read BEFORE points are awarded, because in volleyball
        // and the rugby-shaped leagues the margin is what decides how many
        // points there are to award — a 3-2 is a different result from a 3-0
        // and the table is supposed to say so.
        final ctxForMargin = fixture.scoringContext();
        final outcomeForMargin = ScoringRegistry
            .resolve(fixture.scoringPluginKey)
            .outcome(fixture.scoreState, ctxForMargin);
        final margin =
            (outcomeForMargin.scoreForA - outcomeForMargin.scoreForB).abs();
        final award = competition.matchPointsModel.award(
          margin: margin,
          pointsForWin: competition.pointsForWin,
          pointsForLoss: competition.pointsForLoss,
        );

        final winner = aWon ? a : b;
        final loser = aWon ? b : a;
        winner.won++;
        loser.lost++;
        winner.points += award.winner;
        loser.points += award.loser;
        headToHead['${winner.entrantId}|${loser.entrantId}'] =
            (headToHead['${winner.entrantId}|${loser.entrantId}'] ?? 0) + 1;
        beaten.putIfAbsent(winner.entrantId, () => []).add(loser.entrantId);
      }

      final ctx = fixture.scoringContext();
      final outcome = ScoringRegistry.resolve(fixture.scoringPluginKey)
          .outcome(fixture.scoreState, ctx);
      a.scoreFor += outcome.scoreForA;
      a.scoreAgainst += outcome.scoreForB;
      b.scoreFor += outcome.scoreForB;
      b.scoreAgainst += outcome.scoreForA;

      _accumulateNrr(fixture: fixture, ctx: ctx, a: a, b: b);
      _accumulateSetPoints(fixture: fixture, a: a, b: b);
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

    final chain = chainOverride ??
        Tiebreak.parse(competition.tiebreakChain, competition.sportId);

    final table = _rank(
      rows.values.toList(),
      chain: chain,
      headToHead: headToHead,
      fixtures: fixtures,
      competition: competition,
    );

    return [
      for (var i = 0; i < table.length; i++) table[i].toStanding(rank: i + 1),
    ];
  }

  /// Adds one set-based fixture's sets and points to both entrants.
  ///
  /// Volleyball separates level teams on **ratios** — sets won ÷ sets lost,
  /// then points won ÷ points lost — and a ratio cannot be recovered from the
  /// difference the table already keeps: 3 sets to 0 across two matches is a
  /// better record than 30 to 27, and a difference reads them as the same.
  ///
  /// The per-set scores come from `completedSets`, which every set-based
  /// plugin writes as `{a, b}` per set. A sport that does not write it simply
  /// contributes nothing, and its ratio stays null rather than becoming a
  /// misleading zero.
  void _accumulateSetPoints({
    required Fixture fixture,
    required _Row a,
    required _Row b,
  }) {
    final sets = fixture.scoreState['completedSets'];
    if (sets is! List) return;

    for (final set in sets) {
      if (set is! Map) continue;
      final pa = (set['a'] as num?)?.toInt();
      final pb = (set['b'] as num?)?.toInt();
      if (pa == null || pb == null) continue;

      a.pointsWon += pa;
      a.pointsLost += pb;
      b.pointsWon += pb;
      b.pointsLost += pa;

      if (pa > pb) {
        a.setsWon++;
        b.setsLost++;
      } else if (pb > pa) {
        b.setsWon++;
        a.setsLost++;
      }
    }
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

  /// Orders the whole table, resolving ties the way the sport actually does.
  ///
  /// ## Why this is not one comparator
  ///
  /// A `sort` comparator sees two rows at a time, and the rule most team
  /// sports use cannot be expressed that way. When three teams finish level,
  /// FIBA and FIVB rank them by a table built from **only the matches those
  /// three played against each other** — and if that separates one but leaves
  /// two still level, the rule recurses on the pair. "Who beat whom" has no
  /// pairwise answer in a three-way tie: A beat B, B beat C, C beat A.
  ///
  /// So ties are found first, as runs of equal points, and each run is ranked
  /// as a unit. Everything that genuinely is pairwise still goes through
  /// [_compare].
  List<_Row> _rank(
    List<_Row> all, {
    required List<Tiebreak> chain,
    required Map<String, int> headToHead,
    required List<Fixture> fixtures,
    required Competition competition,
  }) {
    all.sort((x, y) {
      final byPoints = y.points.compareTo(x.points);
      if (byPoints != 0) return byPoints;
      return x.displayName.toLowerCase().compareTo(y.displayName.toLowerCase());
    });

    final ordered = <_Row>[];
    var i = 0;
    while (i < all.length) {
      var j = i + 1;
      while (j < all.length && all[j].points == all[i].points) {
        j++;
      }
      final tied = all.sublist(i, j);
      ordered.addAll(
        tied.length == 1
            ? tied
            : _separate(
                tied,
                chain: chain,
                headToHead: headToHead,
                fixtures: fixtures,
                competition: competition,
                depth: 0,
              ),
      );
      i = j;
    }

    return ordered;
  }

  /// Ranks a set of rows that are level on points.
  ///
  /// [depth] guards the recursion. A group where every mini-league is also
  /// level — three teams who each beat one and lost to one by identical
  /// margins — is genuinely undecidable by results, and every federation
  /// eventually falls back to a draw of lots. Recursing forever instead would
  /// hang the table.
  List<_Row> _separate(
    List<_Row> tied, {
    required List<Tiebreak> chain,
    required Map<String, int> headToHead,
    required List<Fixture> fixtures,
    required Competition competition,
    required int depth,
  }) {
    if (tied.length <= 1 || depth > 4) return tied;

    if (chain.contains(Tiebreak.miniLeague)) {
      final ids = {for (final r in tied) r.entrantId};
      // Only the matches these teams played against each other.
      final mutual = [
        for (final f in fixtures)
          if (ids.contains(f.entrantAId) && ids.contains(f.entrantBId)) f,
      ];

      if (mutual.isNotEmpty) {
        final mini = compute(
          competition: competition,
          entrants: [
            for (final r in tied)
              Entrant(
                id: r.entrantId,
                displayName: r.displayName,
                entrantType: competition.entrantType,
              ),
          ],
          fixtures: mutual,
          // Without miniLeague — see `chainOverride`.
          chainOverride: [
            for (final t in chain)
              if (t != Tiebreak.miniLeague) t,
          ],
        );
        final position = {
          for (var k = 0; k < mini.length; k++) mini[k].entrantId: k,
        };
        final byId = {for (final r in tied) r.entrantId: r};

        // Regroup by mini-league position: rows the mini-table separated are
        // settled; any that are still level recurse.
        final grouped = <int, List<_Row>>{};
        for (final r in tied) {
          grouped.putIfAbsent(position[r.entrantId] ?? 1 << 20, () => []).add(r);
        }
        final keys = grouped.keys.toList()..sort();
        final out = <_Row>[];
        for (final key in keys) {
          final bucket = grouped[key]!;
          out.addAll(
            bucket.length == 1
                ? bucket
                : _separate(
                    bucket,
                    chain: chain,
                    headToHead: headToHead,
                    fixtures: fixtures,
                    competition: competition,
                    depth: depth + 1,
                  ),
          );
        }
        // Only trust the mini-league when it actually reordered something;
        // an identical order means it separated nobody.
        if (out.length == tied.length && byId.length == tied.length) return out;
      }
    }

    return tied..sort((x, y) => _compare(x, y, chain, headToHead));
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
        Tiebreak.setsRatio =>
          _compareNullableDesc(x.setsRatio, y.setsRatio),
        Tiebreak.pointsRatio =>
          _compareNullableDesc(x.pointsRatio, y.pointsRatio),
        // Handled by `_separate` before any pairwise comparison runs; there is
        // nothing sensible it can mean between exactly two rows here.
        Tiebreak.miniLeague => 0,
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
      final names = <String, String>{};
      // Only a draft group may invent its members, for the same reason the
      // whole-competition table above may: a placeholder group has no real
      // entrants yet, while a played group naming somebody unknown is stale.
      final placeholders = <String>{};
      for (final f in entry.value) {
        if (f.entrantAId.isNotEmpty) {
          ids.add(f.entrantAId);
          names[f.entrantAId] = f.entrantAName;
          if (f.isDraft) placeholders.add(f.entrantAId);
        }
        if (f.entrantBId.isNotEmpty) {
          ids.add(f.entrantBId);
          names[f.entrantBId] = f.entrantBName;
          if (f.isDraft) placeholders.add(f.entrantBId);
        }
      }
      tables[entry.key] = compute(
        competition: competition,
        entrants: [
          for (final id in ids)
            if (byId[id] != null)
              byId[id]!
            else if (placeholders.contains(id))
              Entrant(
                id: id,
                displayName: names[id]?.isNotEmpty == true ? names[id]! : id,
                entrantType: competition.entrantType,
              ),
        ],
        fixtures: entry.value,
      );
    }

    return tables;
  }

  /// Builds a table from fixtures alone, synthesizing the rows from the names
  /// the fixtures already carry.
  ///
  /// [compute] needs real [Entrant] documents because a league table must list
  /// a team that has not played yet — leaving them out reads as though they
  /// were never entered. A tournament summary has the opposite problem: it
  /// renders many events at once and cannot afford a per-event entrant read
  /// just to learn who won. Every entrant who appears in a fixture is already
  /// named on it, so for "who leads this table" that is enough.
  ///
  /// The one thing it cannot show is an entrant with no fixtures at all. That
  /// is the right trade here and the wrong one on the event screen, which is
  /// why both exist.
  List<Standing> computeFromFixtures({
    required Competition competition,
    required List<Fixture> fixtures,
  }) {
    final names = <String, String>{};
    for (final f in fixtures) {
      if (f.entrantAId.isNotEmpty) names[f.entrantAId] = f.entrantAName;
      if (f.entrantBId.isNotEmpty) names[f.entrantBId] = f.entrantBName;
    }
    return compute(
      competition: competition,
      entrants: [
        for (final entry in names.entries)
          Entrant(
            id: entry.key,
            displayName: entry.value,
            entrantType: competition.entrantType,
          ),
      ],
      fixtures: fixtures,
    );
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
  int setsWon = 0;
  int setsLost = 0;
  int pointsWon = 0;
  int pointsLost = 0;

  /// Sets won ÷ sets lost. Null when this sport records no sets, so it sorts
  /// last rather than reading as a ratio of zero.
  double? get setsRatio => _ratio(setsWon, setsLost);

  double? get pointsRatio => _ratio(pointsWon, pointsLost);

  /// A side that has lost nothing has an undefined ratio, not an infinite
  /// one. Treated as very large so it ranks top, which is what "won every set
  /// they played" should do.
  static double? _ratio(int won, int lost) {
    if (won == 0 && lost == 0) return null;
    if (lost == 0) return 1e9 + won;
    return won / lost;
  }
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
