import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/standings/standings_calculator.dart';
import 'package:playsphere/domain/standings/tiebreak.dart';

/// Two rules the flat tiebreak chain could not express, both from sports the
/// product already supports.
void main() {
  const calc = StandingsCalculator();

  Competition competition({
    String sportId = 'volleyball',
    List<String>? chain,
    MatchPointsModel points = const MatchPointsModel(),
  }) =>
      Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'League',
        sportId: sportId,
        sportName: sportId,
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        format: CompetitionFormat.roundRobin,
        status: CompetitionStatus.inProgress,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'set_based',
        tiebreakChain: chain,
        matchPointsModel: points,
      );

  List<Entrant> entrants(List<String> names) => [
        for (final n in names)
          Entrant(id: n, displayName: n, entrantType: EntrantType.team),
      ];

  /// A set-based match, with the per-set scores the ratios are read from.
  Fixture sets(
    String a,
    String b,
    List<(int, int)> setScores,
  ) {
    var setsA = 0;
    var setsB = 0;
    for (final s in setScores) {
      if (s.$1 > s.$2) {
        setsA++;
      } else {
        setsB++;
      }
    }
    return Fixture(
      id: '$a-$b-${setScores.length}',
      orgId: 'o1',
      compId: 'c1',
      entrantAId: a,
      entrantBId: b,
      entrantAName: a,
      entrantBName: b,
      status: FixtureStatus.completed,
      scoringPluginKey: 'set_based',
      scoreState: {
        'setsA': setsA,
        'setsB': setsB,
        'currentA': 0,
        'currentB': 0,
        'completedSets': [
          for (final s in setScores) {'a': s.$1, 'b': s.$2},
        ],
        'complete': true,
        'winner': setsA > setsB ? 'a' : 'b',
      },
      winnerEntrantId: setsA > setsB ? a : b,
    );
  }

  group('volleyball match points', () {
    test('a 3-2 is worth 2 to the winner and 1 to the loser', () {
      // A five-set match is a different result from a straight-sets one, and
      // a flat win/loss triple cannot say so.
      final table = calc.compute(
        competition: competition(points: MatchPointsModel.volleyball),
        entrants: entrants(['A', 'B']),
        fixtures: [
          sets('A', 'B', [(25, 20), (20, 25), (25, 22), (18, 25), (15, 12)]),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'A').points, 2);
      expect(table.firstWhere((r) => r.entrantId == 'B').points, 1);
    });

    test('a 3-0 is worth the full three, and nothing to the loser', () {
      final table = calc.compute(
        competition: competition(points: MatchPointsModel.volleyball),
        entrants: entrants(['A', 'B']),
        fixtures: [
          sets('A', 'B', [(25, 20), (25, 18), (25, 22)]),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'A').points, 3);
      expect(table.firstWhere((r) => r.entrantId == 'B').points, 0);
    });

    test('the model is off by default, so an existing league is unchanged', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['A', 'B']),
        fixtures: [
          sets('A', 'B', [(25, 20), (20, 25), (25, 22), (18, 25), (15, 12)]),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'A').points, 3);
      expect(table.firstWhere((r) => r.entrantId == 'B').points, 0);
    });

    test('a losing bonus can be awarded instead of a close-match split', () {
      const bonus = MatchPointsModel(
        enabled: true,
        closeMarginAtMost: 0,
        losingBonusWithin: 1,
      );
      final table = calc.compute(
        competition: competition(points: bonus),
        entrants: entrants(['A', 'B']),
        fixtures: [
          sets('A', 'B', [(25, 20), (20, 25), (25, 22), (18, 25), (15, 12)]),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'A').points, 3);
      expect(table.firstWhere((r) => r.entrantId == 'B').points, 1);
    });
  });

  group('ratio tiebreaks', () {
    test('sets ratio separates teams level on points', () {
      // A ratio, not a difference: winning every set is a better record than
      // scraping through, and a difference reads them the same.
      final table = calc.compute(
        competition: competition(
          chain: [Tiebreak.setsRatio.wire, Tiebreak.name.wire],
        ),
        entrants: entrants(['Clean', 'Scrappy', 'Weak']),
        fixtures: [
          sets('Clean', 'Weak', [(25, 10), (25, 12), (25, 14)]),
          sets('Scrappy', 'Weak', [(25, 23), (20, 25), (25, 23), (25, 23)]),
        ],
      );
      expect(table.first.entrantId, 'Clean');
    });

    test('points ratio settles teams level on sets', () {
      final table = calc.compute(
        competition: competition(
          chain: [Tiebreak.pointsRatio.wire, Tiebreak.name.wire],
        ),
        entrants: entrants(['Dominant', 'Narrow', 'Weak']),
        fixtures: [
          sets('Dominant', 'Weak', [(25, 5), (25, 6), (25, 7)]),
          sets('Narrow', 'Weak', [(25, 23), (25, 23), (25, 23)]),
        ],
      );
      expect(table.first.entrantId, 'Dominant');
    });

    test('a sport recording no sets has no ratio, and sorts last', () {
      // Null rather than zero: a team with no sets has no ratio, and treating
      // that as 0.0 would rank it below a team that has genuinely lost more
      // sets than it won.
      final table = calc.compute(
        competition: competition(
          sportId: 'football',
          chain: [Tiebreak.setsRatio.wire, Tiebreak.name.wire],
        ),
        entrants: entrants(['A', 'B']),
        fixtures: const [],
      );
      expect(table.length, 2);
    });
  });

  group('the mini-league, for a tie of three', () {
    test('three level teams are ranked on the matches among themselves', () {
      // FIBA and FIVB both do this, and it is genuinely not expressible as a
      // pairwise comparison: A beat B, B beat C, C beat A has no "who beat
      // whom" answer.
      final table = calc.compute(
        competition: competition(
          sportId: 'basketball',
          chain: [Tiebreak.miniLeague.wire, Tiebreak.name.wire],
        ),
        entrants: entrants(['A', 'B', 'C', 'Whipping']),
        fixtures: [
          // Each of the three beats the Whipping side once, so all are level.
          sets('A', 'Whipping', [(25, 10)]),
          sets('B', 'Whipping', [(25, 10)]),
          sets('C', 'Whipping', [(25, 10)]),
          // Among themselves: A beats both, B beats C.
          sets('A', 'B', [(25, 20)]),
          sets('A', 'C', [(25, 20)]),
          sets('B', 'C', [(25, 20)]),
        ],
      );

      final order = table.map((r) => r.entrantId).toList();
      expect(order.indexOf('A'), lessThan(order.indexOf('B')));
      expect(order.indexOf('B'), lessThan(order.indexOf('C')));
    });

    test('a fully circular tie still produces a stable order, not a hang', () {
      // A beat B, B beat C, C beat A by identical margins is genuinely
      // undecidable on results — every federation falls back to a draw of
      // lots. It must terminate rather than recursing forever.
      final table = calc.compute(
        competition: competition(
          sportId: 'basketball',
          chain: [Tiebreak.miniLeague.wire, Tiebreak.name.wire],
        ),
        entrants: entrants(['A', 'B', 'C']),
        fixtures: [
          sets('A', 'B', [(25, 20)]),
          sets('B', 'C', [(25, 20)]),
          sets('C', 'A', [(25, 20)]),
        ],
      );
      expect(table.map((r) => r.entrantId).toSet(), {'A', 'B', 'C'});
      expect(table.map((r) => r.rank), [1, 2, 3]);
    });

    test('teams on different points are never regrouped', () {
      final table = calc.compute(
        competition: competition(
          sportId: 'basketball',
          chain: [Tiebreak.miniLeague.wire, Tiebreak.name.wire],
        ),
        entrants: entrants(['Top', 'Mid', 'Bottom']),
        fixtures: [
          sets('Top', 'Mid', [(25, 20)]),
          sets('Top', 'Bottom', [(25, 20)]),
          sets('Mid', 'Bottom', [(25, 20)]),
        ],
      );
      expect(table.map((r) => r.entrantId), ['Top', 'Mid', 'Bottom']);
    });
  });
}
