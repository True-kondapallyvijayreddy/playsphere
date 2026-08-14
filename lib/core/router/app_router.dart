

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/venues/venues_screen.dart';
import '../../features/rankings/rankings_screen.dart';
import '../../features/tournaments/certificates_screen.dart';
import '../../features/tournaments/officials_screen.dart';
import '../../features/tournaments/season_memory_book_screen.dart';
import '../../features/tournaments/public_tournament_screen.dart';
import '../../features/tournaments/tournaments_screen.dart';
import '../../features/tournaments/tournament_detail_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/community/looking_for_board_screen.dart';
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
import '../../features/give/give_collection_centers_screen.dart';
import '../../features/give/give_donate_screen.dart';
import '../../features/give/give_home_screen.dart';
import '../../features/give/give_impact_screen.dart';
import '../../features/give/give_my_donations_screen.dart';
import '../../features/give/give_needs_screen.dart';
import '../../features/give/give_raise_need_screen.dart';
import '../../features/grounds/grounds_screen.dart';
import '../../features/grounds/my_grounds_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/more/more_menu_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/sponsor/sponsor_home_screen.dart';
import '../../features/sponsor/sponsor_browse_screen.dart';
import '../../features/sponsor/sponsor_create_listing_screen.dart';
import '../../features/sponsor/sponsor_my_listings_screen.dart';
import '../../features/sponsor/sponsor_my_pledges_screen.dart';
import '../../features/sponsor/sponsor_listing_detail_screen.dart';
import '../../features/sponsor/sponsor_incoming_offers_screen.dart';
import '../../features/scout/rising_talent_screen.dart';
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
import '../../features/orgs/club_settings_screen.dart';
import '../../features/orgs/members_screen.dart';
import '../../features/orgs/org_home_screen.dart';
import '../../features/orgs/org_picker_screen.dart';
import '../../features/orgs/umpire_registry_screen.dart';
import '../../features/premium/premium_screen.dart';
import '../../features/shop/shop_screen.dart';
import '../../features/profile/career_profile_screen.dart';
import '../../features/profile/my_matches_screen.dart';
import '../../features/profile/my_sports_screen.dart';
import '../../features/profile/player_sport_screen.dart';
import '../../features/profile/player_stats_screen.dart';
import '../../features/rules/sport_rules_screen.dart';
import '../../features/scoring/live_matches_screen.dart';
import '../../features/scoring/live_now_screen.dart';
import '../../features/scoring/quick_match_screen.dart';
import '../../features/scoring/match_center_screen.dart';
import '../../features/scoring/match_result_screen.dart';
import '../../features/scoring/scoring_screen.dart';
import '../../features/scoring/spectator_screen.dart';
import '../models/app_user.dart';
import '../providers.dart';

class Routes {
  const Routes._();

  static const signIn = '/sign-in';
  static const profileSetup = '/welcome';

  /// Where a signed-in member lands: their clubs, their live matches and
  /// whatever is waiting on them, across every club at once.
  static const home = '/home';

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
  static const umpireRegistry = '/community/officials';

  static String venues(String orgId) => '/org/$orgId/venues';

  static String tournaments(String orgId) => '/org/$orgId/tournaments';

  static String rankings(String orgId) => '/org/$orgId/rankings';

  static String tournament(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId';

  static String certificates(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/certificates';

  static String tournamentOfficials(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/officials';

  static String seasonMemories(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId/memories';

  static const myProfile = '/me';
  static String profile(String uid) => '/player/$uid';

  /// What a player can buy for themselves. Deliberately org-free — Premium is
  /// bought by a person and travels with them between clubs, exactly like the
  /// career record it deepens.
  static const premium = '/premium';

  /// Sports kit, from a vendor. Org-free for the same reason as [premium]:
  /// a player buying a racket is buying it as themselves.
  static const shop = '/shop';

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

  /// Talent discovery — §6 Module C. Org-free and role-free: nothing gates
  /// who may open a search, because the real gate (a minor's consent) is
  /// enforced per-profile by `firestore.rules`, not by who is allowed to ask.
  static const scoutSearch = '/scout/search';

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

  /// The advertiser self-serve console. Org-free — an advertiser is a
  /// business acting for itself, not a club.
  static const adConsole = '/ads';

  /// Restricted to the `admin` custom claim — see `GovDashboardScreen`. A
  /// route, not a sub-route of anything, because it belongs to no club and
  /// no sport: it is PlaySphere talking to a district or state, not to a
  /// player.
  static const govDashboard = '/gov';

  /// Grounds available to hire, searchable by city, sport and time.
  ///
  /// Deliberately org-free and deliberately not under `/org/:id/venues`. A
  /// venue is a club's own hall; a ground is a business somebody else owns
  /// and rents to anybody — see `Refs.grounds`.
  static const grounds = '/grounds';

  /// The other side of the same marketplace: what a ground owner manages.
  static const myGrounds = '/grounds/mine';

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

  /// One player's record in one sport, sliced by where the matches came from
  /// — `docs/Heart_of_the_playsphere.md` §18.
  static String playerStats(String uid, String sportId) =>
      '/player/$uid/stats/${Uri.encodeComponent(sportId)}';

  /// One sport within a player's career — their matches in it, the
  /// scorecards, and where they sit in the ranking.
  static String playerSport(String uid, String sportId) =>
      '/player/$uid/sport/${Uri.encodeComponent(sportId)}';

  static String org(String orgId) => '/org/$orgId';
  static String members(String orgId) => '/org/$orgId/members';
  static String clubSettings(String orgId) => '/org/$orgId/settings';
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
  }) {
    final q = <String, String>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (sportId != null && sportId.isNotEmpty) 'sport': sportId,
      if (venue != null && venue.isNotEmpty) 'venue': venue,
    };
    final base = '/org/$orgId/quick-match';
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

/// Routes a signed-out visitor may still open.
///
/// Spectating is deliberately public: the entire point of the product is that
/// a parent at work or a class on a laptop can follow a match. Forcing a sign
/// in to watch would defeat it.
bool _isPublicRoute(String location) {
  if (location.startsWith(Routes.signIn)) return true;
  if (RegExp(r'^/org/[^/]+/live-tournament/').hasMatch(location)) return true;
  return RegExp(r'^/org/[^/]+/event/[^/]+/watch/').hasMatch(location);
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
        return _isPublicRoute(location) ? null : Routes.signIn;
      }

      // Signed in, but we still need the details Google never gives us —
      // principally a date of birth, without which no age category can be
      // judged. Everything is blocked until that is supplied.
      final profile = ref.read(currentUserProvider);
      if (profile.isLoading) return null;

      final complete = profile.valueOrNull?.profileComplete ?? false;
      if (!complete && location != Routes.profileSetup) {
        return Routes.profileSetup;
      }
      if (complete && location == Routes.profileSetup) {
        return Routes.home;
      }
      if (location == Routes.signIn) return Routes.home;

      return null;
    },

    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.path),

    routes: [
      GoRoute(
        path: Routes.signIn,
        builder: (_, __) => const SignInScreen(),
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
      GoRoute(
        path: Routes.myEvents,
        builder: (_, __) => const MyEventsScreen(),
      ),
      // Both of these screens take the signed-in user as a constructor
      // argument rather than reading it themselves, so the route resolves it.
      // They existed and worked for months with nothing routed to them, which
      // is the same as not having shipped them.
      GoRoute(
        path: Routes.lookingFor,
        builder: (_, __) => const _WithSignedInUser(builder: _lookingForBoard),
      ),
      GoRoute(
        path: Routes.umpireRegistry,
        builder: (_, __) => const _WithSignedInUser(builder: _umpireRegistry),
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
        path: Routes.scoutSearch,
        builder: (_, __) => const ScoutSearchScreen(),
      ),
      GoRoute(
        path: Routes.risingTalent,
        builder: (_, __) => const RisingTalentScreen(),
      ),
      GoRoute(
        path: Routes.sports,
        builder: (_, __) => const SportsDirectoryScreen(),
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
            ),
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
            path: 'settings',
            builder: (_, state) =>
                ClubSettingsScreen(orgId: state.pathParameters['orgId']!),
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
                    path: 'certificates',
                    builder: (_, state) => CertificatesScreen(
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
enum _MyScope { matches, sports }

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
