

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/competitions/competition_detail_screen.dart';
import '../../features/competitions/create_competition_screen.dart';
import '../../features/orgs/create_org_screen.dart';
import '../../features/orgs/join_org_screen.dart';
import '../../features/orgs/members_screen.dart';
import '../../features/orgs/org_home_screen.dart';
import '../../features/orgs/org_picker_screen.dart';
import '../../features/rules/sport_rules_screen.dart';
import '../../features/scoring/live_matches_screen.dart';
import '../../features/scoring/scoring_screen.dart';
import '../../features/scoring/spectator_screen.dart';
import '../providers.dart';

class Routes {
  const Routes._();

  static const signIn = '/sign-in';
  static const profileSetup = '/welcome';
  static const orgs = '/orgs';
  static const rules = '/rules';
  static const createOrg = '/orgs/new';
  static const joinOrg = '/orgs/join';

  static String org(String orgId) => '/org/$orgId';
  static String members(String orgId) => '/org/$orgId/members';
  static String live(String orgId) => '/org/$orgId/live';
  static String createCompetition(String orgId) => '/org/$orgId/new-event';
  static String competition(String orgId, String compId) =>
      '/org/$orgId/event/$compId';
  static String scoring(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/score/$fixtureId';
  static String watch(String orgId, String compId, String fixtureId) =>
      '/org/$orgId/event/$compId/watch/$fixtureId';
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
    initialLocation: Routes.orgs,
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
        return Routes.orgs;
      }
      if (location == Routes.signIn) return Routes.orgs;

      return null;
    },

    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.path),

    routes: [
      GoRoute(
        path: Routes.signIn,
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.rules,
        builder: (_, __) => const SportRulesScreen(),
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
            builder: (_, __) => const JoinOrgScreen(),
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
            path: 'live',
            builder: (_, state) =>
                LiveMatchesScreen(orgId: state.pathParameters['orgId']!),
          ),
          GoRoute(
            path: 'new-event',
            builder: (_, state) =>
                CreateCompetitionScreen(orgId: state.pathParameters['orgId']!),
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
              onPressed: () => context.go(Routes.orgs),
              child: const Text('Back to my organizations'),
            ),
          ],
        ),
      ),
    );
  }
}
