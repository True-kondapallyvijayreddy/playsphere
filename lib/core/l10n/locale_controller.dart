import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The locales PlaySphere ships. Telugu first after English, because the
/// pilot is Telangana and the spec calls for a Telugu-first UX review.
const supportedLocales = <Locale>[
  Locale('en'),
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
