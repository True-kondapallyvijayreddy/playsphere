import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// The toss has to reach the ENGINE, not just the config beside it.
///
/// `recordToss` wrote `battingFirst` into the fixture's frozen scoring config
/// and stopped there. An engine reads its rules once, in `initialState`, and
/// that runs when the draw is generated or a quick match is created — long
/// before anybody tosses a coin. Cricket's opening innings was therefore built
/// from a config with no `battingFirst` in it, defaulted to side A, and stayed
/// there.
///
/// So a side that won the toss and elected to bat did not bat. The error then
/// propagated through everything downstream of "whose innings is this": the
/// innings break, the target, the winner, and the net run rate the match fed
/// into the league table.
///
/// These tests pin the property `recordToss` now relies on — that rebuilding
/// the opening state from the post-toss config actually changes who bats — and
/// the boundary that makes rebuilding safe.
void main() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix) => [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: '$prefix$n', name: '$prefix Player $n'),
      ];

  ScoringContext contextWith(Map<String, dynamic> config) => ScoringContext(
        entrantAName: 'Warangal',
        entrantBName: 'Nizamabad',
        config: config,
        lineupA: squad('A'),
        lineupB: squad('B'),
      );

  const baseConfig = <String, dynamic>{
    'oversPerInnings': 20,
    'ballsPerOver': 6,
    'playersPerTeam': 11,
  };

  String battingSideOf(Map<String, dynamic> state) =>
      ((state['innings'] as List).first as Map)['battingSide'] as String;

  test('with no toss recorded, side A bats — the old default', () {
    final state = cricket.initialState(contextWith(baseConfig));
    expect(battingSideOf(state), 'a');
  });

  test('a toss won by side B, electing to bat, puts side B in first', () {
    // The whole bug in one assertion: before the fix this state was never
    // rebuilt, so the answer here stayed 'a' no matter what the toss said.
    final state = cricket.initialState(
      contextWith({...baseConfig, 'battingFirst': 'b'}),
    );
    expect(battingSideOf(state), 'b');
  });

  test('the chasing side is derived from who batted first', () {
    // Not just cosmetic: `_settle` opens the second innings for whoever did
    // not bat, so getting the first one wrong inverts the whole match.
    var state = cricket.initialState(
      contextWith({
        ...baseConfig,
        'oversPerInnings': 1,
        'battingFirst': 'b',
      }),
    );
    final ctx = contextWith({
      ...baseConfig,
      'oversPerInnings': 1,
      'battingFirst': 'b',
    });

    // B opens, bats out its single over.
    state = cricket
        .apply(
          state,
          const ScoreAction(
            type: 'open',
            payload: {'striker': 'B1', 'nonStriker': 'B2', 'bowler': 'A1'},
          ),
          ctx,
        )
        .state;
    for (var ball = 0; ball < 6; ball++) {
      state = cricket
          .apply(state, const ScoreAction(type: 'runs', payload: {'runs': 2}),
              ctx)
          .state;
    }

    final innings = state['innings'] as List;
    expect(innings, hasLength(2));
    expect((innings[0] as Map)['battingSide'], 'b');
    expect((innings[1] as Map)['battingSide'], 'a',
        reason: 'the side that did not bat first is the side chasing');
    expect(state['target'], 13);
  });

  test('rebuilding an opening state is only safe before the first ball', () {
    // `recordToss` refuses once `lastSeq > 0`, and this is why: the rebuild
    // discards the innings entirely. After a delivery there is a log to
    // honour, and replacing the state under it would silently drop real runs.
    final ctx = contextWith({...baseConfig, 'battingFirst': 'a'});
    var state = cricket.initialState(ctx);
    state = cricket
        .apply(
          state,
          const ScoreAction(
            type: 'open',
            payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
          ),
          ctx,
        )
        .state;
    state = cricket
        .apply(state, const ScoreAction(type: 'runs', payload: {'runs': 4}),
            ctx)
        .state;

    expect(((state['innings'] as List).first as Map)['runs'], 4);

    final rebuilt = cricket.initialState(
      contextWith({...baseConfig, 'battingFirst': 'b'}),
    );
    expect(((rebuilt['innings'] as List).first as Map)['runs'], 0,
        reason: 'which is exactly what must not be allowed to happen to a '
            'match already under way');
  });
}
