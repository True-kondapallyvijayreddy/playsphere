import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;

import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
import '../core/models/sponsorship.dart';
import 'org_repository.dart' show guard, guardStream;

/// Sponsor an Athlete / Sponsor a Team: listings and the pledges against
/// them. Its own repository, not folded into [GiveRepository], for the same
/// reason `SponsorshipListing`'s class doc gives — the two features share a
/// vocabulary but not a lifecycle.
class SponsorRepository {
  const SponsorRepository();

  // --- Discovery -----------------------------------------------------------

  /// The public board: open/partially-fulfilled listings, optionally
  /// narrowed by sport, target type or district. Newest first, same shape as
  /// `GiveRepository.watchVerifiedNeeds`.
  Stream<List<SponsorshipListing>> watchListings({
    String? sport,
    SponsorshipTargetType? targetType,
    String? district,
  }) =>
      guardStream(() {
        var q = Refs.sponsorshipListings
            .where('status', whereIn: ['open', 'partially_fulfilled']);
        if (sport != null && sport.trim().isNotEmpty) {
          q = q.where('sport', isEqualTo: sport);
        }
        if (targetType != null) {
          q = q.where('targetType', isEqualTo: targetType.wire);
        }
        if (district != null && district.trim().isNotEmpty) {
          q = q.where('geo.district', isEqualTo: district);
        }
        return q
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots()
            .map((s) => s.docs
                .map(SponsorshipListing.fromDoc)
                .toList(growable: false));
      });

  Stream<SponsorshipListing?> watchListing(String listingId) => guardStream(
        () => Refs.sponsorshipListing(listingId).snapshots().map(
              (d) => d.exists ? SponsorshipListing.fromDoc(d) : null,
            ),
      );

  /// Listings this person owns — as the athlete themselves, as the guardian
  /// who published one on a minor's behalf, or as the org admin who
  /// published one for a team.
  Stream<List<SponsorshipListing>> watchMyListings(String uid) => guardStream(
        () => Refs.sponsorshipListings
            .where('createdByUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs
                .map(SponsorshipListing.fromDoc)
                .toList(growable: false)),
      );

  /// Publishes a listing. Lands exactly as [SponsorshipListing.toCreate]
  /// shapes it — open, zero sponsors. `firestore.rules` is what actually
  /// enforces who may author a listing for whom; see its comment on
  /// `sponsorshipListings` for the minor-guardian requirement.
  Future<String> publishListing(
    SponsorshipListing listing, {
    required String createdByUid,
  }) =>
      guard(() async {
        final ref = Refs.sponsorshipListings.doc();
        await ref.set(listing.toCreate(createdByUid: createdByUid));
        return ref.id;
      });

  // --- Pledges ---------------------------------------------------------

  /// Offers a sponsor has made, across every listing — their own "my
  /// sponsorships" trail.
  Stream<List<SponsorPledge>> watchMyPledges(String sponsorUid) => guardStream(
        () => Refs.sponsorPledges
            .where('sponsorUid', isEqualTo: sponsorUid)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) =>
                s.docs.map(SponsorPledge.fromDoc).toList(growable: false)),
      );

  /// Every pledge waiting on one listing — the owner's inbox.
  Stream<List<SponsorPledge>> watchPledgesForListing(String listingId) =>
      guardStream(
        () => Refs.sponsorPledges
            .where('listingId', isEqualTo: listingId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) =>
                s.docs.map(SponsorPledge.fromDoc).toList(growable: false)),
      );

  Future<String> offerSponsorship(SponsorPledge pledge) => guard(() async {
        final ref = Refs.sponsorPledges.doc();
        await ref.set(pledge.toCreate());
        return ref.id;
      });

  /// The listing owner accepting or declining an offer. `firestore.rules`
  /// restricts this to the listing's own `createdByUid` and to exactly this
  /// transition — see the rule comment on `sponsorPledges`.
  Future<void> respondToPledge(
    String pledgeId, {
    required bool accept,
  }) =>
      guard(() => Refs.sponsorPledge(pledgeId).update({
            'status': accept ? 'accepted' : 'declined',
            'respondedAt': FieldValue.serverTimestamp(),
          }));

  /// The sponsor withdrawing their own still-pending offer.
  Future<void> withdrawPledge(String pledgeId) => guard(
        () => Refs.sponsorPledge(pledgeId).update({
          'status': 'withdrawn',
          'respondedAt': FieldValue.serverTimestamp(),
        }),
      );
}
