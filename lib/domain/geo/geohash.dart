import 'dart:math' as math;

/// Turns a point into a sortable string, and a search radius into the
/// handful of Firestore range queries that cover it.
///
/// ## Why this exists
///
/// A ground has `latitude`/`longitude`, but Firestore cannot answer "within
/// 10km of here" against two number fields at once — a query may only carry
/// a range (`<`, `>`) filter on one field, and lat *and* lng both need one.
/// Geohashing collapses the 2D point into a single string where nearby
/// points mostly share a prefix, so "nearby" becomes a small number of
/// single-field string-range queries — the same trick behind every
/// Firestore/DynamoDB "near me" feature that isn't backed by a dedicated
/// geo index.
///
/// ## Why the neighbour cells are found by re-encoding, not by lookup table
///
/// The classic geohash implementations (GeoFire and its ports) compute the
/// eight neighbours of a cell with a hand-built table of adjacency rules —
/// famously easy to transcribe wrong, and hard to convince yourself is right
/// by reading it. This does the same job by decoding the centre cell back to
/// a bounding box, stepping one cell-width/height in each compass direction,
/// and re-encoding that point at the same precision. It leans on
/// [encode]/[decodeBbox] being exact inverses of each other, which a round
/// trip test can check directly — there is no separate table to get wrong.
///
/// Query looseness at the edges is harmless: [distanceKm] filters every
/// candidate by its real great-circle distance after the query returns, so
/// this only has to find a superset of the true answer, never the exact set.
class Geohash {
  const Geohash._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes a point to a base-32 geohash string of [precision] characters.
  static String encode(double lat, double lng, {int precision = 9}) {
    var latRange = <double>[-90.0, 90.0];
    var lngRange = <double>[-180.0, 180.0];
    final hash = StringBuffer();
    var even = true;
    var bit = 0;
    var ch = 0;
    while (hash.length < precision) {
      if (even) {
        final mid = (lngRange[0] + lngRange[1]) / 2;
        if (lng >= mid) {
          ch |= (1 << (4 - bit));
          lngRange[0] = mid;
        } else {
          lngRange[1] = mid;
        }
      } else {
        final mid = (latRange[0] + latRange[1]) / 2;
        if (lat >= mid) {
          ch |= (1 << (4 - bit));
          latRange[0] = mid;
        } else {
          latRange[1] = mid;
        }
      }
      even = !even;
      if (bit < 4) {
        bit++;
      } else {
        hash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return hash.toString();
  }

  /// The lat/lng bounding box a geohash string represents — the exact
  /// inverse of [encode].
  static GeoBox decodeBbox(String hash) {
    var latRange = <double>[-90.0, 90.0];
    var lngRange = <double>[-180.0, 180.0];
    var even = true;
    for (final c in hash.split('')) {
      final cd = _base32.indexOf(c);
      if (cd < 0) continue;
      for (final mask in const [16, 8, 4, 2, 1]) {
        final bit = cd & mask;
        if (even) {
          final mid = (lngRange[0] + lngRange[1]) / 2;
          if (bit != 0) {
            lngRange[0] = mid;
          } else {
            lngRange[1] = mid;
          }
        } else {
          final mid = (latRange[0] + latRange[1]) / 2;
          if (bit != 0) {
            latRange[0] = mid;
          } else {
            latRange[1] = mid;
          }
        }
        even = !even;
      }
    }
    return GeoBox(
      minLat: latRange[0],
      maxLat: latRange[1],
      minLng: lngRange[0],
      maxLng: lngRange[1],
    );
  }

  /// Great-circle distance between two points, in kilometres.
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLng = _radians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _radians(double deg) => deg * math.pi / 180;

  /// The precision (character count) whose cells are at least as large as
  /// [radiusKm] in both dimensions — coarse enough that the query's 3×3 block
  /// of cells is guaranteed to cover the search circle, however the centre
  /// point sits inside its own cell.
  static int precisionForRadiusKm(double radiusKm) {
    // Approximate max cell width/height in km at each character count.
    const cellSizesKm = <double>[
      5010, // 1
      1252, // 2
      156.5, // 3
      39.1, // 4
      4.89, // 5
      1.22, // 6
      0.153, // 7
      0.0382, // 8
      0.00477, // 9
    ];
    var precision = 1;
    for (var i = 0; i < cellSizesKm.length; i++) {
      if (cellSizesKm[i] >= radiusKm) precision = i + 1;
    }
    return precision;
  }

  /// The centre cell plus its eight neighbours at [precision] characters —
  /// the query set that covers a circle of any radius up to roughly one cell
  /// width around [lat]/[lng], given a precision picked by
  /// [precisionForRadiusKm].
  static List<String> neighborsOf(double lat, double lng, int precision) {
    final centerHash = encode(lat, lng, precision: precision);
    final box = decodeBbox(centerHash);
    final latStep = box.maxLat - box.minLat;
    final lngStep = box.maxLng - box.minLng;
    final centerLat = (box.minLat + box.maxLat) / 2;
    final centerLng = (box.minLng + box.maxLng) / 2;

    final cells = <String>{};
    for (final dLat in const [-1, 0, 1]) {
      for (final dLng in const [-1, 0, 1]) {
        var pointLat = centerLat + dLat * latStep;
        var pointLng = centerLng + dLng * lngStep;
        // Clamp the pole rather than wrapping — a ground search never needs
        // to reason about the poles, and clamping keeps encode() in its
        // valid domain.
        pointLat = pointLat.clamp(-90.0, 90.0);
        // Wrap longitude across the antimeridian so a ground near it (rare
        // in this product's footprint, but cheap to get right) still finds
        // its western/eastern neighbour instead of an out-of-range value.
        if (pointLng > 180) pointLng -= 360;
        if (pointLng < -180) pointLng += 360;
        cells.add(encode(pointLat, pointLng, precision: precision));
      }
    }
    return cells.toList(growable: false);
  }

  /// `[start, end)` bounds for a Firestore range query that matches every
  /// geohash with [cellPrefix] as a prefix. `'~'` sorts after every base-32
  /// character this alphabet uses, so nothing that starts with [cellPrefix]
  /// can sort at or beyond `cellPrefix + '~'`.
  static (String start, String end) queryBoundsFor(String cellPrefix) =>
      (cellPrefix, '$cellPrefix~');
}

/// A lat/lng bounding box, as decoded from a geohash cell.
class GeoBox {
  const GeoBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}
