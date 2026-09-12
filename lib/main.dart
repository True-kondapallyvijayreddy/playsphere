import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/firebase/app_check_setup.dart';
import 'core/l10n/locale_controller.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
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

/// Whether crashes can be reported from this build.
///
/// Crashlytics has no web implementation — touching `FirebaseCrashlytics
/// .instance` in a browser throws — and reporting from a debug session would
/// bury real field crashes under a developer's own hot reloads. Both handlers
/// below fall back to the console in those cases, which is exactly what they
/// did before.
bool get _crashReportingEnabled => !kIsWeb && !kDebugMode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A white page is the least useful failure a user can be shown: it says
  // "something threw" and nothing else, and on the web the cause is only
  // visible in a browser console nobody has open. These two handlers turn any
  // build-time or uncaught async failure into something readable on screen.
  //
  // This one stays purely visual: by the time it runs, FlutterError.onError
  // has already been handed the same FlutterErrorDetails, so reporting here
  // too would file every build failure twice.
  ErrorWidget.builder = (details) => _ErrorPane(details: details);

  // Clean URLs on the web, so a live match can be shared as
  // /org/abc/live/xyz rather than a fragment nobody trusts.
  usePathUrlStrategy();

  // Android 16 (targetSdk 36) draws every app edge-to-edge and removes the
  // opt-out, so the only choice left is whether the pre-16 devices behave the
  // same way. Opting in here means one layout to reason about instead of two,
  // and the system bars are made transparent so the Scaffold's own surface
  // shows through rather than a grey band. Scaffold, AppBar and NavigationBar
  // already consume the resulting insets; nothing else in the app positions
  // itself against the screen edge.
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Icon brightness has to be stated. Transparent bars mean the clock and
    // the battery now sit on the app's own surface, and the platform default
    // is light icons — which on this palette is white on near-white, i.e.
    // invisible. Dark icons are pinned rather than derived because
    // `themeMode` below is pinned to light for brand reasons; if that ever
    // follows the device again, this has to follow it too.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

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

  // Attestation, immediately after the app exists and before anything reads
  // or writes.
  //
  // `firestore.rules` authorizes identities, not clients, and a web API key is
  // public by design — so until this, every rule in the product was reachable
  // by a script rather than only by the app. Deliberately NOT fatal and
  // deliberately not awaited for correctness: enforcement is a server-side
  // setting that is currently off, so a client that cannot attest behaves
  // exactly as it always has. See `activateAppCheck` for the rollout order,
  // which matters — enforcing Firestore first would lock out every old build
  // in the wild at once.
  await activateAppCheck();

  // Installed AFTER Firebase.initializeApp, because Crashlytics needs the app
  // to exist before it can be handed anything. Before this, all three
  // handlers ended at debugPrint — a crash on a phone on a ground in a
  // district we have never visited went to a console nobody would ever read,
  // which meant the product had no idea what was breaking in the field.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (_crashReportingEnabled) {
      FirebaseCrashlytics.instance.recordFlutterError(details);
    } else {
      debugPrint('[PlaySphere] widget error: ${details.exception}');
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (_crashReportingEnabled) {
      // Fatal: an uncaught async error is not something the app recovered
      // from, and reporting it as non-fatal hides it in the wrong list.
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('[PlaySphere] uncaught async error: $error');
    }
    return true;
  };

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

class PlaySphereApp extends ConsumerStatefulWidget {
  const PlaySphereApp({super.key});

  @override
  ConsumerState<PlaySphereApp> createState() => _PlaySphereAppState();
}

class _PlaySphereAppState extends ConsumerState<PlaySphereApp> {
  @override
  void initState() {
    super.initState();
    // Starts the offline scoring queue moving (Bug #9). Mounted here rather
    // than on the scoring pad because a scorer who has finished a match never
    // opens that pad again, and until this call existed that was the only
    // thing that ever replayed the queue — matches sat unsynced for days on a
    // phone with full signal.
    //
    // Post-frame so the first paint is never behind a network round trip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncDriverProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PlaySphere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Pinned to light on purpose. The palette IS the product's identity —
      // turf green and ball red — and following the device setting meant a
      // phone in dark mode rendered the whole app in near-black, which reads
      // as a different app rather than as the same app at night. The dark
      // theme is kept for a later, deliberate choice; it is not something a
      // system toggle gets to make on the brand's behalf.
      themeMode: ThemeMode.light,
      // Null follows the device language; a user who has picked one overrides
      // it.
      //
      // English only for now — see `supportedLocales`. Telugu and Hindi are
      // translated and deliberately not offered, because the translations
      // reach three screens and everything after them is an English literal.
      // The delegates stay wired so restoring a locale is one line.
      locale: ref.watch(localeControllerProvider),
      supportedLocales: supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: ref.watch(appRouterProvider),
      // Draws over whatever the router resolves to — home, sign-in, profile
      // setup — for a fixed few seconds on every cold start, on the web
      // exactly as much as on a phone. The router still runs underneath at
      // full speed, so by the time this lifts, the real destination is
      // already sitting there rather than only starting to load then.
      builder: (context, child) =>
          _SplashGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Holds [SplashScreen] over [child] for a fixed span on every cold start.
///
/// Deliberately a flat timer rather than tied to auth or profile resolution:
/// this is brand, not a loading spinner, and a person on a fast connection
/// whose session resolves in 200ms should still see it — otherwise the splash
/// would appear for some people and not others, which reads as a flicker
/// rather than a screen.
class _SplashGate extends StatefulWidget {
  const _SplashGate({required this.child});

  final Widget child;

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

/// How long [SplashScreen] covers the app on a cold start.
///
/// This was four seconds, and on the web that was four seconds added to a
/// start-up that already had megabytes to fetch before it could paint: the
/// engine, the bundle and the poster itself all land first, and only then does
/// this timer begin. The brand still gets its moment — long enough to read as a
/// screen rather than a flash — but it is no longer the largest single delay
/// between opening the app and being able to use it.
///
/// Raise it if the splash should linger; it is the only knob, and nothing else
/// depends on the value.
const Duration kSplashHold = Duration(milliseconds: 900);

class _SplashGateState extends State<_SplashGate> {
  bool _showSplash = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kSplashHold, () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stacked rather than swapped: the child keeps building (and the router
    // keeps redirecting) underneath the whole time, so nothing behind the
    // splash has to restart once it lifts.
    return Stack(
      children: [
        widget.child,
        if (_showSplash) const SplashScreen(),
      ],
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
