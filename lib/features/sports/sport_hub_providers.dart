import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/coach.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/ground.dart';
import '../../core/models/organization.dart';
import '../../core/models/sponsorship.dart';
import '../../core/models/team.dart';
import '../../core/providers.dart';
import '../../data/scout_repository.dart';
import '../../domain/scoring/scoring_registry.dart';

/// Everything about ONE sport, drawn from what the platform already knows.
///
/// ## Why these are derivations and not new collections
///
/// The obvious way to build a sport hub is to denormalise: put a `sportIds`
/// array on every club, every player and every ground, and query it. Three of
/// those already exist and would be wrong:
///
///  * A club does not HAVE a sport. It has members who play several, and the
///    honest answer to "is this a cricket club" is "does it run cricket". That
///    is derivable from its competitions and cannot go stale, where a manually
///    maintained `sportIds` on the club would be wrong the day a school adds
///    volleyball and nobody edits the club.
///  * A player's sports are the sports they have actually played, which the
///    career rollup already computes.
///  * A ground genuinely does have fixed `sportIds` — a turf pitch is a turf
///    pitch — so that one IS a stored field, and is queried as one.
///
/// The rule the hub follows everywhere: **only what is active in this sport**,
/// never the whole platform filtered down to nothing.

/// Every open event on the platform for this sport.
final sportEventsProvider =
    Provider.family<AsyncValue<List<Competition>>, String>((ref, sportId) {
  return ref.watch(globalEventsProvider).whenData(
        (all) => [
          for (final c in all)
            if (c.sportId == sportId) c,
        ]..sort((a, b) {
            final x = a.startDate;
            final y = b.startDate;
            if (x == null || y == null) return 0;
            return x.compareTo(y);
          }),
      );
});

/// Clubs that actually run this sport.
///
/// Derived from the events above rather than from a field on the club, for
/// the reason given at the top of this file. A club appears here because it
/// is putting cricket on — which is exactly what someone browsing cricket
/// wants to know, and is self-maintaining.
final sportClubsProvider =
    Provider.family<AsyncValue<List<Organization>>, String>((ref, sportId) {
  final events = ref.watch(sportEventsProvider(sportId));
  final orgs = ref.watch(publicOrgsProvider);
  if (events.isLoading || orgs.isLoading) return const AsyncValue.loading();

  final activeOrgIds = {
    for (final c in events.valueOrNull ?? const <Competition>[]) c.orgId,
  };
  return AsyncValue.data([
    for (final o in orgs.valueOrNull ?? const <Organization>[])
      if (activeOrgIds.contains(o.id)) o,
  ]);
});

/// Matches being played in this sport right now, across every club running it.
///
/// Scoped to the clubs found above rather than queried platform-wide: a
/// collection-group read of every live fixture would be refused for the
/// unlisted clubs among them, and would grow without bound as the platform
/// does. Capped for the same reason.
final sportLiveProvider =
    Provider.family<AsyncValue<List<Fixture>>, String>((ref, sportId) {
  final clubs = ref.watch(sportClubsProvider(sportId));
  final ids = [for (final o in clubs.valueOrNull ?? const <Organization>[]) o.id]
      .take(_maxClubsWatched)
      .toList();
  if (ids.isEmpty) return const AsyncValue.data([]);

  final live = <Fixture>[];
  for (final id in ids) {
    for (final f in ref.watch(liveFixturesProvider(id)).valueOrNull ??
        const <Fixture>[]) {
      if (f.sportId == sportId) live.add(f);
    }
  }
  return AsyncValue.data(live);
});

/// One listener per club is a real cost, and a popular sport could otherwise
/// open dozens on a screen somebody is only browsing.
const _maxClubsWatched = 12;

/// Grounds that serve this sport.
///
/// The one genuinely stored relationship, and `GroundRepository.searchGrounds`
/// already answers exactly this question — "no words, but a sport" is a case
/// it was written for. A future rather than a stream on purpose: browsing
/// grounds is something a person does once by pressing a button, not
/// something they sit watching.
final sportGroundsProvider =
    FutureProvider.family<List<Ground>, String>((ref, sportId) {
  return ref
      .read(groundRepositoryProvider)
      .searchGrounds(sportId: sportId, limit: 20);
});

/// The platform-wide rollup row for this sport — tournaments, teams, players.
/// Nightly, and labelled as such wherever it is shown.
final sportStatRowProvider = Provider.family((ref, String sportId) {
  return ref.watch(sportStatsProvider).whenData((rows) => rows[sportId]);
});

/// Tournaments, as distinct from ordinary events: the multi-stage ones a
/// browser is looking for when they ask what is on.
final sportTournamentsProvider =
    Provider.family<AsyncValue<List<Competition>>, String>((ref, sportId) {
  return ref.watch(sportEventsProvider(sportId)).whenData(
        (all) => [
          for (final c in all)
            if (c.format != CompetitionFormat.singleMatch) c,
        ],
      );
});

/// Squads playing this sport — the club sides and the independent ones.
///
/// ## Two halves, because they are reachable in two different ways
///
/// A club team is found through the clubs already established as running
/// this sport, the same fan-out [sportLiveProvider] uses.
///
/// An independent team has no club to be found through, and for a while this
/// provider claimed that made it unreachable from the client and left it to
/// `functions/sports.js`. That was wrong, and worth spelling out because the
/// same reasoning is correct one line above. A FIXTURE really cannot be
/// queried platform-wide: `firestore.rules` gates it on
/// `orgIsReadable(orgId)`, a per-document condition, and Firestore fails a
/// whole list containing one document it must refuse. `/teams/{teamId}` has
/// no such condition — it is a flat `allow read: if isSignedIn()` — so
/// "every independent cricket team" is a perfectly ordinary indexed query,
/// and it has been available all along. See [Refs.independentTeamsForSport].
final sportTeamsProvider =
    Provider.family<AsyncValue<List<Team>>, String>((ref, sportId) {
  final clubs = ref.watch(sportClubsProvider(sportId));
  if (clubs.isLoading) return const AsyncValue.loading();

  // Not an early return when no club runs this sport, unlike the live
  // provider: the independent teams below have nothing to do with clubs, and
  // bailing out here would hide every one of them in exactly the sport where
  // they are the only teams there are.
  final ids = [for (final o in clubs.valueOrNull ?? const <Organization>[]) o.id]
      .take(_maxClubsWatched)
      .toList();

  final teams = <Team>[];
  for (final id in ids) {
    for (final t in ref.watch(clubTeamsProvider(id)).valueOrNull ??
        const <Team>[]) {
      // Archived squads are history, not discovery. An event team is a
      // one-tournament roster and would swamp the standing clubs.
      if (t.sportId == sportId && t.status == TeamStatus.active) teams.add(t);
    }
  }
  // The half with no club behind it. Its own query already pins the sport,
  // the type and the status, so nothing needs filtering here.
  teams.addAll(
    ref.watch(independentTeamsProvider(sportId)).valueOrNull ?? const <Team>[],
  );
  teams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return AsyncValue.data(teams);
});

/// Sponsorship on offer in this sport — the marketplace already filters on
/// `sport`, so this is that query with the hub's sport pinned rather than
/// anything new.
final sportSponsorshipsProvider =
    StreamProvider.family<List<SponsorshipListing>, String>((ref, sportId) {
  return ref.watch(sponsorRepositoryProvider).watchListings(sport: sportId);
});

/// Coaches who teach this sport.
///
/// The one list on the hub that is a plain indexed query rather than a
/// derivation. A coach genuinely declares their sports — unlike a club,
/// which has members who play several and no honest single answer — so
/// `sportIds` is a stored field here and is queried as one. See
/// `CoachProfile` for why that is not the same mistake as a `sportIds` on a
/// club, and why an empty list means "listed nothing" rather than "coaches
/// everything".
final sportCoachesProvider =
    StreamProvider.family<List<CoachProfile>, String>((ref, sportId) {
  return ref.watch(coachRepositoryProvider).watchCoachesForSport(sportId);
});

/// The stats this sport keeps a ranking board for — runs and wickets in
/// cricket, raid and tackle points in kabaddi, goals in football.
///
/// An empty list is a real answer rather than a fallback to some generic
/// key: a board headed by a stat the sport does not keep is worse than no
/// board, so a plugin that publishes none gets no rankings section at all.
List<String> sportHeadlineStats(String sportId) =>
    ScoringRegistry.forSport(sportId).headlineStats;

/// The players actually playing this sport, most recently active first.
///
/// This is the one list on the hub that could not be derived from clubs.
/// A player belongs to the sport because they have a `career_stats` row in
/// it, which is written when a match they played is settled — so the list is
/// exactly "who has been playing cricket", and it stays true without anybody
/// maintaining a profile field.
///
/// Every candidate has already cleared `firestore.rules` on its own user
/// document by the time [ScoutRepository.searchCandidates] returns it, so
/// this is safe to show a browser: a minor with no consent record for this
/// reader, and an adult who kept their profile private, are dropped by the
/// database rather than filtered out here. A signed-out visitor cannot read
/// `career_stats` at all and sees the empty state — correct, not an error.
///
/// One-shot, and small. The scout search fetches 60 candidates because a
/// scout is filtering them; the hub shows four, so it pays for twelve — the
/// per-candidate profile read is what costs, and every one over the four
/// displayed is only there so a private profile among them does not leave a
/// hole in the list.
final sportPlayersProvider =
    FutureProvider.family<List<ScoutSearchResult>, String>((ref, sportId) {
  return ref
      .read(scoutRepositoryProvider)
      .searchCandidates(sportId: sportId, limit: 12);
});

/// One club's last few results in this sport.
final _orgSportResultsProvider = StreamProvider.family<List<Fixture>,
    ({String orgId, String sportId})>((ref, key) {
  return ref
      .watch(careerRepositoryProvider)
      .watchOrgSportResults(key.orgId, key.sportId);
});

/// What has finished in this sport lately, across the clubs running it.
///
/// The counterpart to [sportLiveProvider], scoped the same way and for the
/// same reason — a platform-wide query over completed fixtures is not
/// authorizable, because `firestore.rules` opens a fixture only to a
/// readable club or to somebody named on it, and Firestore fails a list
/// containing one document it must refuse rather than trimming it.
///
/// Watched over fewer clubs than live is. A live match is the reason
/// somebody opened this screen; a result from last Tuesday is not worth a
/// twelfth listener.
final sportResultsProvider =
    Provider.family<AsyncValue<List<Fixture>>, String>((ref, sportId) {
  final clubs = ref.watch(sportClubsProvider(sportId));
  if (clubs.isLoading) return const AsyncValue.loading();

  final ids = [for (final o in clubs.valueOrNull ?? const <Organization>[]) o.id]
      .take(_maxClubsForResults)
      .toList();
  if (ids.isEmpty) return const AsyncValue.data([]);

  final results = <Fixture>[];
  for (final id in ids) {
    results.addAll(
      ref
              .watch(_orgSportResultsProvider((orgId: id, sportId: sportId)))
              .valueOrNull ??
          const <Fixture>[],
    );
  }
  results.sort((a, b) {
    final x = a.completedAt;
    final y = b.completedAt;
    if (x == null || y == null) return 0;
    return y.compareTo(x);
  });
  return AsyncValue.data(results);
});

const _maxClubsForResults = 6;
