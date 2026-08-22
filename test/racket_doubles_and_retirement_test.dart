import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/pickleball_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/tennis_plugin.dart';
import 'package:playsphere/domain/scoring/racket_rules.dart';
import 'package:playsphere/domain/scoring/rule_config.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// The racket sports as their rulebooks actually define them.
///
/// Three things are pinned here that the engines used to get wrong or not do
/// at all:
///
///  * **Doubles is a different game, not a bigger singles.** Every one of
///    these sports rotates service — and table tennis rotates the RECEIVER
///    too — and playing the wrong partner is a fault. A pad that names only
///    the pair is no help to the umpire making that call.
///  * **A match can end without being played out.** Tennis and table tennis
///    had no retirement action of any kind, so an injury left a fixture that
///    could never be closed.
///  * **Ends change on a schedule the laws fix**, and the numbers for it were
///    sitting unread in the presets.
void main() {
  const pairA = [
    MatchPlayer(id: 'A1', name: 'Sania'),
    MatchPlayer(id: 'A2', name: 'Ankita'),
  ];
  const pairB = [
    MatchPlayer(id: 'B1', name: 'Rohan'),
    MatchPlayer(id: 'B2', name: 'Vikram'),
  ];

  /// Applies a list of actions, asserting each one was accepted.
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

  // ==========================================================================
  group('Retirement', () {
    ScoreAction retire(Side side, RetireReason reason) => ScoreAction(
          type: RacketMatch.retireAction,
          side: side,
          payload: {'reason': reason.wire},
        );

    test('tennis can be retired at all — it previously could not', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'tennis').toMap(),
      );
      var s = run(tennis, ctx, [
        for (var i = 0; i < 4; i++) const ScoreAction(type: 'point', side: Side.a),
      ]);
      expect(s['gamesA'], 1);

      final r = tennis.apply(s, retire(Side.a, RetireReason.injury), ctx);
      expect(r.isAccepted, isTrue, reason: r.rejection);
      s = r.state;

      expect(s['complete'], isTrue);
      // The side that retired LOSES: the match is awarded to the opponent.
      expect(s['winner'], 'b');
      expect(tennis.outcome(s, ctx).winnerSide, Side.b);
      expect(tennis.statusLine(s, ctx), contains('Sania'));
    });

    test('table tennis can be retired at all — it previously could not', () {
      const tt = TableTennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'table_tennis').toMap(),
      );
      final r = tt.apply(
        tt.initialState(ctx),
        retire(Side.b, RetireReason.walkover),
        ctx,
      );
      expect(r.isAccepted, isTrue, reason: r.rejection);
      expect(r.state['winner'], 'a');
      expect(tt.statusLine(r.state, ctx), contains('walkover'));
    });

    test('a retirement without a reason is refused', () {
      const badminton = BadmintonPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'badminton').toMap(),
      );
      final r = badminton.apply(
        badminton.initialState(ctx),
        const ScoreAction(type: RacketMatch.retireAction, side: Side.a),
        ctx,
      );
      expect(r.isAccepted, isFalse);
      expect(r.rejection, contains('reason'));
    });

    test('the reason survives, and distinguishes a walkover from an injury',
        () {
      const badminton = BadmintonPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'badminton').toMap(),
      );
      for (final reason in RetireReason.offered) {
        final r = badminton.apply(
          badminton.initialState(ctx),
          retire(Side.a, reason),
          ctx,
        );
        expect(r.isAccepted, isTrue, reason: r.rejection);
        expect(badminton.retireReasonOf(r.state), reason);
        expect(badminton.retiredSide(r.state), Side.a);
      }
    });

    test('reopening clears the retirement AND its reason', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'tennis').toMap(),
      );
      final retired = tennis
          .apply(tennis.initialState(ctx), retire(Side.a, RetireReason.injury),
              ctx)
          .state;
      final reopened =
          tennis.apply(retired, const ScoreAction(type: 'reopen'), ctx).state;

      expect(reopened['complete'], isFalse);
      expect(tennis.retiredSide(reopened), isNull);
      // The reason must go with it. A match reopened and then played out
      // would otherwise stay stamped 'injury' forever.
      expect(tennis.retireReasonOf(reopened), isNull);
    });
  });

  // ==========================================================================
  group('Doubles service rotation', () {
    test('badminton names the server AND the receiver', () {
      const badminton = BadmintonPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania / Ankita',
        entrantBName: 'Rohan / Vikram',
        config: {
          ...RulePresets.resolve(sportId: 'badminton').toMap(),
          'doubles': true,
        },
        lineupA: pairA,
        lineupB: pairB,
      );
      final s = badminton.initialState(ctx);
      expect(badminton.serverName(s, ctx), isNotNull);
      expect(badminton.receiverName(s, ctx), isNotNull);
      // The receiver is on the other side of the net from the server.
      final serving = badminton.serverFor(s);
      expect(ctx.lineupFor(serving).map((p) => p.name),
          contains(badminton.serverName(s, ctx)));
      expect(ctx.lineupFor(serving.opposite).map((p) => p.name),
          contains(badminton.receiverName(s, ctx)));
    });

    test('badminton keeps the serve while the pair wins rallies', () {
      const badminton = BadmintonPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {
          ...RulePresets.resolve(sportId: 'badminton').toMap(),
          'doubles': true,
        },
        lineupA: pairA,
        lineupB: pairB,
      );
      var s = badminton.initialState(ctx);
      final opener = badminton.serverFor(s);

      s = run(badminton, ctx, [ScoreAction(type: 'rally', side: opener)], s);
      expect(badminton.serverFor(s), opener,
          reason: 'winning the rally keeps the serve');

      s = run(
          badminton, ctx, [ScoreAction(type: 'rally', side: opener.opposite)], s);
      expect(badminton.serverFor(s), opener.opposite,
          reason: 'losing the rally hands the serve over');
    });

    test('table tennis rotates the receiver as well as the server', () {
      const tt = TableTennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {
          ...RulePresets.resolve(sportId: 'table_tennis').toMap(),
          'doubles': true,
        },
        lineupA: pairA,
        lineupB: pairB,
      );

      // The four-way cycle: A1→B1, B1→A2, A2→B2, B2→A1. Walk two points at a
      // time so each step is one complete service turn.
      final seen = <String>[];
      var s = tt.initialState(ctx);
      for (var turn = 0; turn < 4; turn++) {
        seen.add('${tt.serverName(s, ctx)}>${tt.receiverName(s, ctx)}');
        s = run(tt, ctx, [
          const ScoreAction(type: 'point', side: Side.a),
          const ScoreAction(type: 'point', side: Side.a),
        ], s);
      }

      // Every one of the four service turns is a different pairing — that is
      // what the cycle means, and it is what a rotation bug destroys.
      expect(seen.toSet().length, 4, reason: 'saw $seen');
      // And it comes back around.
      expect('${tt.serverName(s, ctx)}>${tt.receiverName(s, ctx)}', seen.first);
    });

    test('tennis alternates partners across a pair\'s service games', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: {
          ...RulePresets.resolve(sportId: 'tennis').toMap(),
          'doubles': true,
        },
        lineupA: pairA,
        lineupB: pairB,
      );

      var s = tennis.initialState(ctx);
      final first = tennis.serverName(s, ctx);

      // Four games: the same side serves games 1 and 3, with different
      // partners.
      for (var g = 0; g < 2; g++) {
        s = run(tennis, ctx, [
          for (var i = 0; i < 4; i++)
            const ScoreAction(type: 'point', side: Side.a),
        ], s);
      }
      final third = tennis.serverName(s, ctx);
      expect(third, isNot(first),
          reason: 'the partner takes the next service game for that pair');
    });

    test('singles is unaffected — the side is the player', () {
      const tt = TableTennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'Sania',
        entrantBName: 'Rohan',
        config: RulePresets.resolve(sportId: 'table_tennis').toMap(),
        lineupA: const [MatchPlayer(id: 'A1', name: 'Sania')],
        lineupB: const [MatchPlayer(id: 'B1', name: 'Rohan')],
      );
      final s = tt.initialState(ctx);
      expect(tt.receiverName(s, ctx), isNull,
          reason: 'there is no receiver rotation to report in singles');
      expect(tt.serverName(s, ctx), isNotNull);
    });
  });

  // ==========================================================================
  group('Change of ends', () {
    test('table tennis changes ends at 5 in the deciding game only', () {
      const tt = TableTennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: RulePresets.resolve(sportId: 'table_tennis').toMap(),
      );

      // Not in an ordinary game.
      var s = run(tt, ctx, [
        for (var i = 0; i < 6; i++) const ScoreAction(type: 'point', side: Side.a),
      ]);
      expect(tt.endsChangeDue(s, ctx), isNull);

      // Deciding game of a best-of-five is at 2 games all.
      s = tt.initialState(ctx);
      s = {...s, 'gamesA': 2, 'gamesB': 2};
      s = run(tt, ctx, [
        for (var i = 0; i < 4; i++) const ScoreAction(type: 'point', side: Side.a),
      ], s);
      expect(tt.endsChangeDue(s, ctx), isNull, reason: '4 is not yet 5');

      s = run(tt, ctx, [const ScoreAction(type: 'point', side: Side.a)], s);
      expect(tt.endsChangeDue(s, ctx), isNotNull, reason: 'a side has reached 5');
      expect(tt.endsAcknowledged(s, ctx), isFalse);

      final acked = tt
          .apply(s, const ScoreAction(type: RacketMatch.changeEndsAction), ctx);
      expect(acked.isAccepted, isTrue, reason: acked.rejection);
      expect(tt.endsAcknowledged(acked.state, ctx), isTrue);
    });

    test('tennis changes ends after every odd game', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: RulePresets.resolve(sportId: 'tennis').toMap(),
      );

      var s = tennis.initialState(ctx);
      expect(tennis.endsChangeDue(s, ctx), isNull, reason: 'no games played');

      // Game 1.
      s = run(tennis, ctx, [
        for (var i = 0; i < 4; i++) const ScoreAction(type: 'point', side: Side.a),
      ], s);
      expect(tennis.endsChangeDue(s, ctx), isNotNull, reason: 'after game 1');

      s = tennis
          .apply(s, const ScoreAction(type: RacketMatch.changeEndsAction), ctx)
          .state;

      // Game 2 — an even number of games, so no change.
      s = run(tennis, ctx, [
        for (var i = 0; i < 4; i++) const ScoreAction(type: 'point', side: Side.b),
      ], s);
      expect(tennis.endsChangeDue(s, ctx), isNull, reason: 'after game 2');

      // Game 3 — odd again.
      s = run(tennis, ctx, [
        for (var i = 0; i < 4; i++) const ScoreAction(type: 'point', side: Side.a),
      ], s);
      expect(tennis.endsChangeDue(s, ctx), isNotNull, reason: 'after game 3');
    });

    test('a change of ends cannot be acknowledged when none is due', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: RulePresets.resolve(sportId: 'tennis').toMap(),
      );
      final r = tennis.apply(
        tennis.initialState(ctx),
        const ScoreAction(type: RacketMatch.changeEndsAction),
        ctx,
      );
      expect(r.isAccepted, isFalse);
    });
  });

  // ==========================================================================
  group('Pickleball', () {
    const pb = PickleballPlugin();

    /// [rally] switches on rally scoring while KEEPING the 11-point game, so
    /// a test can drive the score straight down one side without having to
    /// win the serve back between every point. The shipped rally preset plays
    /// to 21 — that is a separate format, exercised on its own below.
    ScoringContext ctxFor({bool doubles = false, bool rally = false}) =>
        ScoringContext(
          entrantAName: doubles ? 'Sania / Ankita' : 'Sania',
          entrantBName: doubles ? 'Rohan / Vikram' : 'Rohan',
          config: {
            ...RulePresets.resolve(sportId: 'pickleball').toMap(),
            if (rally) 'rallyScoring': true,
            'doubles': doubles,
          },
          lineupA: doubles ? pairA : const [MatchPlayer(id: 'A1', name: 'Sania')],
          lineupB: doubles ? pairB : const [MatchPlayer(id: 'B1', name: 'Rohan')],
        );

    ScoreAction rally(Side side) => ScoreAction(type: 'rally', side: side);

    test('only the serving side can score', () {
      final ctx = ctxFor();
      var s = pb.initialState(ctx);
      final server = pb.serverFor(s);
      final receiver = server.opposite;

      // The receiver wins the rally: no point, only the serve moves.
      s = run(pb, ctx, [rally(receiver)], s);
      expect(s['currentA'], 0);
      expect(s['currentB'], 0);
      expect(pb.serverFor(s), receiver, reason: 'the receiver won the serve');

      // Now the same side wins again, this time while serving.
      s = run(pb, ctx, [rally(receiver)], s);
      final scored = receiver == Side.a ? s['currentA'] : s['currentB'];
      expect(scored, 1, reason: 'the serving side scores');
    });

    test('the shipped rally preset is a 21 point game', () {
      final rules =
          RulePresets.resolve(sportId: 'pickleball', presetId: 'pickleball_21_rally')
              .toMap();
      expect(rules['rallyScoring'], isTrue);
      expect(rules['pointsPerSet'], 21);
    });

    test('rally scoring awards every rally, however it was served', () {
      final ctx = ctxFor(rally: true);
      var s = pb.initialState(ctx);
      final receiver = pb.serverFor(s).opposite;
      s = run(pb, ctx, [rally(receiver)], s);
      final scored = receiver == Side.a ? s['currentA'] : s['currentB'];
      expect(scored, 1, reason: 'under rally scoring the receiver scores too');
    });

    test('doubles gives each side two servers, and the opener only one', () {
      final ctx = ctxFor(doubles: true);
      var s = pb.initialState(ctx);
      final opener = pb.serverFor(s);

      // The first service turn of the game opens on server 2 — the whole
      // reason a pickleball game is called "0 – 0 – 2".
      expect(pb.serverNumber(s), 2);
      expect(pb.calledScore(s, ctx), '0 – 0 – 2');

      // Losing that rally is an immediate side out, because there is no
      // second server left to come.
      s = run(pb, ctx, [rally(opener.opposite)], s);
      expect(pb.serverFor(s), opener.opposite);
      expect(pb.serverNumber(s), 1);

      // The receiving side now gets a full two servers.
      final now = pb.serverFor(s);
      s = run(pb, ctx, [rally(now.opposite)], s);
      expect(pb.serverFor(s), now, reason: 'serve passes to the partner first');
      expect(pb.serverNumber(s), 2);

      s = run(pb, ctx, [rally(now.opposite)], s);
      expect(pb.serverFor(s), now.opposite, reason: 'now it is a side out');
    });

    test('singles has one server a side — no second serve', () {
      final ctx = ctxFor();
      var s = pb.initialState(ctx);
      final opener = pb.serverFor(s);
      expect(pb.serverNumber(s), 1);
      s = run(pb, ctx, [rally(opener.opposite)], s);
      expect(pb.serverFor(s), opener.opposite,
          reason: 'losing the rally in singles is an immediate side out');
    });

    test('the service court follows the serving side\'s own score', () {
      final ctx = ctxFor();
      var s = pb.initialState(ctx);
      expect(pb.serviceCourt(s), 'right', reason: '0 is even');

      // Get the serving side to one point.
      final server = pb.serverFor(s);
      s = run(pb, ctx, [rally(server)], s);
      expect(pb.serviceCourt(s), 'left', reason: '1 is odd');
    });

    test('a game is to 11, win by two, with no cap', () {
      final ctx = ctxFor(rally: true); // rally scoring makes this easy to drive
      var s = run(pb, ctx, [
        for (var i = 0; i < 10; i++) rally(Side.a),
        for (var i = 0; i < 10; i++) rally(Side.b),
      ]);
      expect(s['gamesA'], 0);
      s = run(pb, ctx, [rally(Side.a)], s); // 11-10
      expect(s['gamesA'], 0, reason: '11-10 does not win — win by two');
      s = run(pb, ctx, [rally(Side.a)], s); // 12-10
      expect(s['gamesA'], 1);
    });

    test('ends change at 6 in a game to 11', () {
      final ctx = ctxFor(rally: true);
      var s = run(pb, ctx, [for (var i = 0; i < 5; i++) rally(Side.a)]);
      expect(pb.endsChangeDue(s, ctx), isNull);
      s = run(pb, ctx, [rally(Side.a)], s);
      expect(pb.endsChangeDue(s, ctx), isNotNull, reason: 'a side reached 6');
    });

    test('the receiver is never shown at game point under side-out scoring',
        () {
      final ctx = ctxFor();
      var s = pb.initialState(ctx);
      // Hand the serving side 10 points by having them win every rally.
      final server = pb.serverFor(s);
      s = run(pb, ctx, [for (var i = 0; i < 10; i++) rally(server)], s);

      final board = pb.duelBoard(s, ctx)!;
      expect(board[server].tag, isNotNull, reason: 'the server is at game point');
      // The receiver cannot win the game on the next rally — they cannot score
      // at all — so claiming game point for them would be a lie.
      expect(board[server.opposite].tag, isNull);
    });

    test('a completed match reports games, not the zeroed point counters', () {
      final ctx = ctxFor(rally: true);
      var s = run(pb, ctx, [
        for (var i = 0; i < 11; i++) rally(Side.a),
        for (var i = 0; i < 11; i++) rally(Side.a),
      ]);
      expect(s['complete'], isTrue);
      final board = pb.duelBoard(s, ctx)!;
      expect(board.a.score, '2');
      expect(board.b.score, '0');
    });
  });

  // ==========================================================================
  group('The retire control', () {
    /// Every racket engine must offer retirement, and must ask why — the pad
    /// generates its buttons from this, so a sport missing it is a sport that
    /// cannot be closed when somebody walks off.
    for (final (name, plugin, sportId) in <(String, ScoringPlugin, String)>[
      ('badminton', const BadmintonPlugin(), 'badminton'),
      ('table tennis', const TableTennisPlugin(), 'table_tennis'),
      ('tennis', const TennisPlugin(), 'tennis'),
      ('pickleball', const PickleballPlugin(), 'pickleball'),
    ]) {
      test('$name offers one retire button per side, each asking why', () {
        final ctx = ScoringContext(
          entrantAName: 'Sania',
          entrantBName: 'Rohan',
          config: RulePresets.resolve(sportId: sportId).toMap(),
        );
        final controls = [
          for (final g in plugin.controls(plugin.initialState(ctx), ctx))
            for (final c in g.controls)
              if (c.action == RacketMatch.retireAction) c,
        ];

        expect(controls.length, 2, reason: 'one per side, not one per reason');
        expect(controls.map((c) => c.side).toSet(), {Side.a, Side.b});

        for (final c in controls) {
          expect(c.needsInput, isTrue, reason: 'the reason must be asked');
          expect(c.choices, hasLength(1));
          final choice = c.choices.single;
          expect(choice.key, 'reason');
          expect(choice.optional, isFalse);
          expect(choice.options, isNotEmpty);

          // Every offered answer must be one the engine actually accepts.
          for (final option in choice.options) {
            final r = plugin.apply(
              plugin.initialState(ctx),
              ScoreAction(
                type: c.action,
                side: c.side,
                payload: {...c.payload, choice.key: option.value},
              ),
              ctx,
            );
            expect(r.isAccepted, isTrue,
                reason: '${option.value}: ${r.rejection}');
            expect(r.state['winner'], c.side.opposite.wire);
          }
        }
      });
    }
  });

  // ==========================================================================
  group('Catalogue', () {
    test('every racket sport resolves to an engine and a default ruleset', () {
      for (final id in ['badminton', 'table_tennis', 'tennis', 'pickleball',
        'padel', 'squash']) {
        final spec = SportCatalog.byId(id);
        expect(spec.id, id);
        expect(ScoringRegistry.forSport(id), isNotNull,
            reason: '$id has no engine');
        expect(RulePresets.defaultFor(id), isNotNull,
            reason: '$id has no default ruleset');
        expect(SideFormats.forSport(id), isNotEmpty,
            reason: '$id offers no singles/doubles choice');
      }
    });

    test('padel plays golden point when the preset says so', () {
      const tennis = TennisPlugin();
      final ctx = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        config: RulePresets.resolve(
          sportId: 'padel',
          presetId: 'padel_golden_point',
        ).toMap(),
      );
      // Deuce, then one point decides — no advantage.
      var s = run(tennis, ctx, [
        for (var i = 0; i < 3; i++) const ScoreAction(type: 'point', side: Side.a),
        for (var i = 0; i < 3; i++) const ScoreAction(type: 'point', side: Side.b),
      ]);
      expect(s['gamesA'], 0);
      s = run(tennis, ctx, [const ScoreAction(type: 'point', side: Side.a)], s);
      expect(s['gamesA'], 1, reason: 'the golden point takes the game outright');
    });

    test('squash is point-a-rally to 11, best of five', () {
      final rules = RulePresets.resolve(sportId: 'squash').toMap();
      expect(rules['pointsPerSet'], 11);
      expect(rules['setsToWin'], 3);
      expect(rules['winBy'], 2);
    });
  });
}
