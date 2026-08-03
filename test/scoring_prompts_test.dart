import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// The contract between an engine and the pad: if an action refuses to apply
/// without naming somebody, its button must say so.
///
/// This existed as an unwritten assumption and was broken for eleven of the
/// thirteen sports. The pad recognised three cricket action names and asked
/// for players on those alone; every other engine rejected its own buttons.
/// Football's Goal, kho-kho's Tag, kabaddi's Raid, basketball's every shot —
/// all returned "Who scored?" to a scorer who had never been offered anywhere
/// to answer. Those sports had a full pad and no way to record a single point.
///
/// The test below is the guard: press every button every plugin offers, with
/// the payload the pad would send, and assert the engine accepts it.
void main() {
  /// A line-up big enough for any sport in the catalogue.
  List<MatchPlayer> squad(String prefix) => [
        for (var i = 1; i <= 12; i++)
          MatchPlayer(id: '$prefix$i', name: '$prefix player $i', uid: '$prefix$i'),
      ];

  ScoringContext contextFor(SportSpec sport) => ScoringContext(
        entrantAName: 'Side A',
        entrantBName: 'Side B',
        config: sport.config,
        lineupA: squad('a'),
        lineupB: squad('b'),
      );

  /// Exactly what `ScoringScreen._askPlayers` builds: each prompt filled from
  /// the line-up its `from` points at, relative to the button's own side.
  Map<String, dynamic> resolvePrompts(
    ScoreControl control,
    ScoringContext ctx,
  ) {
    final payload = <String, dynamic>{};
    for (final prompt in control.prompts) {
      final acting = control.side;
      final pool = acting == Side.neutral ||
              prompt.from == PromptSource.eitherSide
          ? [...ctx.lineupFor(Side.a), ...ctx.lineupFor(Side.b)]
          : switch (prompt.from) {
              PromptSource.actingSide => ctx.lineupFor(acting),
              PromptSource.opposingSide => ctx.lineupFor(acting.opposite),
              PromptSource.eitherSide => const <MatchPlayer>[],
            };
      if (pool.isEmpty) continue;
      if (prompt.multiple) {
        // A kabaddi tackle is several defenders, written as a list. One name
        // is a legal answer, so one is what this sends.
        payload[prompt.key] = [pool.first.id];
        continue;
      }
      // Distinct people per role: a striker and a non-striker are two
      // different players, and the engine says so.
      payload[prompt.key] = pool[payload.length % pool.length].id;
    }
    for (final v in control.values) {
      if (v.optional) continue;
      final n = ((v.min ?? 1) + 10).clamp(v.min ?? 0.001, v.max ?? 1e6);
      payload[v.key] = v.isInteger ? n.round() : n;
    }
    // The one case a positional walk gets wrong.
    if (payload.containsKey('striker') && payload.containsKey('nonStriker')) {
      payload['nonStriker'] = ctx.lineupFor(control.side)[1].id;
    }
    return payload;
  }

  group('every button a plugin offers is one the engine accepts', () {
    for (final sport in SportCatalog.all) {
      test(sport.name, () {
        final plugin = ScoringRegistry.resolve(sport.pluginKey);
        final ctx = contextFor(sport);
        final state = plugin.initialState(ctx);

        for (final group in plugin.controls(state, ctx)) {
          for (final control in group.controls) {
            final result = plugin.apply(
              state,
              ScoreAction(
                type: control.action,
                side: control.side,
                payload: {
                  ...control.payload,
                  ...resolvePrompts(control, ctx),
                },
              ),
              ctx,
            );

            // A rejection is legitimate — "you cannot end a level match",
            // "there is already a batter on strike". What must never happen
            // is a rejection because NOBODY WAS NAMED, since that is the pad
            // failing to ask rather than the rules being enforced.
            final why = result.rejection ?? '';
            final asksForAPerson = RegExp(
              r'^(Who|Which (player|keeper|goalkeeper|athlete|batter|bowler))',
            ).hasMatch(why);

            expect(
              asksForAPerson,
              isFalse,
              reason: '${sport.name}: "${control.label}" '
                  '(${control.action}) was rejected with "$why" — the '
                  'control must declare a PlayerPrompt for it.',
            );
          }
        }
      });
    }
  });

  group('prompts point at line-ups that exist', () {
    test('no prompt asks for a side the control does not have', () {
      // A neutral control has no side of its own, so a prompt that resolves
      // relative to one would offer an empty dropdown and strand the scorer.
      for (final sport in SportCatalog.all) {
        final plugin = ScoringRegistry.resolve(sport.pluginKey);
        final ctx = contextFor(sport);
        for (final group in plugin.controls(plugin.initialState(ctx), ctx)) {
          for (final control in group.controls) {
            if (control.side != Side.neutral) continue;
            for (final prompt in control.prompts) {
              expect(
                prompt.from,
                PromptSource.eitherSide,
                reason: '${sport.name}: neutral control "${control.label}" '
                    'has a prompt relative to a side it does not have',
              );
            }
          }
        }
      }
    });

    test('prompt keys are unique within a control', () {
      // Two prompts writing the same payload key means the second silently
      // overwrites the first, and one of the two people is lost.
      for (final sport in SportCatalog.all) {
        final plugin = ScoringRegistry.resolve(sport.pluginKey);
        final ctx = contextFor(sport);
        for (final group in plugin.controls(plugin.initialState(ctx), ctx)) {
          for (final control in group.controls) {
            final keys = control.prompts.map((p) => p.key).toList();
            expect(keys.toSet().length, keys.length,
                reason: '${sport.name}: ${control.label}');
          }
        }
      }
    });
  });

  group('the toss is asked in each sport\'s own words', () {
    test('no sport is offered bat or field unless it has a bat', () {
      // The dialog offered Bat and Field to all thirteen sports, so the
      // record of every non-cricket match asserted something that had not
      // happened.
      for (final sport in SportCatalog.all) {
        final ids = TossOptions.forSport(sport.id).map((c) => c.id);
        if (sport.id == 'cricket') {
          expect(ids, containsAll(['bat', 'field']));
        } else {
          expect(ids.contains('bat'), isFalse, reason: sport.id);
        }
      }
    });

    test('every sport offers a real choice and can name a starter', () {
      for (final sport in SportCatalog.all) {
        final choices = TossOptions.forSport(sport.id);
        expect(choices.length, greaterThanOrEqualTo(2), reason: sport.id);
        // Exactly one side starts, so exactly one choice may hand over the
        // first turn to its picker.
        expect(choices.where((c) => c.givesFirstTurn).length, 1,
            reason: sport.id);
      }
    });

    test('only cricket writes battingFirst', () {
      for (final sport in SportCatalog.all) {
        expect(TossOptions.decidesBatting(sport.id), sport.id == 'cricket',
            reason: sport.id);
      }
    });

    test('racquet sports ask serve or receive', () {
      for (final id in ['badminton', 'table_tennis', 'tennis']) {
        final ids = TossOptions.forSport(id).map((c) => c.id);
        expect(ids, containsAll(['serve', 'receive']), reason: id);
      }
    });

    test('an unknown sport still gets a usable toss', () {
      expect(TossOptions.forSport('quidditch').length, greaterThanOrEqualTo(2));
      expect(TossOptions.resolve('quidditch', 'nonsense').givesFirstTurn, isTrue);
    });
  });
}
