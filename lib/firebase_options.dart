// Firebase configuration for project `playsphere-os` (Firestore: asia-south1).
//
// These values are public client identifiers, not secrets — Firebase expects
// them to ship inside the app bundle. Everything that actually protects data
// lives in `firestore.rules`, which is enforced server-side. Treat that file,
// not this one, as the security boundary.
//
// Regenerate with:
//   firebase apps:sdkconfig <PLATFORM> <APP_ID> --project playsphere-os
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        throw UnsupportedError(
          'PlaySphere has no Firebase configuration for $defaultTargetPlatform. '
          'Register the platform with `firebase apps:create` and re-run '
          '`firebase apps:sdkconfig`.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAS2gvaFHeGDZ7EyhN0xly_9O_HTkzZk7k',
    appId: '1:178810835926:web:4f03df40924a29160e4a77',
    messagingSenderId: '178810835926',
    projectId: 'playsphere-os',
    authDomain: 'playsphere-os.firebaseapp.com',
    storageBucket: 'playsphere-os.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDkktlVR8pL2uEOwgC-GgzDQS_o7Gnhtzc',
    appId: '1:178810835926:android:e6cd42ec6ccb2c170e4a77',
    messagingSenderId: '178810835926',
    projectId: 'playsphere-os',
    storageBucket: 'playsphere-os.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCcSh5k2UBZlkT-w2X2MimyX8QszQKlb7A',
    appId: '1:178810835926:ios:10520ef5b1c937200e4a77',
    messagingSenderId: '178810835926',
    projectId: 'playsphere-os',
    storageBucket: 'playsphere-os.firebasestorage.app',
    iosBundleId: 'com.company.playsphere',
  );
}
