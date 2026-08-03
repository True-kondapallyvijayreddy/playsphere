

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/venues/venues_screen.dart';
import '../../features/tournaments/tournaments_screen.dart';
import '../../features/tournaments/tournament_detail_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/community/looking_for_board_screen.dart';
import '../../features/competitions/challenges_screen.dart';
import '../../features/competitions/competition_detail_screen.dart';
import '../../features/competitions/create_competition_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/orgs/club_files_screen.dart';
import '../../features/orgs/club_gallery_screen.dart';
import '../../features/orgs/create_org_screen.dart';
import '../../features/orgs/join_org_screen.dart';
import '../../features/orgs/members_screen.dart';
import '../../features/orgs/org_home_screen.dart';
import '../../features/orgs/org_picker_screen.dart';
import '../../features/orgs/umpire_registry_screen.dart';
import '../../features/profile/career_profile_screen.dart';
import '../../features/rules/sport_rules_screen.dart';
import '../../features/scoring/live_matches_screen.dart';
import '../../features/scoring/quick_match_screen.dart';
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

  static String tournament(String orgId, String tournamentId) =>
      '/org/$orgId/tournaments/$tournamentId';

  static const myProfile = '/me';
  static String profile(String uid) => '/player/$uid';

  static String org(String orgId) => '/org/$orgId';
  static String members(String orgId) => '/org/$orgId/members';
  static String analytics(String orgId) => '/org/$orgId/analytics';
  static String live(String orgId) => '/org/$orgId/live';
  static String challenges(String orgId) => '/org/$orgId/challenges';
  static String gallery(String orgId) => '/org/$orgId/gallery';
  static String files(String orgId) => '/org/$orgId/files';
  static String createCompetition(String orgId) => '/org/$orgId/new-event';

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
  static String scoring(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/score/$fixtureId';
  static String watch(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/watch/$fixtureId';

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
}

/// Routes a signed-out visitor may still open.
///
/// Spectating is deliberately public: the entire point of the product is that
/// a parent at work or a class on a laptop can follow a match. Forcing a sign
/// in to watch would defeat it.
bool _isPublicRoute(String location) {
  if (location.startsWith(Routes.signIn)) return true;
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
        path: '/player/:uid',
        builder: (_, state) =>
            CareerProfileScreen(uid: state.pathParameters['uid']!),
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
          GoRoute(
            path: 'new-event',
            builder: (_, state) =>
                CreateCompetitionScreen(orgId: state.pathParameters['orgId']!),
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
