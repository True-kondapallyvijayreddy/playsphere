import 'package:flutter/material.dart';

/// The screen every cold start shows first — before sign-in, before home,
/// before the router has even decided which of those a person lands on.
///
/// Draws the same poster [flutter_native_splash] hands to Android 11 and
/// below (see the `flutter_native_splash` block in pubspec.yaml) rather than
/// composing the mark and wordmark itself, so a phone that briefly shows the
/// platform's own splash first sees the identical image continue rather than
/// cut to a different composition. [SplashGate] is what decides how long this
/// stays up; this widget only draws.
///
/// Nothing is laid over the poster. A caption drawn here — and only here —
/// would appear on the Flutter splash and be missing from the native one that
/// precedes it on Android 11 and below, which reads as a flicker of text
/// rather than as one continuous image. Anything the poster should say
/// belongs in the poster.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const _brandBlack = Color(0xFF0A0A0A);
  /// WebP, not the PNG the generators read.
  ///
  /// The poster is the first image the app draws and it blocks nothing else
  /// from being looked at, so its download sits squarely on the start-up path.
  /// As a PNG it was 1.9MB — larger than the entire compiled app — for artwork
  /// the viewer sees for under a second. The same image as WebP is 228KB and
  /// visually identical at this size.
  ///
  /// `assets/branding/splash.png` still exists and is still what
  /// `flutter_native_splash` reads in pubspec.yaml; it is a build-time source
  /// now rather than something shipped in the bundle.
  static const _asset = 'assets/branding/splash.webp';

  /// The poster's own pixel dimensions. Locking the image to this ratio,
  /// rather than letting it stretch to whatever the device's aspect ratio
  /// happens to be, is what keeps the artwork composed the same way on a tall
  /// phone and a wide desktop browser alike. A phone's screen is close enough
  /// to this ratio that it fills edge to edge anyway; a browser window only
  /// letterboxes at the sides.
  static const _posterAspectRatio = 853 / 1844;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _brandBlack,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: _posterAspectRatio,
        child: Image.asset(
          _asset,
          fit: BoxFit.cover,
          // A missing asset must not take the whole splash down with it —
          // the brand black behind this shows instead.
          errorBuilder: (context, _, __) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
