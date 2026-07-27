import '../phase4_fixtures_scoring.dart';

/// Table Tennis / Chess simple win-loss scoring plugin (§4.3).
class SimpleWinLossScoringPlugin implements ScoringPlugin {
  @override
  String get key => 'simple_win_loss';

  @override
  Map<String, dynamic> initialState(FixtureEntity fixture) {
    return {
      'homeScore': 0,
      'awayScore': 0,
      'isComplete': false,
      'winnerEntrantId': null,
      'isDraw': false,
    };
  }

  @override
  Map<String, dynamic> applyEvent(
    Map<String, dynamic> state,
    MatchEventEntity event,
  ) {
    final next = Map<String, dynamic>.from(state);

    if (event.eventType == 'point_won') {
      final isHome = event.payload['isHome'] == true;
      if (isHome) {
        next['homeScore'] = (next['homeScore'] as int) + 1;
      } else {
        next['awayScore'] = (next['awayScore'] as int) + 1;
      }
    } else if (event.eventType == 'game_finalized') {
      next['isComplete'] = true;
      next['winnerEntrantId'] = event.payload['winnerEntrantId'];
      next['isDraw'] = event.payload['isDraw'] == true;
    }

    return next;
  }

  @override
  bool isMatchComplete(Map<String, dynamic> state) {
    return state['isComplete'] == true;
  }

  @override
  ScoringPluginResult deriveResult(Map<String, dynamic> state) {
    return ScoringPluginResult(
      winnerEntrantId: state['winnerEntrantId'] as String?,
      isDraw: state['isDraw'] == true,
    );
  }

  @override
  Map<String, dynamic> renderSummary(Map<String, dynamic> state) {
    return {
      'scoreDisplay': '${state['homeScore']} - ${state['awayScore']}',
      'statusText': isMatchComplete(state) ? 'Final' : 'In Progress',
    };
  }
}

/// Set-based plugin for Badminton / Volleyball.
class SetBasedScoringPlugin implements ScoringPlugin {
  @override
  String get key => 'set_based';

  @override
  Map<String, dynamic> initialState(FixtureEntity fixture) {
    return {
      'homeSets': 0,
      'awaySets': 0,
      'currentSetHome': 0,
      'currentSetAway': 0,
      'isComplete': false,
      'winnerEntrantId': null,
      'isDraw': false,
    };
  }

  @override
  Map<String, dynamic> applyEvent(
    Map<String, dynamic> state,
    MatchEventEntity event,
  ) {
    final next = Map<String, dynamic>.from(state);

    if (event.eventType == 'point_won') {
      final isHome = event.payload['isHome'] == true;
      if (isHome) {
        next['currentSetHome'] = (next['currentSetHome'] as int) + 1;
      } else {
        next['currentSetAway'] = (next['currentSetAway'] as int) + 1;
      }

      final h = next['currentSetHome'] as int;
      final a = next['currentSetAway'] as int;

      if ((h >= 21 || a >= 21) && (h - a).abs() >= 2) {
        if (h > a) {
          next['homeSets'] = (next['homeSets'] as int) + 1;
        } else {
          next['awaySets'] = (next['awaySets'] as int) + 1;
        }
        next['currentSetHome'] = 0;
        next['currentSetAway'] = 0;

        if (next['homeSets'] == 2 || next['awaySets'] == 2) {
          next['isComplete'] = true;
          next['winnerEntrantId'] =
              next['homeSets'] == 2 ? fixtureEntrantA(event) : fixtureEntrantB(event);
        }
      }
    }

    return next;
  }

  String fixtureEntrantA(MatchEventEntity event) =>
      event.payload['entrantAId'] as String? ?? 'home';
  String fixtureEntrantB(MatchEventEntity event) =>
      event.payload['entrantBId'] as String? ?? 'away';

  @override
  bool isMatchComplete(Map<String, dynamic> state) {
    return state['isComplete'] == true;
  }

  @override
  ScoringPluginResult deriveResult(Map<String, dynamic> state) {
    return ScoringPluginResult(
      winnerEntrantId: state['winnerEntrantId'] as String?,
      isDraw: false,
    );
  }

  @override
  Map<String, dynamic> renderSummary(Map<String, dynamic> state) {
    return {
      'scoreDisplay':
          'Sets: ${state['homeSets']} - ${state['awaySets']} (${state['currentSetHome']}-${state['currentSetAway']})',
      'statusText': isMatchComplete(state) ? 'Final' : 'Live',
    };
  }
}

/// Run-based plugin for Cricket-lite.
class RunBasedScoringPlugin implements ScoringPlugin {
  @override
  String get key => 'run_based';

  @override
  Map<String, dynamic> initialState(FixtureEntity fixture) {
    return {
      'homeRuns': 0,
      'homeWickets': 0,
      'awayRuns': 0,
      'awayWickets': 0,
      'isComplete': false,
      'winnerEntrantId': null,
      'isDraw': false,
    };
  }

  @override
  Map<String, dynamic> applyEvent(
    Map<String, dynamic> state,
    MatchEventEntity event,
  ) {
    final next = Map<String, dynamic>.from(state);

    if (event.eventType == 'runs_scored') {
      final isHome = event.payload['isHome'] == true;
      final runs = event.payload['runs'] as int? ?? 1;
      if (isHome) {
        next['homeRuns'] = (next['homeRuns'] as int) + runs;
      } else {
        next['awayRuns'] = (next['awayRuns'] as int) + runs;
      }
    } else if (event.eventType == 'wicket_lost') {
      final isHome = event.payload['isHome'] == true;
      if (isHome) {
        next['homeWickets'] = (next['homeWickets'] as int) + 1;
      } else {
        next['awayWickets'] = (next['awayWickets'] as int) + 1;
      }
    }

    return next;
  }

  @override
  bool isMatchComplete(Map<String, dynamic> state) {
    return state['isComplete'] == true;
  }

  @override
  ScoringPluginResult deriveResult(Map<String, dynamic> state) {
    return ScoringPluginResult(
      winnerEntrantId: state['winnerEntrantId'] as String?,
      isDraw: state['isDraw'] == true,
    );
  }

  @override
  Map<String, dynamic> renderSummary(Map<String, dynamic> state) {
    return {
      'scoreDisplay':
          'Home: ${state['homeRuns']}/${state['homeWickets']} | Away: ${state['awayRuns']}/${state['awayWickets']}',
      'statusText': isMatchComplete(state) ? 'Final' : 'In Progress',
    };
  }
}
