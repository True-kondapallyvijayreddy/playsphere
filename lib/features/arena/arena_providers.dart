import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/arena_match.dart';
import '../../core/models/arena_stats.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../data/arena_repository.dart';

final arenaRepositoryProvider = Provider((ref) => const ArenaRepository());

/// Every Arena game the profile in use is part of, newest first.
///
/// One stream for the whole feature. Invitations, games in progress and
/// finished games are the same documents in three states, so they are split
/// below rather than fetched separately — which also means a game changing
/// state moves between the lists without a second round trip.
final myArenaMatchesProvider = StreamProvider<List<ArenaMatch>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(arenaRepositoryProvider).watchMyMatches(uid);
});

/// How the home screen slices that list.
class ArenaInbox {
  const ArenaInbox({
    required this.invitations,
    required this.yourMove,
    required this.theirMove,
    required this.sent,
    required this.finished,
  });

  static const empty = ArenaInbox(
    invitations: [],
    yourMove: [],
    theirMove: [],
    sent: [],
    finished: [],
  );

  /// Challenges waiting on THIS person to accept.
  final List<ArenaMatch> invitations;

  /// Live games where it is their move. The only list with a badge, because
  /// it is the only one that is actually asking for something.
  final List<ArenaMatch> yourMove;

  final List<ArenaMatch> theirMove;

  /// Challenges they sent that nobody has answered yet.
  final List<ArenaMatch> sent;

  final List<ArenaMatch> finished;

  int get waitingCount => invitations.length + yourMove.length;
  bool get isEmpty =>
      invitations.isEmpty &&
      yourMove.isEmpty &&
      theirMove.isEmpty &&
      sent.isEmpty &&
      finished.isEmpty;
}

final arenaInboxProvider = Provider<ArenaInbox>((ref) {
  final uid = ref.watch(currentUidProvider);
  final matches = ref.watch(myArenaMatchesProvider).valueOrNull;
  if (uid == null || matches == null) return ArenaInbox.empty;

  final invitations = <ArenaMatch>[];
  final yourMove = <ArenaMatch>[];
  final theirMove = <ArenaMatch>[];
  final sent = <ArenaMatch>[];
  final finished = <ArenaMatch>[];

  for (final m in matches) {
    switch (m.status) {
      case ArenaStatus.pending:
        (m.challengerUid == uid ? sent : invitations).add(m);
      case ArenaStatus.active:
        // `isTurn` replays the move list, which is why this is a Provider
        // computed once per snapshot rather than something each card works
        // out for itself while scrolling.
        (m.isTurn(uid) ? yourMove : theirMove).add(m);
      case ArenaStatus.finished:
        finished.add(m);
      case ArenaStatus.declined:
      case ArenaStatus.cancelled:
        break;
    }
  }

  return ArenaInbox(
    invitations: invitations,
    yourMove: yourMove,
    theirMove: theirMove,
    sent: sent,
    finished: finished,
  );
});

/// How many Arena things are waiting on this person — the number on the home
/// screen's Arena button.
final arenaWaitingCountProvider = Provider<int>(
  (ref) => ref.watch(arenaInboxProvider).waitingCount,
);

/// One live game.
final arenaMatchProvider =
    StreamProvider.family<ArenaMatch?, String>((ref, matchId) {
  return ref.watch(arenaRepositoryProvider).watchMatch(matchId);
});

// ---------------------------------------------------------------------------
// The ladder
// ---------------------------------------------------------------------------

/// The Arena leaderboard — a fun tally, never a rating. See [ArenaStats].
final arenaLeaderboardProvider = StreamProvider<List<ArenaStats>>(
  (ref) => ref.watch(arenaRepositoryProvider).watchLeaderboard(),
);

/// This player's own record, which they should see whether or not they are in
/// the top fifty.
final myArenaStatsProvider = StreamProvider<ArenaStats?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(arenaRepositoryProvider).watchStats(uid);
});

// ---------------------------------------------------------------------------
// Who you can challenge
// ---------------------------------------------------------------------------

/// Somebody this member may challenge, and where they know them from.
class ArenaOpponent {
  const ArenaOpponent({
    required this.uid,
    required this.displayName,
    required this.clubNames,
    this.photoUrl,
    this.orgId,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;

  /// Every club the two of them share. Plural on purpose — a member of both
  /// the school and the academy showed up twice in the list before this, once
  /// per club, which read as two different people with the same name.
  final List<String> clubNames;

  /// The club the challenge is filed under, for the label on the game. The
  /// first shared one; it is a caption, never a permission.
  final String? orgId;

  String get where => clubNames.join(' · ');
}

/// Everyone in every club this member belongs to, as one deduplicated list.
///
/// The Arena screen used to render a section per club, each capped at thirty
/// names. Two things were wrong with that. Somebody in four clubs got four
/// separate lists to hunt through, with anyone in two of them appearing twice.
/// And the cap silently hid members of any club with more than thirty people —
/// which is most schools — so "challenge anyone in your club" was not true.
///
/// One list, deduplicated, sorted by name, with the search box filtering all
/// of it at once. People outside these clubs are reachable by player code,
/// which is the other half of the answer and deliberately not a directory:
/// the app has no global people-search, and adding one to start a game of
/// chess would be the wrong trade.
final arenaOpponentsProvider = Provider<List<ArenaOpponent>>((ref) {
  final me = ref.watch(currentUidProvider);
  final memberships =
      ref.watch(myMembershipsProvider).valueOrNull ?? const <Membership>[];

  final orgIds = memberships
      .where((m) => m.status == MembershipStatus.active)
      .map((m) => m.orgId)
      .toSet();

  final byUid = <String, ArenaOpponent>{};
  for (final orgId in orgIds) {
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final members =
        ref.watch(orgMembersProvider(orgId)).valueOrNull ?? const <Membership>[];

    for (final member in members) {
      if (member.uid == me) continue;
      if (member.status != MembershipStatus.active) continue;

      final existing = byUid[member.uid];
      byUid[member.uid] = ArenaOpponent(
        uid: member.uid,
        displayName: member.displayName,
        photoUrl: member.photoUrl ?? existing?.photoUrl,
        orgId: existing?.orgId ?? orgId,
        clubNames: [
          ...?existing?.clubNames,
          org?.name ?? 'A club',
        ],
      );
    }
  }

  return byUid.values.toList()
    ..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
});
