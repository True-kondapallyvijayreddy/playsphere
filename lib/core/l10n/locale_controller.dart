import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The locales PlaySphere OFFERS.
///
/// English only, for now, and that is a correction rather than a retreat.
///
/// ## Why the other two are not here
///
/// `app_te.arb` and `app_hi.arb` are complete: seventy keys each, translated.
/// The problem was never the translations, it was their reach — exactly three
/// of two hundred and thirty-three feature files call `AppLocalizations`
/// (sign-in, profile setup, and the picker itself), and roughly two thousand
/// two hundred user-facing strings are English literals in the widget tree.
///
/// So the picker worked and the product did not. A user in a Telangana school
/// selected తెలుగు, watched the sign-in screen change, and then used an
/// English app — including every error message, the whole scoring pad, and the
/// season planner. Offering a language a product does not speak is worse than
/// offering one, because it is a promise broken in front of the person it was
/// made to.
///
/// Nothing is deleted. The delegates, the .arb files, the translations and
/// [labelFor] all stay, so restoring a locale is adding one line here — and
/// the honest precondition for adding it is that the strings have been
/// extracted, not that the file exists. `test/localization_reach_test.dart`
/// measures how far off that is.
const supportedLocales = <Locale>[
  Locale('en'),
];

/// The locales PlaySphere has translations for but does not yet offer.
///
/// Kept as a named list rather than as a comment so the gap is measurable:
/// the reach test asserts these stay out of [supportedLocales] until the UI
/// actually speaks them.
const translatedButNotShipped = <Locale>[
  Locale('te'),
  Locale('hi'),
];

/// The user's chosen language, or null to follow the device.
///
/// Persisted rather than held in memory because a scorer who set the app to
/// Telugu should not find it back in English after the phone kills the app
/// mid-match — which on a 2GB device it will.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._prefs) : super(_read(_prefs));

  final SharedPreferences? _prefs;

  static const _key = 'playsphere_locale_v1';

  static Locale? _read(SharedPreferences? prefs) {
    final code = prefs?.getString(_key);
    if (code == null || code.isEmpty) return null;
    final match = supportedLocales.where((l) => l.languageCode == code);
    return match.isEmpty ? null : match.first;
  }

  /// Sets the language. Passing null returns to following the device, which
  /// is the right default for a shared or borrowed phone.
  Future<void> set(Locale? locale) async {
    state = locale;
    if (locale == null) {
      await _prefs?.remove(_key);
    } else {
      await _prefs?.setString(_key, locale.languageCode);
    }
  }

  /// The label to show for a language, written in that language — a user
  /// looking for Telugu is looking for "తెలుగు", not for "Telugu".
  static String labelFor(Locale locale) => switch (locale.languageCode) {
        'te' => 'తెలుగు',
        'hi' => 'हिन्दी',
        _ => 'English',
      };
}

/// Set during startup once SharedPreferences has loaded. Overridden in
/// `main` so the controller never has to await inside a build.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>((ref) {
  return LocaleController(ref.watch(sharedPreferencesProvider));
});
