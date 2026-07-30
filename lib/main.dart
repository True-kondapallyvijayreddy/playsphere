import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';

/// Point the app at a local Firestore emulator instead of the real
/// `playsphere-os` project:
///
///     flutter run --dart-define=USE_FIRESTORE_EMULATOR=true
///
/// Off by default, and compiled out of a release build entirely, so a
/// shipped app can never be pointed at a developer's laptop. Exists so
/// changes to `firestore.rules` can be exercised by hand before they are
/// deployed — without a local target, the only way to try a rules change is
/// to deploy it to the database real competitions are running on.
const _useFirestoreEmulator =
    bool.fromEnvironment('USE_FIRESTORE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A white page is the least useful failure a user can be shown: it says
  // "something threw" and nothing else, and on the web the cause is only
  // visible in a browser console nobody has open. These two handlers turn any
  // build-time or uncaught async failure into something readable on screen.
  ErrorWidget.builder = (details) => _ErrorPane(details: details);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[PlaySphere] widget error: ${details.exception}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlaySphere] uncaught async error: $error');
    return true;
  };

  // Clean URLs on the web, so a live match can be shared as
  // /org/abc/live/xyz rather than a fragment nobody trusts.
  usePathUrlStrategy();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stack) {
    // Deliberately fatal rather than silently continuing. The previous build
    // caught this and dropped into an in-memory demo mode, which meant the
    // app cheerfully told people their scores were saved when nothing was
    // reaching a server. An app with no backend must say so.
    runApp(_StartupFailure(error: error, stack: stack));
    return;
  }

  if (_useFirestoreEmulator && !kReleaseMode) {
    // An Android emulator reaches the host machine through 10.0.2.2; every
    // other target reaches it on loopback. Getting this wrong presents as a
    // hang rather than an error, so it is worth the branch.
    // defaultTargetPlatform rather than Platform.isAndroid: dart:io does not
    // exist on the web, and importing it risks breaking a release web build.
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final host = isAndroid ? '10.0.2.2' : '127.0.0.1';
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    debugPrint('[PlaySphere] Firestore → emulator at $host:8080');
  }

  // Offline persistence is not a nice-to-have here: matches are scored on
  // grounds with no signal. With this on, the scoring pad keeps working and
  // Firestore flushes the queued writes when the network returns.
  //
  // `useFirestoreEmulator` already sets `sslEnabled: false` and
  // `persistenceEnabled: false` on the settings it installs, so this
  // assignment must not clobber it — against the emulator we keep its
  // settings and lose only local persistence, which is not what a rules
  // check is exercising anyway.
  if (!_useFirestoreEmulator) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // Loaded here rather than inside the widget tree so the chosen language is
  // known before the first frame. Resolving it later makes the app flash
  // English and then repaint in Telugu, which reads as a bug.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const PlaySphereApp(),
    ),
  );
}

class PlaySphereApp extends ConsumerWidget {
  const PlaySphereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PlaySphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Null follows the device language; a user who has picked one overrides
      // it. Telugu, Hindi and English ship from Phase 1 per CLAUDE.md §2.6.
      locale: ref.watch(localeControllerProvider),
      supportedLocales: supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

/// Replaces the framework's default error widget so a thrown build renders a
/// legible message in place of the failing subtree, instead of a grey box in
/// release or nothing at all on the web.
class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // Deliberately built from raw widgets, not Theme.of(context): this must
    // render even when the failure is in the app shell or the theme itself.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFFFDECEC),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This screen failed to build',
                style: TextStyle(
                  color: Color(0xFF8B1A1A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                '${details.exception}',
                style: const TextStyle(
                  color: Color(0xFF5A1010),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                details.stack.toString().split('\n').take(12).join('\n'),
                style: const TextStyle(
                  color: Color(0xFF7A3A3A),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when Firebase itself cannot start. Gives the operator something
/// actionable instead of a white screen.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_off, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'PlaySphere could not reach its backend',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Firebase failed to initialise, so nothing would be saved. '
                    'Rather than run in a state where scores appear to save '
                    'but do not, the app has stopped here.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '$error',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
