import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Offline persistence is not a nice-to-have here: matches are scored on
  // grounds with no signal. With this on, the scoring pad keeps working and
  // Firestore flushes the queued writes when the network returns.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: PlaySphereApp()));
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
      routerConfig: ref.watch(appRouterProvider),
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
