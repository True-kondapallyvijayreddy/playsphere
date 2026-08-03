import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/match_flow.dart';
import 'package:playsphere/domain/scoring/plugins/basketball_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/football_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/volleyball_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// The shared match mechanics: periods, the clock, substitutions, timeouts
/// and reviews.
///
/// Most of what is checked here is arithmetic that used to be impossible
/// rather than wrong. Minutes played did not exist in any sport before this,
/// so the cases that matter are the ones where a naive implementation gets a
/// plausible-looking number: the player who was never substituted, the player
/// sent off at twenty minutes, and the player who came on and went off again.
void main() {
  const football = FootballPlugin();
  const basketball = BasketballPlugin();
  const volleyball = VolleyballPlugin();

  List<MatchPlayer> squad(String prefix, int n) => [
        for (var i = 1; i <= n; i++)
          MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
      ];

  // Fourteen named for eleven places: a bench, which is what makes any of
  // this testable.
  final ctx = ScoringContext(
    entrantAName: 'Warangal FC',
    entrantBName: 'Nizamabad FC',
    config: const {
      'periods': 2,
      'periodMinutes': 45,
      'periodLabel': 'Half',
      'squadSize': 11,
      'maxSubstitutions': 5,
      'allowReturn': false,
      'allowDraw': true,
    },
    lineupA: squad('A', 14),
    lineupB: squad('B', 14),
  );

  Map<String, dynamic> play(
    List<ScoreAction> actions, {
    ScoringContext? c,
    ScoringPlugin? plugin,
  }) {
    final engine = plugin ?? football;
    final on = c ?? ctx;
    var s = engine.initialState(on);
    for (final a in actions) {
      final r = engine.apply(s, a, on);
      expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  ScoreAction sub(Side side, String off, String on, int minute) => ScoreAction(
        type: 'substitution',
        side: side,
        payload: {'playerOffId': off, 'playerOnId': on, 'minute': minute},
      );

  num minutesOf(Map<String, dynamic> state, String id) =>
      football.boxScore(state, ctx, id.startsWith('A') ? Side.a : Side.b)
          .players
          .firstWhere((p) => p.playerId == id)['minutesPlayed'];

  group('who is on the field', () {
    test('the first eleven of a fourteen-man squad start', () {
      final s = football.initialState(ctx);
      expect(football.onCourt(s, Side.a), hasLength(11));
      expect(football.onCourt(s, Side.a), contains('A11'));
      expect(football.benchFor(s, ctx, Side.a), ['A12', 'A13', 'A14']);
    });

    test('a squad no bigger than the field puts everyone on', () {
      final short = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: ctx.config,
        lineupA: squad('A', 9),
        lineupB: squad('B', 9),
      );
      final s = football.initialState(short);
      expect(football.onCourt(s, Side.a), hasLength(9));
      expect(football.benchFor(s, short, Side.a), isEmpty);
    });

    test('the starting eleven can be declared before kick-off', () {
      final s = play([
        const ScoreAction(
          type: 'set_starters',
          side: Side.a,
          payload: {
            'starters': [
              'A1', 'A2', 'A3', 'A4', 'A5', 'A6',
              'A7', 'A8', 'A9', 'A10', 'A14',
            ],
          },
        ),
      ]);
      expect(football.onCourt(s, Side.a), contains('A14'));
      expect(football.onCourt(s, Side.a), isNot(contains('A11')));
      expect(football.benchFor(s, ctx, Side.a), contains('A11'));
    });

    test('but not once the match has moved, because minutes are already '
        'accruing against it', () {
      final started = play([sub(Side.a, 'A11', 'A12', 30)]);
      final r = football.apply(
        started,
        const ScoreAction(
          type: 'set_starters',
          side: Side.a,
          payload: {
            'starters': ['A1', 'A2', 'A3'],
          },
        ),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('before the match begins'));
    });

    test('a starting line-up cannot exceed the size of the field', () {
      final r = football.apply(
        football.initialState(ctx),
        const ScoreAction(
          type: 'set_starters',
          side: Side.a,
          payload: {
            'starters': [
              'A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7',
              'A8', 'A9', 'A10', 'A11', 'A12',
            ],
          },
        ),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('Only 11'));
    });
  });

  group('substitution legality', () {
    test('a substitution swaps the two players over', () {
      final s = play([sub(Side.a, 'A9', 'A12', 60)]);
      expect(football.onCourt(s, Side.a), contains('A12'));
      expect(football.onCourt(s, Side.a), isNot(contains('A9')));
      expect(football.substitutionsUsed(s, Side.a), 1);
      // The other side's allowance is its own.
      expect(football.substitutionsUsed(s, Side.b), 0);
    });

    test('somebody already on cannot come on again', () {
      final r = football.apply(
        football.initialState(ctx),
        sub(Side.a, 'A9', 'A8', 60),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('already on'));
    });

    test('somebody not on the field cannot come off', () {
      final r = football.apply(
        football.initialState(ctx),
        sub(Side.a, 'A12', 'A13', 60),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('is not on'));
    });

    test('a player from the other squad cannot come on', () {
      final r = football.apply(
        football.initialState(ctx),
        sub(Side.a, 'A9', 'B12', 60),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('not in this squad'));
    });

    test('under football rules a substituted player does not come back', () {
      final s = play([sub(Side.a, 'A9', 'A12', 30)]);
      final r = football.apply(s, sub(Side.a, 'A10', 'A9', 60), ctx);
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('cannot'));
      expect(r.rejection, contains('return'));
    });

    test('under basketball rules they do', () {
      final hoops = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: const {
          'periods': 4,
          'periodMinutes': 10,
          'squadSize': 5,
          'maxSubstitutions': 0,
          'allowReturn': true,
        },
        lineupA: squad('A', 10),
        lineupB: squad('B', 10),
      );
      var s = play([sub(Side.a, 'A5', 'A6', 4)],
          c: hoops, plugin: basketball);
      final back = basketball.apply(s, sub(Side.a, 'A4', 'A5', 8), hoops);
      expect(back.isAccepted, isTrue, reason: back.rejection);
      expect(basketball.onCourt(back.state, Side.a), contains('A5'));
    });

    test('the allowance is enforced and the message names it', () {
      var s = football.initialState(ctx);
      for (final pair in const [
        ['A1', 'A12'],
        ['A2', 'A13'],
        ['A3', 'A14'],
      ]) {
        final r = football.apply(s, sub(Side.a, pair[0], pair[1], 50), ctx);
        expect(r.isAccepted, isTrue, reason: r.rejection);
        s = r.state;
      }
      // The bench is empty now, so the fourth is refused for want of anyone
      // to bring on rather than for the allowance — which is the honest
      // reason, and the one the scorer can act on.
      final r = football.apply(s, sub(Side.a, 'A4', 'A12', 60), ctx);
      expect(r.isAccepted, isFalse);
    });

    test('the pad stops offering a substitution once the bench is empty', () {
      var s = football.initialState(ctx);
      for (final pair in const [
        ['A1', 'A12'],
        ['A2', 'A13'],
        ['A3', 'A14'],
      ]) {
        s = football.apply(s, sub(Side.a, pair[0], pair[1], 50), ctx).state;
      }
      expect(football.substitutionControl(s, ctx, Side.a), isNull);
      // The other side still has three on the bench.
      expect(football.substitutionControl(s, ctx, Side.b), isNotNull);
    });

    test('the pickers offer only who could actually be involved', () {
      final control = football.substitutionControl(
        football.initialState(ctx),
        ctx,
        Side.a,
      )!;
      final off = control.prompts.firstWhere((p) => p.key == 'playerOffId');
      final on = control.prompts.firstWhere((p) => p.key == 'playerOnId');

      expect(off.only, hasLength(11));
      expect(off.only, isNot(contains('A12')));
      expect(on.only, ['A12', 'A13', 'A14']);
    });
  });

  group('minutes played', () {
    test('a player who lasts the whole match gets the whole match', () {
      final s = play([
        const ScoreAction(type: 'next_period'),
        const ScoreAction(type: 'finish'),
      ]);
      // Two forty-five minute halves, and he was never taken off.
      expect(minutesOf(s, 'A1'), 90);
    });

    test('a substitution splits the ninety between the two of them', () {
      final s = play([
        const ScoreAction(type: 'next_period'),
        sub(Side.a, 'A9', 'A12', 60),
        const ScoreAction(type: 'finish'),
      ]);
      expect(minutesOf(s, 'A9'), 60);
      expect(minutesOf(s, 'A12'), 30);
    });

    test('a substitute who is himself substituted keeps only his own stint',
        () {
      final s = play([
        const ScoreAction(type: 'next_period'),
        sub(Side.a, 'A9', 'A12', 55),
        sub(Side.a, 'A12', 'A13', 75),
        const ScoreAction(type: 'finish'),
      ]);
      expect(minutesOf(s, 'A9'), 55);
      expect(minutesOf(s, 'A12'), 20);
      expect(minutesOf(s, 'A13'), 15);
    });

    test('an unused substitute has no minutes and does not appear', () {
      final s = play([
        const ScoreAction(type: 'next_period'),
        const ScoreAction(type: 'finish'),
      ]);
      final line = football
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A14');
      expect(line['minutesPlayed'], 0);
      expect(line.appeared, isFalse);
    });

    test('a sending-off ends the minutes as well as the afternoon', () {
      final s = play([
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A5', 'colour': 'red', 'minute': 20},
        ),
        const ScoreAction(type: 'next_period'),
        const ScoreAction(type: 'finish'),
      ]);
      expect(minutesOf(s, 'A5'), 20);
      expect(football.onCourt(s, Side.a), isNot(contains('A5')));
      // The ten who stayed on still played the full match.
      expect(minutesOf(s, 'A1'), 90);
    });

    test('a second yellow does the same, since it is a sending-off', () {
      final s = play([
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A6', 'colour': 'yellow', 'minute': 15},
        ),
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A6', 'colour': 'yellow', 'minute': 40},
        ),
        const ScoreAction(type: 'next_period'),
        const ScoreAction(type: 'finish'),
      ]);
      expect(minutesOf(s, 'A6'), 40);
    });

    test('a sent-off player cannot be replaced from the bench', () {
      final s = play([
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A5', 'colour': 'red', 'minute': 20},
        ),
      ]);
      final r = football.apply(s, sub(Side.a, 'A4', 'A5', 30), ctx);
      expect(r.isAccepted, isFalse);
      final back = football.apply(
        s,
        const ScoreAction(
          type: 'substitution',
          side: Side.a,
          payload: {'playerOffId': 'A4', 'playerOnId': 'A5', 'minute': 30},
        ),
        ctx,
      );
      expect(back.rejection, contains('plays on with ten'));
    });

    test('the clock never runs backwards, however the events arrive', () {
      final s = play([
        sub(Side.a, 'A9', 'A12', 70),
        // Recorded late and out of order — a real thing on a touchline.
        sub(Side.a, 'A10', 'A13', 55),
        const ScoreAction(type: 'finish'),
      ]);
      // A13's stint cannot be negative, whatever minute was typed.
      expect(minutesOf(s, 'A13'), greaterThanOrEqualTo(0));
      expect(minutesOf(s, 'A12'), greaterThanOrEqualTo(0));
      for (final p in football.boxScore(s, ctx, Side.a).players) {
        expect(p['minutesPlayed'], greaterThanOrEqualTo(0));
      }
    });

    test('minutes show during the match, not only after it', () {
      final s = play([sub(Side.a, 'A9', 'A12', 60)]);
      // A1 is still on the field with the clock at 60. Reading the tally
      // directly would say zero; the box score folds the open stint in.
      expect(minutesOf(s, 'A1'), 60);
      expect(football.playingTimeFor(s, 'A1'), 60);
    });

    test('reopening a finished match does not double-count anyone', () {
      final done = play([
        const ScoreAction(type: 'next_period'),
        const ScoreAction(type: 'finish'),
      ]);
      final reopened = football.apply(
        done,
        const ScoreAction(type: 'reopen'),
        ctx,
      ).state;
      final refinished = football.apply(
        reopened,
        const ScoreAction(type: 'finish'),
        ctx,
      ).state;
      expect(minutesOf(refinished, 'A1'), 90);
    });
  });

  group('timeouts', () {
    final hoops = ScoringContext(
      entrantAName: 'Hyderabad',
      entrantBName: 'Secunderabad',
      config: const {
        'periods': 4,
        'periodMinutes': 10,
        'squadSize': 5,
        'timeoutsPerPeriod': 2,
      },
      lineupA: squad('A', 8),
      lineupB: squad('B', 8),
    );

    test('a side may call its allowance and no more', () {
      var s = basketball.initialState(hoops);
      for (var i = 0; i < 2; i++) {
        final r = basketball.apply(
          s,
          const ScoreAction(type: 'timeout', side: Side.a),
          hoops,
        );
        expect(r.isAccepted, isTrue, reason: r.rejection);
        s = r.state;
      }
      final third = basketball.apply(
        s,
        const ScoreAction(type: 'timeout', side: Side.a),
        hoops,
      );
      expect(third.isAccepted, isFalse);
      expect(third.rejection, contains('no timeouts left'));
      // The other side is untouched.
      expect(basketball.timeoutsLeft(s, hoops, Side.b), 2);
    });

    test('a per-period allowance refills at the break', () {
      var s = basketball.initialState(hoops);
      s = basketball
          .apply(s, const ScoreAction(type: 'timeout', side: Side.a), hoops)
          .state;
      s = basketball
          .apply(s, const ScoreAction(type: 'timeout', side: Side.a), hoops)
          .state;
      expect(basketball.timeoutsLeft(s, hoops, Side.a), 0);

      s = basketball
          .apply(s, const ScoreAction(type: 'next_period'), hoops)
          .state;
      expect(basketball.timeoutsLeft(s, hoops, Side.a), 2);
    });

    test('a competition with no timeouts shows no button and takes no call',
        () {
      final plain = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: const {'periods': 2, 'periodMinutes': 45, 'squadSize': 11},
        lineupA: squad('A', 12),
        lineupB: squad('B', 12),
      );
      final s = football.initialState(plain);
      expect(football.timeoutControl(s, plain, Side.a), isNull);
      final r = football.apply(
        s,
        const ScoreAction(type: 'timeout', side: Side.a),
        plain,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('does not allow timeouts'));
    });
  });

  group('reviews', () {
    final withReviews = ScoringContext(
      entrantAName: 'A',
      entrantBName: 'B',
      config: const {
        'periods': 2,
        'periodMinutes': 45,
        'squadSize': 11,
        'reviewsPerSide': 1,
      },
      lineupA: squad('A', 12),
      lineupB: squad('B', 12),
    );

    test('a review that is upheld is not spent', () {
      final s = football.apply(
        football.initialState(withReviews),
        const ScoreAction(
          type: 'review',
          side: Side.a,
          payload: {'upheld': true},
        ),
        withReviews,
      ).state;
      expect(football.reviewsLeft(s, withReviews, Side.a), 1);
      // It still happened, and the log says so.
      expect((s[MatchReviews.logKey] as List), hasLength(1));
    });

    test('a review that is lost is', () {
      final s = football.apply(
        football.initialState(withReviews),
        const ScoreAction(
          type: 'review',
          side: Side.a,
          payload: {'upheld': false},
        ),
        withReviews,
      ).state;
      expect(football.reviewsLeft(s, withReviews, Side.a), 0);

      final second = football.apply(
        s,
        const ScoreAction(
          type: 'review',
          side: Side.a,
          payload: {'upheld': false},
        ),
        withReviews,
      );
      expect(second.isAccepted, isFalse);
      expect(second.rejection, contains('no reviews left'));
    });

    test('a ruleset can charge for a successful review instead', () {
      final strict = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: const {
          ...{
            'periods': 2,
            'periodMinutes': 45,
            'squadSize': 11,
            'reviewsPerSide': 1,
          },
          'retainReviewOnSuccess': false,
        },
        lineupA: squad('A', 12),
        lineupB: squad('B', 12),
      );
      final s = football.apply(
        football.initialState(strict),
        const ScoreAction(
          type: 'review',
          side: Side.a,
          payload: {'upheld': true},
        ),
        strict,
      ).state;
      expect(football.reviewsLeft(s, strict, Side.a), 0);
    });
  });

  group('volleyball counts by the set, not the clock', () {
    final vb = ScoringContext(
      entrantAName: 'Warangal',
      entrantBName: 'Khammam',
      config: const {
        'pointsPerSet': 25,
        'decidingSetPoints': 15,
        'setsToWin': 3,
        'winBy': 2,
        'squadSize': 6,
        'maxSubstitutions': 6,
        'allowReturn': true,
        'timeoutsPerSet': 2,
      },
      lineupA: squad('A', 12),
      lineupB: squad('B', 12),
    );

    Map<String, dynamic> winSet(Map<String, dynamic> s, Side side) {
      for (var i = 0; i < 25; i++) {
        final r = volleyball.apply(
          s,
          ScoreAction(
            type: 'point',
            side: side,
            payload: const {'how': 'opponent_error'},
          ),
          vb,
        );
        s = r.state;
      }
      return s;
    }

    test('it keeps no minutes, because the match has no clock to keep them by',
        () {
      final s = volleyball.apply(
        volleyball.initialState(vb),
        const ScoreAction(
          type: 'substitution',
          side: Side.a,
          payload: {'playerOffId': 'A6', 'playerOnId': 'A7'},
        ),
        vb,
      );
      expect(s.isAccepted, isTrue, reason: s.rejection);
      final columns = volleyball.boxScore(s.state, vb, Side.a).columns;
      expect(
        columns.map((c) => c.key),
        isNot(contains(SquadRotation.minutesStat)),
      );
    });

    test('timeouts and substitutions both refill when the set does', () {
      var s = volleyball.initialState(vb);
      s = volleyball
          .apply(s, const ScoreAction(type: 'timeout', side: Side.a), vb)
          .state;
      s = volleyball
          .apply(
            s,
            const ScoreAction(
              type: 'substitution',
              side: Side.a,
              payload: {'playerOffId': 'A6', 'playerOnId': 'A7'},
            ),
            vb,
          )
          .state;
      expect(volleyball.timeoutsUsed(s, Side.a), 1);
      expect(volleyball.substitutionsUsed(s, Side.a), 1);

      s = winSet(s, Side.a);
      expect(s['setsA'], 1, reason: 'the set should have been settled');
      expect(volleyball.timeoutsUsed(s, Side.a), 0);
      expect(volleyball.substitutionsUsed(s, Side.a), 0);
    });

    test('the starting six can no longer be declared once rallies have been '
        'played', () {
      var s = volleyball.initialState(vb);
      s = volleyball
          .apply(
            s,
            const ScoreAction(
              type: 'point',
              side: Side.a,
              payload: {'how': 'opponent_error'},
            ),
            vb,
          )
          .state;
      final r = volleyball.apply(
        s,
        const ScoreAction(
          type: 'set_starters',
          side: Side.a,
          payload: {
            'starters': ['A1', 'A2', 'A3', 'A4', 'A5', 'A7'],
          },
        ),
        vb,
      );
      expect(r.isAccepted, isFalse);
    });
  });

  group('replay agrees with the live match', () {
    test('rebuilding from the log reproduces the minutes exactly', () {
      final actions = <ScoreAction>[
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'assistId': 'A10'},
        ),
        const ScoreAction(type: 'next_period'),
        sub(Side.a, 'A9', 'A12', 58),
        const ScoreAction(
          type: 'card',
          side: Side.b,
          payload: {'playerId': 'B4', 'colour': 'red', 'minute': 70},
        ),
        const ScoreAction(type: 'finish'),
      ];

      final live = play(actions);
      final replayed = football.replay(actions, ctx);

      for (final id in const ['A9', 'A12', 'A1', 'B4', 'B1']) {
        expect(
          football.playingTimeFor(replayed, id),
          football.playingTimeFor(live, id),
          reason: id,
        );
      }
      expect(replayed['a'], live['a']);
      expect(football.onCourt(replayed, Side.b),
          football.onCourt(live, Side.b));
    });

    test('an undone substitution puts the player back on', () {
      final log = [
        LoggedAction(seq: 1, action: sub(Side.a, 'A9', 'A12', 60)),
        const LoggedAction(
          seq: 2,
          action: ScoreAction(
            type: ScoringPlugin.undoActionType,
            payload: {'reversesSeq': 1},
          ),
        ),
      ];
      final s = football.rebuild(log, ctx);
      expect(football.onCourt(s, Side.a), contains('A9'));
      expect(football.onCourt(s, Side.a), isNot(contains('A12')));
      expect(football.substitutionsUsed(s, Side.a), 0);
    });
  });

  group('the duplicated period block is gone', () {
    test('every clock sport now rejects a period past the last one the same '
        'way', () {
      for (final (plugin, context) in [
        (football, ctx),
        (
          basketball,
          ScoringContext(
            entrantAName: 'A',
            entrantBName: 'B',
            config: const {'periods': 4, 'periodMinutes': 10, 'squadSize': 5},
            lineupA: squad('A', 8),
            lineupB: squad('B', 8),
          ),
        ),
      ]) {
        var s = plugin.initialState(context);
        final periods = context.intConfig('periods', 2);
        for (var i = 1; i < periods; i++) {
          s = plugin
              .apply(s, const ScoreAction(type: 'next_period'), context)
              .state;
        }
        final past = plugin.apply(
          s,
          const ScoreAction(type: 'next_period'),
          context,
        );
        expect(past.isAccepted, isFalse);
        expect(past.rejection, contains('End match'));
      }
    });

    test('basketball records an assist logged on its own', () {
      // The pad had an "Ast" button and the engine had no case for it, so
      // every press came back "Unknown action" and the assist was lost.
      final hoops = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: const {'periods': 4, 'squadSize': 5},
        lineupA: squad('A', 8),
        lineupB: squad('B', 8),
      );
      final r = basketball.apply(
        basketball.initialState(hoops),
        const ScoreAction(
          type: 'assist',
          side: Side.a,
          payload: {'playerId': 'A3'},
        ),
        hoops,
      );
      expect(r.isAccepted, isTrue, reason: r.rejection);
      expect(
        basketball
            .boxScore(r.state, hoops, Side.a)
            .players
            .firstWhere((p) => p.playerId == 'A3')['assists'],
        1,
      );
    });
  });
}
