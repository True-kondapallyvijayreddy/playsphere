import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_combine.dart';
import '../../core/models/challenge.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/organization.dart';
import '../../core/models/scoring_request.dart';
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

/// Everything being played right now, across every club this person is in.
final myLiveFixturesProvider = Provider<AsyncValue<List<Fixture>>>((ref) {
  final orgIds = ref.watch(myActiveOrgIdsProvider);
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  return combineAsyncAll([
    for (final id in orgIds) ref.watch(liveFixturesProvider(id)),
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
        (a, b) => _eventSortKey(b).compareTo(_eventSortKey(a)),
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

/// Sorts events by the date that matters for each one, falling back to when it
/// was created so a draft with no dates still lands somewhere sensible.
DateTime _eventSortKey(Competition c) =>
    c.startDate ?? c.registrationClosesAt ?? c.createdAt ?? DateTime(2000);
