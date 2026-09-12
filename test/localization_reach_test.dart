import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/l10n/locale_controller.dart';

/// How far the translations actually reach.
///
/// ## Why this test exists rather than a ticket
///
/// `app_en.arb`, `app_te.arb` and `app_hi.arb` each held seventy keys,
/// translated and complete. Exactly three of two hundred and thirty-three
/// feature files called `AppLocalizations`: sign-in, profile setup, and the
/// language picker itself. Everything after the first two screens — the
/// scoring pad, the season planner, every error message an organizer will ever
/// read — was among roughly two thousand two hundred English literals.
///
/// So the picker worked and the product did not. Somebody in a Telangana
/// school selected తెలుగు, watched the sign-in screen change, and then used an
/// English app.
///
/// `pubspec.yaml` records Telugu and Hindi as a stated MUST from Phase 1, on
/// the grounds that retrofitting i18n later is far more expensive than
/// carrying it — which is now the position the project is in. The decision
/// taken was to ship one honest language and keep the machinery, so this test
/// holds that decision to its own terms: it fails if a locale is offered
/// without the UI speaking it, and it records the real number so "how far off
/// are we" is a command rather than an estimate.
void main() {
  /// Feature and shared files that render UI.
  List<File> uiFiles() => [
        for (final dir in ['lib/features', 'lib/shared'])
          ...Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      ];

  test('a locale is only offered once the UI speaks it', () {
    // The invariant. Adding `Locale('te')` back to `supportedLocales` without
    // extracting the strings fails here, which is the mistake this replaces.
    final localized = uiFiles()
        .where((f) => f.readAsStringSync().contains('AppLocalizations'))
        .length;
    final total = uiFiles().length;
    final reach = localized / total;

    if (supportedLocales.length > 1) {
      expect(
        reach,
        greaterThan(0.8),
        reason: 'Offering ${supportedLocales.length} languages while only '
            '$localized of $total UI files call AppLocalizations means the '
            'app changes language on a handful of screens and not on the rest. '
            'Extract the strings, or take the locale back out of '
            'supportedLocales.',
      );
    }
  });

  test('English is always offered', () {
    expect(supportedLocales.map((l) => l.languageCode), contains('en'));
  });

  test('the translations are kept, not deleted', () {
    // The .arb files and the delegates stay wired, so restoring a locale is
    // one line rather than a project restart. A future cleanup that deletes
    // them would quietly turn a deferred decision into a permanent one.
    for (final code in ['en', 'te', 'hi']) {
      expect(File('lib/l10n/app_$code.arb').existsSync(), isTrue,
          reason: 'lib/l10n/app_$code.arb is the work already done. Keep it.');
    }
    expect(translatedButNotShipped.map((l) => l.languageCode).toList()..sort(),
        ['hi', 'te']);
    // And they must not overlap: a locale cannot be both shipped and withheld.
    for (final l in translatedButNotShipped) {
      expect(supportedLocales, isNot(contains(l)));
    }
  });

  test('the three .arb files stay in step with each other', () {
    // Whatever is translated has to be translated everywhere. A key present in
    // English and missing in Telugu is a screen that falls back silently.
    // Parsed rather than pattern-matched. A regex over the raw file also
    // catches the nested keys inside each `@key` metadata block —
    // "description", "placeholders", "type" — which exist only in the English
    // file and made it look as though Telugu was missing five translations
    // that were never strings.
    Set<String> keysOf(String code) {
      final decoded = jsonDecode(
        File('lib/l10n/app_$code.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      return decoded.keys.where((k) => !k.startsWith('@')).toSet();
    }

    final en = keysOf('en');
    expect(keysOf('te').difference(en), isEmpty,
        reason: 'Telugu has keys English does not');
    expect(en.difference(keysOf('te')), isEmpty,
        reason: 'these English keys have no Telugu translation');
    expect(en.difference(keysOf('hi')), isEmpty,
        reason: 'these English keys have no Hindi translation');
  });
}
