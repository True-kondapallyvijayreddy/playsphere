import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/career_repository.dart';
import '../data/community_repository.dart';
import '../data/competition_repository.dart';
import '../data/memory_composer.dart';
import '../data/memory_repository.dart';
import '../data/org_repository.dart';
import '../data/scoring_service.dart';
import '../data/umpire_repository.dart';
import '../domain/standings/standings_calculator.dart';
import 'async_combine.dart';
import 'auth/auth_service.dart';
import 'models/app_user.dart';
import 'models/challenge.dart';
import 'models/competition.dart';
import 'models/memory.dart';
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
final communityRepositoryProvider =
    Provider((ref) => const CommunityRepository());
final umpireRepositoryProvider = Provider((ref) => const UmpireRepository());

/// Queued scoring events not yet confirmed by the server.
///
/// A provider rather than a `StreamBuilder` over the getter, because the getter
/// returns a fresh stream on every access — reading it inside `build` would
/// resubscribe on each rebuild.
final pendingScoreEventsProvider = StreamProvider<int>(
  (ref) => ref.watch(scoringServiceProvider).pendingCountStream,
);

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

/// Every sport a player has a record in, most-played first.
final careerProvider =
    StreamProvider.family<List<CareerLine>, String>((ref, uid) {
  return ref.watch(careerRepositoryProvider).watchCareer(uid);
});

// NOTE — the Cross-Sport Index (§8.2) is deliberately NOT wired here.
//
// `CrossSportIndex.compute` needs a `SportPopulation` per sport: every rated
// player's rating in that sport, to turn a raw Glicko number into a percentile.
// The client cannot obtain that. A `ratings` document stores only
// rating/deviation/volatility/gamesPlayed — `firestore.rules` enforces exactly
// those keys with `hasOnly`, so there is no `sportId` field to query a
// collectionGroup by, and reading every rating on the platform to compute a
// percentile is precisely the unbounded read pattern being removed elsewhere.
//
// Without a population, `percentileOf` returns 50 for everybody and the index
// collapses to a constant. Surfacing that as a headline "Sports OS Index" would
// be a fabricated number on a player's profile, which is worse than an absent
// one. It needs a scheduled aggregate (a per-sport rating histogram document)
// on the server tier — see the deferred Cloud Functions work. The engine and
// its tests are correct and stay ready for that.

/// Memories a player is tagged in, newest first.
final playerMemoriesProvider =
    StreamProvider.family<List<Memory>, String>((ref, uid) {
  return ref.watch(memoryRepositoryProvider).watchPlayerMemories(uid);
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
