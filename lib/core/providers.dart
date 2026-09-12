import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/billing_repository.dart';
import '../data/gov_repository.dart';
import '../data/razorpay_checkout.dart';
import '../core/models/gov_aggregate_row.dart';
import '../data/coach_repository.dart';
import '../data/sports_medic_repository.dart';
import '../data/sports_shop_repository.dart';
import '../data/career_repository.dart';
import '../data/leaderboard_repository.dart';
import '../data/tournament_repository.dart';
import '../data/community_repository.dart';
import '../data/competition_repository.dart';
import '../data/memory_composer.dart';
import '../data/club_file_repository.dart';
import '../data/memory_repository.dart';
import '../data/notification_repository.dart';
import '../data/ground_repository.dart';
import '../data/org_repository.dart';
import '../data/team_repository.dart';
import 'models/player_listing.dart';
import 'models/team.dart';
import 'models/team_join_request.dart';
import '../data/give_repository.dart';
import '../data/shop_repository.dart';
import '../data/discovery_repository.dart';
import '../data/scout_repository.dart';
import '../data/talent_board_repository.dart';
import '../data/sport_stats_repository.dart';
import '../core/models/sport_stat_row.dart';
import '../data/sponsor_repository.dart';
import '../data/staff_repository.dart';
import '../data/club_commerce_repository.dart';
import '../data/ad_repository.dart';
import '../data/food_repository.dart';
import '../data/scoring_service.dart';
import '../data/umpire_repository.dart';
import '../domain/career/head_to_head.dart';
import '../domain/career/leaderboard.dart';
import '../domain/rating/overall_glicko.dart';
import '../domain/standings/standings_calculator.dart';
import '../domain/draw/season_capacity.dart';
import '../domain/tournament/player_boards.dart';
import '../domain/tournament/tournament_leaderboard.dart';
import '../domain/tournament/tournament_overview.dart';
import 'ads/promo.dart';
import 'async_combine.dart';
import 'auth/auth_service.dart';
import 'l10n/locale_controller.dart';
import 'sync/sync_driver.dart';
import 'models/app_user.dart';
import 'models/billing.dart';
import 'models/glicko_badge.dart';
import 'models/venue.dart';
import 'models/venue_plan.dart';
import 'models/tournament.dart';
import 'models/tournament_invite.dart';
import 'models/tournament_official.dart';
import 'models/challenge.dart';
import 'models/coach.dart';
import 'models/sports_medic.dart';
import 'models/sports_shop.dart';
import 'models/competition.dart';
import 'models/dispute.dart';
import 'models/memory.dart';
import 'models/enums.dart';
import 'models/fixture.dart';
import 'models/ground.dart';
import 'models/ground_verification.dart';
import '../domain/cheer.dart';
import 'models/group_entry.dart';
import 'models/organization.dart';
import 'models/owner_proposal.dart';
import 'models/club_standing.dart';
import 'models/ranking_entry.dart';
import 'models/sub_group.dart';
import 'models/scoring_request.dart';
import 'models/shop_product.dart';
import 'models/give_collection_center.dart';
import 'models/give_donation.dart';
import 'models/give_impact_stats.dart';
import 'models/give_need.dart';
import 'models/platform_staff.dart';
import 'models/sponsorship.dart';
import 'models/umpire_profile.dart';
import 'models/club_product.dart';
import 'models/ad_campaign.dart';
import 'models/food_order.dart';
import '../domain/scout/talent_board.dart';
import '../domain/scout/talent_profile.dart';
import 'models/club_file.dart';
import 'models/squad_entry.dart';
import 'notifications/notification_model.dart';
import 'notifications/notification_service.dart';
import 'models/season_interest.dart';
import 'permissions/capability.dart';

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final userRepositoryProvider = Provider((ref) => const UserRepository());
final orgRepositoryProvider = Provider((ref) => const OrgRepository());
final teamRepositoryProvider = Provider((ref) => const TeamRepository());
final competitionRepositoryProvider =
    Provider((ref) => const CompetitionRepository());

/// One team, live.
final teamProvider = StreamProvider.family<Team?, String>(
  (ref, teamId) => ref.watch(teamRepositoryProvider).watchTeam(teamId),
);

/// The signed-in person's active teams.
///
/// Empty — not an error — when nobody is signed in, so a picker on a screen
/// that renders before auth settles shows "no teams yet" rather than throwing.
final myTeamsProvider = StreamProvider<List<Team>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <Team>[]);
  return ref.watch(teamRepositoryProvider).watchMyTeams(uid);
});

/// A club's active teams — permanent squads and any event teams it has raised.
final clubTeamsProvider = StreamProvider.family<List<Team>, String>(
  (ref, orgId) => ref.watch(teamRepositoryProvider).watchClubTeams(orgId),
);

/// Independent teams playing one sport — the squads with no club behind
/// them, which [clubTeamsProvider] by definition cannot reach.
final independentTeamsProvider = StreamProvider.family<List<Team>, String>(
  (ref, sportId) =>
      ref.watch(teamRepositoryProvider).watchIndependentTeams(sportId),
);

/// Who is waiting on one team's captain to let them on.
final teamJoinRequestsProvider =
    StreamProvider.family<List<TeamJoinRequest>, String>(
  (ref, teamId) =>
      ref.watch(teamRepositoryProvider).watchJoinRequests(teamId),
);

/// Whether the acting profile — the signed-in person, or a managed child
/// they're currently "managing as" — has already asked to join this team,
/// so the button can say "Asked" rather than inviting a second ask.
final hasAskedToJoinProvider =
    StreamProvider.family<bool, String>((ref, teamId) {
  final uid = ref.watch(actingProfileProvider)?.uid;
  if (uid == null) return Stream.value(false);
  return ref
      .watch(teamRepositoryProvider)
      .watchHasRequested(teamId: teamId, uid: uid);
});

/// The event teams raised for one competition.
final competitionTeamsProvider = StreamProvider.family<List<Team>, String>(
  (ref, compId) =>
      ref.watch(teamRepositoryProvider).watchCompetitionTeams(compId),
);
/// One [ScoringService] for the container, disposed with it.
///
/// It owns two broadcast `StreamController`s — the write-failure feed the
/// scoring pad listens on, and the pending-queue count — and nothing closed
/// either. A `Provider` alone leaks them for the lifetime of the process,
/// which in a test harness is every test that builds a container.
final scoringServiceProvider = Provider<ScoringService>((ref) {
  final service = ScoringService();
  ref.onDispose(service.dispose);
  return service;
});
/// Buying and reading plans.
///
/// The gateway is injected here and nowhere else, which is the whole point of
/// the seam: switching PlaySphere from the launch offer to real Razorpay
/// charges is a one-line change in this provider, and every screen that sells
/// something keeps working untouched. Tests override this provider with a
/// gateway that records what it was asked to collect.
final billingRepositoryProvider =
    Provider((ref) => const BillingRepository());

/// The real-money checkout — see `RazorpayCheckout`'s doc comment for why
/// this is a separate flow from [billingRepositoryProvider] rather than a
/// second `PaymentGateway`. Dormant while `Pricing.introOfferActive` is
/// true: nothing calls it, and the Cloud Function it talks to refuses to run
/// while the offer is on regardless.
final razorpayCheckoutProvider =
    Provider((ref) => const RazorpayCheckout());

/// Live status of one payment this device started through
/// [razorpayCheckoutProvider] — watched by [showRealPaymentSheet] so the
/// waiting screen updates itself the moment the webhook lands.
final paymentStatusProvider =
    StreamProvider.family<PlanPaymentStatus, String>((ref, paymentId) {
  return ref.watch(razorpayCheckoutProvider).watchStatus(paymentId);
});

/// Whether this phone's ACCOUNT currently holds Premium.
///
/// A provider rather than a getter on the screen so the answer is computed
/// once per profile change instead of once per widget, and so the ad slots,
/// the drawer entry and the profile badge can never disagree about it.
///
/// Read off [authUserProvider] rather than the profile in use, because
/// Premium is bought with a payment method and a child profile has none: a
/// parent who has paid should not find the ads back and the entitlement gone
/// the moment they switch into their child's profile.
final isPremiumProvider = Provider<bool>((ref) {
  final me = ref.watch(authUserProvider).valueOrNull;
  if (me == null) return false;
  return me.hasPremiumAt(DateTime.now());
});

/// This account's receipts — plan purchases and ground bookings.
final myPaymentsProvider = StreamProvider<List<PlanPayment>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(billingRepositoryProvider).watchMyPayments(uid);
});

/// The sports this player actually plays, for promo targeting.
///
/// Read off the career record rather than asked for. The whole argument for
/// PlaySphere selling its own ad inventory is that it knows the sport without
/// running a survey — a badminton player should see badminton, and that fact
/// is already sitting in `users/{uid}/career_stats`.
///
/// Returns an empty list rather than an error or a spinner while the career
/// is loading: an untargeted banner is a fine outcome, a banner slot that
/// throws is not.
final myPromoSportIdsProvider = Provider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const [];
  final career = ref.watch(careerProvider(uid)).valueOrNull;
  if (career == null) return const [];
  return sportIdsFor(career.map((c) => c.sportId));
});

final coachRepositoryProvider = Provider((ref) => const CoachRepository());

/// This person's own coach listing, or null if they have never made one.
///
/// Null is the answer for almost every account — most people are players, not
/// coaches — so nothing on an ordinary screen should depend on it. It is what
/// the "list yourself as a coach" entry reads to decide whether it is an
/// invitation or an edit.
final myCoachProfileProvider = StreamProvider<CoachProfile?>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(coachRepositoryProvider).watchCoach(uid);
});

/// One coach's listing, for their page.
final coachProvider =
    StreamProvider.family<CoachProfile?, String>((ref, uid) {
  return ref.watch(coachRepositoryProvider).watchCoach(uid);
});

// --- Local sports shops ----------------------------------------------------

final sportsShopRepositoryProvider =
    Provider((ref) => const SportsShopRepository());

/// What somebody typed into the shop directory. A record for the same reason
/// `CoachQuery` and [OfficialsQuery] are — these are asked together, and
/// re-running the search because they arrived in two frames is a wasted read.
typedef ShopQuery = ({
  String keywords,
  String city,
  ShopStock? stock,
  ShopService? service,
  String? sportId,
});

final shopQueryProvider = StateProvider<ShopQuery>(
  (ref) => (
    keywords: '',
    city: '',
    stock: null,
    service: null,
    sportId: null,
  ),
);

/// The shop directory's results.
///
/// Returns nothing until something has been asked — see
/// `SportsShopRepository.searchShops` for why a bare city or a single filter
/// counts as asking but an untouched screen does not.
final sportsShopSearchProvider =
    FutureProvider.autoDispose<List<SportsShop>>((ref) {
  final q = ref.watch(shopQueryProvider);
  return ref.watch(sportsShopRepositoryProvider).searchShops(
        keywords: q.keywords,
        stock: q.stock,
        service: q.service,
        sportId: q.sportId,
        city: q.city,
      );
});

/// One shop's listing, for its page.
final sportsShopProvider =
    StreamProvider.family<SportsShop?, String>((ref, uid) {
  return ref.watch(sportsShopRepositoryProvider).watchShop(uid);
});

/// This account's own shop listing, or null if they have never made one —
/// what the "list your shop" entry reads to decide whether it is an
/// invitation or an edit, same shape as [myCoachProfileProvider].
final mySportsShopProvider = StreamProvider<SportsShop?>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(sportsShopRepositoryProvider).watchShop(uid);
});

final sportsMedicRepositoryProvider =
    Provider((ref) => const SportsMedicRepository());

/// This person's own sports-medicine listing, or null — which is the answer
/// for all but a handful of accounts.
///
/// Read by the "are you a doctor or physio?" banner to decide whether it is
/// an invitation or a way back into an existing listing, exactly as
/// [myCoachProfileProvider] is.
final mySportsMedicProfileProvider =
    StreamProvider<SportsMedicProfile?>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(sportsMedicRepositoryProvider).watchMedic(uid);
});

/// One practitioner's listing, for their page.
final sportsMedicProvider =
    StreamProvider.family<SportsMedicProfile?, String>((ref, uid) {
  return ref.watch(sportsMedicRepositoryProvider).watchMedic(uid);
});

final groundRepositoryProvider = Provider((ref) => const GroundRepository());

/// The grounds the signed-in person owns. Empty for the vast majority of
/// accounts — most people are players, not ground owners.
final myGroundsProvider = StreamProvider<List<Ground>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(groundRepositoryProvider).watchMyGrounds(uid);
});

final groundProvider =
    StreamProvider.family<Ground?, String>((ref, groundId) {
  return ref.watch(groundRepositoryProvider).watchGround(groundId);
});

/// One day's bookings on one ground, live.
///
/// A stream rather than the one-shot read the booking sheet used to make. Two
/// clubs looking for a pitch on Sunday evening at the same moment is the
/// expected traffic pattern for a popular ground, not a rare race — and the
/// person watching a stale grid picks a slot that is already gone and gets an
/// error instead of a booking.
final groundDayBookingsProvider = StreamProvider.family<List<GroundBooking>,
    ({String groundId, DateTime day})>((ref, args) {
  return ref.watch(groundRepositoryProvider).watchDayBookings(
        groundId: args.groundId,
        day: args.day,
      );
});

/// Whether this person has already reported this ground, so the button can
/// say so rather than inviting a second identical report.
final myGroundReportProvider = StreamProvider.family<GroundReport?,
    ({String groundId, String uid})>((ref, args) {
  return ref.watch(groundRepositoryProvider).watchMyReport(
        groundId: args.groundId,
        uid: args.uid,
      );
});

/// The evidence behind one listing — its owner's, and a reviewer's, only.
final groundProofsProvider =
    StreamProvider.family<List<GroundProof>, String>((ref, groundId) {
  return ref.watch(groundRepositoryProvider).watchGroundProofs(groundId);
});

/// The ownership declaration filed with one listing.
final groundClaimProvider =
    FutureProvider.family<GroundOwnershipClaim?, String>((ref, groundId) {
  return ref.watch(groundRepositoryProvider).groundClaim(groundId);
});

/// Listings waiting on a reviewer. Admin-claim gated in `firestore.rules`;
/// a normal account gets a permission error, which is the intended answer.
final groundReviewQueueProvider = FutureProvider<List<Ground>>((ref) {
  return ref.watch(groundRepositoryProvider).reviewQueue();
});

/// The complaints filed against one listing.
final groundReportsForProvider =
    StreamProvider.family<List<GroundReport>, String>((ref, groundId) {
  return ref.watch(groundRepositoryProvider).watchReportsFor(groundId);
});

/// Every booking against one ground, for its owner's calendar.
final groundBookingsProvider =
    StreamProvider.family<List<GroundBooking>, String>((ref, groundId) {
  return ref.watch(groundRepositoryProvider).watchGroundBookings(groundId);
});

/// Bookings this person has made, across every ground.
final myGroundBookingsProvider =
    StreamProvider<List<GroundBooking>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(groundRepositoryProvider).watchMyBookings(uid);
});

/// One ground search: some words, and optionally a sport and an hour.
///
/// A value class with equality rather than a raw string, so `family` caches
/// "cricket grounds in Gachibowli at 7pm" separately from "any ground in
/// Gachibowli" instead of treating them as the same request.
///
/// [keywords] was [city] until the search stopped being a city search — see
/// `GroundRepository.searchGrounds`. It takes whatever was typed, whole: a
/// name, an area, a city, a sport, or several of those at once.
class GroundQuery {
  const GroundQuery({
    this.keywords = '',
    this.sportId,
    this.openAtHour,
  });

  final String keywords;
  final String? sportId;

  /// The hour they want to play, so a ground that is shut then never appears
  /// as an answer.
  final int? openAtHour;

  /// Whether there is anything to search for at all. Words, or a sport to
  /// list — with neither, the search has not been asked a question yet.
  bool get isEmpty => keywords.trim().isEmpty && sportId == null;

  @override
  bool operator ==(Object other) =>
      other is GroundQuery &&
      other.keywords == keywords &&
      other.sportId == sportId &&
      other.openAtHour == openAtHour;

  @override
  int get hashCode => Object.hash(keywords, sportId, openAtHour);
}

final groundSearchProvider =
    FutureProvider.family<List<Ground>, GroundQuery>((ref, q) async {
  if (q.isEmpty) return const [];
  return ref.watch(groundRepositoryProvider).searchGrounds(
        keywords: q.keywords,
        sportId: q.sportId,
        openAtHour: q.openAtHour,
      );
});

final shopRepositoryProvider = Provider((ref) => const ShopRepository());

/// The shop catalog. Falls back to the bundled Decathlon listings when the
/// collection is empty or unreachable — see [ShopRepository].
final shopProductsProvider = StreamProvider<List<ShopProduct>>((ref) {
  return ref.watch(shopRepositoryProvider).watchProducts();
});

final giveRepositoryProvider = Provider((ref) => const GiveRepository());

/// One donor's own donations, newest first — empty (not an error) for a
/// signed-out viewer, since a donation always belongs to somebody.
final myDonationsProvider = StreamProvider<List<GiveDonation>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(giveRepositoryProvider).watchMyDonations(uid);
});

/// Active collection centers, optionally filtered to one city. Null/empty
/// city returns every center — used by the donation form's picker before a
/// city has been chosen.
final giveCollectionCentersProvider =
    StreamProvider.family<List<GiveCollectionCenter>, String?>((ref, city) {
  return ref.watch(giveRepositoryProvider).watchCollectionCenters(city: city);
});

/// The public needs board: verified needs only, optionally by city. See
/// `GiveRepository.watchVerifiedNeeds` for why unverified needs never reach
/// this provider.
final giveNeedsBoardProvider =
    StreamProvider.family<List<GiveNeed>, String?>((ref, city) {
  return ref.watch(giveRepositoryProvider).watchVerifiedNeeds(city: city);
});

/// Needs a club has raised, verified or not — the club's own management view.
final orgNeedsProvider =
    StreamProvider.family<List<GiveNeed>, String>((ref, orgId) {
  return ref.watch(giveRepositoryProvider).watchOrgNeeds(orgId);
});

/// The network's headline numbers. See [GiveImpactStats.empty] for why a
/// fresh/quiet network reads as "just getting started", not as broken.
final giveImpactStatsProvider = StreamProvider<GiveImpactStats>((ref) {
  return ref.watch(giveRepositoryProvider).watchImpactStats();
});

// --- The Give ops desk -----------------------------------------------------
//
// Every provider below reads a queue only the `admin` claim can see. They are
// watched exclusively by `GiveOpsScreen`, which checks
// [isPlatformAdminProvider] before mounting them — so an ordinary account
// never opens one of these listeners and never collects a permission error
// for a screen it was not looking at.

/// The donation pipeline, optionally narrowed to one stage. Null status is
/// "everything", which is what the desk wants on the day's first look.
final giveDonationQueueProvider =
    StreamProvider.family<List<GiveDonation>, DonationStatus?>((ref, status) {
  return ref.watch(giveRepositoryProvider).watchDonationQueue(status: status);
});

/// Raised needs, verified or not. `false` is the review queue — the needs
/// nobody outside this screen can see yet.
final giveNeedQueueProvider =
    StreamProvider.family<List<GiveNeed>, bool?>((ref, verified) {
  return ref.watch(giveRepositoryProvider).watchNeedQueue(verified: verified);
});

/// How much is waiting on the Give desk right now — the two numbers the ops
/// home shows without making anybody open a queue to find them.
///
/// Derived rather than stored: a counter document would need a function to
/// keep it true and would be wrong for exactly as long as that function was
/// broken, whereas this cannot disagree with the lists it is counting.
typedef GiveOpsBacklog = ({int newDonations, int unverifiedNeeds});

final giveOpsBacklogProvider = Provider<GiveOpsBacklog>((ref) {
  final donations = ref
          .watch(giveDonationQueueProvider(DonationStatus.submitted))
          .valueOrNull ??
      const [];
  final needs = ref.watch(giveNeedQueueProvider(false)).valueOrNull ?? const [];
  return (newDonations: donations.length, unverifiedNeeds: needs.length);
});

final sponsorRepositoryProvider =
    Provider((ref) => const SponsorRepository());

/// Filter state for the sponsorship browse screen, one value object so the
/// screen can watch a single provider rather than three independent ones.
class SponsorBrowseFilter {
  const SponsorBrowseFilter({this.sport, this.targetType, this.district});

  final String? sport;
  final SponsorshipTargetType? targetType;
  final String? district;

  SponsorBrowseFilter copyWith({
    String? Function()? sport,
    SponsorshipTargetType? Function()? targetType,
    String? Function()? district,
  }) =>
      SponsorBrowseFilter(
        sport: sport != null ? sport() : this.sport,
        targetType: targetType != null ? targetType() : this.targetType,
        district: district != null ? district() : this.district,
      );
}

final sponsorBrowseFilterProvider =
    StateProvider((ref) => const SponsorBrowseFilter());

final sponsorshipListingsProvider =
    StreamProvider<List<SponsorshipListing>>((ref) {
  final filter = ref.watch(sponsorBrowseFilterProvider);
  return ref.watch(sponsorRepositoryProvider).watchListings(
        sport: filter.sport,
        targetType: filter.targetType,
        district: filter.district,
      );
});

final sponsorshipListingProvider =
    StreamProvider.family<SponsorshipListing?, String>((ref, listingId) {
  return ref.watch(sponsorRepositoryProvider).watchListing(listingId);
});

/// Listings this person owns — as athlete, guardian, or team admin.
final mySponsorshipListingsProvider =
    StreamProvider<List<SponsorshipListing>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(sponsorRepositoryProvider).watchMyListings(uid);
});

/// Offers this person has made as a sponsor.
final myPledgesProvider = StreamProvider<List<SponsorPledge>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(sponsorRepositoryProvider).watchMyPledges(uid);
});

/// Offers waiting on one listing — its owner's inbox.
final pledgesForListingProvider =
    StreamProvider.family<List<SponsorPledge>, String>((ref, listingId) {
  return ref.watch(sponsorRepositoryProvider).watchPledgesForListing(listingId);
});

// --- Sponsor discovery -----------------------------------------------------
//
// "Find someone to sponsor" used to be one list of published listings, which
// answered only half the question it asks. A sponsor arriving with money and
// no particular athlete in mind wants to see who is actually winning in a
// sport — and the best of those have usually never written a listing, because
// writing one is the kind of thing a player does after somebody tells them
// they can. The providers below are the other half: the ranked ladders,
// joined to whichever listings exist, so one screen shows both "people asking
// for backing" and "people worth backing".

/// Every open listing, unfiltered, indexed by who it is for.
///
/// Keyed by `subjectUid` for an athlete listing and `orgId` for a team one —
/// the two never collide, since a uid and an org id are different id spaces.
/// Built off the unfiltered listing stream rather than a query per row: the
/// board is capped at 100 rows by `SponsorRepository.watchListings`, so this
/// is one listener for a whole screen instead of one per ranked player.
final openListingsBySubjectProvider =
    StreamProvider<Map<String, SponsorshipListing>>((ref) {
  return ref.watch(sponsorRepositoryProvider).watchListings().map((listings) {
    final index = <String, SponsorshipListing>{};
    for (final l in listings) {
      final key = l.isAthlete ? l.subjectUid : l.orgId;
      if (key == null || key.isEmpty) continue;
      // First wins. The stream is newest-first, so a player who has published
      // twice is represented by their current listing, not a stale one.
      index.putIfAbsent(key, () => l);
    }
    return Map<String, SponsorshipListing>.unmodifiable(index);
  });
});

/// One ranked athlete on the sponsor board, with whatever backing route
/// exists for them.
///
/// [listing] null is the interesting case and the reason this record exists:
/// it means a top-ranked player has no listing, which the screen turns into
/// an invitation rather than hiding the player. See `SponsorBrowseScreen`.
typedef SponsorTarget = ({
  RankingRow row,
  SponsorshipListing? listing,
});

/// The top ranked athletes in one sport, joined to their listings.
final sponsorTopAthletesProvider =
    Provider.family<AsyncValue<List<SponsorTarget>>, String>((ref, sportId) {
  final ranking = ref.watch(rankingProvider(sportId));
  final index = ref.watch(openListingsBySubjectProvider).valueOrNull ??
      const <String, SponsorshipListing>{};
  return ranking.whenData(
    (rows) => rows
        .map((r) => (row: r, listing: index[r.uid]))
        .toList(growable: false),
  );
});

final clubCommerceRepositoryProvider =
    Provider((ref) => const ClubCommerceRepository());

/// One club's public storefront.
final clubActiveProductsProvider =
    StreamProvider.family<List<ClubProduct>, String>((ref, orgId) {
  return ref.watch(clubCommerceRepositoryProvider).watchActiveProducts(orgId);
});

/// One club's full catalog, active or paused — its own management view.
final clubCatalogProvider =
    StreamProvider.family<List<ClubProduct>, String>((ref, orgId) {
  return ref.watch(clubCommerceRepositoryProvider).watchOrgCatalog(orgId);
});

/// Every order this person has placed, across every club.
final myClubOrdersProvider = StreamProvider<List<ClubOrder>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(clubCommerceRepositoryProvider).watchMyOrders(uid);
});

/// Orders waiting on one club to fulfil.
final clubOrdersProvider =
    StreamProvider.family<List<ClubOrder>, String>((ref, orgId) {
  return ref.watch(clubCommerceRepositoryProvider).watchOrgOrders(orgId);
});

final adRepositoryProvider = Provider((ref) => const AdRepository());

/// This advertiser's own submissions, any status.
final myAdCampaignsProvider = StreamProvider<List<AdCampaign>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(adRepositoryProvider).watchMyCampaigns(uid);
});

/// The ad review queue, one status at a time — `pending` is the inbox that
/// gave this feature its point. Watched only by `AdReviewScreen`, behind the
/// same [isPlatformAdminProvider] check every other staff queue uses.
final adReviewQueueProvider =
    StreamProvider.family<List<AdCampaign>, AdCampaignStatus>((ref, status) {
  return ref.watch(adRepositoryProvider).watchForReview(status);
});

/// How many campaigns are waiting on a decision. Derived from the queue it
/// counts, for the same reason [giveOpsBacklogProvider] is.
final pendingAdCountProvider = Provider<int>((ref) {
  return (ref.watch(adReviewQueueProvider(AdCampaignStatus.pending)).valueOrNull ??
          const [])
      .length;
});

/// Approved campaigns eligible for one slot — the raw feed
/// `promoForSlotProvider` picks from.
final approvedCampaignsForSlotProvider =
    StreamProvider.family<List<AdCampaign>, PromoSlot>((ref, slot) {
  return ref.watch(adRepositoryProvider).watchApprovedForSlot(slot);
});

/// The one promo `PromoBanner` actually renders for [slot]: a live,
/// approved advertiser campaign when one is targeting this slot, otherwise
/// `PromoCatalog`'s house catalog — see `PromoCatalog.forSlotWithCampaigns`.
final promoForSlotProvider = Provider.family<Promo?, PromoSlot>((ref, slot) {
  final campaigns =
      ref.watch(approvedCampaignsForSlotProvider(slot)).valueOrNull ?? const [];
  return PromoCatalog.forSlotWithCampaigns(
    slot,
    liveCampaigns: [for (final c in campaigns) c.toPromo()],
    playerSportIds: ref.watch(myPromoSportIdsProvider),
    seed: PromoCatalog.dailySeed(DateTime.now()),
  );
});

/// The row of promos a `PromoStrip` scrolls through for [slot].
///
/// A list where `promoForSlotProvider` is a single pick — see
/// `PromoCatalog.listForSlot`. Same inputs, so a campaign that would have
/// been chosen as THE banner also leads the strip.
final promoStripProvider =
    Provider.family<List<Promo>, PromoSlot>((ref, slot) {
  final campaigns =
      ref.watch(approvedCampaignsForSlotProvider(slot)).valueOrNull ?? const [];
  return PromoCatalog.listForSlot(
    slot,
    liveCampaigns: [for (final c in campaigns) c.toPromo()],
    playerSportIds: ref.watch(myPromoSportIdsProvider),
  );
});

final foodRepositoryProvider = Provider((ref) => const FoodRepository());

/// One ground's active canteen menu.
final groundActiveMenuProvider =
    StreamProvider.family<List<GroundMenuItem>, String>((ref, groundId) {
  return ref.watch(foodRepositoryProvider).watchActiveMenu(groundId);
});

/// The ground owner's full menu management view.
final groundFullMenuProvider =
    StreamProvider.family<List<GroundMenuItem>, String>((ref, groundId) {
  return ref.watch(foodRepositoryProvider).watchFullMenu(groundId);
});

/// Every food order this person has placed, across every ground.
final myFoodOrdersProvider = StreamProvider<List<FoodOrder>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(foodRepositoryProvider).watchMyOrders(uid);
});

/// Orders waiting on one ground to fulfil.
final groundFoodOrdersProvider =
    StreamProvider.family<List<FoodOrder>, String>((ref, groundId) {
  return ref.watch(foodRepositoryProvider).watchGroundOrders(groundId);
});

final scoutRepositoryProvider = Provider((ref) => const ScoutRepository());

// --- Finding clubs and people you have no connection to yet ---------------

final discoveryRepositoryProvider =
    Provider((ref) => const DiscoveryRepository());

/// This account's own directory listing, or null if they have never published
/// one — which is the answer for almost everybody, because appearing in the
/// directory is opt-in. See [PlayerListing].
///
/// Keyed off the ACCOUNT rather than the profile in use: a listing is a claim
/// somebody makes about themselves, and a guardian browsing as their child
/// must not be shown the child's, nor be able to publish one. The directory
/// is adults only — `firestore.rules` refuses a minor's write independently.
final myPlayerListingProvider = StreamProvider<PlayerListing?>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(discoveryRepositoryProvider).watchMyListing(uid);
});

/// Whether this account may open the full career profile of somebody they have
/// no club in common with.
///
/// This is an ENTITLEMENT gate, not a security boundary, and the distinction
/// matters. What a stranger may read is decided by `firestore.rules` on
/// `/users/{userId}` — a `public` adult profile is readable by anyone signed
/// in, and no client-side flag changes that. What this decides is whether
/// PlaySphere OFFERS the trip: browsing the directory and opening the people
/// in it is the Premium half of discovery, in the same spirit as the rest of
/// `PremiumScreen`'s list — depth on an identity, never the ability to take
/// part in sport.
///
/// Everything a free member could already reach stays reachable. Club-mates,
/// team sheets, leaderboards, scout search and anybody's own profile are all
/// unaffected; this is asked only where the directory hands somebody a
/// stranger they would otherwise never have found.
final canOpenStrangerProfilesProvider = Provider<bool>((ref) {
  return ref.watch(isPremiumProvider);
});

/// One search's parameters, bundled so the search screen watches a single
/// provider rather than five independent ones. `sportId` is null before the
/// scout has picked a sport at all — see `scoutSearchResultsProvider`.
class ScoutSearchQuery {
  const ScoutSearchQuery({
    this.sportId,
    this.filters = TalentSearchFilters.none,
  });

  final String? sportId;
  final TalentSearchFilters filters;

  ScoutSearchQuery copyWith({
    String? Function()? sportId,
    TalentSearchFilters? filters,
  }) =>
      ScoutSearchQuery(
        sportId: sportId != null ? sportId() : this.sportId,
        filters: filters ?? this.filters,
      );
}

final scoutSearchQueryProvider = StateProvider((ref) => const ScoutSearchQuery());

/// A one-shot fetch, not a live listener — `ScoutRepository.searchCandidates`
/// makes a tolerant per-document read across an unbounded set of players, and
/// nothing about that shape lends itself to a Firestore snapshot listener.
/// The screen re-triggers this itself (pull-to-refresh / a "Search" button)
/// rather than staying subscribed.
final scoutSearchResultsProvider =
    FutureProvider.autoDispose<List<ScoutSearchResult>>((ref) {
  final query = ref.watch(scoutSearchQueryProvider);
  if (query.sportId == null) return Future.value(const []);
  return ref.watch(scoutRepositoryProvider).searchCandidates(
        sportId: query.sportId!,
        filters: query.filters,
      );
});

// --- Talent discovery boards --------------------------------------------
//
// The counterpart to the scout *search* above. Search answers "who is good at
// this, here"; the boards answer "who is getting better", which is a ranking
// across players no client may read and is therefore precomputed server-side.
// See `functions/talent.js` and `lib/domain/scout/talent_board.dart`.

final talentBoardRepositoryProvider =
    Provider((ref) => const TalentBoardRepository());

final sportStatsRepositoryProvider =
    Provider((ref) => const SportStatsRepository());

/// The sports directory's totals, keyed by sport id.
///
/// Not `autoDispose`: the directory is a browse screen people step in and out
/// of while deciding what to open, and a nightly-refreshed collection of
/// fifteen small documents is worth keeping warm across those trips rather
/// than re-reading each time.
final sportStatsProvider = StreamProvider<Map<String, SportStatRow>>(
  (ref) => ref.watch(sportStatsRepositoryProvider).watchAll(),
);

/// Which board the discovery screen is showing.
///
/// Defaults to the national, all-ages, public cricket board — the one scope
/// guaranteed to exist for the largest number of users, so the screen has
/// content before anyone touches a filter.
final talentBoardKeyProvider = StateProvider(
  (ref) => const TalentBoardKey(
    sportId: 'cricket',
    audience: BoardAudience.public,
  ),
);

/// A live listener, unlike `scoutSearchResultsProvider`: this is a single
/// document read by id, which is exactly the shape a snapshot listener is
/// cheapest for.
final talentBoardProvider = StreamProvider.autoDispose<TalentBoard?>((ref) {
  final key = ref.watch(talentBoardKeyProvider);
  return ref.watch(talentBoardRepositoryProvider).watchBoard(key);
});

/// Whether this account may read `__scout` boards — the variant that includes
/// minors.
///
/// Reads the custom claim from the ID token. This is a UI affordance only:
/// the claim is enforced in `firestore.rules`, and a client that lies here
/// gets a denied read and an empty board. Its only job is to avoid offering a
/// toggle that would visibly do nothing.
final isScoutProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return false;
  final token = await user.getIdTokenResult();
  return token.claims?['scout'] == true || token.claims?['admin'] == true;
});

// --- Stat leaderboards --------------------------------------------------
//
// App-wide "who leads in this stat" rankings, precomputed the same way the
// talent boards above are — see `functions/leaderboard.js` and
// `lib/domain/career/leaderboard.dart`.

final leaderboardRepositoryProvider =
    Provider((ref) => const LeaderboardRepository());

/// A live listener on one sport/stat board — a single document read by id,
/// same as [talentBoardProvider].
final leaderboardProvider =
    StreamProvider.autoDispose.family<Leaderboard?, LeaderboardKey>((
  ref,
  key,
) {
  return ref.watch(leaderboardRepositoryProvider).watchBoard(key);
});

final communityRepositoryProvider =
    Provider((ref) => const CommunityRepository());

/// A club's `orgs/{id}/subgroups` — the older, club-scoped bucket concept.
///
/// NOT a club's teams, despite the shape. A team is a `teams/{teamId}`
/// document with a `clubId` on it — see `Refs.teamsForClub` for why the
/// collection is top-level — and [clubTeamsProvider] is what reads them.
/// The club header counted subgroups and called them "Teams", which showed
/// "0 Teams" on a club whose members screen listed eleven, because nothing
/// has written a subgroup since teams moved out. Anything counting or
/// listing a club's teams wants [clubTeamsProvider].
final subGroupsProvider = StreamProvider.family<List<SubGroup>, String>(
  (ref, orgId) =>
      ref.watch(communityRepositoryProvider).watchSubGroups(orgId),
);
final umpireRepositoryProvider = Provider((ref) => const UmpireRepository());

/// What somebody typed into the officials directory. A record for the same
/// reason `CoachQuery` is one — sport and availability are asked together,
/// and re-running the query because they arrived in two frames is a wasted
/// read.
typedef OfficialsQuery = ({
  String? sportId,
  String? district,
  bool availableOnly,
});

final officialsQueryProvider = StateProvider<OfficialsQuery>(
  (ref) => (sportId: null, district: null, availableOnly: false),
);

/// The registered officials directory.
///
/// Unlike `coachSearchProvider`, this deliberately answers with the full list
/// before anything has been typed. A coach directory that loaded every coach
/// in the country would be an unbounded read; the officials registry is one
/// row per registered umpire and small enough to show whole — and a directory
/// that starts empty is precisely the failure this screen exists to fix,
/// since until now registering as an official put you somewhere nobody could
/// look. `UmpireRepository.watchUmpires` caps it at 300 either way.
final officialsDirectoryProvider =
    StreamProvider.autoDispose<List<UmpireProfile>>((ref) {
  final q = ref.watch(officialsQueryProvider);
  return ref.watch(umpireRepositoryProvider).watchUmpires(
        sportId: q.sportId,
        district: q.district,
        availableOnly: q.availableOnly,
      );
});

/// This account's own officials-registry entry, or null if they have never
/// registered — what the directory reads to decide whether its call to
/// action says "Register" or "Edit my listing", same shape as
/// [myCoachProfileProvider].
final myUmpireProfileProvider = FutureProvider<UmpireProfile?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return ref.watch(umpireRepositoryProvider).fetchUmpire(uid);
});

/// Queued scoring events not yet confirmed by the server.
///
/// A provider rather than a `StreamBuilder` over the getter, because the getter
/// returns a fresh stream on every access — reading it inside `build` would
/// resubscribe on each rebuild.
final pendingScoreEventsProvider = StreamProvider<int>(
  (ref) => ref.watch(scoringServiceProvider).pendingCountStream,
);

/// Drives the offline queue: replays it on start, on resume, and on a retry
/// tick while anything is still waiting.
///
/// Mounted once by the app shell. Until this existed, `reconcileQueue` was
/// called from exactly one place — `initState` on the scoring pad — so a
/// queued action was only ever retried if the scorer reopened THAT match's
/// pad, which is the last thing anyone does with a finished match. Matches
/// sat unsynced for days on a phone with full signal (Bug #9).
final syncDriverProvider = Provider<SyncDriver>((ref) {
  final service = ref.watch(scoringServiceProvider);
  final driver = SyncDriver(
    reconcile: service.reconcileQueue,
    pendingCount: service.pendingCount,
  );
  ref.onDispose(driver.dispose);
  return driver;
});

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// The single source of truth for "is anyone signed in".
final authStateProvider = StreamProvider<fb.User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// The uid of the Firebase Auth session — the ACCOUNT, i.e. the Google
/// identity this phone is signed in with.
///
/// Deliberately different from [currentUidProvider], which is the PROFILE
/// currently in use and is what almost everything in the app should read.
/// The two are the same uid until a guardian switches into a child's profile
/// (see [actingProfileUidProvider]), and from that moment on they are two
/// different people.
///
/// Read this one only where the answer genuinely belongs to the account and
/// not to the profile in front of you:
///
///  * push registration — a device token is the phone's, not a profile's;
///  * money — receipts, plan purchases, ground bookings, club-store orders,
///    ad campaigns, sponsorship pledges and donations are made by whoever
///    holds the payment method, and a child profile must never be able to
///    spend or be shown what was spent;
///  * the consoles a business account owns — grounds, ads, sponsorships,
///    the coach and sports-medicine listings;
///  * the list of children itself, which is the thing the switcher is built
///    from and so can never be scoped to the profile being switched into.
///
/// Everything else — teams, clubs, matches, RSVPs, notifications, career —
/// belongs to the profile and reads [currentUidProvider].
final authUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
);

/// The account holder's own PlaySphere profile, regardless of which profile
/// is currently being used. The counterpart of [authUidProvider], and the
/// thing the profile switcher shows as "your own profile".
final authUserProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watch(uid);
});

// ---------------------------------------------------------------------------
// Profile switching
//
// One phone, several players. A guardian who has created profiles for
// children with no device of their own switches between them the way a
// household switches Netflix profiles: the whole app becomes that player.
// Their teams, their clubs, their matches, their notifications, their career
// — nothing of the guardian's own is mixed in, and nothing the guardian does
// while switched in is attributed to the guardian.
//
// The mechanism is deliberately a single point: [currentUidProvider] answers
// "whose app is this right now", and the ~130 places that ask it get the
// switch for free. Screens never reimplement their own idea of whose uid to
// read or write, which is exactly how a half-switched app — the child's
// matches next to the guardian's notifications — would otherwise happen.
//
// Server-side the same switch is `isSelfOrCustodian`/`wardUids()` in
// firestore.rules: a guardian may read and write as a child they created,
// and stops being able to the instant the child claims the profile onto
// their own device.
// ---------------------------------------------------------------------------

/// Which profile is in use, and the persistence behind it.
///
/// Persisted, per account, rather than held for the session: a profile
/// switch is a setting, not a mode. A parent who hands the phone to their
/// child and comes back to it tomorrow should find the child's profile
/// still open, the same way Netflix does. What keeps that honest is the
/// banner on every screen naming whose profile this is, not the app quietly
/// reverting overnight to one that says a different name.
///
/// Keyed by the signing-in account, so a phone shared between two Google
/// accounts never restores one account's profile choice into the other's
/// session, and signing out drops the selection entirely.
class ActingProfileController extends Notifier<String?> {
  static String _keyFor(String authUid) => 'ps.actingProfile.$authUid';

  @override
  String? build() {
    final authUid = ref.watch(authUidProvider);
    if (authUid == null) return null;
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs?.getString(_keyFor(authUid));
  }

  /// Switches into `uid`'s profile, or back to the account holder's own when
  /// given null. Safe to call with the uid already in use.
  void switchTo(String? uid) {
    final authUid = ref.read(authUidProvider);
    state = uid == authUid ? null : uid;
    if (authUid == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    if (state == null) {
      prefs?.remove(_keyFor(authUid));
    } else {
      prefs?.setString(_keyFor(authUid), state!);
    }
  }
}

/// The uid of the managed child whose profile is in use, or null while the
/// account holder is using their own — the default, and the answer for every
/// account that has never created a child profile.
final actingProfileUidProvider =
    NotifierProvider<ActingProfileController, String?>(
  ActingProfileController.new,
);

/// Whose app this is right now: the child profile switched into, or the
/// signed-in account itself.
///
/// This is what the whole app reads. See [authUidProvider] for the short
/// list of things that must not.
final currentUidProvider = Provider<String?>((ref) {
  final acting = ref.watch(actingProfileUidProvider);
  final authUid = ref.watch(authUidProvider);
  if (authUid == null) return null;
  return acting ?? authUid;
});

/// Whether the signed-in account carries the `admin` custom claim —
/// PlaySphere's one platform-staff role, already what `firestore.rules`'
/// `isGiveStaff()` checks for the Give collection centres and what gates the
/// government dashboard below it. Re-reads the token rather than trusting a
/// cached value: a claim is granted server-side and a client that has been
/// open since before the grant must not need a sign-out to see it.
final isPlatformAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return false;
  final token = await user.getIdTokenResult();
  return token.claims?['admin'] == true;
});

// --- The operations team ---------------------------------------------------
//
// See `StaffMember`'s class doc for why a roster document exists next to the
// `admin` custom claim rather than instead of it. Short version: a claim
// lives on an auth token, and a Cloud Function that wants to tell somebody a
// campaign has been submitted cannot enumerate token claims — so without
// these rows, every staff notification in the product had no recipient list
// and was simply never sent.

final staffRepositoryProvider = Provider((ref) => const StaffRepository());

/// The whole ops team. Readable only with the `admin` claim, so this is
/// watched from the ops screens and nowhere else.
final staffRosterProvider = StreamProvider<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).watchStaff();
});

/// This account's own roster row, or null if they hold the claim but have
/// never been added to the roster.
///
/// Null is the ordinary state for a brand-new deployment — the owner has the
/// claim before anybody has written a row — and is exactly what the ops team
/// screen turns into its "add yourself" prompt, so the first notification
/// recipient can exist without a console visit.
final myStaffMembershipProvider = StreamProvider<StaffMember?>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(staffRepositoryProvider).watchMe(uid);
});

final govRepositoryProvider = Provider((ref) => const GovRepository());

final govAggregatesProvider = StreamProvider<List<GovAggregateRow>>((ref) {
  return ref.watch(govRepositoryProvider).watchAll();
});

/// The device half of push notifications.
///
/// Sending happens in Cloud Functions — a client cannot be allowed to make
/// other people's phones buzz. This only registers the device so the server
/// can reach it, and turns arriving messages into something the app can route
/// on. See `functions/index.js` for what actually decides to send.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.dispose);
  return service;
});

/// Registers this device against whoever is signed in, and drops the
/// registration when they sign out.
///
/// Watched from the app shell rather than called at sign-in, because a token
/// also has to be registered on a cold start where the session was restored
/// and no sign-in ever happened. Registration is idempotent — it rewrites one
/// document per device — so running it on every auth change is correct rather
/// than merely tolerable.
///
/// Returns void and never throws: a person who declined notifications must
/// still get a working app.
final pushRegistrationProvider = Provider<void>((ref) {
  final uid = ref.watch(authUidProvider);
  final service = ref.watch(notificationServiceProvider);

  if (uid == null) return;

  // The account AND every child profile it still manages. A managed child has
  // no device of their own — that is the entire premise of the feature — so
  // this phone is the only place their match reminders can land. Without the
  // children in this list, switching into a child's profile gives a working
  // app with a permanently silent notification bell.
  final uids = <String>[
    uid,
    for (final child in ref.watch(switchableProfilesProvider)) child.uid,
  ];
  service.register(uids);

  ref.onDispose(() {
    // Deliberately not awaited: a provider disposal must not block, and a
    // failed unregister costs a stale token that the server prunes the first
    // time it tries to use it.
    service.unregister(uids);
  });
});

/// The durable inbox behind a push — see `NotificationRepository` for why
/// `NotificationService` alone left a member's Notifications screen empty.
final notificationRepositoryProvider =
    Provider((ref) => const NotificationRepository());

/// Every club activity this person has ever been sent a push about, newest
/// first: event reminders, match starts, results, membership approvals,
/// challenges, tournament announcements and invites. This is what makes
/// "Notifications" a real history rather than only a live list of things
/// still needing a decision.
final myNotificationFeedProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchFeed(uid);
});

/// How many of those this person has not yet opened, for the bell badge.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final feed = ref.watch(myNotificationFeedProvider).valueOrNull ?? const [];
  return feed.where((n) => !n.read).length;
});

/// The PlaySphere profile in use, which is a different thing from the
/// Firebase auth record behind it: Google gives us a name and an email, but
/// the date of birth that every age rule depends on only exists here — and
/// once a guardian has switched into a child's profile, the account's own
/// name and email are not the ones on screen at all. See [authUserProvider]
/// for the account holder's own.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watch(uid);
});

/// True once the user has supplied the details Google cannot give us. Until
/// then they are routed to the profile-completion screen and cannot enter a
/// competition, because we would have no way to judge their age category.
final profileIsCompleteProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.profileComplete ?? false;
});

/// Every child profile the signed-in ACCOUNT has created — both
/// still-managed and already claimed. See `ManagedChildrenScreen`.
///
/// Scoped to [authUidProvider] and not to the profile in use, necessarily:
/// this is the list the profile switcher is built from, so scoping it to the
/// profile being switched into would empty it the moment it was used and
/// strand the guardian inside a child's profile with no way back.
final myManagedChildrenProvider = StreamProvider<List<AppUser>>((ref) {
  final uid = ref.watch(authUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(userRepositoryProvider).watchManagedChildren(uid);
});

/// The children this account can still switch into: created by it and not
/// yet claimed onto the child's own device. A claimed child stays visible on
/// `ManagedChildrenScreen` — the guardian keeps read access to their career
/// — but is no longer a profile this phone may act as, server-side or here.
final switchableProfilesProvider = Provider<List<AppUser>>((ref) {
  final children = ref.watch(myManagedChildrenProvider).valueOrNull ?? const [];
  return [
    for (final c in children)
      if (c.isManaged) c,
  ];
});

/// The profile in use, as a full [AppUser] — a plain synchronous read of
/// [currentUserProvider] for the many call sites that only ever wanted the
/// value.
///
/// Kept under its original name because "which profile is this action for"
/// is the vocabulary the participation screens already speak. Resolves to
/// null only while the underlying document is still loading, never as a
/// steady state.
final actingProfileProvider = Provider<AppUser?>((ref) {
  return ref.watch(currentUserProvider).valueOrNull;
});

/// True while the account holder is inside one of their children's profiles
/// rather than their own — what the banner, the switcher and every
/// account-only entry in the navigation key off.
final isActingAsChildProvider = Provider<bool>((ref) {
  final acting = ref.watch(actingProfileUidProvider);
  return acting != null && acting != ref.watch(authUidProvider);
});

/// Leaves [actingProfileUidProvider] the moment it stops pointing at a
/// still-managed child — most commonly because the child just claimed their
/// own profile, which is exactly when custodian rights end server-side too
/// (see `isCustodianOfUnclaimed`). Mounted on the app shell so this is
/// checked on every screen: a guardian must never be left inside a profile
/// the server has already stopped letting them read, which is a screenful of
/// permission errors rather than an empty state.
final actingProfileGuardProvider = Provider<void>((ref) {
  final childUid = ref.watch(actingProfileUidProvider);
  if (childUid == null) return;
  final children = ref.watch(myManagedChildrenProvider).valueOrNull;
  if (children == null) return; // Still loading — decide on the next build.
  final stillManaged = children.any((c) => c.uid == childUid && c.isManaged);
  if (!stillManaged) {
    Future.microtask(
      () => ref.read(actingProfileUidProvider.notifier).switchTo(null),
    );
  }
});

// ---------------------------------------------------------------------------
// Organizations
// ---------------------------------------------------------------------------

final myMembershipsProvider = StreamProvider<List<Membership>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(orgRepositoryProvider).watchMyMemberships(uid);
});

/// The clubs one NAMED person belongs to, which is a different question from
/// the one [myMembershipsProvider] answers.
///
/// Almost everything wants "the profile in use", and should keep reading the
/// provider above. This family exists for the one case that cannot: a guardian
/// on their OWN home screen has to know which clubs their children are in, and
/// switching into each child's profile to find out is precisely the trip the
/// home screen exists to save them. See `homeDiscoveryOrgIdsProvider`.
///
/// Only ever asked of the caller or one of their unclaimed wards. That is not
/// a convention this file enforces — it is the collection-group `members` rule
/// in `firestore.rules`, whose `isSelfOrWard(resource.data.uid)` was written
/// for exactly this query shape. Asking it about a stranger returns a
/// permission error, which is the correct answer.
final userMembershipsProvider =
    StreamProvider.family<List<Membership>, String>((ref, uid) {
  return ref.watch(orgRepositoryProvider).watchMyMemberships(uid);
});

/// The clubs one named person follows. The follow half of
/// [userMembershipsProvider], gated by the matching `followers` rule, and
/// present so a child's feed is assembled from the same two relationships a
/// grown-up's is rather than from a narrower guess.
final userFollowedOrgIdsProvider =
    StreamProvider.family<List<String>, String>((ref, uid) {
  return ref.watch(orgRepositoryProvider).watchMyFollowedOrgIds(uid);
});

/// Keeps `users/{uid}.orgIds` in step with the memberships that are the real
/// record of who belongs where.
///
/// Watch this from any screen a signed-in user reliably reaches — it returns
/// nothing and exists only for the write. `profileVisibility: community` is
/// the default for every account, and `firestore.rules` can only honour it by
/// checking the caller's membership against this mirror (rules cannot run a
/// query). A profile whose mirror is stale is a profile its club-mates cannot
/// open, so this runs wherever the memberships stream is already live rather
/// than only at the moment of joining — an approval that flips a membership to
/// `active` happens on somebody ELSE's device, and this user's profile has to
/// catch up on their next visit.
final profileOrgMirrorProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  final me = ref.watch(currentUserProvider).valueOrNull;
  final memberships = ref.watch(myMembershipsProvider).valueOrNull;
  if (uid == null || me == null || memberships == null) return;

  // Freshest first: the rule can only afford to look at the first few.
  final active = memberships.where((m) => m.isActive).toList()
    ..sort((a, b) {
      final at = a.joinedAt;
      final bt = b.joinedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  final wanted = [for (final m in active) m.orgId];

  if (wanted.length == me.orgIds.length) {
    var same = true;
    for (var i = 0; i < wanted.length; i++) {
      if (wanted[i] != me.orgIds[i]) {
        same = false;
        break;
      }
    }
    if (same) return;
  }

  // Not awaited and deliberately silent: this is housekeeping behind a screen
  // the user opened for another reason, and a failed mirror must never
  // surface as an error on it. The next visit tries again.
  ref.read(userRepositoryProvider).mirrorOrgIds(uid, wanted).ignore();
});

/// The same housekeeping for `users/{uid}.pendingOrgIds` — the clubs this
/// person is currently waiting on a decision from.
///
/// Separate from [profileOrgMirrorProvider] rather than folded into it because
/// the two lists move at different moments and for different reasons: the
/// active mirror changes when somebody is let IN, this one changes when they
/// apply and again when the application is decided. Folding them would mean
/// every approval rewrote both fields.
///
/// It is what lets the club's owner open an applicant's profile, and it is
/// also what stops them opening it afterwards — the rule re-checks that the
/// membership is still `pending`, and this prunes the entry once it is not, so
/// a declined applicant does not stay readable to the club that declined them.
final profilePendingMirrorProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  final me = ref.watch(currentUserProvider).valueOrNull;
  final memberships = ref.watch(myMembershipsProvider).valueOrNull;
  if (uid == null || me == null || memberships == null) return;

  final pending = memberships.where((m) => m.isPending).toList()
    ..sort((a, b) {
      final at = a.joinedAt;
      final bt = b.joinedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  final wanted = [for (final m in pending) m.orgId];

  if (_sameOrder(wanted, me.pendingOrgIds)) return;

  ref.read(userRepositoryProvider).mirrorPendingOrgIds(uid, wanted).ignore();
});

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Claims this person's player code if they do not have one yet.
///
/// Mounted on the app shell alongside [profileOrgMirrorProvider], for the same
/// reason: every account created before codes existed needs one, and there is
/// no server tier here to run a migration over the user collection. Doing it
/// on the first screen anybody opens means a code appears without the person
/// having to visit a settings page they have no reason to visit.
///
/// Runs at most once per account — `ensureCode` returns immediately when the
/// profile already carries one, and the profile stream delivers the new code
/// straight back, so the second build finds it set.
final playerCodeProvider = Provider<void>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return;
  if (me.playerCode != null && me.playerCode!.isNotEmpty) return;

  // Not awaited and deliberately silent, exactly like the org mirror above:
  // this is housekeeping behind a screen opened for another reason, and a
  // collision or a dropped connection must never surface as an error on it.
  ref.read(userRepositoryProvider).ensureCode(me).ignore();
});

/// Resolves a typed player code to the person who holds it.
///
/// A `FutureProvider.family` rather than a method call in the widget so a
/// repeated lookup of the same code — a captain adding four players and
/// re-checking one — is served from Riverpod's cache rather than re-read.
final playerByCodeProvider =
    FutureProvider.family<PlayerLookup?, String>((ref, code) {
  return ref.watch(userRepositoryProvider).findByPlayerCode(code);
});

final organizationProvider =
    StreamProvider.family<Organization?, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watch(orgId);
});

/// The caller's membership in one specific organization.
///
/// Every authority decision in the app reads from here. Roles are per-org by
/// definition — being an owner of your apartment club grants nothing at your
/// college — so there is deliberately no global "am I an admin" provider.
final myMembershipProvider =
    StreamProvider.family<Membership?, String>((ref, orgId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(orgRepositoryProvider).watchMembership(orgId, uid);
});

/// Capabilities the caller holds in an organization.
///
/// A pending or absent membership yields an empty set, so screens fail closed
/// while the membership is still loading rather than flashing admin controls.
final myCapabilitiesProvider =
    Provider.family<Set<Capability>, String>((ref, orgId) {
  final membership = ref.watch(myMembershipProvider(orgId)).valueOrNull;
  if (membership == null || !membership.isActive) return const {};
  // Rank AND portfolios. Reading the rank alone was correct only while every
  // capability came from the ladder; it would now hide the store from the
  // club's own treasurer.
  return membership.capabilities;
});

/// The departments the signed-in person runs in this club, rank-implied ones
/// included. Owners get the full set.
final myPortfoliosProvider =
    Provider.family<Set<ClubPortfolio>, String>((ref, orgId) {
  final membership = ref.watch(myMembershipProvider(orgId)).valueOrNull;
  if (membership == null || !membership.isActive) return const {};
  return membership.effectivePortfolios;
});

final orgMembersProvider =
    StreamProvider.family<List<Membership>, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watchMembers(orgId);
});

/// The club's owners, from the member rows rather than a denormalized list —
/// the role is what the security rules check, so it is what the UI must count.
/// Groups entering one competition together. See [GroupEntry].
final groupEntriesProvider =
    StreamProvider.family<List<GroupEntry>, CompRef>((ref, key) {
  return ref.watch(competitionRepositoryProvider).watchGroupEntries(
        orgId: key.orgId,
        compId: key.compId,
      );
});

/// Live cheer tally for one match. See [Cheer].
final cheersProvider =
    StreamProvider.family<CheerTally, FixtureRef>((ref, key) {
  return ref.watch(scoringServiceProvider).watchCheers(
        orgId: key.orgId,
        compId: key.compId,
        fixtureId: key.fixtureId,
        myUid: ref.watch(currentUidProvider),
      );
});

/// Every event on the platform open to outside entries. See
/// `GlobalEventsScreen`.
final globalEventsProvider = StreamProvider<List<Competition>>((ref) {
  return ref.watch(competitionRepositoryProvider).watchGlobalEvents();
});

final orgOwnersProvider =
    StreamProvider.family<List<Membership>, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watchOwners(orgId);
});

/// Open motions to remove an owner. See `OwnerVote`.
final ownerProposalsProvider =
    StreamProvider.family<List<OwnerProposal>, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watchOwnerProposals(orgId);
});

final pendingMembersProvider =
    StreamProvider.family<List<Membership>, String>((ref, orgId) {
  return ref
      .watch(orgRepositoryProvider)
      .watchMembers(orgId, status: MembershipStatus.pending);
});

final publicOrgsProvider = StreamProvider<List<Organization>>((ref) {
  return ref.watch(orgRepositoryProvider).watchPublicOrgs();
});

// ---------------------------------------------------------------------------
// Venues and tournaments
// ---------------------------------------------------------------------------

final tournamentRepositoryProvider =
    Provider((ref) => const TournamentRepository());

/// Every venue a club can play at. Watched rather than fetched because the
/// draw-setup sheet has to offer them the moment one is added.
final venuesProvider =
    StreamProvider.family<List<Venue>, String>((ref, orgId) {
  return ref.watch(tournamentRepositoryProvider).watchVenues(orgId);
});

final venueProvider =
    StreamProvider.family<Venue?, ({String orgId, String venueId})>(
        (ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchVenue(key.orgId, key.venueId);
});

final tournamentsProvider =
    StreamProvider.family<List<Tournament>, String>((ref, orgId) {
  return ref.watch(tournamentRepositoryProvider).watchTournaments(orgId);
});

final tournamentProvider = StreamProvider.family<Tournament?,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchTournament(key.orgId, key.tournamentId);
});

/// The draws belonging to one tournament.
final tournamentEventsProvider = StreamProvider.family<List<Competition>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchEvents(key.orgId, key.tournamentId);
});

/// Every entrant across every event in one season, and the event each one is
/// entered in.
///
/// Exists so a season-level schedule can answer "which of these are ours".
/// [Fixture.entrantAId] is a per-competition entrant document id, so the
/// question cannot be answered from fixtures alone, and matching on the
/// displayed name would light up a different club's "Team B".
///
/// A derived [Provider] rather than a stream of its own: it is the union of
/// streams that already exist and are already being watched by the same
/// screens, so this costs no extra reads. It resolves to an empty list while
/// the events are still loading, which is correct — nothing is highlighted
/// until we know what is ours, rather than the wrong things being.
final tournamentEntrantsProvider = Provider.family<List<Entrant>,
    ({String orgId, String tournamentId})>((ref, key) {
  final events = ref.watch(tournamentEventsProvider(key)).valueOrNull ?? const [];
  return [
    for (final e in events)
      ...ref.watch(entrantsProvider(CompRef(e.orgId, e.id))).valueOrNull ??
          const <Entrant>[],
  ];
});

/// This season's plan for each of its venues — days, sessions, blackouts,
/// match length, daily ceiling. Keyed by venue id; a venue with no entry has
/// no restrictions beyond the building's own hours.
final venuePlansProvider = StreamProvider.family<Map<String, VenuePlan>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchVenuePlans(key.orgId, key.tournamentId);
});

/// Whether the season fits in the venues it has been given, recomputed
/// whenever the plans, the events or the season itself change.
///
/// A future rather than a stream: it reads counts across every event, and a
/// live query per event would cost more than the answer is worth on a screen
/// the organizer opens deliberately.
final seasonCapacityProvider = FutureProvider.family<CapacityReport,
    ({String orgId, String tournamentId})>((ref, key) async {
  ref.watch(venuePlansProvider(key));
  ref.watch(tournamentProvider(key));
  ref.watch(tournamentEventsProvider(key));
  return ref.watch(tournamentRepositoryProvider).assessCapacity(
        orgId: key.orgId,
        tournamentId: key.tournamentId,
      );
});

/// What each venue offers this season, with the organizer's ceiling and the
/// arithmetic side by side.
final venueCapacityLinesProvider = FutureProvider.family<
    List<VenueCapacityLine>, ({String orgId, String tournamentId})>(
  (ref, key) async {
    ref.watch(venuePlansProvider(key));
    ref.watch(tournamentProvider(key));
    return ref.watch(tournamentRepositoryProvider).venueCapacityLines(
          orgId: key.orgId,
          tournamentId: key.tournamentId,
        );
  },
);

/// Whether the timetable as it currently stands keeps every promise.
///
/// Recomputed whenever a fixture moves or a venue plan changes, which is the
/// point: a schedule verified once at generation stops being verified the
/// moment anyone edits it.
final scheduleHealthProvider = FutureProvider.family<ScheduleHealthReport,
    ({String orgId, String tournamentId})>((ref, key) async {
  ref.watch(tournamentFixturesProvider(key));
  ref.watch(venuePlansProvider(key));
  ref.watch(tournamentProvider(key));
  return ref.watch(tournamentRepositoryProvider).checkScheduleHealth(
        orgId: key.orgId,
        tournamentId: key.tournamentId,
      );
});

/// The clubs this tournament has invited, and what each has said.
final tournamentInvitesProvider = StreamProvider.family<List<TournamentInvite>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref.watch(tournamentRepositoryProvider).watchInvitesForTournament(
        orgId: key.orgId,
        tournamentId: key.tournamentId,
      );
});

/// Tournaments other clubs have invited this one into, still unanswered.
final incomingTournamentInvitesProvider =
    StreamProvider.family<List<TournamentInvite>, String>((ref, orgId) {
  return ref.watch(tournamentRepositoryProvider).watchIncomingInvites(orgId);
});

/// Every tournament this club is part of by invitation — asked and not yet
/// answered, or answered yes.
///
/// Wider than [incomingTournamentInvitesProvider] on purpose: that one drives
/// "reply to this", so it stops at `pending`. This one drives "what is my
/// club in", where an accepted invitation is the strongest member there is.
final liveIncomingTournamentInvitesProvider =
    StreamProvider.family<List<TournamentInvite>, String>((ref, orgId) {
  return ref.watch(tournamentRepositoryProvider).watchLiveIncomingInvites(orgId);
});

/// What this profile may do at a season some OTHER club is running, on the
/// strength of an invitation to a club of theirs.
///
/// Null when there is no such invitation, which is the ordinary case and the
/// one every existing screen already handles: the season is either your own
/// club's or none of your business.
///
/// When it is not null, it carries the two facts the screens need and neither
/// of them can work out alone — WHICH of this profile's clubs was asked, and
/// whether this profile is the one who answers for it.
@immutable
class InvitedSeasonContext {
  const InvitedSeasonContext({
    required this.invite,
    required this.canEnterForClub,
  });

  final TournamentInvite invite;

  /// Whether this profile may enter the club into the host's draws.
  ///
  /// `manageCompetitions` at the INVITED club — its owner and admins. An
  /// invitation is addressed to a club, and the club's entry is a commitment
  /// made on behalf of everybody in it; the people who already carry that
  /// authority are the people who already run its competitions. Every other
  /// member gets [SeasonInterest] instead.
  final bool canEnterForClub;

  String get orgId => invite.toOrgId;
}

final invitedSeasonContextProvider = Provider.family<InvitedSeasonContext?,
    ({String hostOrgId, String tournamentId})>((ref, key) {
  // Derived here rather than read from `myActiveOrgIdsProvider`, which lives
  // in the home feature and imports this file — the club list is a core fact
  // and the dashboard's copy of it is the convenience, not the source.
  final memberships =
      ref.watch(myMembershipsProvider).valueOrNull ?? const <Membership>[];
  for (final membership in memberships) {
    if (!membership.isActive) continue;
    final orgId = membership.orgId;
    final invites =
        ref.watch(liveIncomingTournamentInvitesProvider(orgId)).valueOrNull ??
            const <TournamentInvite>[];
    for (final invite in invites) {
      if (invite.fromOrgId != key.hostOrgId) continue;
      if (invite.tournamentId != key.tournamentId) continue;
      return InvitedSeasonContext(
        invite: invite,
        canEnterForClub: ref
            .watch(myCapabilitiesProvider(orgId))
            .contains(Capability.manageCompetitions),
      );
    }
  }
  return null;
});

/// Who at one invited club has put their hand up for the host's season.
final seasonInterestProvider = StreamProvider.family<List<SeasonInterest>,
    ({String orgId, String hostOrgId, String tournamentId})>((ref, key) {
  return ref.watch(tournamentRepositoryProvider).watchSeasonInterest(
        orgId: key.orgId,
        hostOrgId: key.hostOrgId,
        tournamentId: key.tournamentId,
      );
});

/// Every match across every event of one tournament.
final tournamentFixturesProvider = StreamProvider.family<List<Fixture>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchFixtures(key.orgId, key.tournamentId);
});

/// The season owner's officiating panel — who has been pre-assigned to this
/// tournament, ahead of any fixture existing.
final tournamentOfficialsProvider = StreamProvider.family<
    List<TournamentOfficial>, ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchOfficials(key.orgId, key.tournamentId);
});

/// The derived high-level state of a tournament — progress, what is on court,
/// what is next, and who has won what.
final tournamentOverviewProvider = Provider.family<AsyncValue<TournamentOverview>,
    ({String orgId, String tournamentId})>((ref, key) {
  return combineAsync2(
    ref.watch(tournamentEventsProvider(key)),
    ref.watch(tournamentFixturesProvider(key)),
    (events, fixtures) =>
        TournamentOverview.from(events: events, fixtures: fixtures),
  );
});

/// Tournament-wide boards: who has had the best tournament, and how every
/// group is doing without opening fifteen events one at a time.
final tournamentLeaderboardProvider = Provider.family<
    AsyncValue<TournamentLeaderboard>,
    ({String orgId, String tournamentId})>((ref, key) {
  return combineAsync2(
    ref.watch(tournamentEventsProvider(key)),
    ref.watch(tournamentFixturesProvider(key)),
    (events, fixtures) =>
        TournamentLeaderboard.from(events: events, fixtures: fixtures),
  );
});

/// Per-player charts across a whole tournament — §17's Batting/Bowling/
/// Fielding boards, discovered from whatever counters the matches recorded.
///
/// Derived from the fixtures already streamed for the overview and the
/// leaderboard rather than a query of its own, so opening the charts costs
/// nothing beyond the computation.
final tournamentPlayerBoardsProvider = Provider.family<AsyncValue<PlayerBoards>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentFixturesProvider(key))
      .whenData(PlayerBoards.from);
});

/// The same charts, split per sport — §17's season view.
///
/// A multi-sport season is the shape this exists for: one set of charts across
/// five sports is a list nobody's sport is near the top of. Watches the same
/// fixture stream as [tournamentPlayerBoardsProvider], so a screen showing
/// both costs one query, not two.
final tournamentPlayerBoardsBySportProvider = Provider.family<
    AsyncValue<Map<String, PlayerBoards>>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref
      .watch(tournamentFixturesProvider(key))
      .whenData(PlayerBoards.bySport);
});

/// Protests raised against one fixture's result.
final disputesProvider = StreamProvider.family<List<Dispute>,
    ({String orgId, String compId, String fixtureId})>((ref, key) {
  return ref.watch(competitionRepositoryProvider).watchDisputes(
        orgId: key.orgId,
        compId: key.compId,
        fixtureId: key.fixtureId,
      );
});

/// Who a player has faced, and how they have done against each of them.
final headToHeadProvider =
    StreamProvider.family<List<HeadToHeadRecord>, String>((ref, uid) {
  return ref
      .watch(careerRepositoryProvider)
      .watchPlayerFixtures(uid)
      .map((fixtures) => HeadToHead.forPlayer(uid: uid, fixtures: fixtures));
});

/// The ranking list for one sport, summed over the rolling window.
final rankingProvider =
    StreamProvider.family<List<RankingRow>, String>((ref, sportId) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchRankingEntries(sportId: sportId)
      .map(buildRanking);
});

/// The clubs this person follows.
///
/// Empty rather than an error when signed out — a signed-out visitor follows
/// nothing, which is a fact, not a failure.
final myFollowedOrgIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(orgRepositoryProvider).watchMyFollowedOrgIds(uid);
});

/// Whether the signed-in person follows one particular club.
final isFollowingOrgProvider =
    StreamProvider.family<bool, String>((ref, orgId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(false);
  return ref.watch(orgRepositoryProvider).watchIsFollowing(orgId, uid);
});

/// One sport's club ladder, from the nightly inter-club rollup.
final clubStandingsProvider =
    StreamProvider.family<ClubStandings, String>((ref, sportId) {
  return ref.watch(tournamentRepositoryProvider).watchClubStandings(sportId);
});

/// Titles won at tournaments this club has run.
final clubHonoursProvider =
    StreamProvider.family<List<RankingEntry>, String>((ref, orgId) {
  return ref.watch(tournamentRepositoryProvider).watchClubHonours(orgId);
});

/// One player's ranking results, for their profile.
final playerRankingProvider =
    StreamProvider.family<List<RankingEntry>, String>((ref, uid) {
  return ref.watch(tournamentRepositoryProvider).watchPlayerRanking(uid);
});

// ---------------------------------------------------------------------------
// Lifelong profile — career, ratings, memories
// ---------------------------------------------------------------------------

final careerRepositoryProvider = Provider((ref) => const CareerRepository());
final memoryRepositoryProvider = Provider((ref) => const MemoryRepository());
final memoryComposerProvider = Provider((ref) => MemoryComposer());

/// Any user's public-facing profile document.
final userProfileProvider =
    StreamProvider.family<AppUser?, String>((ref, uid) {
  return ref.watch(userRepositoryProvider).watch(uid);
});

/// One person's travelling competitive standing, for a list that holds a uid
/// and nothing else.
///
/// ## Why this is a Future and [userProfileProvider] is a Stream
///
/// A tournament entry list can be a hundred and twenty-eight rows. Opening a
/// hundred and twenty-eight live document listeners to put a number beside a
/// hundred and twenty-eight names is not a trade worth making — the standing
/// is recomputed nightly and on match settlement, so it does not change while
/// somebody is looking at an entry list, and a snapshot read is the honest
/// shape for a value that does not move.
///
/// One read per unique uid, cached by Riverpod for as long as the screen is
/// mounted. Screens that ALREADY hold an [AppUser] — a profile, a team roster
/// — must read `user.glicko` directly instead of calling this: it is the same
/// number, and they have already paid for it.
final glickoBadgeProvider =
    FutureProvider.family<GlickoBadge?, String>((ref, uid) async {
  final user = await ref.watch(userRepositoryProvider).fetch(uid);
  return user?.glicko;
});

/// Every sport a player has a record in, most-played first.
final careerProvider =
    StreamProvider.family<List<CareerLine>, String>((ref, uid) {
  return ref.watch(careerRepositoryProvider).watchCareer(uid);
});

/// The Overall PlaySphere Glicko for one player, computed here rather than
/// read.
///
/// ## Why this one is computed on the client
///
/// `functions/overall_glicko.js` writes the same composite onto `users/{uid}`,
/// and every other screen in the app reads that copy — a roster holding forty
/// `AppUser`s gets forty standings for nothing. This provider exists for the
/// one screen where that copy is the wrong source: the career profile, which
/// has already loaded every rating document to draw the per-sport cards.
///
/// Deriving it from those documents buys two things the denormalised badge
/// cannot give. It is exact rather than nightly — a player who has just
/// finished a match sees the number that match produced, even in the seconds
/// before the trigger lands. And it carries the full breakdown, so the profile
/// can show what each sport contributed instead of asserting a figure. See
/// [OverallGlicko] for why a bare composite is not good enough.
///
/// Note the contrast with the Cross-Sport Index below, which genuinely cannot
/// be computed here: this needs only the player's OWN ratings, where a
/// percentile needs everybody's.
final overallGlickoProvider =
    Provider.family<AsyncValue<OverallGlicko?>, String>((ref, uid) {
  return ref.watch(careerProvider(uid)).whenData((lines) {
    return const OverallGlickoEngine().compute(
      entries: [
        for (final line in lines)
          if (line.ratingEvidence case final e?) e,
      ],
    );
  });
});

/// Every match a player has appeared in, newest first.
///
/// `watchPlayerFixtures` has existed since head-to-head shipped, but only
/// [headToHeadProvider] read it, and only to fold the matches into an
/// opponent tally — the matches themselves were never shown anywhere. This
/// exposes the same single query as a list, so the Matches destination has
/// something to be a destination for.
///
/// Sorted here rather than in the query: the collection-group read is capped
/// by `limit`, and ordering server-side would need a composite index per
/// field. The cap is a few hundred documents, so the client sorts them for
/// free.
final playerFixturesProvider =
    StreamProvider.family<List<Fixture>, String>((ref, uid) {
  return ref.watch(careerRepositoryProvider).watchPlayerFixtures(uid).map(
    (fixtures) {
      final sorted = [...fixtures];
      sorted.sort((a, b) {
        final at = a.completedAt ?? a.startedAt ?? a.scheduledAt;
        final bt = b.completedAt ?? b.startedAt ?? b.scheduledAt;
        // Matches with no date at all sink to the bottom rather than
        // scattering through the list at whatever order Firestore returned.
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return sorted;
    },
  );
});

/// Every match played under one club — the source `ClubRecord` builds a
/// club's record from. See `CareerRepository.watchOrgFixtures` for what a
/// private club's non-participant members will and will not see here.
final orgFixturesProvider =
    StreamProvider.family<List<Fixture>, String>((ref, orgId) {
  return ref.watch(careerRepositoryProvider).watchOrgFixtures(orgId).map(
    (fixtures) {
      final sorted = [...fixtures];
      sorted.sort((a, b) {
        final at = a.completedAt ?? a.startedAt ?? a.scheduledAt;
        final bt = b.completedAt ?? b.startedAt ?? b.scheduledAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return sorted;
    },
  );
});

/// One player's matches in a single sport.
///
/// Filters [playerFixturesProvider] rather than issuing its own query: a
/// second collection-group listener per sport would multiply reads by however
/// many sports a player has, to answer a question the first listener's data
/// already contains.
final playerSportFixturesProvider = Provider.family<AsyncValue<List<Fixture>>,
    ({String uid, String sportId})>((ref, key) {
  // A rating id is not always a sport id — chess is rated per time control
  // (`chess:blitz`, see §7.11) — so compare on the base sport.
  final base = key.sportId.split(':').first;
  return ref.watch(playerFixturesProvider(key.uid)).whenData(
        (fixtures) => [
          for (final f in fixtures)
            if (f.sport.split(':').first == base) f,
        ],
      );
});

/// One club's matches in a single sport — the [orgFixturesProvider]
/// counterpart to [playerSportFixturesProvider], filtered the same way and
/// for the same reason: reuse the one listener rather than open one per
/// sport.
final orgSportFixturesProvider = Provider.family<AsyncValue<List<Fixture>>,
    ({String orgId, String sportId})>((ref, key) {
  final base = key.sportId.split(':').first;
  return ref.watch(orgFixturesProvider(key.orgId)).whenData(
        (fixtures) => [
          for (final f in fixtures)
            if (f.sport.split(':').first == base) f,
        ],
      );
});

// NOTE — the Cross-Sport Index (§8.2) is deliberately NOT wired here.
//
// This is about the PERCENTILE index specifically, not about cross-sport
// standing in general: [overallGlickoProvider] above ships a cross-sport
// composite and is wired up. The two answer different questions. "How strong
// is this person" needs only their own ratings. "Where do they stand against
// everyone else" — the "top 8% in Hyderabad" line — needs the population, and
// that is what the rest of this note is about.
//
// `CrossSportIndex.compute` needs a `SportPopulation` per sport: every rated
// player's rating in that sport, to turn a raw Glicko number into a percentile.
// The client cannot obtain that. A `ratings` document is keyed by sport in its
// PATH and carries no `sportId` field to query a collectionGroup by, and
// reading every rating on the platform to compute a percentile is precisely the
// unbounded read pattern being removed elsewhere. (This note used to cite a
// `hasOnly` field check in `firestore.rules` as the reason; that check is gone —
// ratings became `write: if false` when settlement moved into `onMatchSettled`
// — but the conclusion is unchanged and rests on the path, not the rule.)
//
// Without a population, `percentileOf` returns 50 for everybody and the index
// collapses to a constant. Surfacing that as a headline "Sports OS Index" would
// be a fabricated number on a player's profile, which is worse than an absent
// one. It needs a scheduled aggregate (a per-sport rating histogram document)
// on the server tier — see the deferred Cloud Functions work. The engine and
// its tests are correct and stay ready for that.

/// Memories a player is tagged in, newest first.
///
/// The caller's own clubs are part of the query, not a post-filter: a
/// collection-group read is authorized against the constraints the query
/// carries, so the query has to state which audiences it is entitled to. A
/// signed-out spectator names none and sees public clubs' memories only.
/// Every memory from every match a club has played.
///
/// Distinct from [playerMemoriesProvider], which is a person's own timeline
/// across whatever clubs they have belonged to. This is the club's own album.
final clubFileRepositoryProvider =
    Provider<ClubFileRepository>((ref) => const ClubFileRepository());

/// Documents a club has shared with its members.
final clubFilesProvider =
    StreamProvider.family<List<ClubFile>, String>((ref, orgId) {
  return ref.watch(clubFileRepositoryProvider).watch(orgId);
});

final clubMemoriesProvider =
    StreamProvider.family<List<Memory>, String>((ref, orgId) {
  return ref.watch(memoryRepositoryProvider).watchClubMemories(orgId);
});

final playerMemoriesProvider =
    StreamProvider.family<List<Memory>, String>((ref, uid) {
  final mine = ref.watch(myMembershipsProvider).valueOrNull ?? const [];
  return ref.watch(memoryRepositoryProvider).watchPlayerMemories(
        uid,
        viewerOrgIds: [
          for (final m in mine)
            if (m.isActive) m.orgId,
        ],
      );
});

/// Memories attached to one match.
final fixtureMemoriesProvider =
    StreamProvider.family<List<Memory>, FixtureRef>((ref, key) {
  return ref.watch(memoryRepositoryProvider).watchFixtureMemories(
        orgId: key.orgId,
        compId: key.compId,
        fixtureId: key.fixtureId,
      );
});

/// Every memory from every match of one season — the book a season owner or
/// a player opens once it is done.
final tournamentMemoriesProvider = StreamProvider.family<List<Memory>,
    ({String orgId, String tournamentId})>((ref, key) {
  return ref.watch(memoryRepositoryProvider).watchTournamentMemories(
        orgId: key.orgId,
        tournamentId: key.tournamentId,
      );
});

// ---------------------------------------------------------------------------
// Inter-club challenges
// ---------------------------------------------------------------------------

/// Every challenge this org is party to, issued or received.
final challengesProvider =
    StreamProvider.family<List<Challenge>, String>((ref, orgId) {
  return ref.watch(communityRepositoryProvider).watchChallengesForOrg(orgId);
});

/// Challenges waiting on *this* org to answer.
///
/// Separated from the full list because it is the only subset that carries an
/// obligation, and it drives the badge on the navigation entry — an inbox that
/// does not announce itself is an inbox nobody opens.
final incomingChallengesProvider =
    Provider.family<AsyncValue<List<Challenge>>, String>((ref, orgId) {
  return ref.watch(challengesProvider(orgId)).whenData(
        (all) => all
            .where((c) => c.isIncomingFor(orgId) && c.isPending)
            .toList(growable: false),
      );
});

// ---------------------------------------------------------------------------
// Competitions
// ---------------------------------------------------------------------------

final competitionsProvider =
    StreamProvider.family<List<Competition>, String>((ref, orgId) {
  return ref.watch(competitionRepositoryProvider).watchCompetitions(orgId);
});

/// Identifies a document that lives under an organization. Used as a family
/// key so a screen can never accidentally read a competition from a different
/// tenant than the one in its URL.
class CompRef {
  const CompRef(this.orgId, this.compId);
  final String orgId;
  final String compId;

  @override
  bool operator ==(Object other) =>
      other is CompRef && other.orgId == orgId && other.compId == compId;

  @override
  int get hashCode => Object.hash(orgId, compId);
}

class FixtureRef {
  const FixtureRef(this.orgId, this.compId, this.fixtureId);
  final String orgId;
  final String compId;
  final String fixtureId;

  @override
  bool operator ==(Object other) =>
      other is FixtureRef &&
      other.orgId == orgId &&
      other.compId == compId &&
      other.fixtureId == fixtureId;

  @override
  int get hashCode => Object.hash(orgId, compId, fixtureId);
}

final competitionProvider =
    StreamProvider.family<Competition?, CompRef>((ref, key) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchCompetition(key.orgId, key.compId);
});

/// Every event one named person has entered themselves into, across every
/// club.
///
/// Powers the home screen's "Registered seasons" and "Registered tournaments"
/// buttons. A family rather than a single provider for the same reason
/// [userMembershipsProvider] is one: a guardian's home screen answers for
/// their children too, and switching into each profile to find out what the
/// household has entered is the trip that screen exists to save.
///
/// Only ever asked of the caller or one of their unclaimed wards — the
/// collection-group `registrations` rule refuses anybody else, which is the
/// correct answer.
final userEntriesProvider =
    StreamProvider.family<List<MyEntry>, String>((ref, uid) {
  return ref.watch(competitionRepositoryProvider).watchMyEntries(uid);
});

/// The other half of [userEntriesProvider]: events entered by a TEAM this
/// person was named in.
///
/// Separate because it is a separate query — a team's entry is one document
/// keyed by the team, and the players are in `memberUids` — and separate
/// providers let one fail without taking the other's results down. A player
/// whose club entered them in the league has entered the league, and a screen
/// that only counted entries they filed personally would tell them they are
/// in nothing.
final userTeamEntriesProvider =
    StreamProvider.family<List<MyEntry>, String>((ref, uid) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchMyEntries(uid, asTeamMember: true);
});

final registrationsProvider =
    StreamProvider.family<List<Registration>, CompRef>((ref, key) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchRegistrations(key.orgId, key.compId);
});

final entrantsProvider =
    StreamProvider.family<List<Entrant>, CompRef>((ref, key) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchEntrants(key.orgId, key.compId);
});

/// Every match in one competition, draft matches included only for whoever
/// may manage it.
///
/// The capability is read here rather than passed in by each screen because
/// it changes the query, not just the rendering: `firestore.rules` hides a
/// draft fixture from everyone else, and Firestore denies a list it cannot
/// authorize rather than trimming it. A screen that guessed would not show a
/// member too much — it would show them an error where their fixtures should
/// be.
final fixturesProvider =
    StreamProvider.family<List<Fixture>, CompRef>((ref, key) {
  final canManage = ref
      .watch(myCapabilitiesProvider(key.orgId))
      .contains(Capability.manageCompetitions);
  return ref
      .watch(competitionRepositoryProvider)
      .watchFixtures(key.orgId, key.compId, canManage: canManage);
});

final fixtureProvider =
    StreamProvider.family<Fixture?, FixtureRef>((ref, key) {
  return ref
      .watch(scoringServiceProvider)
      .watchFixture(key.orgId, key.compId, key.fixtureId);
});

/// Members who have put their hand up for either club's side of a match.
///
/// One listener for both sides: a challenge has exactly two squads and they
/// are shown together, so splitting this per side would double the reads to
/// render one card.
final squadEntriesProvider =
    StreamProvider.family<List<SquadEntry>, FixtureRef>((ref, key) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchSquadEntries(key.orgId, key.compId, key.fixtureId);
});

final matchEventsProvider =
    StreamProvider.family<List<MatchEvent>, FixtureRef>((ref, key) {
  return ref
      .watch(scoringServiceProvider)
      .watchEvents(key.orgId, key.compId, key.fixtureId);
});

/// The same log, deep enough to be replayed from the first point.
///
/// [matchEventsProvider]'s 60-event window is right for a feed that reads each
/// entry on its own — a cricket delivery says what it is without reference to
/// the one before it. It is wrong for an engine whose timeline REPLAYS the log
/// to derive running scores (see `RallyTimeline`): handed the last 60 points of
/// a 90-point match, a replay starts from 0-0 in the middle of the second game
/// and prints scores that disagree with the scoreboard directly above them.
///
/// 400 covers a five-set tennis match with corrections, which is the longest
/// log any replaying engine produces. Past that the timeline stops showing
/// running scores rather than showing wrong ones — see `RallyTimeline.timeline`.
final matchTimelineProvider =
    StreamProvider.family<List<MatchEvent>, FixtureRef>((ref, key) {
  return ref.watch(scoringServiceProvider).watchEvents(
        key.orgId,
        key.compId,
        key.fixtureId,
        limit: 400,
      );
});

/// This person's own "let me score this" request for one match, if any.
final myScoringRequestProvider =
    StreamProvider.family<ScoringRequest?, FixtureRef>((ref, key) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(competitionRepositoryProvider).watchMyScoringRequest(
        orgId: key.orgId,
        compId: key.compId,
        fixtureId: key.fixtureId,
        uid: uid,
      );
});

/// People waiting for this club to let them score something.
final pendingScoringRequestsProvider =
    StreamProvider.family<List<ScoringRequest>, String>((ref, orgId) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchPendingScoringRequests(orgId);
});

/// The league table, derived from the fixtures already being streamed.
///
/// Computed rather than stored: a standings row is a pure function of the
/// results behind it, so deriving it means the table can never disagree with
/// the matches it summarises, and it costs no extra reads.
///
/// Exposed as an [AsyncValue] rather than a bare list because a table computed
/// from a *partial* fixture set is not an empty table — it is a wrong one. If
/// the fixtures read is rejected, an organizer must see that, not a plausible
/// standing order built from whatever happened to load.
final standingsProvider =
    Provider.family<AsyncValue<List<Standing>>, CompRef>((ref, key) {
  return combineAsync3(
    ref.watch(competitionProvider(key)),
    ref.watch(entrantsProvider(key)),
    ref.watch(fixturesProvider(key)),
    (competition, entrants, fixtures) {
      if (competition == null) return const <Standing>[];
      return const StandingsCalculator().compute(
        competition: competition,
        entrants: entrants,
        fixtures: fixtures,
      );
    },
  );
});

/// One table per group, for a groups+knockout draw.
///
/// Separate from [standingsProvider] rather than replacing it because the two
/// answer different questions: a league has one table, a groups draw has
/// several and a single merged one is meaningless — Group A's players have
/// never met Group B's, so their points are not comparable.
final groupStandingsProvider =
    Provider.family<AsyncValue<Map<String, List<Standing>>>, CompRef>(
        (ref, key) {
  return combineAsync3(
    ref.watch(competitionProvider(key)),
    ref.watch(entrantsProvider(key)),
    ref.watch(fixturesProvider(key)),
    (competition, entrants, fixtures) {
      if (competition == null) return const <String, List<Standing>>{};
      return const StandingsCalculator().computeGroups(
        competition: competition,
        entrants: entrants,
        fixtures: fixtures,
      );
    },
  );
});

/// Everything currently being played in an organization — the screen a remote
/// spectator opens first.
///
/// The underlying query asks Firestore for `status == live`, which is the
/// most it can do: Firestore cannot express "and the scoreboard moved
/// recently". A fixture enters `live` on its first ball and only leaves on the
/// event that completes it, so every match a scorer walked away from stays in
/// that query forever — which is why this list was showing matches that had
/// finished days earlier. The activity filter is applied here, once, so every
/// screen reading live matches gets the same honest answer.
final liveFixturesProvider =
    StreamProvider.family<List<Fixture>, String>((ref, orgId) {
  return ref.watch(competitionRepositoryProvider).watchLiveFixtures(orgId).map(
        (fixtures) => [
          for (final f in fixtures)
            if (f.isLiveAt(DateTime.now())) f,
        ],
      );
});

/// Matches an organization left mid-scoreboard: still `live` on paper, quiet
/// long enough that nobody would call them live.
///
/// Kept separate from [liveFixturesProvider] rather than merged into it,
/// because these need the opposite treatment — hidden from spectators, but
/// surfaced to organizers, who are the only people who can close them out.
final staleLiveFixturesProvider =
    StreamProvider.family<List<Fixture>, String>((ref, orgId) {
  return ref.watch(competitionRepositoryProvider).watchLiveFixtures(orgId).map(
        (fixtures) => [
          for (final f in fixtures)
            if (f.isStaleLiveAt(DateTime.now())) f,
        ],
      );
});

/// Matches the signed-in user has been assigned to score.
final myScoringAssignmentsProvider =
    StreamProvider<List<Fixture>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(competitionRepositoryProvider)
      .watchMyScoringAssignments(uid);
});
