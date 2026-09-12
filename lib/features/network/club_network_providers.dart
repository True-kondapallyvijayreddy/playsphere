import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/club_thread.dart';
import '../../core/models/organization.dart';
import '../../core/models/tournament.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../data/club_network_repository.dart';
import '../../data/discovery_repository.dart';
import '../home/home_providers.dart';
import '../sports/sport_hub_providers.dart';

final clubNetworkRepositoryProvider =
    Provider((ref) => const ClubNetworkRepository());

/// The clubs the signed-in person OWNS.
///
/// Owners, not admins. The network is where a club commits itself to another
/// club's season, which is the same class of decision as accepting a
/// challenge — see `firestore.rules`, which draws the line in the same place
/// and is the half that actually holds.
final myOwnedOrgIdsProvider = Provider<List<String>>((ref) {
  return [
    for (final id in ref.watch(myActiveOrgIdsProvider))
      if (ref
          .watch(myCapabilitiesProvider(id))
          .contains(Capability.manageOrganization))
        id,
  ];
});

/// Which of the owner's clubs the network is being used AS.
///
/// Most owners run one club and never see this; the ones who run several are
/// exactly the people this feature is for — a district association secretary
/// with three member clubs writes to a school as the association, not as
/// whichever club happened to sort first. Null means "not chosen yet", which
/// [actingClubIdProvider] resolves to the first owned club.
final actingClubOverrideProvider = StateProvider<String?>((ref) => null);

/// The club the network screens act as.
final actingClubIdProvider = Provider<String?>((ref) {
  final owned = ref.watch(myOwnedOrgIdsProvider);
  if (owned.isEmpty) return null;
  final chosen = ref.watch(actingClubOverrideProvider);
  if (chosen != null && owned.contains(chosen)) return chosen;
  return owned.first;
});

/// The acting club's own document — what the composer needs in order to write
/// a thread's denormalized name and crest, and what the plan gate reads.
final actingClubProvider = Provider<Organization?>((ref) {
  final id = ref.watch(actingClubIdProvider);
  if (id == null) return null;
  return ref.watch(organizationProvider(id)).valueOrNull;
});

/// Whether the acting club's plan entitles it to open new conversations.
///
/// Reading a thread and replying inside one never depend on this — see
/// `ClubNetworkRepository`. Only the first message to a club this one has
/// never spoken to does.
final canOpenNewClubThreadsProvider = Provider<bool>((ref) {
  final club = ref.watch(actingClubProvider);
  return club != null && club.hasPaidPlanAt(DateTime.now());
});

/// Every conversation the acting club is part of.
final clubThreadsProvider = StreamProvider<List<ClubThread>>((ref) {
  final orgId = ref.watch(actingClubIdProvider);
  if (orgId == null) return Stream.value(const []);
  return ref.watch(clubNetworkRepositoryProvider).watchThreads(orgId);
});

/// How many conversations have something waiting for the acting club. Drives
/// the badge on the inbox tab, and nothing else.
final unreadClubThreadCountProvider = Provider<int>((ref) {
  final threads = ref.watch(clubThreadsProvider).valueOrNull ?? const [];
  return threads.where((t) => t.isUnread).length;
});

/// One club's own row for one conversation. Null until the first message
/// creates it — see `ClubThreadScreen`, which renders a working composer
/// against exactly that state.
///
/// Keyed on the club as well as the conversation rather than reading
/// [actingClubIdProvider] itself. A thread opened from a link names its two
/// clubs in its id, and the side the reader is on is whichever of the two
/// they own — which is not always the club the network screen last had
/// selected. Passing it in means the row read and the messages shown can
/// never be two different clubs' views of the same conversation.
typedef ClubThreadKey = ({String orgId, String threadId});

final clubThreadProvider =
    StreamProvider.family<ClubThread?, ClubThreadKey>((ref, key) {
  return ref
      .watch(clubNetworkRepositoryProvider)
      .watchThread(orgId: key.orgId, threadId: key.threadId);
});

final clubThreadMessagesProvider =
    StreamProvider.family<List<ClubMessage>, String>((ref, threadId) {
  return ref.watch(clubNetworkRepositoryProvider).watchMessages(threadId);
});

// ---------------------------------------------------------------------------
// The directory
// ---------------------------------------------------------------------------

/// What the club directory is currently asking for.
///
/// Its own state rather than the discovery screen's [discoveryFiltersProvider].
/// The two screens answer different questions — "where can I play?" and "who
/// can we fixture?" — and a sport picked in one has no business narrowing the
/// other. What IS shared is the machinery underneath: the same
/// [DiscoveryFilters] shape, the same bounded page of public clubs, and the
/// same pure `filterClubs`, so the two can never disagree about whether a club
/// is in Warangal.
final clubDirectoryFiltersProvider =
    StateProvider<DiscoveryFilters>((ref) => DiscoveryFilters.none);

final _directoryClubsProvider = StreamProvider.autoDispose<List<Organization>>(
  (ref) => ref.watch(discoveryRepositoryProvider).watchPublicClubs(),
);

/// Public clubs matching the directory filters, minus the ones this person
/// already owns — a club cannot fixture itself, and offering the owner their
/// own crest as somebody to write to reads as a bug.
final clubDirectoryProvider = Provider<AsyncValue<List<Organization>>>((ref) {
  final filters = ref.watch(clubDirectoryFiltersProvider);
  final mine = ref.watch(myOwnedOrgIdsProvider).toSet();

  Set<String>? sportOrgIds;
  final sportId = filters.sportId;
  if (sportId != null) {
    final clubs = ref.watch(sportClubsProvider(sportId));
    if (clubs.isLoading) return const AsyncValue.loading();
    sportOrgIds = {
      for (final o in clubs.valueOrNull ?? const <Organization>[]) o.id,
    };
  }

  return ref.watch(_directoryClubsProvider).whenData((all) {
    final hits = ref.watch(discoveryRepositoryProvider).filterClubs(
          all,
          filters,
          sportOrgIds: sportOrgIds,
        );
    return [
      for (final club in hits)
        if (!mine.contains(club.id)) club,
    ];
  });
});

/// The acting club's own district, for seeding the filters the first time.
///
/// A club owner looking for fixtures almost always starts with "who is near
/// us", and the club already said where it is when it was created. Opening on
/// an answer beats opening on an empty form.
final actingClubDistrictProvider = Provider<String?>((ref) {
  final club = ref.watch(actingClubProvider);
  final district = (club?.geo.district ?? club?.district)?.trim();
  if (district != null && district.isNotEmpty) return district;
  final city = club?.city?.trim();
  return city == null || city.isEmpty ? null : city;
});

/// The seasons the acting club could put in front of another club.
///
/// Drafts and cancelled seasons are deliberately excluded: a draft is a season
/// whose organizer has not decided it is real yet, and a club invited into
/// either would open a page it cannot enter. Finished seasons stay in, because
/// "look at what we ran last year" is a real and useful thing to send to a
/// club you are asking to join the next one.
final shareableSeasonsProvider = Provider<List<Tournament>>((ref) {
  final orgId = ref.watch(actingClubIdProvider);
  if (orgId == null) return const [];
  final seasons = ref.watch(tournamentsProvider(orgId)).valueOrNull ?? const [];
  return [
    for (final t in seasons)
      if (t.status != TournamentStatus.draft &&
          t.status != TournamentStatus.cancelled)
        t,
  ];
});
