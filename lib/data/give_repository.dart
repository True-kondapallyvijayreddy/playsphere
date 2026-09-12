import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue, Query;

import '../core/firebase/firestore_refs.dart';
import '../core/models/enums.dart';
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

  // --- The ops desk -------------------------------------------------------
  //
  // Everything below is the staff half of this feature. Until it existed, a
  // donation landed as `submitted` and a need landed unverified, and neither
  // had anywhere to go from inside the product: the pipeline `DonationStatus`
  // describes in nine stages was writable only from the Firebase console, so
  // "verified need" and "safety checked" were states nothing in the app could
  // ever reach. `firestore.rules` already allowed exactly these writes to the
  // `admin` claim and nothing else; what was missing was a caller. See
  // `GiveOpsScreen` for the console, and `functions/index.js`'s
  // `onGiveDonationSubmitted` / `onGiveNeedRaised` for who gets told.

  /// The donation queue, optionally narrowed to one stage.
  ///
  /// Deliberately not a variant of [watchMyDonations]: that one is a donor
  /// reading their own trail by `donorUid` and this one is staff reading
  /// everybody's, which are two different branches of the `giveDonations`
  /// read rule. Keeping them apart keeps it obvious which is being asked for.
  Stream<List<GiveDonation>> watchDonationQueue({DonationStatus? status}) =>
      guardStream(() {
        Query<Map<String, dynamic>> q = Refs.giveDonations;
        if (status != null) {
          q = q.where('status', isEqualTo: status.wire);
        }
        return q
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots()
            .map((s) =>
                s.docs.map(GiveDonation.fromDoc).toList(growable: false));
      });

  /// Moves one donation to its next stage and appends to its history.
  ///
  /// The history entry is appended client-side with `arrayUnion` rather than
  /// rewritten wholesale, so two staff members acting at the same moment
  /// cannot silently drop each other's entry. See `GiveStatusEvent.toMap`
  /// for why the timestamp inside an array element is a client clock — the
  /// only place in this codebase where that is true, and why.
  Future<void> advanceDonation(
    String donationId, {
    required DonationStatus to,
    String? notes,
  }) =>
      guard(
        () => Refs.giveDonation(donationId).update({
          'status': to.wire,
          'history': FieldValue.arrayUnion([
            GiveStatusEvent(status: to, at: DateTime.now()).toMap(),
          ]),
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Matches a donation against a verified need. Sets the stage as well as
  /// the link — being assigned to a need IS
  /// [DonationStatus.assigned], and letting the two drift apart is how a
  /// donation ends up counted against a need it was never actually sent to.
  Future<void> assignDonationToNeed(
    String donationId, {
    required String needId,
  }) =>
      guard(
        () => Refs.giveDonation(donationId).update({
          'assignedNeedId': needId,
          'status': DonationStatus.assigned.wire,
          'history': FieldValue.arrayUnion([
            GiveStatusEvent(status: DonationStatus.assigned, at: DateTime.now())
                .toMap(),
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Every need, verified or not — the staff view [watchVerifiedNeeds]
  /// deliberately is not. Pass `verified: false` for the review queue.
  Stream<List<GiveNeed>> watchNeedQueue({bool? verified}) => guardStream(() {
        Query<Map<String, dynamic>> q = Refs.giveNeeds;
        if (verified != null) {
          q = q.where('verified', isEqualTo: verified);
        }
        return q
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots()
            .map((s) => s.docs.map(GiveNeed.fromDoc).toList(growable: false));
      });

  /// Staff confirming (or withdrawing confirmation of) a raised need. This
  /// is the single write that decides whether a need is visible on the
  /// public board at all — see [watchVerifiedNeeds].
  Future<void> setNeedVerified(String needId, {required bool verified}) =>
      guard(
        () => Refs.giveNeed(needId).update({
          'verified': verified,
          'verifiedAt': verified ? FieldValue.serverTimestamp() : null,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Closing a need out, or reopening one closed by mistake.
  Future<void> setNeedStatus(String needId, GiveNeedStatus status) => guard(
        () => Refs.giveNeed(needId).update({
          'status': status.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

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
