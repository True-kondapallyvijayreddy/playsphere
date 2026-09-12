import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Getting OUT of an innings.
///
/// Both bugs pinned here stranded a real match on a phone with no button that
/// could move it forward, which is worse than a wrong number: a wrong number
/// can be corrected afterwards, an unfinishable match cannot be played.
///
///  * **The last ball of an over.** A wicket there clears the striker, and
///    then the over rollover rotates the ends — so the EMPTY crease is the
///    non-striker's, not the striker's. Every branch of `controls` tested for
///    a missing striker, so the pad fell through to its opening dialog, the
///    one group that offered no way to end the innings, and `new_batter`
///    refused the batter it was asking for.
///  * **A short-handed side.** All out means "cannot field two batters", which
///    is a fact about the squad that turned up, not about the format's
///    nominal team size. Taken from the config alone, a six-a-side innings
///    waited forever for an eleventh batter who was never registered.
void main() {
  const cricket = CricketPlugin();

  List<MatchPlayer> squad(String prefix, int n) => [
        for (var i = 1; i <= n; i++)
          MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
      ];

  ScoringContext ctxWith({int perTeam = 11, int squadA = 11, int overs = 5}) =>
      ScoringContext(
        entrantAName: 'Warangal',
        entrantBName: 'Nizamabad',
        config: {
          'oversPerInnings': overs,
          'ballsPerOver': 6,
          'playersPerTeam': perTeam,
          'battingFirst': 'a',
        },
        lineupA: squad('A', squadA),
        lineupB: squad('B', 11),
      );

  Map<String, dynamic> play(
    Map<String, dynamic> state,
    List<ScoreAction> actions,
    ScoringContext ctx,
  ) {
    var s = state;
    for (final a in actions) {
      final r = cricket.apply(s, a, ctx);
      expect(r.isAccepted, isTrue,
          reason: 'rejected "${a.type}": ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  ScoreAction runs(int n) => ScoreAction(type: 'runs', payload: {'runs': n});
  const wicket = ScoreAction(type: 'wicket', payload: {'how': 'bowled'});

  Map<String, dynamic> opened(ScoringContext ctx) =>
      play(cricket.initialState(ctx), const [
        ScoreAction(
          type: 'open',
          payload: {'striker': 'A1', 'nonStriker': 'A2', 'bowler': 'B1'},
        ),
      ], ctx);

  /// Every action the pad is currently offering, flattened.
  Set<String> offered(Map<String, dynamic> s, ScoringContext ctx) => {
        for (final g in cricket.controls(s, ctx))
          for (final c in g.controls) c.action,
      };

  Map<String, dynamic> innings(Map<String, dynamic> s) =>
      (s['innings'] as List)[(s['inningsIndex'] as num).toInt()]
          as Map<String, dynamic>;

  group('a wicket on the last ball of an over', () {
    // Five dots, then a wicket: the sixth ball closes the over AND takes the
    // wicket, which is the exact collision the pad could not represent.
    Map<String, dynamic> lastBallWicket(ScoringContext ctx) => play(
          opened(ctx),
          [runs(0), runs(0), runs(0), runs(0), runs(0), wicket],
          ctx,
        );

    test('leaves the NON-striker end empty, not the striker end', () {
      final ctx = ctxWith();
      final cur = innings(lastBallWicket(ctx));
      // A1 was out; A2 rotated onto strike for the new over.
      expect(cur['striker'], 'A2');
      expect(cur['nonStriker'], isNull);
      expect(cur['bowler'], isNull, reason: 'the bowler must change');
    });

    test('the pad asks for a bowler and can still end the innings', () {
      final ctx = ctxWith();
      final actions = offered(lastBallWicket(ctx), ctx);
      // Before the fix this fell through to the opening dialog, whose only
      // action was 'open' — no way forward and no way out.
      expect(actions, contains('new_bowler'));
      expect(actions, contains('end_innings'),
          reason: 'the scorer must always be able to end the innings');
      expect(actions, isNot(contains('open')));
    });

    test('the incoming batter fills the empty non-striker end', () {
      final ctx = ctxWith();
      var s = lastBallWicket(ctx);
      s = play(s, const [
        ScoreAction(type: 'new_bowler', payload: {'playerId': 'B2'}),
        ScoreAction(type: 'new_batter', payload: {'playerId': 'A3'}),
      ], ctx);

      final cur = innings(s);
      expect(cur['striker'], 'A2', reason: 'the survivor keeps the strike');
      expect(cur['nonStriker'], 'A3');
      // And the match is scorable again.
      expect(offered(s, ctx), contains('runs'));
    });

    test('the batter already at the crease is refused', () {
      final ctx = ctxWith();
      var s = lastBallWicket(ctx);
      s = play(s, const [
        ScoreAction(type: 'new_bowler', payload: {'playerId': 'B2'}),
      ], ctx);
      final r = cricket.apply(
        s,
        const ScoreAction(type: 'new_batter', payload: {'playerId': 'A2'}),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('already at the crease'));
    });
  });

  /// Takes [n] wickets, naming a new bowler at every over break and a new
  /// batter into whichever crease the last wicket emptied. Stops early the
  /// moment the innings closes, which is the thing under test.
  Map<String, dynamic> takeWickets(
    Map<String, dynamic> start,
    ScoringContext ctx,
    int n,
  ) {
    var s = start;
    var nextBowler = 1;

    // Derived from the state rather than counted, so the helper can be called
    // twice on the same innings without handing back a batter who is out.
    String? freeBatter(Map<String, dynamic> cur) {
      final batting = (cur['batting'] as Map?) ?? const {};
      for (final p in ctx.lineupFor(Side.a)) {
        if (p.id == cur['striker'] || p.id == cur['nonStriker']) continue;
        if ((batting[p.id] as Map?)?['out'] == true) continue;
        return p.id;
      }
      return null;
    }
    for (var i = 0; i < n; i++) {
      if ((s['inningsIndex'] as num).toInt() != 0) return s;
      var cur = innings(s);
      if (cur['bowler'] == null) {
        nextBowler = nextBowler % 11 + 1;
        s = play(s, [
          ScoreAction(type: 'new_bowler', payload: {'playerId': 'B$nextBowler'}),
        ], ctx);
        cur = innings(s);
      }
      if (cur['striker'] == null || cur['nonStriker'] == null) {
        final who = freeBatter(cur);
        if (who == null) return s;
        s = play(s, [
          ScoreAction(type: 'new_batter', payload: {'playerId': who}),
        ], ctx);
      }
      final r = cricket.apply(s, wicket, ctx);
      if (!r.isAccepted) return s;
      s = r.state;
    }
    return s;
  }

  group('a side is all out when IT runs out of batters', () {
    test('a 2-player side is all out on the first wicket', () {
      // The format still says 11 a side. The squad says two.
      final ctx = ctxWith(perTeam: 11, squadA: 2);
      final s = play(opened(ctx), [wicket], ctx);

      final first = (s['innings'] as List).first as Map<String, dynamic>;
      expect(first['closed'], isTrue, reason: 'one wicket is all out');
      expect(s['inningsIndex'], 1, reason: 'the second innings must open');
      expect(s['target'], isNotNull);
    });

    test('the second innings is handed to the other side to start', () {
      final ctx = ctxWith(perTeam: 11, squadA: 2);
      final s = play(opened(ctx), [runs(4), wicket], ctx);

      expect(innings(s)['battingSide'], 'b');
      expect(s['target'], 5);
      // A fresh innings names nobody, so the opening dialog is right here.
      expect(offered(s, ctx), contains('open'));
      expect(s['complete'], isNot(true));
    });

    test('a 6-a-side squad is all out at five, not ten', () {
      final ctx = ctxWith(perTeam: 11, squadA: 6, overs: 20);
      // Four down, both creases occupied, still going.
      var s = takeWickets(opened(ctx), ctx, 4);
      expect(innings(s)['wickets'], 4);
      expect((s['innings'] as List).first['closed'], isNot(true));

      s = takeWickets(s, ctx, 1);
      expect((s['innings'] as List).first['wickets'], 5);
      expect((s['innings'] as List).first['closed'], isTrue);
      expect(s['inningsIndex'], 1);
    });

    test('a full squad is unaffected — still ten wickets', () {
      final ctx = ctxWith(perTeam: 11, squadA: 11, overs: 20);
      var s = takeWickets(opened(ctx), ctx, 9);
      expect(innings(s)['wickets'], 9);
      expect((s['innings'] as List).first['closed'], isNot(true));

      s = takeWickets(s, ctx, 1);
      expect((s['innings'] as List).first['wickets'], 10);
      expect((s['innings'] as List).first['closed'], isTrue);
    });

    test('a squad larger than the format is still all out at ten', () {
      final ctx = ctxWith(perTeam: 11, squadA: 15, overs: 20);
      final s = takeWickets(opened(ctx), ctx, 10);
      expect((s['innings'] as List).first['wickets'], 10);
      expect((s['innings'] as List).first['closed'], isTrue);
    });

    test('an unentered line-up falls back to the configured team size', () {
      // Nobody registered: the squad is not evidence of a short-handed side.
      const ctx = ScoringContext(
        entrantAName: 'Warangal',
        entrantBName: 'Nizamabad',
        config: {
          'oversPerInnings': 20,
          'ballsPerOver': 6,
          'playersPerTeam': 11,
          'battingFirst': 'a',
        },
      );
      final s = play(opened(ctx), [wicket], ctx);
      expect((s['innings'] as List).first['closed'], isNot(true),
          reason: 'one wicket cannot end an innings of eleven',);
    });
  });

  group('the pad never strands the scorer', () {
    test('every state reachable mid-innings offers a way out', () {
      final ctx = ctxWith(squadA: 3, overs: 20);
      var s = opened(ctx);
      // Walk a whole short innings and check the escape hatch at every step.
      for (final a in [runs(1), runs(0), wicket, runs(2)]) {
        final r = cricket.apply(s, a, ctx);
        if (!r.isAccepted) break;
        s = r.state;
        if (s['complete'] == true) break;
        final actions = offered(s, ctx);
        expect(actions, isNotEmpty, reason: 'the pad must offer something');
      }
    });
  });
}
