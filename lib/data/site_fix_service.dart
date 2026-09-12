/// Getting a location reading the anti-fraud checks can actually use.
///
/// ## Why this is not just `Geolocator.getCurrentPosition`
///
/// The existing "use my location" button in the ground form asks for a
/// `medium` accuracy fix and is happy with whatever comes back, because all
/// it feeds is "grounds near me" — a listing pinned 200m out is a cosmetic
/// problem there. The same call is nowhere near good enough to answer "was
/// this person standing at this ground", which is what the capture flow needs
/// it for.
///
/// Three differences, each of which matters:
///
/// **It refuses the cache.** `forceLocationManager` and a zero distance
/// filter mean the platform returns a reading taken now, not the last one it
/// happens to remember from wherever the phone was an hour ago. A cached fix
/// is the easiest possible way to "prove presence" at a place you left.
///
/// **It asks for the best accuracy the device has** and reports the accuracy
/// back, so `SitePresence` can refuse a fix that is a cell-tower guess.
///
/// **It carries the mocked flag through.** Android tells you when a mock
/// provider produced the reading; that fact is useless if it is dropped
/// between the plugin and the check.
library;

import 'package:geolocator/geolocator.dart';

import '../core/errors/app_exception.dart';
import '../domain/geo/site_presence.dart';

/// Reads the device's position for evidence rather than for convenience.
class SiteFixService {
  const SiteFixService();

  /// How long to wait for a good fix before giving up.
  ///
  /// Twenty seconds. A cold GPS start outdoors on a cheap Android is often
  /// ten to fifteen, and cutting it short pushes the person into a retry loop
  /// that never converges — which reads to them as "the app is broken", and
  /// they leave.
  static const timeLimit = Duration(seconds: 20);

  /// A fresh, high-accuracy reading, or a [ValidationException] saying what
  /// to do about it.
  ///
  /// Throws rather than returning null so the caller cannot forget to handle
  /// the failure: every call site here is a gate, and a gate that silently
  /// passes on a missing value is not a gate.
  Future<SiteFix> current() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const ValidationException(
        'PlaySphere needs your location to confirm you are at this ground. '
        'Allow location access and try again.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ValidationException(
        'Location access is blocked for PlaySphere. Turn it on in your '
        'phone\'s settings for this app, then try again.',
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ValidationException(
        'Turn on location services on your phone, then try again.',
      );
    }

    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          // No cached reading. See the class comment — this is the single
          // most important line in the file.
          distanceFilter: 0,
          timeLimit: timeLimit,
        ),
      );
    } catch (_) {
      // Includes the timeout. Deliberately one message: from the person's
      // point of view "it did not work, go outside and try again" is the
      // only useful instruction whatever the platform's reason was.
      throw const ValidationException(
        'Could not get a location fix. Step into the open, away from '
        'buildings, and try again.',
      );
    }

    return SiteFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMetres: pos.accuracy,
      // The device clock, which is what `SitePresence.checkFix` compares
      // against `DateTime.now()` from the same clock. Comparing two readings
      // of one clock is sound even when that clock is wrong; the server
      // timestamp on the stored proof is what anchors it to real time.
      at: DateTime.now(),
      isMocked: pos.isMocked,
    );
  }

  /// A fresh reading that has already passed the single-fix checks.
  ///
  /// The two are separated so the wizard can show a "getting your
  /// location…" state around the slow half and an error dialog around the
  /// fast half, but nearly every caller wants both and should use this.
  Future<SiteFix> currentChecked({DateTime? now}) async {
    final fix = await current();
    final verdict = SitePresence.checkFix(fix, now: now ?? DateTime.now());
    if (!verdict.isOk) {
      throw ValidationException(verdict.problem!.message);
    }
    return fix;
  }
}
