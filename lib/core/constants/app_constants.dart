/// Global, non-environment-specific constants for PlaySphere.
class AppConstants {
  AppConstants._();

  static const String appName = 'PlaySphere';
  static const String appTagline =
      'The Event & Competition Operating System';

  static const int defaultPageSize = 20;
  static const Duration defaultTimeout = Duration(seconds: 30);
}

/// User roles as defined in the PlaySphere RBAC model (Blueprint §4).
enum UserRole {
  superAdmin,
  organizationOwner,
  organizationAdmin,
  eventManager,
  sportsCoordinator,
  judge,
  volunteer,
  captain,
  participant,
  parent,
  spectator,
}

/// High level event lifecycle stages (Blueprint §7).
enum EventStage {
  draft,
  published,
  registration,
  verification,
  teamFormation,
  scheduling,
  execution,
  results,
  awards,
  archive,
}

/// Top-level event categories (Blueprint §8).
enum EventCategory {
  sports,
  cultural,
  academic,
  community,
  corporate,
}

/// Supported fixture / bracket formats (Blueprint §11).
enum FixtureFormat {
  knockout,
  league,
  roundRobin,
  swiss,
  doubleElimination,
  custom,
}

/// Team formation strategies (Blueprint §10).
enum TeamFormationMethod {
  random,
  manual,
  aiBalanced,
  auction,
  houseWise,
  departmentWise,
}
