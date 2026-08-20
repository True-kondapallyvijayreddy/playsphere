import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_combine.dart';
import '../../core/models/challenge.dart';
import '../../core/models/announcement.dart';
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

/// The clubs whose events belong on this person's dashboard: the ones they
/// are in, plus the ones they follow.
///
/// Following is a reader's relationship — it is a request for exactly this,
/// a club's news on your own home screen, and it is the only thing following
/// does. A club is listed once even if both apply, because a member who also
/// followed would otherwise see every event twice.
final myFeedOrgIdsProvider = Provider<List<String>>((ref) {
  final mine = ref.watch(myActiveOrgIdsProvider);
  final followed = ref.watch(myFollowedOrgIdsProvider).valueOrNull ?? const [];
  // Membership first, so the dashboard still leads with your own clubs.
  return <String>{...mine, ...followed}.toList();
});

/// Every competition across every club on the feed, newest first.
final myClubEventsProvider = Provider<AsyncValue<List<Competition>>>((ref) {
  final orgIds = ref.watch(myFeedOrgIdsProvider);
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



// --- Match availability calls ------------------------------------------------

/// One club's live match calls. Members only — see [myMatchRsvpsProvider].
final matchRsvpsProvider =
    StreamProvider.family<List<Announcement>, String>((ref, orgId) {
  return ref.watch(communityRepositoryProvider).watchMatchRsvps(orgId);
});

/// The discussion under one match call.
///
/// A record rather than two positional args so the family key compares by
/// value — a positional tuple of two strings would work, but a named record
/// reads at the call site, which is where the mistake of swapping an orgId
/// and an announcementId would otherwise be invisible.
///
/// Only ever watched while the thread is expanded. Subscribing on behalf of
/// every collapsed card in the feed would open one listener per club match
/// for a thread nobody has opened.
final matchCommentsProvider = StreamProvider.family<List<MatchChatMessage>,
    ({String orgId, String announcementId})>((ref, key) {
  return ref.watch(communityRepositoryProvider).watchMatchComments(
        orgId: key.orgId,
        announcementId: key.announcementId,
      );
});

/// Every live match call across the clubs this person actually belongs to,
/// newest first.
///
/// ## Why membership and not the feed list
///
/// Every other list on this screen is built from [myFeedOrgIdsProvider], which
/// includes clubs the person merely FOLLOWS — right for a public notice about
/// a tournament, wrong for this. "Who is free on Sunday" is addressed to a
/// squad, and answering it commits you to turning up. Showing it to a follower
/// invites a stranger to a club's internal game and puts a name on the team
/// sheet that the organizer never expected; it is also the honest reading of
/// the request that these are for members.
///
/// So this is [myActiveOrgIdsProvider] — active membership, nothing else. No
/// capability gate: unlike a challenge or a join request, a match call is
/// aimed at the ordinary member, and they are exactly who must see it.
final myMatchRsvpsProvider =
    Provider<AsyncValue<List<Announcement>>>((ref) {
  final orgIds = ref.watch(myActiveOrgIdsProvider);
  if (orgIds.isEmpty) return const AsyncValue.data([]);
  final combined = combineAsyncAll([
    for (final id in orgIds) ref.watch(matchRsvpsProvider(id)),
  ]);
  return combined.whenData((all) {
    // Soonest kick-off first, NOT newest posted first.
    //
    // The two disagree exactly when they matter most: an organizer posting on
    // Friday about next month's fixture would otherwise bury the call for
    // tomorrow morning that went up on Tuesday. What a member needs at the top
    // is the match they have to answer first.
    final sorted = [...all]..sort((a, b) {
      final x = a.match?.matchDate;
      final y = b.match?.matchDate;
      if (x == null || y == null) return 0;
      return x.compareTo(y);
    });
    return sorted;
  });
});

/// A match this person has said they are In for, that overlaps another.
///
/// ## What counts as a clash
///
/// Two calls whose kick-offs are within [kClashWindow] of each other. Not an
/// exact-time comparison: club matches are called for "6pm" and last two
/// hours, and a person who has promised to be at one ground at 6 and another
/// at 7 has a problem that an equality test would never notice.
///
/// Only ever between two YESES. A maybe is not a promise, and warning somebody
/// off a match they have not committed to is how a useful alert becomes one
/// people learn to dismiss.
const Duration kClashWindow = Duration(hours: 3);

/// Whether [candidate] would clash with something [uid] has already said yes
/// to, given every call they can see.
///
/// Pure and synchronous so the card, the vote-time dialog and the test all ask
/// the same question of the same function.
List<Announcement> clashesFor({
  required Announcement candidate,
  required Iterable<Announcement> against,
  required String uid,
}) {
  final when = candidate.match?.matchDate;
  if (when == null) return const [];
  return [
    for (final other in against)
      if (other.id != candidate.id &&
          other.poll?.voteOf(uid) == Rsvp.yes &&
          other.match != null &&
          _overlaps(when, other.match!.matchDate))
        other,
  ];
}

bool _overlaps(DateTime a, DateTime b) =>
    a.difference(b).abs() < kClashWindow;

/// The clashes among the calls this person has ALREADY accepted — two yeses at
/// the same hour, however they got there.
///
/// Separate from [clashesFor] because it answers a different question. That
/// one is asked before a vote ("would this clash?"); this one is asked by the
/// feed afterwards ("does anything I have agreed to clash?"), and has to keep
/// reporting a clash that was created by the OTHER organizer moving their
/// fixture on top of one this person had already accepted.
final myRsvpClashesProvider = Provider<Map<String, List<Announcement>>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final calls = ref.watch(myMatchRsvpsProvider).valueOrNull ?? const [];
  if (uid == null) return const {};
  final mine = [
    for (final a in calls)
      if (a.poll?.voteOf(uid) == Rsvp.yes) a,
  ];
  return {
    for (final a in mine)
      if (clashesFor(candidate: a, against: mine, uid: uid)
          case final hits when hits.isNotEmpty)
        a.id: hits,
  };
});
