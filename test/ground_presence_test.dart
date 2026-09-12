import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/ground_verification.dart';
import 'package:playsphere/domain/geo/site_presence.dart';

/// The rules that decide whether a ground listing is allowed to exist.
///
/// This is the anti-fraud layer's load-bearing arithmetic, and it fails
/// silently in both directions: too strict and honest turf owners in villages
/// with poor sky view cannot list at all, too loose and someone lists a
/// ground they have never visited and starts asking bookers for UPI
/// advances. Neither failure shows up in a screenshot, so both are asserted
/// here.
void main() {
  // A real pair of coordinates in Gachibowli, so the distances below are
  // metres on the actual earth rather than degrees pretending to be metres.
  const groundLat = 17.4401;
  const groundLng = 78.3489;

  final now = DateTime(2026, 8, 30, 18);

  SiteFix fixAt({
    double lat = groundLat,
    double lng = groundLng,
    double accuracy = 12,
    Duration ago = const Duration(seconds: 5),
    bool mocked = false,
  }) =>
      SiteFix(
        latitude: lat,
        longitude: lng,
        accuracyMetres: accuracy,
        at: now.subtract(ago),
        isMocked: mocked,
      );

  /// Roughly [metres] north of the ground. One degree of latitude is about
  /// 111.32 km everywhere, which is close enough for a test asserting either
  /// side of a 300m threshold.
  double latOffsetBy(double metres) => groundLat + metres / 111320.0;

  group('a single fix', () {
    test('a clean fix taken here and now is usable', () {
      expect(SitePresence.checkFix(fixAt(), now: now).isOk, isTrue);
    });

    test('no fix at all is refused, and retrying might help', () {
      final r = SitePresence.checkFix(null, now: now);
      expect(r.problem, SitePresenceProblem.noFix);
      expect(r.problem!.isRetryable, isTrue);
    });

    test('a vague fix is refused — a 400m circle is not "standing here"', () {
      final r = SitePresence.checkFix(fixAt(accuracy: 400), now: now);
      expect(r.problem, SitePresenceProblem.tooVague);
    });

    test('an accuracy of zero is refused rather than treated as perfect', () {
      // A spoofing library that forgets to populate accuracy leaves it at 0,
      // and a naive `accuracy < 100` test reads that as the best fix ever
      // recorded. This is the assertion that keeps that from being true.
      expect(
        SitePresence.checkFix(fixAt(accuracy: 0), now: now).problem,
        SitePresenceProblem.tooVague,
      );
    });

    test('a mocked fix is refused and is not worth retrying', () {
      final r = SitePresence.checkFix(fixAt(mocked: true), now: now);
      expect(r.problem, SitePresenceProblem.mocked);
      expect(r.problem!.isRetryable, isFalse);
    });

    test('mocking is caught even when the fix claims perfect accuracy', () {
      // The ordering inside checkFix matters: spoofed fixes usually report a
      // flawless accuracy, so testing accuracy first would pass the single
      // worst case straight through.
      final r = SitePresence.checkFix(
        fixAt(accuracy: 1, mocked: true),
        now: now,
      );
      expect(r.problem, SitePresenceProblem.mocked);
    });

    test('a fix from ten minutes ago is stale', () {
      final r = SitePresence.checkFix(
        fixAt(ago: const Duration(minutes: 10)),
        now: now,
      );
      expect(r.problem, SitePresenceProblem.stale);
    });

    test('a fix timestamped in the future is stale, not accepted', () {
      // Moving the device clock forward is the obvious way to make an old
      // fix look fresh.
      final r = SitePresence.checkFix(
        fixAt(ago: const Duration(minutes: -10)),
        now: now,
      );
      expect(r.problem, SitePresenceProblem.stale);
    });
  });

  group('a whole submission', () {
    test('photos taken around one ground hang together', () {
      final r = SitePresence.checkSet(
        [
          fixAt(),
          fixAt(lat: latOffsetBy(80), ago: const Duration(minutes: 2)),
          fixAt(lat: latOffsetBy(140), ago: const Duration(minutes: 4)),
        ],
        now: now,
      );
      expect(r.isOk, isTrue);
    });

    test('photos a kilometre apart are not one ground', () {
      final r = SitePresence.checkSet(
        [fixAt(), fixAt(lat: latOffsetBy(1000))],
        now: now,
      );
      expect(r.problem, SitePresenceProblem.scattered);
      expect(r.spreadMetres, greaterThan(900));
    });

    test('the spread is measured pairwise, not from the first photo', () {
      // Three fixes 200m apart in a line: every one is within 300m of the
      // first two, but the set spans 400m. A first-anchored check would pass
      // this, which is how a listing gets assembled while walking down a
      // road past somebody else's ground.
      final r = SitePresence.checkSet(
        [
          fixAt(),
          fixAt(lat: latOffsetBy(200)),
          fixAt(lat: latOffsetBy(400)),
        ],
        now: now,
      );
      expect(r.problem, SitePresenceProblem.scattered);
    });

    test('one mocked photo poisons an otherwise clean set', () {
      final r = SitePresence.checkSet(
        [fixAt(), fixAt(lat: latOffsetBy(50), mocked: true)],
        now: now,
      );
      expect(r.problem, SitePresenceProblem.mocked);
    });

    test('a session left open for an hour is no longer one visit', () {
      final r = SitePresence.checkSet(
        [
          fixAt(ago: const Duration(minutes: 65)),
          fixAt(ago: const Duration(minutes: 62)),
        ],
        now: now,
      );
      expect(r.problem, SitePresenceProblem.sessionTooLong);
    });

    test('a pin dropped on a different ground is refused', () {
      // The careless fraud: genuine photographs of a real place, filed under
      // the address of a busier one two kilometres away.
      final r = SitePresence.checkSet(
        [fixAt(), fixAt(lat: latOffsetBy(60))],
        now: now,
        pinLatitude: latOffsetBy(2000),
        pinLongitude: groundLng,
      );
      expect(r.problem, SitePresenceProblem.pinMismatch);
    });

    test('a pin at the gate of a big ground is fine', () {
      final r = SitePresence.checkSet(
        [fixAt(), fixAt(lat: latOffsetBy(150))],
        now: now,
        pinLatitude: latOffsetBy(120),
        pinLongitude: groundLng,
      );
      expect(r.isOk, isTrue);
    });

    test('an empty set proves nothing', () {
      expect(
        SitePresence.checkSet([], now: now).problem,
        SitePresenceProblem.noFix,
      );
    });

    test('the pin comes from the most precise reading, not an average', () {
      final precise = fixAt(lat: latOffsetBy(100), accuracy: 6);
      final best = SitePresence.bestFix([fixAt(accuracy: 40), precise]);
      expect(best.accuracyMetres, 6);
      expect(best.latitude, precise.latitude);
    });
  });

  group('what the booker is shown', () {
    test('a legacy listing nobody has been to is unproven', () {
      expect(
        GroundTrust.of(
          status: GroundVerificationStatus.unverified,
          checkInCount: 0,
        ),
        GroundTrust.unproven,
      );
    });

    test('a fresh on-site listing reads as captured, not verified', () {
      expect(
        GroundTrust.of(
          status: GroundVerificationStatus.pending,
          checkInCount: 0,
        ),
        GroundTrust.captured,
      );
    });

    test('three arrivals confirm a ground nobody has reviewed', () {
      expect(
        GroundTrust.of(
          status: GroundVerificationStatus.pending,
          checkInCount: 3,
        ),
        GroundTrust.locationConfirmed,
      );
    });

    test('two arrivals are not yet enough', () {
      expect(
        GroundTrust.of(
          status: GroundVerificationStatus.pending,
          checkInCount: 2,
        ),
        GroundTrust.captured,
      );
    });

    test('a human review outranks the crowd', () {
      // Arrivals prove the ground exists. Only a reviewer who looked at an
      // electricity bill knows the other thing that matters, which is who is
      // entitled to take the money.
      expect(
        GroundTrust.of(
          status: GroundVerificationStatus.verified,
          checkInCount: 3,
        ),
        GroundTrust.verified,
      );
    });

    test('suspension beats everything, including arrivals', () {
      // The ground is real and people have stood on it. It is still the
      // listing that has been taking advances, and the badge must not
      // reassure anybody.
      expect(
        GroundTrust.of(
          status: GroundVerificationStatus.suspended,
          checkInCount: 12,
        ),
        GroundTrust.blocked,
      );
    });
  });

  group('what a suspended listing may still do', () {
    test('a suspended ground takes no bookings and is not searchable', () {
      expect(GroundVerificationStatus.suspended.isBookable, isFalse);
      expect(GroundVerificationStatus.suspended.isDiscoverable, isFalse);
    });

    test('a rejected ground takes no bookings', () {
      expect(GroundVerificationStatus.rejected.isBookable, isFalse);
    });

    test('waiting for review does not stop a genuine owner earning', () {
      // The deliberate product call: the badge is the lever, not the gate. A
      // marketplace where every honest owner waits on one reviewer's inbox
      // has no fraud problem because it has no supply.
      expect(GroundVerificationStatus.pending.isBookable, isTrue);
      expect(GroundVerificationStatus.unverified.isBookable, isTrue);
    });
  });

  group('report weighting', () {
    test('an advance demand outweighs a wrong address three to one', () {
      expect(
        GroundReportReason.askedForAdvance.weight,
        greaterThan(GroundReportReason.wrongDetails.weight * 2),
      );
    });

    test('the reasons that allege dishonesty are marked as such', () {
      expect(GroundReportReason.askedForAdvance.isFraud, isTrue);
      expect(GroundReportReason.doesNotExist.isFraud, isTrue);
      expect(GroundReportReason.notTheirGround.isFraud, isTrue);
      expect(GroundReportReason.wrongDetails.isFraud, isFalse);
    });

    test('one person gets one report per ground', () {
      // The composite id is the whole limit. A generated id would let one
      // account file the same complaint forty times and suspend a
      // competitor's listing before lunch.
      final a = GroundReport.idFor(reporterUid: 'u1', groundId: 'g1');
      final b = GroundReport.idFor(reporterUid: 'u1', groundId: 'g1');
      final c = GroundReport.idFor(reporterUid: 'u2', groundId: 'g1');
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('arrival radius', () {
    GroundCheckIn checkInAt(double distanceMetres) => GroundCheckIn(
          bookingId: 'b1',
          uid: 'u1',
          latitude: groundLat,
          longitude: groundLng,
          accuracyMetres: 20,
          distanceMetres: distanceMetres,
          capturedAt: now,
        );

    test('a walk across a cricket ground still counts as arriving', () {
      // The radius is deliberately generous. A cricket ground is 150m across
      // and the gate can be a walk from the pitch; an honest arrival rejected
      // is a person who never checks in again.
      expect(checkInAt(180).isWithinRange, isTrue);
    });

    test('a check-in from a kilometre away confirms nothing', () {
      expect(checkInAt(1000).isWithinRange, isFalse);
    });

    test('the boundary itself counts', () {
      expect(
        checkInAt(GroundCheckIn.confirmingRadiusMetres).isWithinRange,
        isTrue,
      );
    });
  });
}
