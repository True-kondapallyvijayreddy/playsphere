import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/standings/net_run_rate.dart';
import 'package:playsphere/domain/standings/standings_calculator.dart';
import 'package:playsphere/domain/standings/tiebreak.dart';

/// Golden tests for net run rate, per CLAUDE.md §12.6.
///
/// Every assertion here is a hard-coded expected number, computed by hand from
/// the definition, not a comparison of the code against itself. NRR decides
/// who qualifies out of a group, so the three things it gets wrong in naive
/// implementations are each worth a test:
///
///   * overs decimalised as balls/6 (47.2 overs is 47.333, never 47.4),
///   * a side bowled out charged its FULL allotted overs,
///   * three-decimal precision.
void main() {
  // --------------------------------------------------------------------------
  // Building fixtures with a given innings shape directly. NRR reads the
  // projected innings, so a test can state the scorecard rather than replaying
  // several hundred deliveries to produce one.
  Map<String, dynamic> innings({
    required String battingSide,
    required int runs,
    required int legalBalls,
    required int wickets,
  }) =>
      {
        'battingSide': battingSide,
        'runs': runs,
        'legalBalls': legalBalls,
        'wickets': wickets,
      };

  Fixture cricketFixture({
    required String aId,
    required String bId,
    required List<Map<String, dynamic>> inns,
    required String? winnerId,
    int oversPerInnings = 20,
    bool isDraw = false,
  }) =>
      Fixture(
        id: 'f${aId}_$bId${inns.hashCode}',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: aId,
        entrantBId: bId,
        entrantAName: aId,
        entrantBName: bId,
        status: FixtureStatus.completed,
        winnerEntrantId: winnerId,
        isDraw: isDraw,
        scoringPluginKey: CricketPlugin.pluginKey,
        sportId: 'cricket',
        scoringConfig: {
          'oversPerInnings': oversPerInnings,
          'ballsPerOver': 6,
          'playersPerTeam': 11,
        },
        scoreState: {'innings': inns},
      );

  // ==========================================================================
  group('overs are decimalised by balls/6', () {
    test('47.2 overs means 47.333, never 47.4', () {
      const record = InningsRecord(
        battingSide: 'a',
        runs: 284,
        legalBalls: 47 * 6 + 2, // 47.2 overs
        wickets: 4,
        allOut: false,
        allottedBalls: 50 * 6,
      );
      expect(record.oversForRate(6), closeTo(47.3333, 0.0001));
      // The naive reading — treating the ".2" as two tenths — is 47.4.
      expect(record.oversForRate(6), isNot(closeTo(47.4, 0.001)));
    });

    test('a whole number of overs is exact', () {
      const record = InningsRecord(
        battingSide: 'a',
        runs: 120,
        legalBalls: 120,
        wickets: 3,
        allOut: false,
        allottedBalls: 120,
      );
      expect(record.oversForRate(6), 20.0);
    });
  });

  // ==========================================================================
  group('a side bowled out is charged its full allotted overs', () {
    test('60 all out in 12 overs counts as 20 overs, not 12', () {
      const record = InningsRecord(
        battingSide: 'a',
        runs: 60,
        legalBalls: 72, // 12 overs
        wickets: 10,
        allOut: true,
        allottedBalls: 120, // 20 overs
      );
      expect(record.ballsForRate, 120);
      expect(record.oversForRate(6), 20.0);
      // Charged correctly the rate is 3.00, not the flattering 5.00 that
      // rewards collapsing quickly.
      expect(record.runs / record.oversForRate(6), 3.0);
    });

    test('a side that was not bowled out is charged what it actually faced',
        () {
      const record = InningsRecord(
        battingSide: 'a',
        runs: 150,
        legalBalls: 90, // 15 overs — a chase completed early
        wickets: 4,
        allOut: false,
        allottedBalls: 120,
      );
      expect(record.ballsForRate, 90);
      expect(record.oversForRate(6), 15.0);
    });
  });

  // ==========================================================================
  group('net run rate is computed to three decimals', () {
    test('a worked example matches the hand calculation', () {
      final tally = NrrTally();
      // Scored 180 in 20 overs; conceded 150 in 20 overs.
      tally.addBatting(180, 20);
      tally.addBowling(150, 20);
      // 9.000 - 7.500 = +1.500
      expect(tally.value, 1.5);
    });

    test('a rate that does not terminate is rounded to three decimals', () {
      final tally = NrrTally();
      // 100 runs in 19.4 overs = 100 / 19.6667 = 5.0847...
      tally.addBatting(100, 118 / 6);
      // 100 conceded in 20 overs = 5.000
      tally.addBowling(100, 20);
      expect(tally.value, 0.085);
    });

    test('a negative rate is reported as such', () {
      final tally = NrrTally();
      tally.addBatting(120, 20); // 6.000
      tally.addBowling(160, 20); // 8.000
      expect(tally.value, -2.0);
    });

    test('a team that has not both batted and bowled has no rate', () {
      final onlyBatted = NrrTally()..addBatting(100, 20);
      expect(onlyBatted.value, isNull);

      final neither = NrrTally();
      expect(neither.value, isNull);
    });

    test('rates accumulate across matches, not averaged per match', () {
      final tally = NrrTally();
      // Match 1: 200 in 20, conceded 180 in 20.
      tally.addBatting(200, 20);
      tally.addBowling(180, 20);
      // Match 2: 100 in 10, conceded 140 in 20.
      tally.addBatting(100, 10);
      tally.addBowling(140, 20);
      // Totals: 300 / 30 = 10.000 for, 320 / 40 = 8.000 against.
      expect(tally.value, 2.0);
    });
  });

  // ==========================================================================
  group('formatting', () {
    test('a rate prints with a sign and three decimals', () {
      expect(NetRunRate.format(1.5), '+1.500');
      expect(NetRunRate.format(-0.25), '-0.250');
      expect(NetRunRate.format(0), '0.000');
      expect(NetRunRate.format(null), '—');
    });
  });

  // ==========================================================================
  group('extraction from a match', () {
    const ctxConfig = {
      'oversPerInnings': 20,
      'ballsPerOver': 6,
      'playersPerTeam': 11,
    };

    Fixture f(List<Map<String, dynamic>> inns) => cricketFixture(
          aId: 'A',
          bId: 'B',
          inns: inns,
          winnerId: 'A',
        );

    test('both innings are read, with the batting side attributed', () {
      final fixture = f([
        innings(battingSide: 'a', runs: 180, legalBalls: 120, wickets: 5),
        innings(battingSide: 'b', runs: 150, legalBalls: 120, wickets: 8),
      ]);
      final records = NetRunRate.inningsOf(
        scoreState: fixture.scoreState,
        ctx: fixture.scoringContext(),
        pluginKey: CricketPlugin.pluginKey,
      );
      expect(records.length, 2);
      expect(records.first.battingSide, 'a');
      expect(records.first.runs, 180);
      expect(records.last.battingSide, 'b');
    });

    test('all out is detected from wickets against the squad size', () {
      final fixture = f([
        innings(battingSide: 'a', runs: 60, legalBalls: 72, wickets: 10),
      ]);
      final records = NetRunRate.inningsOf(
        scoreState: fixture.scoreState,
        ctx: fixture.scoringContext(),
        pluginKey: CricketPlugin.pluginKey,
      );
      expect(records.single.allOut, isTrue);
      expect(records.single.ballsForRate, 120);
    });

    test('an innings nobody batted in is ignored', () {
      final fixture = f([
        innings(battingSide: 'a', runs: 180, legalBalls: 120, wickets: 5),
        innings(battingSide: 'b', runs: 0, legalBalls: 0, wickets: 0),
      ]);
      final records = NetRunRate.inningsOf(
        scoreState: fixture.scoreState,
        ctx: fixture.scoringContext(),
        pluginKey: CricketPlugin.pluginKey,
      );
      expect(records.length, 1);
    });

    test('a non-cricket fixture yields nothing', () {
      final records = NetRunRate.inningsOf(
        scoreState: const {'innings': []},
        ctx: const Fixture(
          id: 'x',
          orgId: 'o',
          compId: 'c',
          entrantAId: 'a',
          entrantBId: 'b',
          entrantAName: 'A',
          entrantBName: 'B',
          status: FixtureStatus.completed,
          scoringConfig: ctxConfig,
        ).scoringContext(),
        pluginKey: 'football',
      );
      expect(records, isEmpty);
    });
  });

  // ==========================================================================
  group('the league table separates cricket teams on net run rate', () {
    Competition comp({List<String>? chain}) => Competition(
          id: 'c1',
          orgId: 'o1',
          name: 'Group A',
          sportId: 'cricket',
          sportName: 'Cricket',
          archetype: CompetitionArchetype.versus,
          entrantType: EntrantType.team,
          format: CompetitionFormat.leagueTable,
          status: CompetitionStatus.inProgress,
          category: const CompetitionCategory(label: 'Open'),
          scoringPluginKey: CricketPlugin.pluginKey,
          tiebreakChain: chain,
        );

    const entrants = [
      Entrant(id: 'A', displayName: 'Warangal', entrantType: EntrantType.team),
      Entrant(id: 'B', displayName: 'Nizamabad', entrantType: EntrantType.team),
      Entrant(id: 'C', displayName: 'Khammam', entrantType: EntrantType.team),
    ];

    test('two teams level on points are split by net run rate', () {
      // A beats C by scoring quickly. B beats C narrowly. A and B both have
      // one win, so only the rate separates them.
      final fixtures = [
        cricketFixture(
          aId: 'A',
          bId: 'C',
          winnerId: 'A',
          inns: [
            innings(battingSide: 'b', runs: 100, legalBalls: 120, wickets: 6),
            innings(battingSide: 'a', runs: 101, legalBalls: 60, wickets: 2),
          ],
        ),
        cricketFixture(
          aId: 'B',
          bId: 'C',
          winnerId: 'B',
          inns: [
            innings(battingSide: 'b', runs: 100, legalBalls: 120, wickets: 6),
            innings(battingSide: 'a', runs: 101, legalBalls: 119, wickets: 8),
          ],
        ),
      ];

      final table = const StandingsCalculator().compute(
        competition: comp(),
        entrants: entrants,
        fixtures: fixtures,
      );

      final a = table.firstWhere((r) => r.entrantId == 'A');
      final b = table.firstWhere((r) => r.entrantId == 'B');
      expect(a.points, b.points, reason: 'both won once');
      expect(a.netRunRate!, greaterThan(b.netRunRate!),
          reason: 'A chased in 10 overs, B took nearly 20');
      expect(a.rank, lessThan(b.rank));
    });

    test('a team bowled out is punished for the full quota', () {
      final fixtures = [
        cricketFixture(
          aId: 'A',
          bId: 'B',
          winnerId: 'A',
          inns: [
            innings(battingSide: 'a', runs: 180, legalBalls: 120, wickets: 4),
            // B all out for 60 in 12 overs — charged 20.
            innings(battingSide: 'b', runs: 60, legalBalls: 72, wickets: 10),
          ],
        ),
      ];

      final table = const StandingsCalculator().compute(
        competition: comp(),
        entrants: entrants,
        fixtures: fixtures,
      );

      final b = table.firstWhere((r) => r.entrantId == 'B');
      // B: scored 60 off 20 (charged), conceded 180 off 20 = 3.000 - 9.000.
      expect(b.netRunRate, -6.0);

      final a = table.firstWhere((r) => r.entrantId == 'A');
      expect(a.netRunRate, 6.0);
    });

    test('a team with no completed innings sorts below a negative rate', () {
      // C never played, so it has no rate at all.
      final fixtures = [
        cricketFixture(
          aId: 'A',
          bId: 'B',
          winnerId: 'A',
          inns: [
            innings(battingSide: 'a', runs: 100, legalBalls: 120, wickets: 4),
            innings(battingSide: 'b', runs: 90, legalBalls: 120, wickets: 9),
          ],
        ),
      ];

      final table = const StandingsCalculator().compute(
        competition: comp(),
        entrants: entrants,
        fixtures: fixtures,
      );
      final c = table.firstWhere((r) => r.entrantId == 'C');
      expect(c.netRunRate, isNull);
      // B lost and has a negative rate, but it has still played.
      final b = table.firstWhere((r) => r.entrantId == 'B');
      expect(b.netRunRate!, lessThan(0));
      expect(b.rank, lessThan(c.rank));
    });

    test('head to head outranks a better net run rate when points are level',
        () {
      // A and B win one each, so points are level. A's wins are far more
      // emphatic, giving it the better rate — but B won the match between
      // them, and the default cricket chain puts head-to-head first.
      final fixtures = [
        // B beats A narrowly. This is the meeting that decides it.
        cricketFixture(
          aId: 'B',
          bId: 'A',
          winnerId: 'B',
          inns: [
            innings(battingSide: 'a', runs: 100, legalBalls: 120, wickets: 5),
            innings(battingSide: 'b', runs: 99, legalBalls: 120, wickets: 9),
          ],
        ),
        // A crushes C.
        cricketFixture(
          aId: 'A',
          bId: 'C',
          winnerId: 'A',
          inns: [
            innings(battingSide: 'a', runs: 200, legalBalls: 120, wickets: 2),
            innings(battingSide: 'b', runs: 50, legalBalls: 120, wickets: 10),
          ],
        ),
        // B loses to C, levelling the points with A.
        cricketFixture(
          aId: 'B',
          bId: 'C',
          winnerId: 'C',
          inns: [
            innings(battingSide: 'a', runs: 100, legalBalls: 120, wickets: 9),
            innings(battingSide: 'b', runs: 101, legalBalls: 118, wickets: 4),
          ],
        ),
      ];

      final table = const StandingsCalculator().compute(
        competition: comp(),
        entrants: entrants,
        fixtures: fixtures,
      );

      final a = table.firstWhere((r) => r.entrantId == 'A');
      final b = table.firstWhere((r) => r.entrantId == 'B');

      expect(a.points, b.points, reason: 'one win each — the tie is real');
      expect(a.netRunRate!, greaterThan(b.netRunRate!),
          reason: 'A has by far the better rate');
      expect(b.rank, lessThan(a.rank),
          reason: 'but B won the head-to-head, which is applied first');
    });

    test('a league can configure net run rate ahead of head to head', () {
      final fixtures = [
        cricketFixture(
          aId: 'B',
          bId: 'A',
          winnerId: 'B',
          inns: [
            innings(battingSide: 'a', runs: 100, legalBalls: 120, wickets: 5),
            innings(battingSide: 'b', runs: 99, legalBalls: 120, wickets: 9),
          ],
        ),
        cricketFixture(
          aId: 'A',
          bId: 'B',
          winnerId: 'A',
          inns: [
            innings(battingSide: 'a', runs: 200, legalBalls: 120, wickets: 2),
            innings(battingSide: 'b', runs: 50, legalBalls: 120, wickets: 10),
          ],
        ),
      ];

      // One win each, so points are level and the chain decides.
      final byNrr = const StandingsCalculator().compute(
        competition: comp(chain: ['net_run_rate']),
        entrants: entrants,
        fixtures: fixtures,
      );
      final a = byNrr.firstWhere((r) => r.entrantId == 'A');
      final b = byNrr.firstWhere((r) => r.entrantId == 'B');
      expect(a.points, b.points);
      expect(a.netRunRate!, greaterThan(b.netRunRate!));
      expect(a.rank, lessThan(b.rank));
    });
  });

  // ==========================================================================
  group('tiebreak chains', () {
    test('cricket defaults to head-to-head then net run rate', () {
      final chain = Tiebreak.defaultsFor('cricket');
      expect(chain.first, Tiebreak.headToHead);
      expect(chain[1], Tiebreak.netRunRate);
    });

    test('chess defaults to Buchholz then Sonneborn-Berger', () {
      final chain = Tiebreak.defaultsFor('chess');
      expect(chain.first, Tiebreak.buchholz);
      expect(chain[1], Tiebreak.sonnebornBerger);
    });

    test('other sports default to goal difference', () {
      final chain = Tiebreak.defaultsFor('football');
      expect(chain.contains(Tiebreak.scoreDifference), isTrue);
      expect(chain.contains(Tiebreak.netRunRate), isFalse);
    });

    test('a configured chain always terminates on something total', () {
      final chain = Tiebreak.parse(['net_run_rate'], 'cricket');
      expect(chain.last, Tiebreak.name,
          reason: 'otherwise sorting is not deterministic');
    });

    test('an unparseable chain falls back to the sport default', () {
      expect(Tiebreak.parse(null, 'cricket'), Tiebreak.defaultsFor('cricket'));
      expect(Tiebreak.parse(['nonsense'], 'cricket'),
          Tiebreak.defaultsFor('cricket'));
    });
  });
}
