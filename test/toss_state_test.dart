import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/kho_kho_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
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

  /// Every other sport had the same bug cricket did, one layer along.
  ///
  /// `recordToss` has written `startingSide` into the frozen config for every
  /// sport for a while — "who served first" and "who raided first" belong on a
  /// scorecard as much as "who batted first". Cricket was the only engine that
  /// ever read it, under its own `battingFirst` key. So a badminton pair that
  /// won the toss and chose to serve opened the match receiving, and the
  /// scorer had to notice and correct it on the first rally of every match.
  ///
  /// The choice itself is already resolved before it gets here: `TossOptions`
  /// knows that "receive" and "choose ends" hand the first turn to the other
  /// side, and `TossDialog._startingSide` turns winner + choice into one
  /// answer. These pin the last link — that the answer reaches the engine.
  group('the toss decides who starts, in every sport', () {
    ScoringContext startingWith(String? side) => ScoringContext(
          entrantAName: 'Anand',
          entrantBName: 'Bhavani',
          config: side == null ? const {} : {'startingSide': side},
          lineupA: const [MatchPlayer(id: 'p1', name: 'Anand')],
          lineupB: const [MatchPlayer(id: 'p2', name: 'Bhavani')],
        );

    test('badminton opens with the toss winner serving', () {
      const plugin = BadmintonPlugin();
      expect(plugin.initialState(startingWith('b'))['server'], 'b');
      expect(plugin.initialState(startingWith('a'))['server'], 'a');
    });

    test('tennis opens with the toss winner serving', () {
      const plugin = TennisPlugin();
      expect(plugin.initialState(startingWith('b'))['server'], 'b');
    });

    test('table tennis opens with the toss winner serving', () {
      const plugin = TableTennisPlugin();
      expect(plugin.initialState(startingWith('b'))['firstServer'], 'b');
    });

    test('kho-kho opens with the side that chose to chase attacking', () {
      const plugin = KhoKhoPlugin();
      expect(plugin.initialState(startingWith('b'))['attackingSide'], 'b');
    });

    test('a skipped toss still opens with side A, as it always did', () {
      // Nothing recorded the toss, so there is no answer to honour. Side A is
      // the only defensible default and is what every match played before
      // this change opened with.
      const plugin = BadmintonPlugin();
      expect(plugin.initialState(startingWith(null))['server'], 'a');
    });

    test('an unrecognised value falls back to A rather than to neither side',
        () {
      // `Side.fromWire` answers `neutral` for anything it does not know, and
      // "neither side serves" is not a state any of these engines can open in.
      const plugin = BadmintonPlugin();
      expect(plugin.initialState(startingWith('nonsense'))['server'], 'a');
    });
  });
}
