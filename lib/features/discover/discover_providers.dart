import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/organization.dart';
import '../../core/models/player_listing.dart';
import '../../core/providers.dart';
import '../../data/discovery_repository.dart';
import '../sports/sport_hub_providers.dart';

/// What the discovery screen is currently asking for.
///
/// One provider for both tabs, deliberately. Somebody who has typed
/// "Warangal" and picked cricket to look for a club is asking the same
/// question of people, and making them retype it on the second tab is the
/// kind of friction that ends a session.
final discoveryFiltersProvider =
    StateProvider<DiscoveryFilters>((ref) => DiscoveryFilters.none);

/// The searcher's own district, for seeding the filters the first time.
///
/// Somebody who has already said where they play should not have to type it
/// again to find anything; somebody who has not gets an unfiltered browse,
/// which is the right default for a person who has just arrived and does not
/// yet know what their district is called.
final discoveryHomeDistrictProvider = Provider<String?>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  final district = me?.geo.district?.trim();
  return district == null || district.isEmpty ? null : district;
});

/// One bounded page of public clubs, unfiltered.
///
/// Nothing on the discovery screen is expressible as a Firestore constraint —
/// see `DiscoveryRepository.watchPublicClubs` — so this listener is opened
/// once and every filter is applied over it. Keying it on the filters would
/// tear down and rebuild a snapshot listener on each keystroke.
final _publicClubsProvider = StreamProvider.autoDispose<List<Organization>>(
  (ref) => ref.watch(discoveryRepositoryProvider).watchPublicClubs(),
);

/// Public clubs matching the current filters.
///
/// The sport filter is applied by intersecting with `sportClubsProvider`,
/// which derives "clubs that run this sport" from the competitions they are
/// actually putting on rather than from a field on the club — see that
/// provider's own reasoning. Reused rather than reimplemented so the sport
/// hub and this screen can never disagree about whether a club plays cricket.
final discoverClubsProvider = Provider<AsyncValue<List<Organization>>>((ref) {
  final filters = ref.watch(discoveryFiltersProvider);
  final sportId = filters.sportId;

  Set<String>? sportOrgIds;
  if (sportId != null) {
    final clubs = ref.watch(sportClubsProvider(sportId));
    if (clubs.isLoading) return const AsyncValue.loading();
    sportOrgIds = {
      for (final o in clubs.valueOrNull ?? const <Organization>[]) o.id,
    };
  }

  return ref.watch(_publicClubsProvider).whenData(
        (all) => ref.watch(discoveryRepositoryProvider).filterClubs(
              all,
              filters,
              sportOrgIds: sportOrgIds,
            ),
      );
});

/// The directory read, keyed on the half of the filters Firestore sees.
///
/// A future rather than a stream: a directory search is a question somebody
/// asked once, and holding nine geohash listeners open on a phone while they
/// read the answers buys nothing.
final _playerFetchProvider =
    FutureProvider.autoDispose.family<List<PlayerListing>, DiscoveryQuery>(
  (ref, query) => ref.watch(discoveryRepositoryProvider).fetchPlayers(query),
);

/// People in the directory matching the current filters.
///
/// Two layers on purpose. The fetch above re-runs when a district or a sport
/// changes; this one re-runs on every keystroke and never touches the
/// network. See [DiscoveryFilters.serverQuery].
final discoverPlayersProvider =
    Provider.autoDispose<AsyncValue<List<PlayerNearby>>>((ref) {
  final filters = ref.watch(discoveryFiltersProvider);
  return ref.watch(_playerFetchProvider(filters.serverQuery)).whenData(
        (listings) =>
            ref.watch(discoveryRepositoryProvider).rankPlayers(listings, filters),
      );
});

/// Re-runs the directory read behind the current filters — what a retry or a
/// pull-to-refresh needs, since the screen only holds the derived provider.
void refreshDiscoverPlayers(WidgetRef ref) {
  ref.invalidate(_playerFetchProvider(
    ref.read(discoveryFiltersProvider).serverQuery,
  ));
}
