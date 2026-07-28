import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/competition_repository.dart';
import '../data/org_repository.dart';
import '../data/scoring_service.dart';
import 'auth/auth_service.dart';
import 'models/app_user.dart';
import 'models/competition.dart';
import 'models/enums.dart';
import 'models/fixture.dart';
import 'models/organization.dart';
import 'permissions/capability.dart';

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final userRepositoryProvider = Provider((ref) => const UserRepository());
final orgRepositoryProvider = Provider((ref) => const OrgRepository());
final competitionRepositoryProvider =
    Provider((ref) => const CompetitionRepository());
final scoringServiceProvider = Provider((ref) => ScoringService());

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// The single source of truth for "is anyone signed in".
final authStateProvider = StreamProvider<fb.User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

final currentUidProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
);

/// The signed-in user's PlaySphere profile, which is a different thing from
/// their Firebase auth record: Google gives us a name and an email, but the
/// date of birth that every age rule depends on only exists here.
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

// ---------------------------------------------------------------------------
// Organizations
// ---------------------------------------------------------------------------

final myMembershipsProvider = StreamProvider<List<Membership>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(orgRepositoryProvider).watchMyMemberships(uid);
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
  return PermissionMatrix.capabilitiesOf(membership.role);
});

final orgMembersProvider =
    StreamProvider.family<List<Membership>, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watchMembers(orgId);
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

final fixturesProvider =
    StreamProvider.family<List<Fixture>, CompRef>((ref, key) {
  return ref
      .watch(competitionRepositoryProvider)
      .watchFixtures(key.orgId, key.compId);
});

final fixtureProvider =
    StreamProvider.family<Fixture?, FixtureRef>((ref, key) {
  return ref
      .watch(scoringServiceProvider)
      .watchFixture(key.orgId, key.compId, key.fixtureId);
});

final matchEventsProvider =
    StreamProvider.family<List<MatchEvent>, FixtureRef>((ref, key) {
  return ref
      .watch(scoringServiceProvider)
      .watchEvents(key.orgId, key.compId, key.fixtureId);
});

/// Everything currently being played in an organization — the screen a remote
/// spectator opens first.
final liveFixturesProvider =
    StreamProvider.family<List<Fixture>, String>((ref, orgId) {
  return ref.watch(competitionRepositoryProvider).watchLiveFixtures(orgId);
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
