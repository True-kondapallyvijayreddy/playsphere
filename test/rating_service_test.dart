import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/data/rating_service.dart';
import 'package:playsphere/domain/rating/glicko2.dart';
import 'package:playsphere/domain/scoring/plugins/athletics_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/basketball_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/carrom_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/chess_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/football_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/hockey_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/kabaddi_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/kho_kho_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/volleyball_plugin.dart';

void main() {
  group('RatingService — contribution weights', () {
    const service = RatingService();

    const playerA1 = MatchPlayer(id: 'p_a1', name: 'Alice', uid: 'user_a1');
    const playerA2 = MatchPlayer(id: 'p_a2', name: 'Bob', uid: 'user_a2');

    test('equal tallies yield the default weight of 1.0', () {
      final weights = service.calculatePerformanceWeights(
        <String, dynamic>{},
        [playerA1, playerA2],
      );
      expect(weights['p_a1'], equals(1.0));
      expect(weights['p_a2'], equals(1.0));
    });

    test('higher contribution yields a higher weight, clamped to 1.8', () {
      final scoreState = <String, dynamic>{
        'players': {
          'p_a1': {'goals': 3, 'assists': 1},
          'p_a2': {'goals': 0, 'assists': 0},
        },
      };
      final weights =
          service.calculatePerformanceWeights(scoreState, [playerA1, playerA2]);
      expect(weights['p_a1'], equals(1.8));
      expect(weights['p_a2'], equals(0.2));
    });

    test('cricket contributions reward runs, wickets and catches', () {
      final scoreState = <String, dynamic>{
        'players': {
          'p_a1': {'runsScored': 52, 'wickets': 2, 'catches': 1},
          'p_a2': {'runsScored': 10},
        },
      };
      final weights =
          service.calculatePerformanceWeights(scoreState, [playerA1, playerA2]);
      expect(weights['p_a1']!, greaterThan(1.0));
      expect(weights['p_a2']!, lessThan(1.0));
    });

    test('basketball contributions reflect points, rebounds and assists', () {
      final scoreState = <String, dynamic>{
        'players': {
          'p_a1': {'points': 25, 'defRebounds': 10, 'assists': 5},
          'p_a2': {'points': 4, 'defRebounds': 2, 'assists': 1},
        },
      };
      final weights =
          service.calculatePerformanceWeights(scoreState, [playerA1, playerA2]);
      expect(weights['p_a1']!, greaterThan(weights['p_a2']!));
    });

    test('a milestone is worth more than the raw units alone', () {
      // 50 runs earns a bonus; 49 does not. The gap must exceed one run.
      final fifty = service.calculatePerformanceWeights(
        {
          'players': {
            'p_a1': {'runsScored': 50},
            'p_a2': {'runsScored': 50},
          }
        },
        [playerA1, playerA2],
      );
      // Both equal, so both 1.0 — check the raw effect instead via asymmetry.
      expect(fifty['p_a1'], 1.0);

      final asymmetric = service.calculatePerformanceWeights(
        {
          'players': {
            'p_a1': {'runsScored': 50},
            'p_a2': {'runsScored': 49},
          }
        },
        [playerA1, playerA2],
      );
      // 50 runs + 15 bonus = 65 against 49. That gap is far wider than the
      // single run between them.
      expect(asymmetric['p_a1']! / asymmetric['p_a2']!, greaterThan(1.2));
    });

    // ------------------------------------------------------------------
    // The guard that stops this table drifting away from the engines again.
    //
    // Every weight key below was once written in snake_case while the engines
    // emitted camelCase, so the weighting silently did nothing for every
    // sport but football. Nothing caught it, because the old tests fed the
    // wrong keys in by hand.
    test('every contribution weight key is emitted by a real engine', () {
      final emitted = <String>{
        for (final c in FootballPlugin.columns) c.key,
        for (final c in HockeyPlugin.columns) c.key,
        for (final c in BasketballPlugin.columns) c.key,
        for (final c in KabaddiPlugin.columns) c.key,
        for (final c in KhoKhoPlugin.columns) c.key,
        for (final c in VolleyballPlugin.columns) c.key,
        for (final c in TennisPlugin.columns) c.key,
        for (final c in TableTennisPlugin.columns) c.key,
        for (final c in BadmintonPlugin.columns) c.key,
        for (final c in ChessPlugin.columns) c.key,
        for (final c in CarromPlugin.columns) c.key,
        for (final c in AthleticsPlugin.columns) c.key,
        // Cricket keeps its authoritative figures in the innings records and
        // mirrors them into the tally, so its keys are named rather than
        // read off a column list.
        'runsScored', 'ballsFaced', 'fours', 'sixes', 'dismissed',
        'wickets', 'ballsBowled', 'runsConceded', 'maidens',
        'catches', 'stumpings', 'runOuts', 'runOutAssists',
        // Raw tally keys that engines write but only surface through a
        // derived column — basketball totals the two rebound counters into
        // one "REB" column, so neither raw key appears in `columns`.
        'offRebounds', 'defRebounds',
      };

      final orphans = RatingService.contributionWeights.keys
          .where((k) => !emitted.contains(k))
          .toList();

      expect(
        orphans,
        isEmpty,
        reason: 'these weight keys match no engine output, so they weight '
            'nothing: $orphans',
      );
    });
  });

  group('RatingService — rating pools', () {
    Fixture fixtureFor(String sportId, {Map<String, dynamic> config = const {}}) =>
        Fixture(
          id: 'f1',
          orgId: 'o1',
          compId: 'c1',
          entrantAId: 'a',
          entrantBId: 'b',
          entrantAName: 'A',
          entrantBName: 'B',
          status: FixtureStatus.completed,
          sportId: sportId,
          scoringConfig: config,
        );

    test('sports sharing an engine keep separate rating pools', () {
      // Both run the athletics engine; they must not share a rating.
      expect(
        fixtureFor('athletics_sprint').ratingKey,
        isNot(fixtureFor('swimming').ratingKey),
      );
      // Both ran simple_points before; carrom and chess are distinct sports.
      expect(
        fixtureFor('carrom').ratingKey,
        isNot(fixtureFor('chess').ratingKey),
      );
    });

    test('chess is rated per time control', () {
      final blitz =
          fixtureFor('chess', config: {'timeControl': 'blitz'}).ratingKey;
      final classical =
          fixtureFor('chess', config: {'timeControl': 'classical'}).ratingKey;
      expect(blitz, 'chess:blitz');
      expect(classical, 'chess:classical');
      expect(blitz, isNot(classical));
    });

    test('a fixture with no sport falls back to its plugin key', () {
      const legacy = Fixture(
        id: 'f1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'A',
        entrantBName: 'B',
        status: FixtureStatus.completed,
        scoringPluginKey: 'cricket',
      );
      expect(legacy.sport, 'cricket');
      expect(legacy.ratingKey, 'cricket');
    });
  });

  group('Glicko-2 settlement', () {
    test('a win raises the rating, narrows RD and counts the game', () {
      const glicko = Glicko2();
      const initial = Rating(
        rating: 1500,
        deviation: 350,
        volatility: 0.06,
        gamesPlayed: 0,
      );
      const opponent = Rating(rating: 1500, deviation: 350);

      final win = glicko.rate(
        initial,
        [const RatingGame(opponent: opponent, score: 1.0, weight: 1.0)],
      );
      expect(win.rating, greaterThan(1500));
      expect(win.deviation, lessThan(350));
      expect(win.gamesPlayed, equals(1));

      final mvpWin = glicko.rate(
        initial,
        [const RatingGame(opponent: opponent, score: 1.0, weight: 1.8)],
      );
      expect(mvpWin.rating, greaterThan(win.rating));
    });
  });
}
