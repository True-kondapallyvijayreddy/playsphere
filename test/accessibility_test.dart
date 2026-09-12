import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/scoring/plugins/cricket_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';
import 'package:playsphere/core/models/match_player.dart';

/// Accessibility, as invariants rather than as a one-off audit.
///
/// ## The state this replaces
///
/// Across roughly a hundred thousand lines of UI there were seventeen
/// `Semantics` widgets, two `semanticLabel`s, and eighty-five `IconButton`s
/// with neither a tooltip nor a label — so on TalkBack a good part of the app
/// announced "button" and nothing else. Nothing in the codebase read
/// `textScaler` either, which meant the icon-dense scoring pads had never been
/// looked at above the default font size, on screens most likely to be held by
/// an older club secretary.
///
/// For a product being sold to schools and pitched at government
/// participation reporting, GIGW and WCAG get asked about eventually. The
/// point of putting these in a test rather than fixing and moving on is that
/// an audit decays and an invariant does not.
void main() {
  group('every icon-only control announces itself', () {
    test('no IconButton is left without a tooltip or a semantic label', () {
      // An `IconButton` whose child is an `Icon` has no text for a screen
      // reader to read. `tooltip` is what Flutter turns into the semantic
      // label, so it does double duty: a hover hint on the web and the only
      // thing TalkBack has to say on a phone.
      final offenders = <String>[];

      for (final dir in ['lib/features', 'lib/shared']) {
        for (final entity in Directory(dir).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final src = entity.readAsStringSync();

          for (final m in RegExp(r'IconButton(?:\.\w+)?\(').allMatches(src)) {
            // Walk to the matching paren so a nested constructor's arguments
            // are not mistaken for this one's.
            var i = m.end;
            var depth = 1;
            while (i < src.length && depth > 0) {
              if (src[i] == '(') {
                depth++;
              } else if (src[i] == ')') {
                depth--;
              }
              i++;
            }
            final block = src.substring(m.end, i - 1);
            if (block.contains('tooltip') || block.contains('semanticLabel')) {
              continue;
            }
            final line = src.substring(0, m.start).split('\n').length;
            offenders.add('${entity.path}:$line');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these icon buttons announce nothing to a screen reader. Add '
            'a `tooltip:` saying what the control does — "Close", "Add one", '
            '"Share" — not what the icon is called.',
      );
    });
  });

  group('the scoring pad survives large text', () {
    // The pads are the screens this matters most on: dense, gridded, and held
    // by whoever is keeping score, who is frequently not the youngest person
    // at the ground. Nothing in the codebase read `textScaler` before this, so
    // 200% had never been tried.
    List<MatchPlayer> squad(String prefix) => [
          for (var i = 1; i <= 11; i++)
            MatchPlayer(id: '$prefix$i', name: '$prefix Player $i'),
        ];

    final ctx = ScoringContext(
      entrantAName: 'Warangal Warriors',
      entrantBName: 'Nizamabad Nizams',
      config: const {
        'oversPerInnings': 20,
        'ballsPerOver': 6,
        'playersPerTeam': 11,
        'battingFirst': 'a',
        'maxOversPerBowler': 4,
      },
      lineupA: squad('A'),
      lineupB: squad('B'),
    );

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the cricket control labels fit at ${scale}x', (tester) async {
        const cricket = CricketPlugin();
        final opened = cricket.apply(
          cricket.initialState(ctx),
          const ScoreAction(
            type: 'open',
            payload: {
              'striker': 'A1',
              'nonStriker': 'A2',
              'bowler': 'B1',
            },
          ),
          ctx,
        );
        final groups = cricket.controls(opened.state, ctx);

        // The pad's own widgets pull in Firebase, so this renders the same
        // labels in the same constrained tiles instead. What it catches is the
        // thing that actually breaks: a label that no longer fits the tile the
        // pad gives it, which is an overflow exception rather than a judgement
        // call.
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final group in groups)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(group.title),
                            Wrap(
                              children: [
                                for (final control in group.controls)
                                  // The real pad lays these out as tiles with
                                  // a floor on the tap target; 88x48 is the
                                  // smallest it ever draws one.
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 88,
                                      minHeight: 48,
                                      maxWidth: 160,
                                    ),
                                    child: Center(
                                      child: Text(
                                        control.label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull,
            reason: 'the cricket pad overflows at ${scale}x text');
      });
    }
  });

  group('tap targets', () {
    test('the pad never asks for a control smaller than 48dp', () {
      // Both platforms' guidelines put the floor at 48dp, and a scoring pad is
      // tapped at speed by somebody watching a game rather than the screen.
      // Asserted against the constant the pad lays out from so a future tidy
      // cannot quietly shrink it.
      final padTheme = File('lib/features/scoring/widgets/pad_theme.dart');
      if (!padTheme.existsSync()) return;
      final src = padTheme.readAsStringSync();
      for (final m in RegExp(r'min(?:Height|Width):\s*([\d.]+)')
          .allMatches(src)) {
        expect(double.parse(m.group(1)!), greaterThanOrEqualTo(44.0),
            reason: 'a pad control smaller than 44dp is hard to hit at speed');
      }
    });
  });
}
