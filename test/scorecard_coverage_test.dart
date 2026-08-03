import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// Does what I recorded actually appear on the scorecard?
///
/// The step after "the button works". An engine can accept an event, tally it
/// against a player, and still show the scorer nothing — the tally is written
/// into state that no `boxScore` reads, so the pad displays a scoreboard with
/// a team total and no idea who did what. For a product whose whole promise is
/// a lifelong per-player record, a point that lands nowhere visible is a point
/// that may as well not have been recorded.
///
/// So this plays each sport the way the pad does — press the button, answer
/// the prompts it declares — and then asks the same question a player asks
/// afterwards: is my name on it, with my number next to it?
void main() {
  List<MatchPlayer> squad(String prefix) => [
        for (var i = 1; i <= 12; i++)
          MatchPlayer(
            id: '$prefix$i',
            name: '$prefix player $i',
            uid: '$prefix$i',
          ),
      ];

  ScoringContext contextFor(SportSpec sport) => ScoringContext(
        entrantAName: 'Side A',
        entrantBName: 'Side B',
        config: sport.config,
        lineupA: squad('a'),
        lineupB: squad('b'),
      );

  /// Fills a control's prompts exactly as `ScoringScreen._askPlayers` does.
  Map<String, dynamic> answerPrompts(
    ScoreControl control,
    ScoringContext ctx,
  ) {
    final payload = <String, dynamic>{};
    for (final prompt in control.prompts) {
      final acting = control.side;
      final pool =
          acting == Side.neutral || prompt.from == PromptSource.eitherSide
              ? [...ctx.lineupFor(Side.a), ...ctx.lineupFor(Side.b)]
              : switch (prompt.from) {
                  PromptSource.actingSide => ctx.lineupFor(acting),
                  PromptSource.opposingSide => ctx.lineupFor(acting.opposite),
                  PromptSource.eitherSide => const <MatchPlayer>[],
                };
      if (pool.isEmpty) continue;
      payload[prompt.key] =
          prompt.multiple ? [pool.first.id] : pool[payload.length].id;
    }
    // Numbers, as the picker sends them: a plausible measurement inside
    // whatever bounds the prompt declared.
    for (final v in control.values) {
      if (v.optional) continue;
      final n = ((v.min ?? 1) + 10).clamp(v.min ?? 0.001, v.max ?? 1e6);
      payload[v.key] = v.isInteger ? n.round() : n;
    }
    if (payload.containsKey('striker') && payload.containsKey('nonStriker')) {
      payload['nonStriker'] = ctx.lineupFor(control.side)[1].id;
    }
    return payload;
  }

  /// Presses every button the plugin currently offers, keeping the state of
  /// each one the engine accepted — a real sequence, not a single event.
  Map<String, dynamic> playAWhile(
    ScoringPlugin plugin,
    ScoringContext ctx, {
    int rounds = 3,
  }) {
    var state = plugin.initialState(ctx);
    for (var round = 0; round < rounds; round++) {
      for (final group in plugin.controls(state, ctx)) {
        for (final control in group.controls) {
          // Nothing that ends the match — a finished match stops accepting
          // events and the rest of the sequence would be tested against a
          // closed scorecard.
          if (const {'finish', 'reopen', 'end_innings', 'end_turn'}
              .contains(control.action)) {
            continue;
          }
          final result = plugin.apply(
            state,
            ScoreAction(
              type: control.action,
              side: control.side,
              payload: {
                ...control.payload,
                ...answerPrompts(control, ctx),
              },
            ),
            ctx,
          );
          if (result.isAccepted) state = result.state;
        }
      }
    }
    return state;
  }

  /// Sports whose engine records no per-player statistic at all, and why.
  ///
  /// Listed rather than skipped silently, because each one is a real hole in
  /// the promise of a lifelong per-player record and the list should shrink.
  /// A sport must be added here deliberately — the default is that what a
  /// scorer records reaches the scorecard.
  const noPlayerStatsYet = <String, String>{
    // The escape hatch for uncatalogued sports. A bare +1 per side is the
    // point of it; adding player identity would make it less general.
    'other': 'deliberately a side-only tally',
    // A chess result is 1/0.5/0 for the two players, and the plugin models
    // them as sides. Per-player rows would restate the scoreboard.
    'chess': 'result is the whole record; players are the sides',
  };

  group('what a scorer records reaches the scorecard', () {
    for (final sport in SportCatalog.all) {
      test(sport.name, skip: noPlayerStatsYet[sport.id], () {
        final plugin = ScoringRegistry.resolve(sport.pluginKey);
        final ctx = contextFor(sport);
        final state = playAWhile(plugin, ctx);

        // Cricket's card is structurally unlike the rest — an innings, a
        // batting order, two disciplines — so it is built by the plugin
        // rather than by the generic box score, and checked on its own terms.
        if (plugin is CricketPlugin) {
          final cards = plugin.allCards(state, ctx);
          expect(cards, isNotEmpty, reason: 'cricket produced no innings card');
          expect(
            cards.first.batting,
            isNotEmpty,
            reason: 'cricket recorded deliveries but named no batter',
          );
          return;
        }

        final named = <String>{};
        for (final side in const [Side.a, Side.b]) {
          final box = plugin.boxScore(state, ctx, side);
          if (box == null) continue;
          for (final line in box.appeared) {
            named.add(line.playerId);
          }
        }

        expect(
          named,
          isNotEmpty,
          reason: '${sport.name}: a full sequence of events was applied and '
              'the scorecard names nobody — the tallies are being written '
              'somewhere no boxScore reads.',
        );
      });
    }
  });

  group('a scorecard is honest about who did nothing', () {
    test('an untouched match names nobody at all', () {
      // The opposite failure, and just as bad: a card that lists every squad
      // member with a row of zeroes before a ball is bowled reads as eleven
      // players who contributed nothing.
      for (final sport in SportCatalog.all) {
        final plugin = ScoringRegistry.resolve(sport.pluginKey);
        final ctx = contextFor(sport);
        final state = plugin.initialState(ctx);

        for (final side in const [Side.a, Side.b]) {
          final box = plugin.boxScore(state, ctx, side);
          if (box == null) continue;
          expect(
            box.appeared,
            isEmpty,
            reason: '${sport.name}: somebody is credited before the match '
                'has started',
          );
        }
      }
    });
  });
}
