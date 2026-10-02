import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';
import 'package:playsphere/domain/tournament/season_sports.dart';

import 'season_home_test.dart' show event, fx, now;

/// Regressions from the 18–19 Sep manual season test run.
void main() {
  group('TC-57: a sport held up by a protest is not "Complete"', () {
    const season = Tournament(
      id: 's1',
      orgId: 'org1',
      name: 'House Games',
      status: TournamentStatus.inProgress,
    );
    SportStage stageWith(List<FixtureStatus> statuses) => SeasonSport.split(
          tournament: season,
          events: [event('bad1', 'badminton', 'Badminton')],
          fixtures: [
            for (var i = 0; i < statuses.length; i++)
              fx('f$i', status: statuses[i], winner: 'a'),
          ],
          leaderboard: null,
          roster: const [],
          now: now,
        ).single.stage;

    test('a disputed semi-final and a walkover final need a ruling', () {
      expect(
        stageWith([FixtureStatus.disputed, FixtureStatus.walkover]),
        SportStage.needsRuling,
      );
    });

    test('an abandoned match needs a ruling too', () {
      expect(
        stageWith([FixtureStatus.completed, FixtureStatus.abandoned]),
        SportStage.needsRuling,
      );
    });

    test('every match resulted is complete', () {
      expect(
        stageWith([FixtureStatus.completed, FixtureStatus.walkover]),
        SportStage.complete,
      );
    });
  });

  group('TC-52: a finished badminton match headlines in games', () {
    final plugin = ScoringRegistry.resolve('badminton');
    const ctx = ScoringContext(entrantAName: 'A', entrantBName: 'B');

    test('won 22-20, 21-0 reads 2 - 0, not the reset rally score', () {
      final headline = plugin.headline({
        'complete': true,
        'gamesA': 2,
        'gamesB': 0,
        'currentA': 0,
        'currentB': 0,
      }, ctx);
      expect(headline, '2 - 0');
    });

    test('retired before any game ended keeps the rally score', () {
      final headline = plugin.headline({
        'complete': true,
        'gamesA': 0,
        'gamesB': 0,
        'currentA': 14,
        'currentB': 10,
      }, ctx);
      expect(headline, '14 - 10');
    });

    test('in play shows the rally score', () {
      final headline = plugin.headline({
        'gamesA': 1,
        'gamesB': 0,
        'currentA': 7,
        'currentB': 5,
      }, ctx);
      expect(headline, '7 - 5');
    });
  });
}
