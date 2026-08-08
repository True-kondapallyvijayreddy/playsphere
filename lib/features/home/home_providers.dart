import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_combine.dart';
import '../../core/models/challenge.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/organization.dart';
import '../../core/models/scoring_request.dart';
import '../../core/models/tournament_invite.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';

/// The clubs this person actually belongs to, most-recently-joined first.
///
/// Everything on the home dashboard fans out from this list. Pending
/// memberships are excluded on purpose: until an admin approves you, the club
/// owes you nothing and its matches are not yours to see.
final myActiveMembershipsProvider =
    Provider<AsyncValue<List<Membership>>>((ref) {
  return ref.watch(myMembershipsProvider).whenData((all) {
    final active = all.where((m) => m.isActive).toList()
      ..sort((a, b) {
        final at = a.joinedAt;
        final bt = b.joinedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    return active;
  });
});

final myActiveOrgIdsProvider = Provider<List<String>>((ref) {
  final active = ref.watch(myActiveMembershipsProvider).valueOrNull ?? const [];
  return [for (final m in active) m.orgId];
});

/// The club the global screens point their org-scoped links at.
///
/// The most recently joined one, because that is overwhelmingly the club a
/// person is currently active in — a student who joined a district academy
/// last week is not opening the app for the school club they joined in 2019.
final primaryOrgIdProvider = Provider<String?>((ref) {
  final ids = ref.watch(myActiveOrgIdsProvider);
  return ids.isEmpty ? null : ids.first;
});

/// Everything being played right now, across every club this person is in,
/// keeping whatever loaded when a club's read is refused.
///
/// Deliberately tolerant, unlike the other fan-outs on this screen. A person
/// in four clubs used to lose the entire live section — every match at every
/// club — because ONE club's collection-group read was rejected, most often a
/// membership left pointing at a club that no longer exists. The screen said
/// "Could not load live matches" and showed nothing, which is Bug #4.
///
/// The club that failed is not swallowed: it surfaces through
/// [myLiveFixtureFailuresProvider], which the dashboard renders as a notice
/// beside the matches that did load.
final myLiveFixturesPartialProvider = Provider<PartialAsync<Fixture>>((ref) {
  final orgIds = ref.watch(myActiveOrgIdsProvider);
  if (orgIds.isEmpty) {
    return const PartialAsync(items: [], failures: [], isLoading: false);
  }
  return combineAsyncTolerant([
    for (final id in orgIds) ref.watch(liveFixturesProvider(id)),
  ]);
});

/// The live matches themselves, as the rest of the app already expected them.
///
/// Reports an error only when EVERY club failed — at that point there really
/// is nothing to show and a spinner or an empty state would both be lies.
final myLiveFixturesProvider = Provider<AsyncValue<List<Fixture>>>((ref) {
  final partial = ref.watch(myLiveFixturesPartialProvider);
  if (partial.isTotalFailure) {
    return AsyncValue.error(partial.failures.first, StackTrace.empty);
  }
  if (partial.isLoading && partial.items.isEmpty) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(partial.items);
});

/// How many of this person's clubs could not be read, for the notice that
/// keeps a partial answer honest.
final myLiveFixtureFailuresProvider = Provider<int>(
  (ref) => ref.watch(myLiveFixturesPartialProvider).failures.length,
);

/// Matches your clubmates are playing right now — including at other clubs.
///
/// A member turning out for a district side or a friend's club used to
/// disappear from their own club's view entirely, because every live list is
/// scoped to one club's competitions. These are the same people, found by who
/// is on the team sheet rather than by whose competition it is.
///
/// Capped at 30 watched clubmates by Firestore's `arrayContainsAny` limit —
/// see `CompetitionRepository.watchClubmateLiveFixtures`. Matches already
/// visible through [myLiveFixturesProvider] are removed here rather than
/// shown twice.
final clubmateLiveFixturesProvider =
    StreamProvider<List<Fixture>>((ref) {
  final members = <String>{};
  for (final orgId in ref.watch(myActiveOrgIdsProvider)) {
    for (final m in ref.watch(orgMembersProvider(orgId)).valueOrNull ??
        const <Membership>[]) {
      if (m.isActive) members.add(m.uid);
    }
  }
  members.remove(ref.watch(currentUidProvider));
  if (members.isEmpty) return Stream.value(const []);

  final mine = {
    for (final f in ref.watch(myLiveFixturesProvider).valueOrNull ??
        const <Fixture>[])
      f.id,
  };

  return ref
      .watch(competitionRepositoryProvider)
      .watchClubmateLiveFixtures(memberUids: members.toList())
      .map((all) => [
            for (final f in all)
              if (!mine.contains(f.id)) f,
          ]);
});

/// Every competition across every club, newest first.
final myClubEventsProvider = Provider<AsyncValue<List<Competition>>>((ref) {
  final orgIds = ref.watch(myActiveOrgIdsProvider);
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(competitionsProvider(id)),
  ]).whenData((all) {
    final sorted = [...all]..sort(
        (a, b) => b.sortDate.compareTo(a.sortDate),
      );
    return sorted;
  });
});

/// Competitions worth showing on a dashboard: running now, or open for
/// entries, or scheduled. A completed event belongs on the club's page, not on
/// the screen that answers "what should I do today".
final myUpcomingEventsProvider = Provider<AsyncValue<List<Competition>>>((ref) {
  const wanted = {
    CompetitionStatus.inProgress,
    CompetitionStatus.registrationOpen,
    CompetitionStatus.registrationClosed,
    CompetitionStatus.scheduled,
  };
  return ref.watch(myClubEventsProvider).whenData(
        (all) => all.where((c) => wanted.contains(c.status)).toList(),
      );
});

/// Challenges from other clubs waiting on a club of this person's to answer.
///
/// Only asked of clubs where the person could actually do something about it.
/// A member with no event authority seeing "3 challenges waiting" is being
/// shown an obligation they cannot discharge.
final myIncomingChallengesProvider =
    Provider<AsyncValue<List<Challenge>>>((ref) {
  final orgIds = [
    for (final id in ref.watch(myActiveOrgIdsProvider))
      if (ref
          .watch(myCapabilitiesProvider(id))
          .contains(Capability.manageCompetitions))
        id,
  ];
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(incomingChallengesProvider(id)),
  ]);
});

/// Tournaments other clubs have invited a club of this person's into.
///
/// Gated on the same capability as challenges, and for the same reason: an
/// invitation is an offer only an organizer can answer, and a member shown
/// "2 invitations waiting" is being handed an obligation they cannot act on.
final myTournamentInvitesProvider =
    Provider<AsyncValue<List<TournamentInvite>>>((ref) {
  final orgIds = [
    for (final id in ref.watch(myActiveOrgIdsProvider))
      if (ref
          .watch(myCapabilitiesProvider(id))
          .contains(Capability.manageCompetitions))
        id,
  ];
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(incomingTournamentInvitesProvider(id)),
  ]);
});

/// People waiting to be let into a club this person administers.
///
/// Same gate as above, for the same reason — and a harder one, because the
/// pending-members query is only readable by someone who can approve them.
/// Asking it as an ordinary member is a permission error, not an empty list.
final myPendingApprovalsProvider =
    Provider<AsyncValue<List<Membership>>>((ref) {
  final orgIds = [
    for (final id in ref.watch(myActiveOrgIdsProvider))
      if (ref.watch(myCapabilitiesProvider(id)).contains(Capability.manageMembers))
        id,
  ];
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(pendingMembersProvider(id)),
  ]);
});

/// People asking to score a match at one of this person's clubs.
///
/// Gated on `manageCompetitions` for the same reason as the challenge and
/// join-request lists above: it is the capability that can actually grant the
/// request, and showing an obligation to someone who cannot discharge it is
/// worse than not showing it.
final myScoringRequestsProvider =
    Provider<AsyncValue<List<ScoringRequest>>>((ref) {
  final orgIds = [
    for (final id in ref.watch(myActiveOrgIdsProvider))
      if (ref
          .watch(myCapabilitiesProvider(id))
          .contains(Capability.manageCompetitions))
        id,
  ];
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(pendingScoringRequestsProvider(id)),
  ]);
});

/// How many things are waiting on this person, for the badge on the bell.
///
/// Counts the four action-item lists that Notifications shows rather than a
/// stored unread count, so that part of the badge cannot drift out of step
/// with the screen behind it: the number falls the moment the underlying
/// obligation is discharged, whoever discharged it and on whichever device.
///
/// Join requests count as one no matter how many people are queued, matching
/// the single "N people are waiting to join" card they collapse into.
///
/// Also folds in [unreadNotificationCountProvider] — a plain member with no
/// scoring assignment, no challenge to answer and nothing to approve used to
/// see a bell that never once lit up, no matter how much was happening at
/// their club, because every one of the counts above is gated on an
/// organizer capability they do not hold. The activity feed is not.
final waitingOnYouCountProvider = Provider<int>((ref) {
  final scoring = ref.watch(myScoringAssignmentsProvider).valueOrNull ?? const [];
  final challenges = ref.watch(myIncomingChallengesProvider).valueOrNull ?? const [];
  final approvals = ref.watch(myPendingApprovalsProvider).valueOrNull ?? const [];
  final scoreAsks = ref.watch(myScoringRequestsProvider).valueOrNull ?? const [];
  final invites = ref.watch(myTournamentInvitesProvider).valueOrNull ?? const [];
  final unreadActivity = ref.watch(unreadNotificationCountProvider);

  return scoring.length +
      challenges.length +
      scoreAsks.length +
      invites.length +
      (approvals.isEmpty ? 0 : 1) +
      unreadActivity;
});

