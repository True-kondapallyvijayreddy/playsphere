

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/arena/arena_board_screen.dart';
import '../../features/arena/arena_challenge_screen.dart';
import '../../features/arena/arena_home_screen.dart';
import '../../features/arena/arena_leaderboard_screen.dart';
import '../../features/venues/venues_screen.dart';
import '../../features/rankings/rankings_screen.dart';
import '../../features/tournaments/certificates_screen.dart';
import '../../features/tournaments/tournament_schedule_screen.dart';
import '../../features/tournaments/officials_screen.dart';
import '../../features/tournaments/venue_planner_screen.dart';
import '../../features/tournaments/season_entrant_screen.dart';
import '../../features/tournaments/season_memory_book_screen.dart';
import '../../features/tournaments/public_tournament_screen.dart';
import '../../features/tournaments/tournaments_screen.dart';
import '../../features/tournaments/tournament_detail_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/family/add_child_screen.dart';
import '../../features/family/claim_code_screen.dart';
import '../../features/family/claim_entry_screen.dart';
import '../../features/family/managed_children_screen.dart';
import '../../features/community/looking_for_board_screen.dart';
import '../../features/network/club_network_screen.dart';
import '../../features/network/club_thread_screen.dart';
import '../../features/community/match_rsvp_screen.dart';
import '../../features/competitions/global_events_screen.dart';
import '../../features/competitions/challenges_screen.dart';
import '../../features/competitions/competition_detail_screen.dart';
import '../../features/competitions/choose_event_type_screen.dart';
import '../../features/competitions/create_competition_screen.dart';
import '../../features/competitions/guided_tournament_screen.dart';
import '../../features/competitions/guided_season_screen.dart';
import '../../features/competitions/create_season_screen.dart';
import '../../features/competitions/entrant_detail_screen.dart';
import '../../features/competitions/my_events_screen.dart';
import '../../features/auctions/auction_create_screen.dart';
import '../../features/auctions/auction_detail_screen.dart';
import '../../features/auctions/auction_lot_screen.dart';
import '../../features/auctions/auction_people_screen.dart';
import '../../features/auctions/auction_settings_screen.dart';
import '../../features/auctions/auction_team_screen.dart';
import '../../features/auctions/auction_trades_screen.dart';
import '../../features/auctions/auctions_home_screen.dart';
import '../../features/give/give_collection_centers_screen.dart';
import '../../features/give/give_donate_screen.dart';
import '../../features/give/give_home_screen.dart';
import '../../features/give/give_impact_screen.dart';
import '../../features/give/give_my_donations_screen.dart';
import '../../features/give/give_needs_screen.dart';
import '../../features/give/give_raise_need_screen.dart';
import '../../features/grounds/grounds_screen.dart';
import '../../features/grounds/ground_review_screen.dart';
import '../../features/grounds/my_grounds_screen.dart';
import '../../features/home/active_seasons_screen.dart';
import '../../features/home/open_registrations.dart';
import '../../features/home/home_screen.dart';
import '../../features/more/more_menu_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/officials/officials_directory_screen.dart';
import '../../features/ops/ops_home_screen.dart';
import '../../features/ops/ops_team_screen.dart';
import '../../features/sponsor/sponsor_home_screen.dart';
import '../../features/sponsor/sponsor_browse_screen.dart';
import '../../features/sponsor/sponsor_create_listing_screen.dart';
import '../../features/sponsor/sponsor_my_listings_screen.dart';
import '../../features/sponsor/sponsor_my_pledges_screen.dart';
import '../../features/sponsor/sponsor_listing_detail_screen.dart';
import '../../features/sponsor/sponsor_incoming_offers_screen.dart';
import '../../features/scout/rising_talent_screen.dart';
import '../../features/ads/ad_review_screen.dart';
import '../../features/coaches/coach_detail_screen.dart';
import '../../features/coaches/coach_profile_edit_screen.dart';
import '../../features/coaches/coaches_screen.dart';
import '../../features/give/give_ops_screen.dart';
import '../../features/medical/sports_emergency_screen.dart';
import '../../features/medical/sports_injuries_screen.dart';
import '../../features/medical/sports_medic_detail_screen.dart';
import '../../features/medical/sports_medic_registration_screen.dart';
import '../../features/medical/sports_medicine_screen.dart';
import '../../features/medical/sports_medics_directory_screen.dart';
import '../../features/medical/sports_warmups_screen.dart';
import '../../features/sports/sport_hub_screen.dart';
import '../../features/sports/sports_directory_screen.dart';
import '../../features/scout/scout_search_screen.dart';
import '../../features/ads/ad_console_screen.dart';
import '../../features/gov/gov_dashboard_screen.dart';
import '../../features/grounds/ground_detail_screen.dart';
import '../../features/grounds/ground_food_screen.dart';
import '../../features/grounds/ground_food_manage_screen.dart';
import '../../features/grounds/ground_food_orders_screen.dart';
import '../../features/grounds/my_food_orders_screen.dart';
import '../../features/shop/club_store_screen.dart';
import '../../features/shop/club_store_manage_screen.dart';
import '../../features/shop/club_store_orders_screen.dart';
import '../../features/shop/my_club_orders_screen.dart';
import '../../features/orgs/club_files_screen.dart';
import '../../features/orgs/club_gallery_screen.dart';
import '../../features/orgs/create_org_screen.dart';
import '../../features/orgs/join_org_screen.dart';
import '../../features/orgs/club_events_screen.dart';
import '../../features/orgs/club_settings_screen.dart';
import '../../features/orgs/club_staff_screen.dart';
import '../../features/orgs/club_sport_stats_screen.dart';
import '../../features/orgs/club_stats_screen.dart';
import '../../features/orgs/members_screen.dart';
import '../../features/orgs/org_home_screen.dart';
import '../../features/orgs/org_picker_screen.dart';
import '../../features/orgs/umpire_registry_screen.dart';
import '../../features/premium/premium_screen.dart';
import '../../features/shop/shop_screen.dart';
import '../../features/shops/sports_shop_detail_screen.dart';
import '../../features/shops/sports_shop_registration_screen.dart';
import '../../features/shops/sports_shops_screen.dart';
import '../../features/discover/discover_screen.dart';
import '../../features/discover/player_listing_edit_screen.dart';
import '../../features/profile/career_profile_screen.dart';
import '../../features/profile/leaderboard_screen.dart';
import '../../features/profile/my_matches_screen.dart';
import '../../features/profile/my_sports_screen.dart';
import '../../features/profile/player_clubs_screen.dart';
import '../../features/profile/player_sport_screen.dart';
import '../../features/profile/player_stats_screen.dart';
import '../../features/rules/sport_rules_screen.dart';
import '../../features/teams/create_team_screen.dart';
import '../../features/teams/create_standalone_team_screen.dart';
import '../../features/teams/my_teams_screen.dart';
import '../../features/teams/standalone_teams_screen.dart';
import '../../features/teams/team_detail_screen.dart';
import '../../features/scoring/live_matches_screen.dart';
import '../../features/scoring/live_now_screen.dart';
import '../../features/competitions/quick_tournament_screen.dart';
import '../../features/scoring/quick_match_screen.dart';
import '../../features/scoring/match_center_screen.dart';
import '../../features/scoring/match_result_screen.dart';
import '../../features/scoring/scoring_screen.dart';
import '../../features/scoring/spectator_screen.dart';
import '../../domain/club_events.dart';
import '../models/club_thread.dart';
import '../models/app_user.dart';
import '../providers.dart';

class Routes {
  const Routes._();

  static const signIn = '/sign-in';
  static const profileSetup = '/welcome';

  /// Where a signed-in member lands: their clubs, their live matches and
  /// whatever is waiting on them, across every club at once.
  static const home = '/home';

  /// The Arena: board games between members. Org-free, because a game
  /// belongs to the two people playing it and not to a club — see
  /// `Refs.arenaMatches`.
  static const arena = '/arena';

  /// The Arena's own ladder. Deliberately not under `/rankings`, which is
  /// where the numbers that mean something live.
  static const arenaLadder = '/arena/ladder';

  /// Picking an opponent for one game.
  static String arenaChallenge(String gameId) => '/arena/new/$gameId';

  /// One game's board.
  static String arenaBoard(String matchId) => '/arena/game/$matchId';

  static const orgs = '/orgs';
  static const rules = '/rules';
  static const more = '/more';

  /// Every open event on the platform. Deliberately org-free: discovering a
  /// tournament is the one journey that must not start inside a club.
  static const globalEvents = '/events';
  static const notifications = '/notifications';

  /// Every live match across every club this person belongs to, in one place.
  ///
  /// Deliberately org-free, unlike [live]: a member in four clubs has four
  /// separate per-club live pages and no single one of them was ever "what is
  /// live for me right now" — this is what the home screen's "More" button
  /// opens once there are more matches live than fit in the preview.
  static const liveNow = '/live';

  /// Every event and tournament across every club this person belongs to.
  ///
  /// Deliberately org-free, same reasoning as [liveNow]: this is what the
  /// home screen's "More" button opens once there are more open-for-entry
  /// events than fit in its five-item preview.
  static const myEvents = '/events/mine';

  /// The two lists behind the home screen's "Active seasons & tournaments"
  /// buttons: everything this household can actually enter today, split the
  /// way the buttons split it.
  ///
  /// Both are distinct from [myEvents], which is every event across the clubs
  /// the profile in use belongs to, in whatever state it is in. These two are
  /// only the ones open for entry, and they answer for the whole household —
  /// see `ActiveSeasonsScreen`.
  static const openSeasons = '/seasons/open';
  static const openTournaments = '/tournaments/open';

  /// The same two, for what this household has already entered rather than
  /// what it still could.
  static const registeredSeasons = '/seasons/registered';
  static const registeredTournaments = '/tournaments/registered';

  /// The list one of the four home tiles opens.
  ///
  /// A function of the tile rather than four constants read at four call
  /// sites, so a tile cannot be given a destination that does not match what
  /// it says — and so a third kind or a third lens fails to compile here
  /// instead of silently sending people to the wrong list.
  static String entryList(EntryListKey key) => switch ((key.lens, key.kind)) {
        (RegistrationLens.open, OpenRegistrationKind.season) => openSeasons,
        (RegistrationLens.open, OpenRegistrationKind.tournament) =>
          openTournaments,
        (RegistrationLens.registered, OpenRegistrationKind.season) =>
          registeredSeasons,
        (RegistrationLens.registered, OpenRegistrationKind.tournament) =>
          registeredTournaments,
      };
  static const createOrg = '/orgs/new';
  static const joinOrg = '/orgs/join';

  /// A join link that carries the code, so an invite can be a tap rather than
  /// six characters copied out of a WhatsApp message and typed in wrong.
  ///
  /// The screen it opens still shows the code and still asks the person to
  /// confirm which club they are joining — the link fills the box, it does not
  /// join anything on its own.
  static String joinWithCode(String code) =>
      '$joinOrg?code=${Uri.encodeComponent(code)}';

  /// The absolute link to put in a message, a poster or a QR code.
  static String inviteUrl(String code) => '$publicOrigin${joinWithCode(code)}';
  static const lookingFor = '/community/looking-for';

  /// The officials directory — who has registered to umpire, and how to reach
  /// them.
  ///
  /// This path used to point at the registration form, which meant the
  /// registry had a way in and no way to look at it: an official could
  /// describe themselves and then be found by nobody. The form kept the path
  /// and the directory did not exist. Now the directory owns the front door
  /// and [umpireRegister] is the form, matching how [coaches]/[myCoachProfile]
  /// and [sportsMedics]/[mySportsMedicProfile] already split the same pair.
  static const umpireRegistry = '/community/officials';

  /// Same starting-filter query parameter as [coachesIn] and
  /// [sportsMedicsIn], for the same reason: the sport narrows the list, it is
  /// not the identity of the screen.
  static String officialsIn(String sportId) =>
      '$umpireRegistry?sport=${Uri.encodeComponent(sportId)}';

  /// Registering as an official, or editing the listing you already have.
  /// Declared as a child path of the directory so the back gesture returns to
  /// the list somebody was looking at.
  static const umpireRegister = '/community/officials/register';

  static String venues(String orgId) => '/org/$orgId/venues';

  static String tournaments(String orgId) => '/org/$orgId/tournaments';

  static String rankings(String orgId) => '/org/$orgId/rankings';

  static String tournament(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId';

  static String certificates(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/certificates';

  static String tournamentSchedule(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/schedule';

  static String tournamentOfficials(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/officials';

  /// Where the organizer describes when each ground is actually available —
  /// dates, sessions, blackouts, match length, daily ceiling.
  static String venuePlanner(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/venues';

  static String seasonMemories(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/memories';

  /// One team or player within one season. Deliberately under the season
  /// rather than under an event: a team entered in three draws of a season is
  /// one team, and [entrant] — which is per-competition — makes it three.
  static String seasonEntrant(
    String orgId,
    String tournamentId,
    String entrantId,
  ) =>
      '/org/$orgId/tournaments/$tournamentId/entrant/$entrantId';

  static const myProfile = '/me';
  static String profile(String uid) => '/player/$uid';

  /// A guardian's list of children they manage, and the entry point for
  /// adding one.
  static const myChildren = '/children';
  static const addChild = '/children/new';
  static String claimCodeFor(String childUid) => '/children/$childUid/claim';

  /// Where a child without their own login yet redeems the code their
  /// guardian generated. Deliberately public — see [_isPublicRoute] — there
  /// is no Firebase Auth session at all until this screen's flow creates
  /// one.
  static const claim = '/claim';

  /// What a player can buy for themselves. Deliberately org-free — Premium is
  /// bought by a person and travels with them between clubs, exactly like the
  /// career record it deepens.
  static const premium = '/premium';

  /// Sports kit, from a vendor. Org-free for the same reason as [premium]:
  /// a player buying a racket is buying it as themselves.
  static const shop = '/shop';

  /// The local sports-shop directory — real shops on real streets, not the
  /// [shop] catalogue and not a club's own store. See `SportsShop`.
  ///
  /// `/sports-shops` rather than `/shops`, which would sit one character away
  /// from [shop] and be the kind of near-collision nobody notices until a
  /// deep link goes to the wrong screen.
  static const sportsShops = '/sports-shops';

  /// Same starting-filter query parameter as [coachesIn] and
  /// [sportsMedicsIn], for the same reason.
  static String sportsShopsIn(String sportId) =>
      '$sportsShops?sport=${Uri.encodeComponent(sportId)}';

  /// One shop's page. Keyed by uid, because the listing is.
  static String sportsShop(String uid) => '$sportsShops/$uid';

  /// The form behind "do you run a shop?" — creating a listing and editing
  /// one are the same screen, under `/me` for the same reason
  /// [myCoachProfile] is.
  static const mySportsShop = '/me/shop';

  /// A buyer's own club-store orders, across every club — org-free like
  /// [shop], since an order belongs to the person who placed it.
  static const myClubOrders = '/me/club-orders';

  /// The Give network hub — "Give a Kit. Build a Player." Org-free, same
  /// reasoning as [shop]: a donor gives as themselves, and a club's own
  /// needs are managed from its own dashboard, not from here.
  static const give = '/give';
  static const giveDonate = '/give/donate';
  static const giveMyDonations = '/give/mine';
  static const giveCollectionCenters = '/give/centers';
  static const giveNeeds = '/give/needs';
  static const giveRaiseNeed = '/give/needs/raise';
  static const giveImpact = '/give/impact';

  /// Player auctions. Org-free like [give] and [shop], and for a stronger
  /// reason than either: an auction is called by whoever is running the
  /// tournament, who may belong to no club at all. See
  /// lib/core/models/auction.dart.
  ///
  /// `auctionCreate` is declared before the `:auctionId` routes for the same
  /// reason `giveDonate` is declared before `give` — go_router matches in
  /// order, and `/auctions/new` would otherwise be read as an auction whose
  /// id is "new".
  static const auctions = '/auctions';
  static const auctionCreate = '/auctions/new';

  static String auction(String auctionId) => '/auctions/$auctionId';

  static String auctionPeople(String auctionId) =>
      '/auctions/$auctionId/people';

  static String auctionSettings(String auctionId) =>
      '/auctions/$auctionId/settings';

  static String auctionTrades(String auctionId) =>
      '/auctions/$auctionId/trades';

  /// One player on the block. `lotId` is the player's uid — see `AuctionLot`.
  static String auctionLot(String auctionId, String lotId) =>
      '/auctions/$auctionId/player/$lotId';

  /// One side. `teamId` is the owner's uid — see `AuctionTeam`.
  static String auctionTeam(String auctionId, String teamId) =>
      '/auctions/$auctionId/side/$teamId';

  /// Sponsor an Athlete / Sponsor a Team. Org-free like [give] — a sponsor
  /// acts as themselves, and a listing's owner (athlete, guardian, or team
  /// admin) manages it from here rather than from the club dashboard,
  /// because a listing outlives any one club membership.
  static const sponsor = '/sponsor';
  static const sponsorBrowse = '/sponsor/browse';
  static const sponsorCreate = '/sponsor/create';
  static const sponsorMine = '/sponsor/mine';
  static const sponsorMyPledges = '/sponsor/mine/pledges';
  static String sponsorListing(String listingId) => '/sponsor/listings/$listingId';
  static String sponsorOffers(String listingId) =>
      '/sponsor/listings/$listingId/offers';

  /// Finding clubs and people you have no connection to yet — the answer for
  /// somebody who has just moved and has nobody to get an invite code from.
  ///
  /// Deliberately NOT under `/scout`. Talent discovery is a scout looking down
  /// at a pool of players; this is a player looking outward for somewhere to
  /// play, and the two only look similar from the database's side.
  static const discover = '/discover';

  /// The same screen opened on the people tab. A query parameter, like
  /// [scoutSearchIn], because the tab is a starting position rather than the
  /// identity of the page.
  static const discoverPeople = '$discover?tab=people';

  /// The club owners' network — a club owner's inbox, and the directory of
  /// other clubs to open a conversation with.
  ///
  /// Under `/network` rather than inside `/org/:orgId/...` even though a
  /// thread belongs to a club. An owner who runs three clubs has ONE inbox,
  /// and hanging it off a club id would either split it three ways or make
  /// the id in the URL a lie about which club the person is reading as. The
  /// club being acted as is a choice on the screen — see
  /// `actingClubIdProvider` — not part of the address.
  static const clubNetwork = '/network';

  /// The same screen opened on the directory tab. A query parameter, like
  /// [discoverPeople]: the tab is a starting position, not the page.
  static const clubNetworkFind = '$clubNetwork?tab=find';

  /// One conversation. The id is the derived pair — see [ClubThread.idFor] —
  /// so a link to a thread is stable and a club cannot be sent to somebody
  /// else's.
  static String clubThread(String threadId) => '$clubNetwork/t/$threadId';

  /// The conversation with one named club, which is what "Message this club"
  /// resolves to once the acting club is known. Takes both ids rather than a
  /// thread id so the caller does not have to know how the pair is derived.
  static String clubThreadWith(String myOrgId, String otherOrgId) =>
      clubThread(ClubThread.idFor(myOrgId, otherOrgId));

  /// This account's own directory listing — the opt-in half of [discover].
  static const myPlayerListing = '/me/listing';

  /// Talent discovery — §6 Module C. Org-free and role-free: nothing gates
  /// who may open a search, because the real gate (a minor's consent) is
  /// enforced per-profile by `firestore.rules`, not by who is allowed to ask.
  static const scoutSearch = '/scout/search';

  /// The same search with a sport already picked — what a sport hub's "Find
  /// players" opens. A query parameter rather than a path segment because the
  /// sport is a starting filter the person can change on the screen, not the
  /// identity of the page: `/scout/search` and `/scout/search?sport=cricket`
  /// are the same screen, and back from either lands in the same place.
  static String scoutSearchIn(String sportId) =>
      '$scoutSearch?sport=${Uri.encodeComponent(sportId)}';

  /// The coach directory — everyone who has listed themselves as teaching a
  /// sport. Public and sign-in free, like the ground and sponsorship
  /// directories: a parent looking for a coach has usually not made an
  /// account yet, and asking them to before they can even look is how a
  /// directory stays empty.
  static const coaches = '/coaches';

  /// The same directory with a sport already picked — what a sport hub's
  /// "All coaches" opens. A query parameter for the same reason
  /// [scoutSearchIn] uses one: the sport is a starting filter, not the
  /// identity of the page.
  static String coachesIn(String sportId) =>
      '$coaches?sport=${Uri.encodeComponent(sportId)}';

  /// One coach's page. Keyed by uid, because the listing is.
  static String coach(String uid) => '$coaches/$uid';

  /// The form behind "do you coach?" — creating a listing and editing one are
  /// the same screen. Under `/me` rather than `/coaches/mine` so it sorts
  /// with the other things that are about the signed-in person.
  static const myCoachProfile = '/me/coach';

  /// The Sports Medicine & Performance hub — practitioners, warm-ups,
  /// injuries and on-field emergencies.
  ///
  /// Org-free, like [give] and [shop]. An injury belongs to a person, not to
  /// whichever of their clubs they happened to have selected, and making
  /// somebody pick a club before they can read what to do about a concussion
  /// would be the worst possible place to ask that question.
  static const sportsMedicine = '/medical';

  /// The practitioner directory. Public and sign-in free, like [coaches]: a
  /// parent looking for a physiotherapist for their daughter has usually not
  /// made an account, and requiring one before they can look is how a
  /// directory stays empty.
  static const sportsMedics = '$sportsMedicine/find';

  /// The directory with a sport already applied — what an injury page's
  /// "find a physio" opens. A query parameter for the same reason
  /// [coachesIn] uses one: the sport is a starting filter, not the identity
  /// of the page.
  static String sportsMedicsIn(String sportId) =>
      '$sportsMedics?sport=${Uri.encodeComponent(sportId)}';

  /// One practitioner's page. Keyed by uid, because the listing is.
  static String sportsMedic(String uid) => '$sportsMedics/$uid';

  /// The curated reference. All three read from the `const` library that
  /// ships with the app, so they open on a ground with no signal.
  static const sportsWarmups = '$sportsMedicine/warmups';
  static String sportsWarmupsFor(String sportId) =>
      '$sportsWarmups?sport=${Uri.encodeComponent(sportId)}';
  static const sportsInjuries = '$sportsMedicine/injuries';
  static String sportsInjuriesFor(String sportId) =>
      '$sportsInjuries?sport=${Uri.encodeComponent(sportId)}';
  static const sportsEmergency = '$sportsMedicine/emergency';

  /// The form behind "are you a doctor or physiotherapist?". Under `/me`
  /// for the same reason [myCoachProfile] is.
  static const mySportsMedicProfile = '/me/sports-medic';

  /// Talent discovery's other half — the precomputed "who is improving"
  /// boards rather than a "who is good" search. Also role-free: the boards
  /// that include minors are a different set of documents, gated on the
  /// `scout` claim in `firestore.rules` rather than on reaching this route.
  static const risingTalent = '/scout/rising';

  /// The sport directory — every sport the platform runs, with how much is
  /// happening in each.
  ///
  /// Distinct from [mySports], which is the sports *this person* plays. The
  /// two were easy to conflate and answer opposite questions: one is "where
  /// do I stand", the other is "what is worth entering". Org-free for the
  /// same reason as [globalEvents] — discovering a sport must not require
  /// already being in a club that plays it.
  static const sports = '/sports';

  /// One sport's whole ecosystem — live matches, the clubs running it, the
  /// grounds that have a pitch for it, the events open for entry.
  ///
  /// The nine sport tiles on the home screen used to build this id and then
  /// discard it, pushing every one of them to the directory above. See
  /// `SportHubScreen`.
  static String sport(String sportId) => '/sports/$sportId';

  /// Every match availability call across this person's clubs. Reached from
  /// the RSVP counter on home, which is the only trace of it there.
  static const matchRsvps = '/rsvp';

  /// The advertiser self-serve console. Org-free — an advertiser is a
  /// business acting for itself, not a club.
  static const adConsole = '/ads';

  /// Restricted to the `admin` custom claim — see `GovDashboardScreen`. A
  /// route, not a sub-route of anything, because it belongs to no club and
  /// no sport: it is PlaySphere talking to a district or state, not to a
  /// player.
  static const govDashboard = '/gov';

  // --- Operations ---------------------------------------------------------
  //
  // Every inbound queue in the product used to land in a `pending` document
  // that no screen could read, so the answer to "who receives this?" was
  // nobody. These are the destinations; see `OpsHomeScreen`. All four are
  // gated on the `admin` claim by `firestore.rules`, and the screens check it
  // only so they do not present a queue they cannot load.

  /// The staff control room — every queue and its backlog in one place.
  static const ops = '/ops';

  /// Advertiser campaigns awaiting a decision.
  static const opsAds = '/ops/ads';

  /// The Give desk. Two deep links rather than one screen with remembered
  /// state: verifying needs and moving donations are separate jobs, often
  /// done by different people, and arriving on the wrong one is a wasted tap
  /// every time.
  static const opsGive = '/ops/give';
  static const opsGiveNeeds = '/ops/give/needs';

  /// Who on the team is notified when something lands — see `StaffMember`.
  static const opsTeam = '/ops/team';

  /// Grounds available to hire, searchable by city, sport and time.
  ///
  /// Deliberately org-free and deliberately not under `/org/:id/venues`. A
  /// venue is a club's own hall; a ground is a business somebody else owns
  /// and rents to anybody — see `Refs.grounds`.
  static const grounds = '/grounds';

  /// The other side of the same marketplace: what a ground owner manages.
  static const myGrounds = '/grounds/mine';

  /// PlaySphere staff reviewing listings and acting on reports. Declared
  /// before the `:groundId` route for the same reason [myGrounds] is — go_router
  /// matches in declaration order and `review` would otherwise be read as an id.
  static const groundReview = '/grounds/review';

  static String ground(String groundId) => '/grounds/$groundId';

  /// A buyer's own food orders, across every ground — org-free, same
  /// reasoning as [myClubOrders].
  static const myFoodOrders = '/me/food-orders';

  /// Every match this player has appeared in. A destination of its own, not
  /// an anchor on the profile: "Matches" and "Sports" both used to push
  /// `/me`, so the two counters on the home screen led to the same page and
  /// neither answered the question its label asked.
  static const myMatches = '/me/matches';

  /// The sports this player has a record in, each opening its own page.
  static const mySports = '/me/sports';

  /// Every active squad the signed-in person is on — see [MyTeamsScreen].
  static const myTeams = '/me/teams';

  /// One team's roster, live — see [TeamDetailScreen].
  static String team(String teamId) => '/teams/$teamId';

  /// Teams with no club behind them — where you make one, find one, or join
  /// one by code.
  ///
  /// Not under `/org/...`, unlike [createTeam], and that is the whole point:
  /// a path with an org segment makes the club compulsory no matter how
  /// nullable the field is. See `StandaloneTeamsScreen`.
  static const standaloneTeams = '/teams';

  static const createStandaloneTeam = '/teams/new';

  /// One player's record in one sport, sliced by where the matches came from
  /// — `docs/Heart_of_the_playsphere.md` §18. [highlight], when given, is a
  /// tally key (e.g. `runs`) to land on already picked out — the profile's
  /// per-sport counter tiles link here per-stat rather than just per-sport.
  static String playerStats(String uid, String sportId, {String? highlight}) {
    final path = '/player/$uid/stats/${Uri.encodeComponent(sportId)}';
    return highlight == null
        ? path
        : '$path?highlight=${Uri.encodeComponent(highlight)}';
  }

  /// One sport within a player's career — their matches in it, the
  /// scorecards, and where they sit in the ranking.
  static String playerSport(String uid, String sportId) =>
      '/player/$uid/sport/${Uri.encodeComponent(sportId)}';

  /// Every match a player (not just the signed-in one) has appeared in —
  /// the profile's "Matches" counter needed a real destination, and
  /// [MyMatchesScreen] already takes any uid, so this just reaches it with
  /// one in the URL instead of always resolving to the current user.
  static String playerMatches(String uid) => '/player/$uid/matches';

  /// Every club a player has represented, resolved from
  /// `CareerStats.clubsPlayedFor` — the profile's "Clubs" counter's
  /// destination.
  static String playerClubs(String uid) => '/player/$uid/clubs';

  /// The app-wide "who leads in this stat" board for one sport and one of
  /// its `ScoringPlugin.headlineStats` keys — see `LeaderboardScreen`.
  /// [highlightUid], when given, is picked out on the board if it appears.
  static String leaderboard(String sportId, String statKey, {String? highlightUid}) {
    final path =
        '/leaderboard/${Uri.encodeComponent(sportId)}/${Uri.encodeComponent(statKey)}';
    return highlightUid == null
        ? path
        : '$path?highlightUid=${Uri.encodeComponent(highlightUid)}';
  }

  static String org(String orgId) => '/org/$orgId';
  static String members(String orgId) => '/org/$orgId/members';

  /// A club's events, sorted into seasons, tournaments, single matches and
  /// challenges — see `ClubEventsScreen`.
  ///
  /// The kind rides as a query parameter rather than a path segment because
  /// it is a view preference, not a different resource: `/events` and
  /// `/events?kind=challenge` are the same list, and a bookmark to the second
  /// should keep working if the four kinds are ever re-cut.
  static String clubEvents(String orgId, {ClubEventKind? kind}) =>
      kind == null
          ? '/org/$orgId/events'
          : '/org/$orgId/events?kind=${kind.name}';

  /// A club's record, one row per sport it has played — see
  /// `ClubStatsScreen`.
  static String clubStats(String orgId) => '/org/$orgId/stats';

  /// One sport within a club's record — see `ClubSportStatsScreen`.
  static String clubSportStats(String orgId, String sportId) =>
      '/org/$orgId/stats/${Uri.encodeComponent(sportId)}';
  static String createTeam(String orgId) => '/org/$orgId/teams/new';
  static String clubSettings(String orgId) => '/org/$orgId/settings';

  /// Who runs the club and which department each of them looks after.
  static String clubStaff(String orgId) => '/org/$orgId/settings/staff';
  static String analytics(String orgId) => '/org/$orgId/analytics';
  static String live(String orgId) => '/org/$orgId/live';
  static String challenges(String orgId) => '/org/$orgId/challenges';
  static String gallery(String orgId) => '/org/$orgId/gallery';
  static String files(String orgId) => '/org/$orgId/files';
  /// Step one of creating anything: the event-type chooser (Feature #8).
  /// Everything that used to link straight to the single-sport form now
  /// lands here first.
  static String createCompetition(String orgId) => '/org/$orgId/new-event';

  /// The single-sport competition form, reached by choosing Tournament.
  ///
  /// This is the one-page "quick create" — see [CreateCompetitionScreen] for
  /// why one page is right for an organizer setting up a sports day.
  static String createTournamentEvent(String orgId) =>
      '/org/$orgId/new-event/tournament';

  /// The same tournament, created one step at a time.
  ///
  /// The guided route for a first tournament, where the single page's six
  /// formats and three participation models are choices the organizer does
  /// not yet have the vocabulary to make. Writes an identical [Competition]
  /// through the same repository, so nothing downstream can tell which
  /// entrance was used.
  static String createTournamentGuided(String orgId) =>
      '/org/$orgId/new-event/tournament/guided';

  /// The multi-sport season form: which sports, how many entries each, and
  /// whether outside clubs may enter.
  static String createSeason(String orgId) => '/org/$orgId/new-event/season';

  /// The same season, one step at a time. Same relationship to
  /// [createSeason] as [createTournamentGuided] has to
  /// [createTournamentEvent] — guided by default, one page for the organizer
  /// who already knows what they want.
  static String createSeasonGuided(String orgId) =>
      '/org/$orgId/new-event/season/guided';

  /// Two people or two scratch sides playing right now, with none of the
  /// event machinery in between.
  ///
  /// The optional arguments exist so the event screen can hand this screen
  /// what an organizer already typed there when they picked the Single Match
  /// format, rather than asking for the same name and venue twice.
  static String quickMatch(
    String orgId, {
    String? name,
    String? sportId,
    String? venue,

    /// Members who already said they are coming, by uid.
    ///
    /// Uids and not names, deliberately. A player added by name is a stranger
    /// who happens to share it and nothing accrues to them — the distinction
    /// `QuickMatchScreen` exists to protect. Passing the accounts means the
    /// match lands on the right careers, which is the whole reason the
    /// availability call and the team sheet are the same object.
    List<String> playerUids = const [],
  }) {
    final q = <String, String>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (sportId != null && sportId.isNotEmpty) 'sport': sportId,
      if (venue != null && venue.isNotEmpty) 'venue': venue,
      if (playerUids.isNotEmpty) 'players': playerUids.join(','),
    };
    final base = '/org/$orgId/quick-match';
    if (q.isEmpty) return base;
    return '$base?${Uri(queryParameters: q).query}';
  }

  /// The same roster, split into a bracket instead of two sides.
  ///
  /// A separate route rather than a flag on [quickMatch] because it produces a
  /// different object: a competition with entrants and a draw, not one
  /// fixture. Sharing a screen between them would mean a screen that is two
  /// screens with an `if` down the middle.
  static String quickTournament(
    String orgId, {
    String? name,
    String? sportId,
    String? venue,
    List<String> playerUids = const [],
  }) {
    final q = <String, String>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (sportId != null && sportId.isNotEmpty) 'sport': sportId,
      if (venue != null && venue.isNotEmpty) 'venue': venue,
      if (playerUids.isNotEmpty) 'players': playerUids.join(','),
    };
    final base = '/org/$orgId/quick-tournament';
    if (q.isEmpty) return base;
    return '$base?${Uri(queryParameters: q).query}';
  }
  static String competition(String orgId, String compId) =>
      '/org/$orgId/event/$compId';
  /// The hub a match opens into, whatever created it —
  /// `docs/Heart_of_the_playsphere.md` §4. Officials, configuration and the
  /// start button live here; [scoring] and [watch] are what it leads to.
  static String matchCenter(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/match/$fixtureId';

  /// Where a finished match lands — the result, who won, and what has
  /// actually happened to it since. See `MatchResultScreen`.
  static String matchResult(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/result/$fixtureId';

  static String scoring(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/score/$fixtureId';
  static String watch(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/watch/$fixtureId';
  static String entrant(String orgId, String compId, String entrantId) =>
      '/org/$orgId/event/$compId/entrant/$entrantId';

  /// Where the public web build is served from.
  ///
  /// On the web the app already knows — it is the page it is running on, which
  /// also means a link shared from a preview channel points back at that
  /// channel rather than at production. On Android and iOS there is no origin
  /// to read, so it falls back to the deployed hosting site; override it for
  /// a custom domain with
  /// `--dart-define=PLAYSPHERE_WEB_ORIGIN=https://play.example.org`.
  static String get publicOrigin =>
      kIsWeb ? Uri.base.origin : _configuredOrigin;

  static const _configuredOrigin = String.fromEnvironment(
    'PLAYSPHERE_WEB_ORIGIN',
    defaultValue: 'https://playsphere-os.web.app',
  );

  /// The absolute link to a live match, for someone with no account and no
  /// app. The spectator route is deliberately public (see [_isPublicRoute]),
  /// which is what makes this worth sharing at all — the recipient opens a
  /// score, not a sign-in wall.
  static String watchUrl(String orgId, String compId, String fixtureId) =>
      '$publicOrigin${watch(orgId, compId, fixtureId)}';

  /// The public, signed-out view of a whole tournament.
  static String publicTournament(String orgId, String tournamentId) =>
      '/org/$orgId/live-tournament/$tournamentId';

  static String publicTournamentUrl(String orgId, String tournamentId) =>
      '$publicOrigin${publicTournament(orgId, tournamentId)}';
}

/// Where somebody was trying to go before the router sent them to sign in.
///
/// ## Why this is a static holder and not a provider
///
/// It is written from inside `GoRouter.redirect`, which is not a widget build
/// and must not have provider side effects hung off it — a `StateProvider`
/// mutated during navigation re-runs the redirect that is still executing.
/// This is a single nullable string with one writer and one reader, and a
/// class with two methods is the honest shape for that.
///
/// Read-once by design. [take] clears as it returns, so a destination cannot
/// be replayed on a later sign-in — somebody who signs out and back in a week
/// later should land on Home, not on the invite they opened once.
class PendingDestination {
  const PendingDestination._();

  static String? _location;

  /// Remembers a full location INCLUDING its query string. The query is the
  /// payload for the links this exists for: `?code=ABC123` is the invite.
  ///
  /// Home and the sign-in screen itself are never remembered — resuming to
  /// either is indistinguishable from the default, and remembering sign-in
  /// would loop.
  static void remember(String location) {
    if (location.isEmpty) return;
    if (location == Routes.home) return;
    if (location.startsWith(Routes.signIn)) return;
    _location = location;
  }

  /// The remembered destination, cleared. Null when there was none.
  static String? take() {
    final location = _location;
    _location = null;
    return location;
  }

  /// Drops anything remembered without navigating to it — for a sign-out,
  /// where the next person on this device must not inherit it.
  static void forget() => _location = null;
}

/// Routes a signed-out visitor may still open.
///
/// Spectating is deliberately public: the entire point of the product is that
/// a parent at work or a class on a laptop can follow a match. Forcing a sign
/// in to watch would defeat it.
bool _isPublicRoute(String location) {
  if (location.startsWith(Routes.signIn)) return true;
  // A child claiming a managed profile has no Firebase Auth session at all
  // until partway through that screen's own flow — see ClaimEntryScreen.
  if (location.startsWith(Routes.claim)) return true;
  if (RegExp(r'^/org/[^/]+/live-tournament/').hasMatch(location)) return true;
  return RegExp(r'^/org/[^/]+/event/[^/]+/watch/').hasMatch(location);
}

/// Reads the `kind=` on a club's events link back into a [ClubEventKind].
///
/// Null for anything unrecognised, including null itself, which leaves
/// `ClubEventsScreen` on its own default tab. A shared link is a thing other
/// people paste, and refusing to open the page because the tab name has moved
/// on is a worse answer than opening it at the top.
ClubEventKind? _clubEventKind(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final kind in ClubEventKind.values) {
    if (kind.name == raw) return kind;
  }
  return null;
}

/// Splits the comma-joined uid list a match call hands to the draft screens.
///
/// Empty segments are dropped rather than becoming empty-string uids, which
/// would resolve to no member and put a nameless row on a team sheet.
List<String> _uidList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    debugLogDiagnostics: false,

    // Every authority decision happens here rather than inside widgets, so a
    // deep link pasted into a browser is subject to exactly the same checks
    // as a tap inside the app.
    redirect: (context, state) {
      final location = state.uri.path;
      final authState = ref.read(authStateProvider);

      // Hold still until Firebase has restored the session, otherwise a
      // refresh on the web bounces a signed-in user to the sign-in screen.
      if (authState.isLoading) return null;

      final signedIn = authState.valueOrNull != null;

      if (!signedIn) {
        if (_isPublicRoute(location)) return null;
        // The whole point of a shared invite is that it reaches somebody who
        // is NOT in the product yet — so the one person an invite link has to
        // work for was the one person it did not work for. They were bounced
        // to sign-in, and after signing in they landed on Home with the club
        // and its code discarded, having never been told which club they had
        // been invited to.
        PendingDestination.remember(state.uri.toString());
        return Routes.signIn;
      }

      // Signed in, but we still need the details Google never gives us —
      // principally a date of birth, without which no age category can be
      // judged. Everything is blocked until that is supplied.
      //
      // The ACCOUNT's own profile, not whichever profile is open. This gate
      // is about the human who just signed in, and a managed child is
      // created complete server-side anyway — reading the open profile here
      // would also mean a child document that momentarily fails to resolve
      // could pin the whole app on the setup screen, which is the one screen
      // with no way back out.
      final profile = ref.read(authUserProvider);
      if (profile.isLoading) return null;

      final complete = profile.valueOrNull?.profileComplete ?? false;
      if (!complete && location != Routes.profileSetup) {
        return Routes.profileSetup;
      }
      // Deliberately no "complete && at profileSetup -> home" rule here.
      // ProfileSetupScreen is also the edit-your-details screen a complete
      // profile reaches deliberately (the account panel's pencil icon) —
      // a blanket redirect away the instant it landed on a complete profile
      // bounced that tap straight back to home before the screen ever
      // rendered. The first-time setup flow instead navigates itself, in
      // _save(), the moment its own write succeeds.
      // Signed in and complete: pick up whatever they were trying to open
      // before they were sent here, and fall back to Home when there was
      // nothing — which is every ordinary sign-in.
      if (location == Routes.signIn) {
        return PendingDestination.take() ?? Routes.home;
      }

      return null;
    },

    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.path),

    routes: [
      GoRoute(
        path: Routes.signIn,
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.claim,
        builder: (_, __) => const ClaimEntryScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.rules,
        builder: (_, __) => const SportRulesScreen(),
      ),
      GoRoute(
        path: Routes.globalEvents,
        builder: (_, __) => const GlobalEventsScreen(),
      ),
      GoRoute(
        path: Routes.more,
        builder: (_, __) => const MoreMenuScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.liveNow,
        builder: (_, __) => const LiveNowScreen(),
      ),
      // The Arena. The two deeper paths are declared BEFORE the list, for the
      // same reason the umpire register is: go_router matches in declaration
      // order, and a `/arena/:something` pattern would otherwise swallow them.
      GoRoute(
        path: '/arena/new/:gameId',
        builder: (_, state) => ArenaChallengeScreen(
          gameId: state.pathParameters['gameId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/arena/game/:matchId',
        builder: (_, state) => ArenaBoardScreen(
          matchId: state.pathParameters['matchId'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.arenaLadder,
        builder: (_, __) => const ArenaLeaderboardScreen(),
      ),
      GoRoute(
        path: Routes.arena,
        builder: (_, __) => const ArenaHomeScreen(),
      ),
      GoRoute(
        path: Routes.myEvents,
        builder: (_, __) => const MyEventsScreen(),
      ),
      // The four lists behind the home screen's four tiles, each declared
      // from the tile's own key so the route and what the tile says cannot
      // drift apart.
      for (final lens in RegistrationLens.values)
        for (final kind in OpenRegistrationKind.values)
          GoRoute(
            path: Routes.entryList((kind: kind, lens: lens)),
            builder: (_, __) =>
                ActiveSeasonsScreen(kind: kind, lens: lens),
          ),
      // Both of these screens take the signed-in user as a constructor
      // argument rather than reading it themselves, so the route resolves it.
      // They existed and worked for months with nothing routed to them, which
      // is the same as not having shipped them.
      GoRoute(
        path: Routes.lookingFor,
        builder: (_, __) => const _WithSignedInUser(builder: _lookingForBoard),
      ),
      // The register form is declared BEFORE the directory: go_router matches
      // in declaration order, and `/community/officials/register` would
      // otherwise never be reached past the directory's own path.
      GoRoute(
        path: Routes.umpireRegister,
        builder: (_, __) => const _WithSignedInUser(builder: _umpireRegistry),
      ),
      GoRoute(
        path: Routes.umpireRegistry,
        builder: (_, state) => OfficialsDirectoryScreen(
          initialSportId: state.uri.queryParameters['sport'],
        ),
      ),

      // --- Operations -----------------------------------------------------
      GoRoute(
        path: Routes.opsAds,
        builder: (_, __) => const AdReviewScreen(),
      ),
      GoRoute(
        path: Routes.opsGiveNeeds,
        builder: (_, __) =>
            const GiveOpsScreen(initialTab: GiveOpsTab.needs),
      ),
      GoRoute(
        path: Routes.opsGive,
        builder: (_, __) => const GiveOpsScreen(),
      ),
      GoRoute(
        path: Routes.opsTeam,
        builder: (_, __) => const OpsTeamScreen(),
      ),
      GoRoute(
        path: Routes.ops,
        builder: (_, __) => const OpsHomeScreen(),
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, __) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: Routes.orgs,
        builder: (_, __) => const OrgPickerScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) => const CreateOrgScreen(),
          ),
          GoRoute(
            path: 'join',
            // `?code=` arrives from an invite link or a scanned QR. It only
            // prefills the box — the person still sees which club they are
            // about to join and still has to confirm.
            builder: (_, state) =>
                JoinOrgScreen(initialCode: state.uri.queryParameters['code']),
          ),
        ],
      ),
      // A player's own profile, and anyone else's.
      //
      // Two routes rather than one so `/me` is a stable link that survives the
      // uid being unknown at link-construction time — the account menu does not
      // have to reach for the session to build it.
      GoRoute(
        path: Routes.myProfile,
        builder: (_, __) => const _MyProfileScreen(),
      ),
      GoRoute(
        path: Routes.myChildren,
        builder: (_, __) => const ManagedChildrenScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) => const AddChildScreen(),
          ),
          GoRoute(
            path: ':childUid/claim',
            builder: (_, state) => ClaimCodeScreen(
              childUid: state.pathParameters['childUid']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.premium,
        builder: (_, __) => const PremiumScreen(),
      ),
      // The two halves of the ground marketplace. Neither is under `/org/`:
      // a ground owner has no club, and a player looking for a pitch is
      // looking outward — see Routes.grounds.
      //
      // `/grounds/mine` is declared before the `:groundId` route so the
      // literal wins; go_router matches in declaration order, and `mine`
      // would otherwise be read as a ground id.
      GoRoute(
        path: Routes.myGrounds,
        builder: (_, __) => const MyGroundsScreen(),
      ),
      GoRoute(
        path: Routes.groundReview,
        builder: (_, __) => const GroundReviewScreen(),
      ),
      GoRoute(
        path: Routes.grounds,
        builder: (_, __) => const GroundsScreen(),
      ),
      GoRoute(
        path: '/grounds/:groundId/food/manage',
        builder: (_, state) => GroundFoodManageScreen(
          groundId: state.pathParameters['groundId']!,
        ),
      ),
      GoRoute(
        path: '/grounds/:groundId/food/orders',
        builder: (_, state) => GroundFoodOrdersScreen(
          groundId: state.pathParameters['groundId']!,
        ),
      ),
      GoRoute(
        path: '/grounds/:groundId/food',
        builder: (_, state) => GroundFoodScreen(
          groundId: state.pathParameters['groundId']!,
        ),
      ),
      GoRoute(
        path: '/grounds/:groundId',
        builder: (_, state) => GroundDetailScreen(
          groundId: state.pathParameters['groundId']!,
        ),
      ),
      GoRoute(
        path: Routes.myFoodOrders,
        builder: (_, __) => const MyFoodOrdersScreen(),
      ),
      // Sports shops. `mySportsShop` lives under `/me`, so only the `:uid`
      // route needs ordering care — declared after the bare directory for the
      // same reason the coach routes are.
      GoRoute(
        path: Routes.mySportsShop,
        builder: (_, __) => const SportsShopRegistrationScreen(),
      ),
      GoRoute(
        path: Routes.sportsShops,
        builder: (_, state) => SportsShopsScreen(
          initialSportId: state.uri.queryParameters['sport'],
        ),
      ),
      GoRoute(
        path: '/sports-shops/:uid',
        builder: (_, state) =>
            SportsShopDetailScreen(uid: state.pathParameters['uid']!),
      ),
      GoRoute(
        path: Routes.shop,
        // `?sport=` arrives from a promo banner, and only preselects the
        // filter — the chips are still there and "All sports" is one tap away.
        builder: (_, state) =>
            ShopScreen(initialSportId: state.uri.queryParameters['sport']),
      ),
      GoRoute(
        path: Routes.myClubOrders,
        builder: (_, __) => const MyClubOrdersScreen(),
      ),
      // The Give network. `giveDonate` and `giveRaiseNeed` are declared
      // before `give` so their more specific paths are unaffected by
      // declaration order — go_router matches by full path, not prefix, but
      // keeping the hub first in reading order matches how the other module
      // groups (grounds, shop) are laid out above.
      // Player auctions. `auctionCreate` is declared first so `/auctions/new`
      // is not matched as `/auctions/:auctionId` with the id "new".
      GoRoute(
        path: Routes.auctionCreate,
        builder: (_, __) => const AuctionCreateScreen(),
      ),
      GoRoute(
        path: Routes.auctions,
        builder: (_, __) => const AuctionsHomeScreen(),
      ),
      GoRoute(
        path: '/auctions/:auctionId/people',
        builder: (_, state) => AuctionPeopleScreen(
          auctionId: state.pathParameters['auctionId']!,
        ),
      ),
      GoRoute(
        path: '/auctions/:auctionId/settings',
        builder: (_, state) => AuctionSettingsScreen(
          auctionId: state.pathParameters['auctionId']!,
        ),
      ),
      GoRoute(
        path: '/auctions/:auctionId/trades',
        builder: (_, state) => AuctionTradesScreen(
          auctionId: state.pathParameters['auctionId']!,
        ),
      ),
      GoRoute(
        path: '/auctions/:auctionId/player/:lotId',
        builder: (_, state) => AuctionLotScreen(
          auctionId: state.pathParameters['auctionId']!,
          lotId: state.pathParameters['lotId']!,
        ),
      ),
      GoRoute(
        path: '/auctions/:auctionId/side/:teamId',
        builder: (_, state) => AuctionTeamScreen(
          auctionId: state.pathParameters['auctionId']!,
          teamId: state.pathParameters['teamId']!,
        ),
      ),
      GoRoute(
        path: '/auctions/:auctionId',
        builder: (_, state) => AuctionDetailScreen(
          auctionId: state.pathParameters['auctionId']!,
        ),
      ),
      GoRoute(
        path: Routes.give,
        builder: (_, __) => const GiveHomeScreen(),
      ),
      GoRoute(
        path: Routes.giveDonate,
        builder: (_, __) => const GiveDonateScreen(),
      ),
      GoRoute(
        path: Routes.giveMyDonations,
        builder: (_, __) => const GiveMyDonationsScreen(),
      ),
      GoRoute(
        path: Routes.giveCollectionCenters,
        builder: (_, __) => const GiveCollectionCentersScreen(),
      ),
      GoRoute(
        path: Routes.giveNeeds,
        builder: (_, __) => const GiveNeedsScreen(),
      ),
      GoRoute(
        path: Routes.giveRaiseNeed,
        builder: (_, __) => const GiveRaiseNeedScreen(),
      ),
      GoRoute(
        path: Routes.giveImpact,
        builder: (_, __) => const GiveImpactScreen(),
      ),
      // Sponsor an Athlete / Sponsor a Team. `sponsorBrowse`/`sponsorCreate`/
      // `sponsorMine` are declared before the `:listingId` routes for the
      // same reason `giveDonate`/`giveRaiseNeed` are declared before `give`.
      GoRoute(
        path: Routes.sponsor,
        builder: (_, __) => const SponsorHomeScreen(),
      ),
      GoRoute(
        path: Routes.sponsorBrowse,
        builder: (_, __) => const SponsorBrowseScreen(),
      ),
      GoRoute(
        path: Routes.sponsorCreate,
        builder: (_, __) => const SponsorCreateListingScreen(),
      ),
      GoRoute(
        path: Routes.sponsorMine,
        builder: (_, __) => const SponsorMyListingsScreen(),
      ),
      GoRoute(
        path: Routes.sponsorMyPledges,
        builder: (_, __) => const SponsorMyPledgesScreen(),
      ),
      GoRoute(
        path: '/sponsor/listings/:listingId/offers',
        builder: (_, state) => SponsorIncomingOffersScreen(
          listingId: state.pathParameters['listingId']!,
        ),
      ),
      GoRoute(
        path: '/sponsor/listings/:listingId',
        builder: (_, state) => SponsorListingDetailScreen(
          listingId: state.pathParameters['listingId']!,
        ),
      ),
      GoRoute(
        path: Routes.discover,
        builder: (_, state) => DiscoverScreen(
          initialTab: state.uri.queryParameters['tab'] == 'people' ? 1 : 0,
        ),
      ),
      GoRoute(
        path: Routes.clubNetwork,
        builder: (_, state) => ClubNetworkScreen(
          initialTab: state.uri.queryParameters['tab'] == 'find' ? 1 : 0,
        ),
        routes: [
          GoRoute(
            path: 't/:threadId',
            builder: (_, state) => ClubThreadScreen(
              threadId: state.pathParameters['threadId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.myPlayerListing,
        builder: (_, __) => const PlayerListingEditScreen(),
      ),
      GoRoute(
        path: Routes.scoutSearch,
        builder: (_, state) => ScoutSearchScreen(
          initialSportId: state.uri.queryParameters['sport'],
        ),
      ),
      GoRoute(
        path: Routes.risingTalent,
        builder: (_, __) => const RisingTalentScreen(),
      ),
      GoRoute(
        path: Routes.coaches,
        builder: (_, state) => CoachesScreen(
          initialSportId: state.uri.queryParameters['sport'],
        ),
        routes: [
          // Nested, so the directory is a coach page's natural parent and
          // the back arrow lands on the list they came from.
          GoRoute(
            path: ':uid',
            builder: (_, state) =>
                CoachDetailScreen(uid: state.pathParameters['uid']!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.myCoachProfile,
        builder: (_, __) => const CoachProfileEditScreen(),
      ),

      // The Sports Medicine hub. Every screen is nested under `/medical` so
      // the hub is each one's natural parent and a back arrow from a warm-up
      // or an injury lands there rather than wherever the deep link came
      // from.
      GoRoute(
        path: Routes.sportsMedicine,
        builder: (_, __) => const SportsMedicineScreen(),
        routes: [
          GoRoute(
            path: 'find',
            builder: (_, state) => SportsMedicsDirectoryScreen(
              initialSportId: state.uri.queryParameters['sport'],
            ),
            routes: [
              GoRoute(
                path: ':uid',
                builder: (_, state) => SportsMedicDetailScreen(
                  uid: state.pathParameters['uid']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'warmups',
            builder: (_, state) => SportsWarmupsScreen(
              initialSportId: state.uri.queryParameters['sport'],
            ),
          ),
          GoRoute(
            path: 'injuries',
            builder: (_, state) => SportsInjuriesScreen(
              initialSportId: state.uri.queryParameters['sport'],
            ),
          ),
          GoRoute(
            path: 'emergency',
            builder: (_, __) => const SportsEmergencyScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.mySportsMedicProfile,
        builder: (_, __) => const SportsMedicRegistrationScreen(),
      ),
      GoRoute(
        path: Routes.sports,
        builder: (_, __) => const SportsDirectoryScreen(),
        routes: [
          // Nested, so the directory is this screen's natural parent and the
          // back arrow goes where a person expects.
          GoRoute(
            path: ':sportId',
            builder: (_, state) => SportHubScreen(
              sportId: Uri.decodeComponent(state.pathParameters['sportId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: Routes.matchRsvps,
        builder: (_, __) => const MatchRsvpScreen(),
      ),
      GoRoute(
        path: '/leaderboard/:sportId/:statKey',
        builder: (_, state) => LeaderboardScreen(
          sportId: Uri.decodeComponent(state.pathParameters['sportId']!),
          statKey: Uri.decodeComponent(state.pathParameters['statKey']!),
          highlightUid: state.uri.queryParameters['highlightUid'],
        ),
      ),
      GoRoute(
        path: Routes.adConsole,
        builder: (_, __) => const AdConsoleScreen(),
      ),
      GoRoute(
        path: Routes.govDashboard,
        builder: (_, __) => const GovDashboardScreen(),
      ),
      // "Matches" and "Sports" are destinations in their own right, not
      // anchors on the profile. Both home-screen tiles used to push `/me`,
      // so two differently-labelled counters landed on the same page.
      GoRoute(
        path: Routes.myMatches,
        builder: (_, __) => const _MyScopedScreen(_MyScope.matches),
      ),
      GoRoute(
        path: Routes.mySports,
        builder: (_, __) => const _MyScopedScreen(_MyScope.sports),
      ),
      // Before the `:teamId` route below it. `/teams/new` would otherwise
      // match the team page with an id of "new".
      GoRoute(
        path: Routes.createStandaloneTeam,
        builder: (_, __) => const CreateStandaloneTeamScreen(),
      ),
      GoRoute(
        path: Routes.standaloneTeams,
        builder: (_, __) => const StandaloneTeamsScreen(),
      ),
      GoRoute(
        path: Routes.myTeams,
        builder: (_, __) => const _MyScopedScreen(_MyScope.teams),
      ),
      GoRoute(
        path: '/teams/:teamId',
        builder: (_, state) =>
            TeamDetailScreen(teamId: state.pathParameters['teamId']!),
      ),
      GoRoute(
        path: '/player/:uid',
        builder: (_, state) =>
            CareerProfileScreen(uid: state.pathParameters['uid']!),
        routes: [
          GoRoute(
            path: 'sport/:sportId',
            builder: (_, state) => PlayerSportScreen(
              uid: state.pathParameters['uid']!,
              // Chess ids carry a `:` qualifier (`chess:blitz`), which is
              // percent-encoded into the path and has to come back out.
              sportId:
                  Uri.decodeComponent(state.pathParameters['sportId']!),
            ),
          ),
          GoRoute(
            path: 'stats/:sportId',
            builder: (_, state) => PlayerStatsScreen(
              uid: state.pathParameters['uid']!,
              // Same percent-encoding round trip as the sport page above:
              // chess ids carry a `:` qualifier.
              sportId:
                  Uri.decodeComponent(state.pathParameters['sportId']!),
              highlight: state.uri.queryParameters['highlight'],
            ),
          ),
          GoRoute(
            path: 'matches',
            // MyMatchesScreen already reads any uid it's given — it just
            // never had a URL that carried one other than the current user.
            builder: (_, state) =>
                MyMatchesScreen(uid: state.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'clubs',
            builder: (_, state) =>
                PlayerClubsScreen(uid: state.pathParameters['uid']!),
          ),
        ],
      ),
      GoRoute(
        path: '/org/:orgId',
        builder: (_, state) =>
            OrgHomeScreen(orgId: state.pathParameters['orgId']!),
        routes: [
          GoRoute(
            path: 'members',
            builder: (_, state) =>
                MembersScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'stats',
            builder: (_, state) =>
                ClubStatsScreen(orgId: state.pathParameters['orgId']!),
            routes: [
              GoRoute(
                path: ':sportId',
                builder: (_, state) => ClubSportStatsScreen(
                  orgId: state.pathParameters['orgId']!,
                  sportId:
                      Uri.decodeComponent(state.pathParameters['sportId']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'events',
            builder: (_, state) => ClubEventsScreen(
              orgId: state.pathParameters['orgId']!,
              // An unrecognised `kind=` opens the default tab rather than
              // failing the route: these links are shared, and a season
              // renamed in a future version must not 404 somebody's message.
              initialKind: _clubEventKind(state.uri.queryParameters['kind']),
            ),
          ),
          GoRoute(
            path: 'teams/new',
            builder: (_, state) =>
                CreateTeamScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, state) =>
                ClubSettingsScreen(orgId: state.pathParameters['orgId']!),
            routes: [
              GoRoute(
                path: 'staff',
                builder: (_, state) =>
                    ClubStaffScreen(orgId: state.pathParameters['orgId']!),
              ),
            ],
          ),
          GoRoute(
            path: 'analytics',
            builder: (_, state) =>
                AnalyticsScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'live',
            builder: (_, state) =>
                LiveMatchesScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'challenges',
            builder: (_, state) =>
                ChallengesScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'gallery',
            builder: (_, state) =>
                ClubGalleryScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'rankings',
            builder: (_, state) =>
                RankingsScreen(orgId: state.pathParameters['orgId']!),
          ),
          // Club Commerce. `store/manage` and `store/orders` are declared
          // before `store` for the same reason `giveDonate` precedes `give`.
          GoRoute(
            path: 'store/manage',
            builder: (_, state) =>
                ClubStoreManageScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'store/orders',
            builder: (_, state) =>
                ClubStoreOrdersScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'store',
            builder: (_, state) =>
                ClubStoreScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'live-tournament/:tournamentId',
            builder: (_, state) => PublicTournamentScreen(
              orgId: state.pathParameters['orgId']!,
              tournamentId: state.pathParameters['tournamentId']!,
            ),
          ),
          GoRoute(
            path: 'tournaments',
            builder: (_, state) =>
                TournamentsScreen(orgId: state.pathParameters['orgId']!),
            routes: [
              GoRoute(
                path: ':tournamentId',
                builder: (_, state) => TournamentDetailScreen(
                  orgId: state.pathParameters['orgId']!,
                  tournamentId: state.pathParameters['tournamentId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'schedule',
                    builder: (_, state) => TournamentScheduleScreen(
                      orgId: state.pathParameters['orgId']!,
                      tournamentId: state.pathParameters['tournamentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'certificates',
                    builder: (_, state) => CertificatesScreen(
                      orgId: state.pathParameters['orgId']!,
                      tournamentId: state.pathParameters['tournamentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'venues',
                    builder: (_, state) => VenuePlannerScreen(
                      orgId: state.pathParameters['orgId']!,
                      tournamentId: state.pathParameters['tournamentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'officials',
                    builder: (_, state) => OfficialsScreen(
                      orgId: state.pathParameters['orgId']!,
                      tournamentId: state.pathParameters['tournamentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'memories',
                    builder: (_, state) => SeasonMemoryBookScreen(
                      orgId: state.pathParameters['orgId']!,
                      tournamentId: state.pathParameters['tournamentId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'entrant/:entrantId',
                    builder: (_, state) => SeasonEntrantScreen(
                      orgId: state.pathParameters['orgId']!,
                      tournamentId: state.pathParameters['tournamentId']!,
                      entrantId: state.pathParameters['entrantId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'venues',
            builder: (_, state) =>
                VenuesScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'files',
            builder: (_, state) =>
                ClubFilesScreen(orgId: state.pathParameters['orgId']!),
          ),
          // Creating anything starts with the type chooser (Feature #8); the
          // single-sport form is now one of four destinations behind it
          // rather than the only thing "New event" could mean.
          GoRoute(
            path: 'new-event',
            builder: (_, state) =>
                ChooseEventTypeScreen(orgId: state.pathParameters['orgId']!),
            routes: [
              GoRoute(
                path: 'tournament',
                builder: (_, state) => CreateCompetitionScreen(
                  orgId: state.pathParameters['orgId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'guided',
                    builder: (_, state) => GuidedTournamentScreen(
                      orgId: state.pathParameters['orgId']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'season',
                builder: (_, state) => CreateSeasonScreen(
                  orgId: state.pathParameters['orgId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'guided',
                    builder: (_, state) => GuidedSeasonScreen(
                      orgId: state.pathParameters['orgId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'quick-match',
            builder: (_, state) => QuickMatchScreen(
              orgId: state.pathParameters['orgId']!,
              initialName: state.uri.queryParameters['name'],
              initialSportId: state.uri.queryParameters['sport'],
              initialVenue: state.uri.queryParameters['venue'],
              initialPlayerUids: _uidList(state.uri.queryParameters['players']),
            ),
          ),
          GoRoute(
            path: 'quick-tournament',
            builder: (_, state) => QuickTournamentScreen(
              orgId: state.pathParameters['orgId']!,
              initialName: state.uri.queryParameters['name'],
              initialSportId: state.uri.queryParameters['sport'],
              initialVenue: state.uri.queryParameters['venue'],
              playerUids: _uidList(state.uri.queryParameters['players']),
            ),
          ),
          GoRoute(
            path: 'event/:compId',
            builder: (_, state) => CompetitionDetailScreen(
              orgId: state.pathParameters['orgId']!,
              compId: state.pathParameters['compId']!,
            ),
            routes: [
              GoRoute(
                path: 'match/:fixtureId',
                builder: (_, state) => MatchCenterScreen(
                  orgId: state.pathParameters['orgId']!,
                  compId: state.pathParameters['compId']!,
                  fixtureId: state.pathParameters['fixtureId']!,
                ),
              ),
              GoRoute(
                path: 'result/:fixtureId',
                builder: (_, state) => MatchResultScreen(
                  orgId: state.pathParameters['orgId']!,
                  compId: state.pathParameters['compId']!,
                  fixtureId: state.pathParameters['fixtureId']!,
                ),
              ),
              GoRoute(
                path: 'score/:fixtureId',
                builder: (_, state) => ScoringScreen(
                  orgId: state.pathParameters['orgId']!,
                  compId: state.pathParameters['compId']!,
                  fixtureId: state.pathParameters['fixtureId']!,
                ),
              ),
              GoRoute(
                path: 'watch/:fixtureId',
                builder: (_, state) => SpectatorScreen(
                  orgId: state.pathParameters['orgId']!,
                  compId: state.pathParameters['compId']!,
                  fixtureId: state.pathParameters['fixtureId']!,
                ),
              ),
              GoRoute(
                path: 'entrant/:entrantId',
                builder: (_, state) => EntrantDetailScreen(
                  orgId: state.pathParameters['orgId']!,
                  compId: state.pathParameters['compId']!,
                  entrantId: state.pathParameters['entrantId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Nudges GoRouter to re-run [GoRouter.redirect] when the session or the
/// profile changes, so signing in or completing a profile navigates without
/// the user having to touch anything.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _subs.add(_ref.listen(authStateProvider, (_, __) => notifyListeners()));
    _subs.add(_ref.listen(currentUserProvider, (_, __) => notifyListeners()));
  }

  final Ref _ref;
  final List<ProviderSubscription> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    super.dispose();
  }
}

/// Resolves `/me` to the signed-in user's profile.
///
/// The redirect guard above guarantees a session by the time this builds, but it
/// still handles the null case rather than asserting — a router invariant is a
/// poor reason to crash on someone's own profile.
class _MyProfileScreen extends ConsumerWidget {
  const _MyProfileScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SignInScreen();
    return CareerProfileScreen(uid: uid);
  }
}

/// Which of the signed-in player's own pages a `/me/...` route resolves to.
enum _MyScope { matches, sports, teams }

/// Resolves `/me/matches` and `/me/sports` to the signed-in player.
///
/// Same shape and same reasoning as [_MyProfileScreen]: `/me/...` links are
/// built without reaching for the session, and the uid is looked up here.
class _MyScopedScreen extends ConsumerWidget {
  const _MyScopedScreen(this.scope);

  final _MyScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SignInScreen();
    return switch (scope) {
      _MyScope.matches => MyMatchesScreen(uid: uid),
      _MyScope.sports => MySportsScreen(uid: uid),
      _MyScope.teams => MyTeamsScreen(uid: uid),
    };
  }
}

Widget _lookingForBoard(AppUser user) => LookingForBoardScreen(user: user);

Widget _umpireRegistry(AppUser user) => UmpireRegistryScreen(user: user);

/// Hands a built screen the signed-in user's profile, waiting for it first.
///
/// The redirect guard guarantees a session and a completed profile by the time
/// any of these routes build, but the profile document still arrives over a
/// stream — so there is one frame where it is genuinely absent, and a screen
/// that takes an `AppUser` cannot be built during it.
class _WithSignedInUser extends ConsumerWidget {
  const _WithSignedInUser({required this.builder});

  final Widget Function(AppUser user) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return builder(user);
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text('Nothing here', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(location, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go(Routes.home),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
