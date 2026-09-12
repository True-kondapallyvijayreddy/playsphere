/// Deciding whether somebody was actually standing at a ground when they
/// listed it.
///
/// ## Why this is a pure function and not code inside the wizard
///
/// This is the rule that decides whether a fraudulent listing gets published,
/// which puts it in the same category as `GroundBooking.overlaps` — the one
/// piece of a feature that must not be got wrong, and therefore the one piece
/// that has to be testable without a phone, a camera, a GPS chip or
/// Firestore. Everything here takes numbers and returns a verdict. The widget
/// collects the numbers; it does not get an opinion.
///
/// ## What this can and cannot establish
///
/// Stated plainly so nobody later mistakes it for proof of title.
///
/// It can establish that a set of photographs was taken by this app, at one
/// place, within a few minutes, at coordinates the phone believed in. That is
/// enough to make listing a ground you have never visited genuinely
/// inconvenient, which is the goal.
///
/// It cannot establish that the person owns the ground, and it cannot survive
/// a rooted phone with a spoofing app — [SiteFix.isMocked] catches the lazy
/// version of that and nothing here catches the careful version. Ownership is
/// the ownership document's job and the reviewer's; the careful spoofer is
/// caught, if at all, by arrivals — see `GroundCheckIn`, which is evidence
/// produced by other people and is the only kind a determined fraudster
/// cannot manufacture alone.
library;

import 'geohash.dart';

/// One reading from the phone's location service.
class SiteFix {
  const SiteFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.at,
    this.isMocked = false,
  });

  final double latitude;
  final double longitude;

  /// The phone's own estimate of its error radius.
  final double accuracyMetres;

  final DateTime at;

  /// Android reports this directly; on iOS it is always false because the
  /// platform gives no equivalent. Treated as a hard stop rather than a
  /// weighting — there is no honest reason for a mock provider to be feeding
  /// the app while somebody photographs their own turf.
  final bool isMocked;

  double distanceMetresTo(SiteFix other) =>
      Geohash.distanceKm(latitude, longitude, other.latitude, other.longitude) *
      1000;

  double distanceMetresToPoint(double lat, double lng) =>
      Geohash.distanceKm(latitude, longitude, lat, lng) * 1000;
}

/// Why a capture was refused, with the sentence to show for it.
///
/// A code rather than a bare string so the wizard can branch — a poor fix is
/// worth a "try again outdoors" retry button, a mocked one is not — and so
/// the reason can be logged without shipping UI copy to the server.
enum SitePresenceProblem {
  /// The phone could not produce a fix at all.
  noFix(
    'Location unavailable',
    'PlaySphere could not get your location. Step outside, make sure location '
        'is switched on, and try again.',
  ),

  /// The fix is too vague to mean "here".
  ///
  /// Common and innocent — indoors, under a stand, in a basement car park.
  /// The message says what to do about it rather than implying suspicion.
  tooVague(
    'Location not precise enough',
    'Your phone is not sure where it is yet. Step into the open, wait a few '
        'seconds and try again.',
  ),

  /// A mock location provider was feeding the app.
  mocked(
    'Fake location detected',
    'Your phone is reporting a fake location. Turn off any mock-location app '
        'and list this ground from the ground itself.',
  ),

  /// The fix is old enough that it may be from somewhere else entirely.
  stale(
    'Location is out of date',
    'That reading is too old to use. Try again to take a fresh one.',
  ),

  /// The photographs were not all taken at one place.
  scattered(
    'Photos taken too far apart',
    'These photos were not all taken at the same ground. Take them all while '
        'you are standing at the ground you are listing.',
  ),

  /// The pin is not where the photographs were taken.
  ///
  /// This is the one that catches the careless fraud: photographs of a real
  /// ground the person is standing at, filed under the address of a
  /// different, more profitable one.
  pinMismatch(
    'Pin is not where you are',
    'The location saved for this ground is not where these photos were taken. '
        'Use your current location as the pin.',
  ),

  /// The session ran so long the fixes stop being one visit.
  sessionTooLong(
    'This is taking too long',
    'Start the listing again so the photos and location are captured in one '
        'visit.',
  );

  const SitePresenceProblem(this.title, this.message);

  final String title;
  final String message;

  /// Whether trying again from the same spot could plausibly succeed.
  ///
  /// A vague fix improves if you walk into the open; a mocked one does not
  /// improve, it gets turned off. Offering "retry" for the second is an
  /// invitation to keep hammering the button.
  bool get isRetryable =>
      this == SitePresenceProblem.noFix ||
      this == SitePresenceProblem.tooVague ||
      this == SitePresenceProblem.stale;
}

/// The verdict on one fix or one set of them.
class SitePresenceResult {
  const SitePresenceResult.ok()
      : problem = null,
        spreadMetres = 0;

  const SitePresenceResult.refused(this.problem, {this.spreadMetres = 0});

  final SitePresenceProblem? problem;

  /// How far apart the captures were, when that is what failed. Shown in the
  /// message so the person can tell a GPS wobble from having photographed two
  /// different places.
  final double spreadMetres;

  bool get isOk => problem == null;
}

/// The thresholds, and the checks that apply them.
///
/// Every number here is a trade between rejecting fraud and rejecting an
/// honest owner on a cheap phone in a village with poor sky view. They are
/// deliberately loose. A threshold tight enough to stop a determined
/// fraudster would stop most of the real users first, and this layer is not
/// where a determined fraudster is meant to be caught.
class SitePresence {
  const SitePresence._();

  /// How vague a fix may be and still count as "standing here".
  ///
  /// 100m. A phone with a clear sky reports 5–20m; 100m is roughly what you
  /// get near buildings or under trees, which is where half the grounds in a
  /// district are. Beyond that the reading is a cell-tower guess and means
  /// nothing about which ground you are at.
  static const maxAccuracyMetres = 100.0;

  /// How far apart two captures in one submission may be.
  ///
  /// 300m, measured between the fixes. It has to comfortably exceed the
  /// diagonal of a large cricket ground plus the error on two mediocre fixes,
  /// because photographing the pitch from one end and the gate at the other
  /// is exactly what the wizard asks for.
  static const maxSpreadMetres = 300.0;

  /// How far the saved pin may sit from where the photos were taken.
  ///
  /// Same 300m, and for the same reason: the pin is captured on one of these
  /// fixes, so anything larger means the owner moved the pin somewhere else
  /// on purpose.
  static const maxPinOffsetMetres = 300.0;

  /// How old a fix may be when it is used.
  ///
  /// Two minutes. Long enough to survive a slow camera and a slower upload,
  /// short enough that a fix cannot be carried from a previous location.
  static const maxFixAge = Duration(minutes: 2);

  /// How long the whole capture may take.
  ///
  /// Thirty minutes, from the first fix to submission. Generous — an owner
  /// walking a big ground and re-taking a blurry photo needs the room — but
  /// finite, because a session left open for a day is no longer evidence of a
  /// single visit.
  static const maxSessionAge = Duration(minutes: 30);

  /// Whether one reading may be used at all.
  ///
  /// [now] is passed rather than read so a test can drive staleness without
  /// waiting two minutes.
  static SitePresenceResult checkFix(SiteFix? fix, {required DateTime now}) {
    if (fix == null) {
      return const SitePresenceResult.refused(SitePresenceProblem.noFix);
    }
    // Mocking is checked before accuracy on purpose: a spoofed fix usually
    // reports perfect accuracy, so testing accuracy first would wave the
    // worst case straight through.
    if (fix.isMocked) {
      return const SitePresenceResult.refused(SitePresenceProblem.mocked);
    }
    if (fix.accuracyMetres <= 0 || fix.accuracyMetres > maxAccuracyMetres) {
      return const SitePresenceResult.refused(SitePresenceProblem.tooVague);
    }
    // A future timestamp is a clock that has been moved, which is as
    // interesting as an old one and is caught by the same check.
    final age = now.difference(fix.at);
    if (age > maxFixAge || age.isNegative) {
      return const SitePresenceResult.refused(SitePresenceProblem.stale);
    }
    return const SitePresenceResult.ok();
  }

  /// The widest gap between any two fixes in a set.
  ///
  /// Pairwise rather than "distance from the first", because three photos in
  /// a line 200m apart each would pass a first-anchored test while spanning
  /// 400m. The sets here are two to four items, so the quadratic cost is
  /// nothing.
  static double spreadMetres(List<SiteFix> fixes) {
    var worst = 0.0;
    for (var i = 0; i < fixes.length; i++) {
      for (var j = i + 1; j < fixes.length; j++) {
        final d = fixes[i].distanceMetresTo(fixes[j]);
        if (d > worst) worst = d;
      }
    }
    return worst;
  }

  /// Whether a whole submission hangs together as one visit to one place.
  ///
  /// Runs after every individual fix has already passed [checkFix] — this
  /// asks the question no single reading can answer, which is whether they
  /// are all the *same* place at the *same* time.
  static SitePresenceResult checkSet(
    List<SiteFix> fixes, {
    required DateTime now,
    double? pinLatitude,
    double? pinLongitude,
  }) {
    if (fixes.isEmpty) {
      return const SitePresenceResult.refused(SitePresenceProblem.noFix);
    }
    for (final fix in fixes) {
      if (fix.isMocked) {
        return const SitePresenceResult.refused(SitePresenceProblem.mocked);
      }
    }

    final spread = spreadMetres(fixes);
    if (spread > maxSpreadMetres) {
      return SitePresenceResult.refused(
        SitePresenceProblem.scattered,
        spreadMetres: spread,
      );
    }

    // Oldest fix to now, not first-to-last: a session where the photos were
    // taken quickly an hour ago and submitted now is just as much not-a-visit
    // as one that took an hour.
    var oldest = fixes.first.at;
    for (final fix in fixes) {
      if (fix.at.isBefore(oldest)) oldest = fix.at;
    }
    if (now.difference(oldest) > maxSessionAge) {
      return const SitePresenceResult.refused(
        SitePresenceProblem.sessionTooLong,
      );
    }

    if (pinLatitude != null && pinLongitude != null) {
      for (final fix in fixes) {
        final offset = fix.distanceMetresToPoint(pinLatitude, pinLongitude);
        if (offset > maxPinOffsetMetres) {
          return SitePresenceResult.refused(
            SitePresenceProblem.pinMismatch,
            spreadMetres: offset,
          );
        }
      }
    }

    return const SitePresenceResult.ok();
  }

  /// The point to save as the ground's pin, given the captures.
  ///
  /// The mean of the fixes, weighted towards the precise ones by using the
  /// single most accurate reading rather than a true average. Averaging
  /// coordinates sounds better and is worse: one 90m fix dragged in with two
  /// 8m ones moves the pin off the gate for no gain, and a pin that is
  /// slightly wrong is what makes an honest arrival fail its check-in.
  static SiteFix bestFix(List<SiteFix> fixes) {
    var best = fixes.first;
    for (final fix in fixes) {
      if (fix.accuracyMetres < best.accuracyMetres) best = fix;
    }
    return best;
  }
}
