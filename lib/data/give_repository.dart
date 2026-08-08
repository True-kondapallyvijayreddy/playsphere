import '../core/firebase/firestore_refs.dart';
import '../core/models/give_collection_center.dart';
import '../core/models/give_donation.dart';
import '../core/models/give_impact_stats.dart';
import '../core/models/give_need.dart';
import 'org_repository.dart' show guard, guardStream;

/// The Give network: donations, collection centers, verified needs, and the
/// impact dashboard. Deliberately its own repository rather than folded into
/// [ShopRepository] — see `GiveDonation`'s class doc for why this inventory
/// must never mix with the commercial catalog.
class GiveRepository {
  const GiveRepository();

  // --- Donor side ---------------------------------------------------------

  /// Records a new donation. Always lands as [DonationStatus.submitted] —
  /// see `GiveDonation.toCreate`. Every later stage is written by staff, not
  /// through this repository at all.
  Future<String> submitDonation(GiveDonation donation) => guard(() async {
        final ref = Refs.giveDonations.doc();
        await ref.set(donation.toCreate());
        return ref.id;
      });

  /// One donor's own donations, newest first — their personal traceability
  /// view (donation id, current stage, eventual "delivered to a club in
  /// Telangana").
  Stream<List<GiveDonation>> watchMyDonations(String uid) => guardStream(
        () => Refs.giveDonations
            .where('donorUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots()
            .map((s) => s.docs.map(GiveDonation.fromDoc).toList(
                  growable: false,
                )),
      );

  // --- Collection centers ---------------------------------------------

  /// Active centers in a city, cheapest-first query same shape as
  /// `GroundRepository.searchGrounds`. Empty city returns everything —
  /// used by an admin picker where the donor hasn't typed a city yet.
  Stream<List<GiveCollectionCenter>> watchCollectionCenters({
    String? city,
  }) =>
      guardStream(() {
        var q = Refs.giveCollectionCenters.where('isActive', isEqualTo: true);
        if (city != null && city.trim().isNotEmpty) {
          q = q.where('cityKey', isEqualTo: city.trim().toLowerCase());
        }
        return q.limit(100).snapshots().map(
              (s) => s.docs
                  .map(GiveCollectionCenter.fromDoc)
                  .toList(growable: false),
            );
      });

  // --- Needs board ---------------------------------------------------------

  /// The public board: verified needs only, newest first. Unverified needs
  /// exist (an org admin just raised one) but are deliberately invisible
  /// here until staff confirm them — see `GiveNeed` for why.
  Stream<List<GiveNeed>> watchVerifiedNeeds({String? city}) => guardStream(() {
        var q = Refs.giveNeeds
            .where('verified', isEqualTo: true)
            .where('status', whereIn: ['open', 'partially_fulfilled']);
        if (city != null && city.trim().isNotEmpty) {
          q = q.where('cityKey', isEqualTo: city.trim().toLowerCase());
        }
        return q
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots()
            .map((s) => s.docs.map(GiveNeed.fromDoc).toList(growable: false));
      });

  /// Needs a club has raised, verified or not — the org's own view of what
  /// it has asked for and whether staff have confirmed it yet.
  Stream<List<GiveNeed>> watchOrgNeeds(String orgId) => guardStream(
        () => Refs.giveNeeds
            .where('orgId', isEqualTo: orgId)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(GiveNeed.fromDoc).toList(growable: false)),
      );

  /// Raises a need on behalf of a club/team/player. Lands unverified — see
  /// `GiveNeed.toCreate`. `firestore.rules` requires the caller hold at
  /// least `event_manager` in `orgId` for a team/club need.
  Future<String> raiseNeed(GiveNeed need, {required String createdByUid}) =>
      guard(() async {
        final ref = Refs.giveNeeds.doc();
        await ref.set(need.toCreate(createdByUid: createdByUid));
        return ref.id;
      });

  // --- Impact dashboard ---------------------------------------------------

  /// The network's headline numbers. Defaults to
  /// [GiveImpactStats.empty] — see that class for why a missing document
  /// means "not started yet", not an error.
  Stream<GiveImpactStats> watchImpactStats() => guardStream(
        () => Refs.giveImpactStats.snapshots().map(
              (d) => d.exists ? GiveImpactStats.fromDoc(d) : GiveImpactStats.empty,
            ),
      );
}
