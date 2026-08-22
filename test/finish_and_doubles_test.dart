import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/football_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/kho_kho_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/pickleball_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// Two complaints from a scorer, and what they turned out to be.
///
///  1. **"It keeps asking who won the rally."** In doubles it asked on every
///     single point, because the engine had no idea where the four players
///     were standing and no way to work it out. It does now: one question per
///     side, at that side's first serve, and the laws carry the rest.
///
///  2. **"The match still says in progress."** A football match ends when the
///     referee blows, and nothing in the app can know that — the button that
///     records it was in a tray under the pad where nobody looks at full
///     time. The engines now say when the final period is under way, and the
///     pad puts the button in front of the scorer.
void main() {
  const pairA = [
    MatchPlayer(id: 'A1', name: 'Sania'),
    MatchPlayer(id: 'A2', name: 'Ankita'),
  ];
  const pairB = [
    MatchPlayer(id: 'B1', name: 'Rohan'),
    MatchPlayer(id: 'B2', name: 'Vikram'),
  ];

  Map<String, dynamic> run(
    ScoringPlugin plugin,
    ScoringContext ctx,
    List<ScoreAction> actions, [
    Map<String, dynamic>? from,
  ]) {
    var s = from ?? plugin.initialState(ctx);
    for (final a in actions) {
      final r = plugin.apply(s, a, ctx);
      expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
      s = r.state;
    }
    return s;
  }

  ScoringContext badmintonDoubles() => ScoringContext(
        entrantAName: 'Sania / Ankita',
        entrantBName: 'Rohan / Vikram',
        config: {
          ...RulePresets.resolve(sportId: 'badminton').toMap(),
          'doubles': true,
        },
        lineupA: pairA,
        lineupB: pairB,
      );

  /// The prompts hanging off the pad's primary buttons right now.
  List<PlayerPrompt> promptsOn(
    ScoringPlugin plugin,
    Map<String, dynamic> state,
    ScoringContext ctx,
  ) {
    for (final g in plugin.controls(state, ctx)) {
      for (final c in g.controls) {
        if (c.action == 'rally') return c.prompts;
      }
    }
    return const [];
  }

  // ==========================================================================
  group('Badminton doubles asks once, not every rally', () {
    const badminton = BadmintonPlugin();

    test('the question is asked at a pair\'s first serve and then dropped', () {
      final ctx = badmintonDoubles();
      var s = badminton.initialState(ctx);
      final opener = badminton.serverFor(s);

      final asked = promptsOn(badminton, s, ctx);
      expect(asked, hasLength(1));
      expect(asked.single.key, 'serverId');
      expect(asked.single.label, contains('serving'));

      // Answered on the first rally, whoever won it.
      s = run(badminton, ctx, [
        ScoreAction(
          type: 'rally',
          side: opener,
          payload: {'serverId': ctx.lineupFor(opener)[1].id},
        ),
      ], s);

      expect(badminton.courtsSet(s, opener), isTrue);
      expect(promptsOn(badminton, s, ctx), isEmpty,
          reason: 'the pad must not ask that side again all match');
    });

    test('the answer names the server, and he keeps serving as they win', () {
      final ctx = badmintonDoubles();
      var s = badminton.initialState(ctx);
      final opener = badminton.serverFor(s);
      final second = ctx.lineupFor(opener)[1];

      s = run(badminton, ctx, [
        ScoreAction(
          type: 'rally',
          side: opener,
          payload: {'serverId': second.id},
        ),
      ], s);

      // The point of the whole change: the pair that wins a rally does NOT
      // swap servers. The same player serves from the other court.
      expect(badminton.serverFor(s), opener);
      expect(badminton.serverName(s, ctx), second.name);
      expect(badminton.serviceCourt(s), 'left', reason: 'their score is now 1');

      s = run(badminton, ctx, [ScoreAction(type: 'rally', side: opener)], s);
      expect(badminton.serverName(s, ctx), second.name,
          reason: 'still the same server on the second point in a row');
      expect(badminton.serviceCourt(s), 'right');
    });

    test('a side-out hands the serve over, and back to the right partner', () {
      final ctx = badmintonDoubles();
      var s = badminton.initialState(ctx);
      final opener = badminton.serverFor(s);
      final other = opener.opposite;

      // A serves once and wins, then loses the next rally.
      s = run(badminton, ctx, [
        ScoreAction(
          type: 'rally',
          side: opener,
          payload: {'serverId': ctx.lineupFor(opener).first.id},
        ),
        ScoreAction(
          type: 'rally',
          side: other,
          payload: {'serverId': ctx.lineupFor(other).first.id},
        ),
      ], s);

      expect(badminton.serverFor(s), other, reason: 'the receivers broke');
      expect(badminton.serverName(s, ctx), ctx.lineupFor(other)[1].name,
          reason: 'their score is 1, so the other partner is in the left '
              'court and serves');

      // Hand it straight back. A's arrangement was fixed on the first rally
      // and must survive the excursion without being asked for again.
      s = run(badminton, ctx, [ScoreAction(type: 'rally', side: opener)], s);
      expect(badminton.serverFor(s), opener);
      expect(promptsOn(badminton, s, ctx), isEmpty);
      expect(badminton.serverName(s, ctx), ctx.lineupFor(opener)[1].name,
          reason: 'A is on 2 — even — so the partner who started in the left '
              'court is now serving');
    });

    test('the point is credited without anybody being asked', () {
      final ctx = badmintonDoubles();
      var s = badminton.initialState(ctx);
      final opener = badminton.serverFor(s);
      final server = ctx.lineupFor(opener).first;

      s = run(badminton, ctx, [
        ScoreAction(
          type: 'rally',
          side: opener,
          payload: {'serverId': server.id},
        ),
      ], s);

      // Served and won: the point is the server's, and it is a serve point.
      expect(PlayerTally.of(s, server.id)['pointsWon'], 1);
      expect(PlayerTally.of(s, server.id)['pointsOnServe'], 1);

      // Broken: the receiver gets it, as a receive point.
      final receiverName = badminton.receiverName(s, ctx);
      final receiver = ctx
          .lineupFor(opener.opposite)
          .firstWhere((p) => p.name == receiverName);
      s = run(
          badminton, ctx, [ScoreAction(type: 'rally', side: opener.opposite)], s);
      expect(PlayerTally.of(s, receiver.id)['pointsOnReceive'], 1);
      expect(PlayerTally.of(s, receiver.id)['pointsWon'], 1);
    });

    test('a whole game runs on one tap a rally', () {
      final ctx = badmintonDoubles();
      var s = badminton.initialState(ctx);
      final opener = badminton.serverFor(s);

      // First tap answers the one question; the other twenty do not.
      s = run(badminton, ctx, [
        ScoreAction(
          type: 'rally',
          side: opener,
          payload: {'serverId': ctx.lineupFor(opener).first.id},
        ),
        for (var i = 0; i < 20; i++) ScoreAction(type: 'rally', side: opener),
      ], s);

      expect(badminton.outcome(s, ctx).isComplete, isFalse,
          reason: 'one game of a best-of-three');
      expect(s['gamesA'] == 1 || s['gamesB'] == 1, isTrue);
      // Every point landed on somebody. An empty tally is the bug this
      // replaces — a doubles career that stayed at zero all season.
      expect(PlayerTally.everyone(s)['pointsWon'], 21);
    });

    test('singles is untouched — no prompt, because there is no question', () {
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: {
          ...RulePresets.resolve(sportId: 'badminton').toMap(),
          'doubles': false,
        },
        lineupA: const [MatchPlayer(id: 'A1', name: 'Sania')],
        lineupB: const [MatchPlayer(id: 'B1', name: 'Rohan')],
      );
      final s = badminton.initialState(ctx);
      expect(promptsOn(badminton, s, ctx), isEmpty);

      final after = run(badminton, ctx, [
        const ScoreAction(type: 'rally', side: Side.a),
      ], s);
      expect(PlayerTally.of(after, 'A1')['pointsWon'], 1);
    });
  });

  // ==========================================================================
  group('Pickleball doubles stops asking too', () {
    const pickleball = PickleballPlugin();

    test('no per-rally prompt in doubles, and the rally still lands', () {
      final ctx = ScoringContext(
        entrantAName: 'Sania / Ankita',
        entrantBName: 'Rohan / Vikram',
        config: {
          ...RulePresets.resolve(sportId: 'pickleball').toMap(),
          'doubles': true,
        },
        lineupA: pairA,
        lineupB: pairB,
      );
      var s = pickleball.initialState(ctx);
      expect(promptsOn(pickleball, s, ctx), isEmpty);

      final serving = pickleball.serverFor(s);
      s = run(pickleball, ctx, [ScoreAction(type: 'rally', side: serving)], s);
      expect(PlayerTally.everyone(s)['pointsWon'], 1);
    });

    test('singles keeps the prompt the pad answers for itself', () {
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: {
          ...RulePresets.resolve(sportId: 'pickleball').toMap(),
          'doubles': false,
        },
        lineupA: const [MatchPlayer(id: 'A1', name: 'Sania')],
        lineupB: const [MatchPlayer(id: 'B1', name: 'Rohan')],
      );
      expect(promptsOn(pickleball, pickleball.initialState(ctx), ctx),
          hasLength(1));
    });
  });

  // ==========================================================================
  group('Table tennis doubles stops asking too', () {
    const tt = TableTennisPlugin();

    ScoringContext doubles() => ScoringContext(
          entrantAName: 'Sania / Ankita',
          entrantBName: 'Rohan / Vikram',
          config: {
            ...RulePresets.resolve(sportId: 'table_tennis').toMap(),
            'doubles': true,
          },
          lineupA: pairA,
          lineupB: pairB,
        );

    List<PlayerPrompt> pointPrompts(Map<String, dynamic> s, ScoringContext c) {
      for (final g in tt.controls(s, c)) {
        for (final ctrl in g.controls) {
          if (ctrl.action == 'point') return ctrl.prompts;
        }
      }
      return const [];
    }

    test('no dialog, and the point lands on the player the laws name', () {
      final ctx = doubles();
      var s = tt.initialState(ctx);
      expect(pointPrompts(s, ctx), isEmpty);

      final serving = tt.serverFor(s, ctx);
      final serverName = tt.serverName(s, ctx);
      s = run(tt, ctx, [ScoreAction(type: 'point', side: serving)], s);

      final server =
          ctx.lineupFor(serving).firstWhere((p) => p.name == serverName);
      expect(PlayerTally.of(s, server.id)['pointsWon'], 1,
          reason: 'the server won the point they served');
    });

    test('singles keeps the prompt the pad fills in silently', () {
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: {
          ...RulePresets.resolve(sportId: 'table_tennis').toMap(),
          'doubles': false,
        },
        lineupA: const [MatchPlayer(id: 'A1', name: 'Sania')],
        lineupB: const [MatchPlayer(id: 'B1', name: 'Rohan')],
      );
      expect(pointPrompts(tt.initialState(ctx), ctx), hasLength(1));
    });
  });

  // ==========================================================================
  group('The pad offers to finish when play reaches its end', () {
    test('football offers nothing in the first half and a button in the last',
        () {
      const football = FootballPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Chennai',
        entrantBName: 'Bengaluru',
        config: RulePresets.resolve(sportId: 'football').toMap(),
        lineupA: pairA,
        lineupB: pairB,
      );
      var s = football.initialState(ctx);
      expect(football.finishControl(s, ctx), isNull,
          reason: 'there is half a match still to play');

      s = run(football, ctx, [const ScoreAction(type: 'next_period')], s);
      final finish = football.finishControl(s, ctx);
      expect(finish, isNotNull);
      expect(finish!.action, 'finish');

      // And it is the same action the tray button always carried, so pressing
      // it goes down the path that was already tested.
      final done = run(football, ctx, [const ScoreAction(type: 'finish')], s);
      expect(football.outcome(done, ctx).isComplete, isTrue);
    });

    test('kho kho offers it once both innings have run their turns', () {
      const khoKho = KhoKhoPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: RulePresets.resolve(sportId: 'kho_kho').toMap(),
        lineupA: pairA,
        lineupB: pairB,
      );
      var s = khoKho.initialState(ctx);
      expect(khoKho.finishControl(s, ctx), isNull);

      // Turn 1 of 4 through to turn 4 of 4.
      s = run(khoKho, ctx, [
        for (var i = 0; i < 3; i++) const ScoreAction(type: 'end_turn'),
      ], s);
      expect(khoKho.finishControl(s, ctx), isNotNull,
          reason: 'end_turn already refuses to go past here — the pad should '
              'be offering the finish instead of an error');
    });

    test('a sport that finishes itself is never asked to', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'tennis').toMap(),
        lineupA: const [MatchPlayer(id: 'A1', name: 'Sania')],
        lineupB: const [MatchPlayer(id: 'B1', name: 'Rohan')],
      );
      expect(tennis.finishControl(tennis.initialState(ctx), ctx), isNull);
    });
  });
}
