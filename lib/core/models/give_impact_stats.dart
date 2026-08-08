import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_codec.dart';

/// The Give network's headline numbers, one singleton document at
/// `give/impactStats`.
///
/// ## Written by a Cloud Function, not computed client-side
///
/// Same reasoning as the Cross-Sport Index's `SportPopulation`: counting
/// "how many donations across the whole network have reached each stage"
/// on a client would mean reading every donation ever made, which is an
/// unbounded read the moment the network has any real volume. A trigger on
/// `giveDonations` status transitions increments these counters instead —
/// see `onDonationStatusChanged` in `functions/index.js`.
///
/// [GiveRepository.watchImpactStats] returns [GiveImpactStats.empty] until
/// that function has run at least once (a fresh project, or before the
/// first donation completes a stage). Screens must render that as "just
/// getting started", never as a broken dashboard — a network with real
/// activity and a network that hasn't shipped yet must not look the same,
/// but neither should read as an error.
class GiveImpactStats {
  const GiveImpactStats({
    this.donationsCount = 0,
    this.itemsCollected = 0,
    this.itemsDistributed = 0,
    this.needsFulfilled = 0,
    this.updatedAt,
  });

  static const empty = GiveImpactStats();

  final int donationsCount;
  final int itemsCollected;
  final int itemsDistributed;
  final int needsFulfilled;
  final DateTime? updatedAt;

  /// Deliberately not a field here. A distinct-city count needs a set, not
  /// a counter — `FieldValue.increment` on a trigger cannot tell "a new
  /// donation from a city already active" from "a genuinely new city"
  /// without reading every prior donation, which is exactly the unbounded
  /// read this whole document exists to avoid. `giveCollectionCenters` is
  /// small and curated by staff, unlike donations, so the number of cities
  /// PlaySphere Give is *live in* is cheap to derive from that collection
  /// directly on the client — see `GiveRepository.watchCollectionCenters`.
  bool get hasActivity => donationsCount > 0;

  factory GiveImpactStats.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return empty;
    return GiveImpactStats(
      donationsCount: Fs.integer(d['donationsCount']),
      itemsCollected: Fs.integer(d['itemsCollected']),
      itemsDistributed: Fs.integer(d['itemsDistributed']),
      needsFulfilled: Fs.integer(d['needsFulfilled']),
      updatedAt: Fs.dateOrNull(d['updatedAt']),
    );
  }
}
