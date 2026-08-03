import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/career_repository.dart';
import '../data/tournament_repository.dart';
import '../data/community_repository.dart';
import '../data/competition_repository.dart';
import '../data/memory_composer.dart';
import '../data/club_file_repository.dart';
import '../data/memory_repository.dart';
import '../data/org_repository.dart';
import '../data/scoring_service.dart';
import '../data/umpire_repository.dart';
import '../domain/standings/standings_calculator.dart';
import '../domain/tournament/tournament_leaderboard.dart';
import '../domain/tournament/tournament_overview.dart';
import 'async_combine.dart';
import 'auth/auth_service.dart';
import 'models/app_user.dart';
import 'models/venue.dart';
import 'models/tournament.dart';
import 'models/challenge.dart';
import 'models/competition.dart';
import 'models/memory.dart';
import 'models/enums.dart';
import 'models/fixture.dart';
import 'models/organization.dart';
import 'models/ranking_entry.dart';
import 'models/scoring_request.dart';
import 'models/club_file.dart';
import 'models/squad_entry.dart';
import 'notifications/notification_service.dart';
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
  final uid = ref.watch(currentUidProvider);
  final service = ref.watch(notificationServiceProvider);

  if (uid == null) return;
  service.register(uid);

  ref.onDispose(() {
    // Deliberately not awaited: a provider disposal must not block, and a
    // failed unregister costs a stale token that the server prunes the first
    // time it tries to use it.
    service.unregister(uid);
  });
});

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

/// Every match across every event of one tournament.
final tournamentFixturesProvider =
    StreamProvider.family<List<Fixture>, String>((ref, tournamentId) {
  return ref.watch(tournamentRepositoryProvider).watchFixtures(tournamentId);
});

/// The derived high-level state of a tournament — progress, what is on court,
/// what is next, and who has won what.
final tournamentOverviewProvider = Provider.family<AsyncValue<TournamentOverview>,
    ({String orgId, String tournamentId})>((ref, key) {
  return combineAsync2(
    ref.watch(tournamentEventsProvider(key)),
    ref.watch(tournamentFixturesProvider(key.tournamentId)),
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
    ref.watch(tournamentFixturesProvider(key.tournamentId)),
    (events, fixtures) =>
        TournamentLeaderboard.from(events: events, fixtures: fixtures),
  );
});

/// The ranking list for one sport, summed over the rolling window.
final rankingProvider =
    StreamProvider.family<List<RankingRow>, String>((ref, sportId) {
  return ref
      .watch(tournamentRepositoryProvider)
      .watchRankingEntries(sportId: sportId)
      .map(buildRanking);
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
