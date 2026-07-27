import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analytics/presentation/screens/analytics_dashboard_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/discovery/presentation/screens/talent_discovery_screen.dart';
import '../../features/events/presentation/screens/event_detail_screen.dart';
import '../../features/events/presentation/screens/event_list_screen.dart';
import '../../features/fixtures/presentation/screens/fixture_board_screen.dart';
import '../../features/governance/presentation/screens/government_dashboard_screen.dart';
import '../../features/live_ops/presentation/screens/live_dashboard_screen.dart';
import '../../features/members/presentation/screens/member_profile_screen.dart';
import '../../features/officials/presentation/screens/officials_directory_screen.dart';
import '../../features/organization/presentation/screens/organization_home_screen.dart';
import '../../features/registration/presentation/screens/registration_form_screen.dart';
import '../../features/venue/presentation/screens/venue_management_screen.dart';

import '../../features/events/presentation/screens/create_activity_wizard_screen.dart';
import '../../features/organization/presentation/screens/create_club_screen.dart';
import '../../features/organization/presentation/screens/join_club_screen.dart';
import '../../features/organization/presentation/screens/my_scoring_assignments_screen.dart';
import '../../features/organization/presentation/screens/org_settings_screen.dart';
import '../../features/organization/presentation/screens/participant_home_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const login = '/login';
  static const orgHome = '/org/:orgId';
  static const orgSettings = '/org/:orgId/settings';
  static const participantHome = '/org/:orgId/participant';
  static const scoringAssignments = '/org/:orgId/scoring-assignments';
  static const events = '/org/:orgId/events';
  static const createActivity = '/org/:orgId/create-activity';
  static const createClub = '/org/:orgId/create-club';
  static const joinClub = '/org/:orgId/join-club';
  static const eventDetail = '/org/:orgId/events/:eventId';
  static const registration = '/org/:orgId/events/:eventId/register';
  static const fixtures = '/org/:orgId/events/:eventId/fixtures';
  static const liveOps = '/org/:orgId/events/:eventId/live';
  static const memberProfile = '/org/:orgId/members/:memberId';
  static const analytics = '/org/:orgId/analytics';
  static const discovery = '/org/:orgId/discovery';
  static const venues = '/org/:orgId/venues';
  static const officials = '/org/:orgId/officials';
  static const governance = '/org/:orgId/governance';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/org/maram-homes', // Skip login by default
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.orgHome,
        builder: (context, state) => OrganizationHomeScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.orgSettings,
        builder: (context, state) => OrgSettingsScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.participantHome,
        builder: (context, state) => ParticipantHomeScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.scoringAssignments,
        builder: (context, state) => MyScoringAssignmentsScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.events,
        builder: (context, state) => EventListScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.createActivity,
        builder: (context, state) => CreateActivityWizardScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.createClub,
        builder: (context, state) => CreateClubScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.joinClub,
        builder: (context, state) => JoinClubScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) => EventDetailScreen(
          orgId: state.pathParameters['orgId']!,
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.registration,
        builder: (context, state) => RegistrationFormScreen(
          orgId: state.pathParameters['orgId']!,
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.fixtures,
        builder: (context, state) => FixtureBoardScreen(
          orgId: state.pathParameters['orgId']!,
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.liveOps,
        builder: (context, state) => LiveDashboardScreen(
          orgId: state.pathParameters['orgId']!,
          eventId: state.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.memberProfile,
        builder: (context, state) => MemberProfileScreen(
          orgId: state.pathParameters['orgId']!,
          memberId: state.pathParameters['memberId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.analytics,
        builder: (context, state) => AnalyticsDashboardScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (context, state) => TalentDiscoveryScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.venues,
        builder: (context, state) => VenueManagementScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.officials,
        builder: (context, state) => OfficialsDirectoryScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.governance,
        builder: (context, state) => GovernmentDashboardScreen(
          orgId: state.pathParameters['orgId']!,
        ),
      ),
    ],
  );
});
