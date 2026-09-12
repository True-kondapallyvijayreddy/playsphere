import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/domain/scoring/rule_config.dart';

/// Every rule setting an organizer can edit is either enforced by an engine or
/// declared advisory.
///
/// ## The bug this makes impossible
///
/// `RuleFields.orderedKeys` returns every key in a preset, and the Rules sheet
/// shows them all — the class comment says so deliberately: "Everything in a
/// preset is editable." Twenty-four of the hundred and twelve keys were read
/// by no plugin and no repository at all.
///
/// The sharpest was `maxOversPerBowler`, fourth in the cricket list, directly
/// under overs and players per side. Set it to four for a T20 and nothing
/// enforced it: `bowlerMustChangeEachOver` stopped consecutive overs, so two
/// bowlers could alternate through all twenty. The innings that came out was
/// not legal under any playing condition and it fed Glicko, career bowling
/// figures and the wicket leaderboards exactly like a real one.
///
/// `pointsWin`/`pointsDraw`/`pointsLoss` were worse in a quieter way: they
/// existed in the preset AND as `Competition.pointsForWin`, and only the
/// second was read by `StandingsCalculator` — so a league that set two points
/// a win in the Rules sheet silently kept scoring three.
///
/// A list of the guilty keys would have been a snapshot. This is the invariant
/// instead: a preset key must be findable in the source of something that
/// reads config, or be listed in `RuleFields.advisory` with a reason. Adding an
/// unenforced setting now fails here rather than shipping as a field that
/// looks like it does something.
void main() {
  /// Keys named in any preset's `values:` block.
  Set<String> presetKeys() {
    final src = File('lib/domain/scoring/rule_config.dart').readAsStringSync();
    final keys = <String>{};
    for (final block
        in RegExp(r'values:\s*\{(.*?)\n      \}', dotAll: true).allMatches(src)) {
      for (final m
          in RegExp(r"'([a-zA-Z][a-zA-Z0-9]*)':").allMatches(block.group(1)!)) {
        keys.add(m.group(1)!);
      }
    }
    return keys;
  }

  /// Everything in lib/ except the preset file itself, concatenated.
  ///
  /// Deliberately the whole tree rather than only the plugins: `squadSize` is
  /// read by a line-up widget and `dreamRunPoints` by a kho-kho pad, and a
  /// setting enforced in the UI layer is still enforced.
  String readerSources() {
    final buf = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('rule_config.dart')) continue;
      buf.write(entity.readAsStringSync());
    }
    return buf.toString();
  }

  test('no preset setting is silently unenforced', () {
    final sources = readerSources();
    final undeclared = <String>[];

    for (final key in presetKeys()) {
      final isRead = sources.contains("'$key'");
      if (isRead || RuleFields.isAdvisory(key)) continue;
      undeclared.add(key);
    }

    expect(
      undeclared..sort(),
      isEmpty,
      reason: 'These preset settings are shown to organizers as editable and '
          'are read by nothing in lib/. Either enforce them in the engine, or '
          'add them to RuleFields.advisory with the reason they cannot be.',
    );
  });

  test('every advisory key is actually still in a preset', () {
    // The other direction. A key enforced later, or dropped from the presets
    // altogether, must not linger here claiming to be an unenforced setting
    // that no longer exists — the Rules sheet would never show it and the
    // declaration would be a comment pretending to be a guarantee.
    final keys = presetKeys();
    final sources = readerSources();
    for (final key in RuleFields.advisory.keys) {
      expect(keys, contains(key),
          reason: '"$key" is declared advisory but appears in no preset. '
              'Remove it from RuleFields.advisory.');
      expect(sources.contains("'$key'"), isFalse,
          reason: '"$key" is declared advisory but something in lib/ now reads '
              'it. If it is enforced, take it out of RuleFields.advisory.');
    }
  });

  test('every advisory key explains itself', () {
    for (final entry in RuleFields.advisory.entries) {
      expect(entry.value.length, greaterThan(40),
          reason: '"${entry.key}" needs a reason worth reading, not a label.');
      expect(RuleFields.advisoryReason(entry.key), entry.value);
    }
  });

  test('the cricket bowler quota is enforced, not advisory', () {
    // The headline finding. If somebody ever moves this into `advisory` to
    // make a test pass, that is a regression in competition integrity and not
    // a documentation change.
    expect(RuleFields.isAdvisory('maxOversPerBowler'), isFalse);
    final sources = readerSources();
    expect(sources.contains("'maxOversPerBowler'"), isTrue);
  });

  test('league points live in exactly one place', () {
    // They were in two: the preset and `Competition.pointsForWin`. Only the
    // second was read, so editing the first did nothing.
    final src = File('lib/domain/scoring/rule_config.dart').readAsStringSync();
    for (final key in ['pointsWin', 'pointsDraw', 'pointsLoss']) {
      expect(src.contains("'$key'"), isFalse,
          reason: '$key is back in rule_config.dart. League points belong to '
              'Competition.pointsForWin, which is what StandingsCalculator '
              'reads.');
    }
  });
}
