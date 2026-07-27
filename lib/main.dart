import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/network/firebase_service.dart';
import 'core/network/gcp_bigquery_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('[Firebase Storage & GCP Setup] Initialized Firebase with google-services.json for ${GCPBigQueryService.projectId}');
    
    // Seed and sync Cloud Firestore database
    await FirebaseService.initializeFirestoreData();
  } catch (e) {
    debugPrint('[Firebase Local Fallback] Running with local demo storage: $e');
  }

  runApp(const ProviderScope(child: PlaySphereApp()));
}

class PlaySphereApp extends ConsumerWidget {
  const PlaySphereApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'PlaySphere Sports OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
