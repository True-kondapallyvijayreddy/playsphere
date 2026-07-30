import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/l10n/locale_controller.dart';
import 'package:playsphere/l10n/app_localizations.dart';

/// Guards the three languages against drifting apart.
///
/// CLAUDE.md §2.6 makes Telugu, Hindi and English a MUST from Phase 1, and
/// §12.7 forbids hard-coded user-facing strings. The failure mode this
/// prevents is the ordinary one: someone adds an English key, ships, and the
/// Telugu build silently falls back to English for that screen.
void main() {
  Map<String, dynamic> arb(String locale) {
    final file = File('lib/l10n/app_$locale.arb');
    expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  /// Message keys only — `@`-prefixed entries are metadata, not strings.
  Set<String> keysOf(Map<String, dynamic> map) =>
      map.keys.where((k) => !k.startsWith('@')).toSet();

  group('translation completeness', () {
    test('Telugu and Hindi define every key English defines', () {
      final en = keysOf(arb('en'));
      final te = keysOf(arb('te'));
      final hi = keysOf(arb('hi'));

      expect(
        en.difference(te),
        isEmpty,
        reason: 'these keys have no Telugu translation',
      );
      expect(
        en.difference(hi),
        isEmpty,
        reason: 'these keys have no Hindi translation',
      );
    });

    test('no translation defines a key English does not', () {
      // A stray key is dead weight that will never render, and usually means
      // a rename landed in one file and not the others.
      final en = keysOf(arb('en'));
      expect(keysOf(arb('te')).difference(en), isEmpty);
      expect(keysOf(arb('hi')).difference(en), isEmpty);
    });

    test('every English key carries a description for translators', () {
      final en = arb('en');
      final undocumented = keysOf(en)
          .where((k) => k != '@@locale')
          .where((k) => !en.containsKey('@$k'))
          .toList();
      expect(
        undocumented,
        isEmpty,
        reason: 'a translator cannot render a string they have no context '
            'for: $undocumented',
      );
    });

    test('placeholders match across languages', () {
      // A translation that drops a placeholder throws at runtime rather than
      // rendering wrong, so this is a crash guard, not a polish check.
      final placeholder = RegExp(r'\{(\w+)[,}]');
      Set<String> placeholdersIn(String value) =>
          placeholder.allMatches(value).map((m) => m.group(1)!).toSet();

      final en = arb('en');
      for (final locale in ['te', 'hi']) {
        final other = arb(locale);
        for (final key in keysOf(en)) {
          if (key == '@@locale') continue;
          final enValue = en[key];
          final otherValue = other[key];
          if (enValue is! String || otherValue is! String) continue;
          expect(
            placeholdersIn(otherValue),
            placeholdersIn(enValue),
            reason: '$locale "$key" has different placeholders to English',
          );
        }
      }
    });

    test('no translated value is left as the English source', () {
      // Product names and language names are legitimately identical, so they
      // are exempt; everything else being identical means it was never
      // actually translated.
      const exempt = {
        'appTitle',
        'languageEnglish',
        'languageTelugu',
        'languageHindi',
        'standingsNetRunRate',
      };
      final en = arb('en');
      for (final locale in ['te', 'hi']) {
        final other = arb(locale);
        final untranslated = keysOf(en)
            .where((k) => k != '@@locale' && !exempt.contains(k))
            .where((k) => en[k] is String && en[k] == other[k])
            .toList();
        expect(
          untranslated,
          isEmpty,
          reason: '$locale still shows the English string for: $untranslated',
        );
      }
    });

    test('the generator reports nothing untranslated', () {
      // `flutter gen-l10n` writes this file; a non-empty object means a
      // locale is falling back to English at runtime.
      final file = File('lib/l10n/untranslated.json');
      if (!file.existsSync()) return;
      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return;
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded, isEmpty, reason: 'untranslated messages: $decoded');
    });
  });

  group('AppLocalizations', () {
    test('ships exactly the locales the app advertises', () {
      final generated =
          AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
      final advertised = supportedLocales.map((l) => l.languageCode).toSet();
      expect(generated, advertised);
      expect(advertised, {'en', 'te', 'hi'});
    });

    test('resolves a real string in each language', () async {
      for (final locale in supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(l10n.scoringTitle, isNotEmpty);
        expect(l10n.errorNetwork, isNotEmpty);
      }
    });

    test('plurals render differently for one and many', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(en.competitionEntrants(1), isNot(en.competitionEntrants(5)));
      expect(en.scoringOfflinePending(0), isNot(en.scoringOfflinePending(3)));

      final te = await AppLocalizations.delegate.load(const Locale('te'));
      expect(te.competitionEntrants(1), isNot(te.competitionEntrants(5)));
    });

    test('a placeholder is substituted, not printed literally', () async {
      for (final locale in supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        final line = l10n.resultWonBy('Warangal');
        expect(line, contains('Warangal'));
        expect(line, isNot(contains('{winner}')));
      }
    });
  });

  group('LocaleController', () {
    test('labels each language in its own script', () {
      expect(LocaleController.labelFor(const Locale('te')), 'తెలుగు');
      expect(LocaleController.labelFor(const Locale('hi')), 'हिन्दी');
      expect(LocaleController.labelFor(const Locale('en')), 'English');
    });

    test('an unset preference follows the device', () {
      final controller = LocaleController(null);
      expect(controller.state, isNull);
    });
  });
}
