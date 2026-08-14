import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/domain/geo/geohash.dart';

void main() {
  group('Geohash.encode', () {
    test('is longer for higher precision, same prefix', () {
      final short = Geohash.encode(17.385, 78.4867, precision: 5);
      final long = Geohash.encode(17.385, 78.4867, precision: 9);
      expect(long.startsWith(short), isTrue);
      expect(long.length, 9);
    });
  });

  group('Geohash.decodeBbox', () {
    test('is the inverse of encode: the point lies inside its own box', () {
      const lat = 17.385, lng = 78.4867; // Hyderabad
      for (final precision in [4, 6, 8]) {
        final hash = Geohash.encode(lat, lng, precision: precision);
        final box = Geohash.decodeBbox(hash);
        expect(lat, inInclusiveRange(box.minLat, box.maxLat));
        expect(lng, inInclusiveRange(box.minLng, box.maxLng));
      }
    });
  });

  group('Geohash.distanceKm', () {
    test('is zero for the same point', () {
      expect(Geohash.distanceKm(17.385, 78.4867, 17.385, 78.4867), 0);
    });

    test('Hyderabad to Warangal is roughly 130km, not 13 or 1300', () {
      final d = Geohash.distanceKm(17.385, 78.4867, 17.9689, 79.5941);
      expect(d, inInclusiveRange(100, 160));
    });
  });

  group('Geohash.neighborsOf', () {
    test('returns 9 (or fewer, if two coincide near a boundary) cells, '
        'always including the centre', () {
      const lat = 17.385, lng = 78.4867;
      final precision = Geohash.precisionForRadiusKm(5);
      final centerHash = Geohash.encode(lat, lng, precision: precision);
      final cells = Geohash.neighborsOf(lat, lng, precision);
      expect(cells.length, lessThanOrEqualTo(9));
      expect(cells, contains(centerHash));
    });

    test('every real point within the search radius falls in one of the '
        'nine returned cells', () {
      const centerLat = 17.385, centerLng = 78.4867;
      const radiusKm = 5.0;
      final precision = Geohash.precisionForRadiusKm(radiusKm);
      final cells =
          Geohash.neighborsOf(centerLat, centerLng, precision).toSet();

      // Scatter points on a ring at exactly the search radius, in every
      // compass direction, and confirm each one's cell was returned. This is
      // the property the whole query technique depends on: a ground just
      // inside the circle must never be missed because it happened to land
      // in a tenth cell nobody queried.
      const kmPerDegreeLat = 110.574;
      for (var bearing = 0; bearing < 360; bearing += 15) {
        final rad = bearing * 3.1415926535 / 180;
        final dLat = (radiusKm * 0.999) / kmPerDegreeLat *
            (bearing == 0 ? 1 : _cosApprox(rad));
        final dLng = (radiusKm * 0.999) /
            (111.320 * _cosApproxDeg(centerLat)) *
            _sinApprox(rad);
        final pLat = centerLat + dLat;
        final pLng = centerLng + dLng;
        final cell = Geohash.encode(pLat, pLng, precision: precision);
        expect(
          cells.contains(cell),
          isTrue,
          reason: 'bearing $bearing° at ${radiusKm}km missed cell $cell '
              '(searched: $cells)',
        );
      }
    });
  });
}

// Tiny local trig helpers so this test has no extra dependency — precision
// to a couple of decimal places is more than enough for a coverage check.
double _cosApprox(double rad) {
  var x = rad % (2 * 3.1415926535);
  var term = 1.0, sum = 1.0;
  for (var n = 1; n <= 10; n++) {
    term *= -x * x / ((2 * n - 1) * (2 * n));
    sum += term;
  }
  return sum;
}

double _sinApprox(double rad) {
  var x = rad % (2 * 3.1415926535);
  var term = x, sum = x;
  for (var n = 1; n <= 10; n++) {
    term *= -x * x / ((2 * n) * (2 * n + 1));
    sum += term;
  }
  return sum;
}

double _cosApproxDeg(double deg) => _cosApprox(deg * 3.1415926535 / 180);
