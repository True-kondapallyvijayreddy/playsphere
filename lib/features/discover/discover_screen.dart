import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/player_listing.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/discovery_repository.dart';
import '../../domain/gov/age_group.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/location_fields.dart';
import '../../shared/premium_gate.dart';
import '../../shared/ui_kit.dart';
import 'discover_providers.dart';

/// "I'm new here." The screen for somebody with no club, no code and nobody
/// to ask for one.
///
/// ## Why this had to exist
///
/// Every other way into this product runs through somebody who is already
/// inside it: an invite code read out in a WhatsApp group, a QR on a
/// noticeboard, a coach who adds you. That is the right primary path and it
/// stays the primary path. But a player who moves from Hyderabad to Delhi —
/// the exact person CLAUDE.md §1 describes, whose portable career is the
/// product's founding promise — arrives in Delhi knowing nobody, and the
/// portable career is worth nothing if there is no way to find a club to use
/// it in. Before this screen the only answer the app had for them was "ask
/// someone for a code", which is precisely what they cannot do.
///
/// ## Two tabs, because there are two questions
///
/// **Clubs** is the one that matters most and is deliberately free for
/// everyone, including the people it is for. Gating "find a club" behind a
/// subscription would gate participation itself, which the Premium screen's
/// own doc says the product will not do.
///
/// **People** is the directory — opt-in, adults only, and the surface where
/// Premium buys reach. See [PlayerListing] for what is published and by whom.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.initialTab = 0});

  /// 0 = clubs, 1 = people. The More menu points at both.
  final int initialTab;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  final _query = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  /// Puts the searcher's own district in the box the first time, so the
  /// screen opens on an answer rather than on an empty form.
  ///
  /// [home] is WATCHED by the caller rather than read here, and that is the
  /// whole subtlety: the profile arrives over a stream, so on the first frame
  /// there is no district to seed with. A `ref.read` sees null, and nothing
  /// this screen watches changes when the profile lands — so the seed would
  /// never happen on a real device, only in a test that had the profile ready
  /// synchronously. Watching means this runs again the frame the profile
  /// resolves.
  ///
  /// Done once, and only when nothing has been typed — re-seeding would fight
  /// somebody clearing the box on purpose.
  void _seedFromProfile(String? home) {
    if (_seeded || home == null) return;
    _seeded = true;
    // Deferred: this writes provider state, and a write during build is a
    // build that depends on its own outcome.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(discoveryFiltersProvider.notifier);
      if (notifier.state.district == null) {
        notifier.state = notifier.state.copyWith(district: home);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _seedFromProfile(ref.watch(discoveryHomeDistrictProvider));

    return AppScaffold(
      title: 'Find your people',
      subtitle: 'Clubs and players near you',
      body: Column(
        children: [
          ContentBounds(
            maxWidth: 820,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PsSearchField(
                  hint: 'Search by name',
                  controller: _query,
                  onChanged: (v) => ref
                      .read(discoveryFiltersProvider.notifier)
                      .update((f) => f.copyWith(query: v)),
                ),
                const SizedBox(height: 10),
                _FilterBar(showPeopleFilters: _tabs.index == 1),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            onTap: (_) => setState(() {}),
            tabs: const [
              Tab(text: 'Clubs'),
              Tab(text: 'People'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _ClubResults(),
                _PeopleResults(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Place, sport and — on the people tab — age, intent and gender.
///
/// A row of controls rather than a sheet behind a button. Every one of these
/// changes the answer materially, and a newcomer who does not yet know what
/// the product can filter by will not go looking for a sheet to find out.
class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar({required this.showPeopleFilters});

  final bool showPeopleFilters;

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final _district = TextEditingController();
  bool _seeded = false;
  bool _locating = false;

  @override
  void dispose() {
    _district.dispose();
    super.dispose();
  }

  void _update(DiscoveryFilters Function(DiscoveryFilters) f) =>
      ref.read(discoveryFiltersProvider.notifier).update(f);

  /// Turns the radius search on, asking for a fix if the profile has none.
  ///
  /// Reads the point off the profile first. Somebody who already saved their
  /// location when they set their profile up should not be asked for GPS
  /// again just to search — and somebody who never did gets asked here,
  /// which is the moment the reason for asking is obvious.
  Future<void> _toggleNearMe(bool on) async {
    if (!on) {
      _update((f) => f.copyWith(useMyLocation: false));
      return;
    }

    final filters = ref.read(discoveryFiltersProvider);
    if (filters.hasPoint) {
      _update((f) => f.copyWith(useMyLocation: true));
      return;
    }

    final me = ref.read(currentUserProvider).valueOrNull;
    final lat = me?.geo.lat;
    final lng = me?.geo.lng;
    if (lat != null && lng != null) {
      _update((f) => f.copyWith(lat: lat, lng: lng, useMyLocation: true));
      return;
    }

    setState(() => _locating = true);
    try {
      final fix = await currentSearchPoint();
      if (!mounted) return;
      _update((f) =>
          f.copyWith(lat: fix.$1, lng: fix.$2, useMyLocation: true));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(discoveryFiltersProvider);
    if (!_seeded && filters.district != null && _district.text.isEmpty) {
      _district.text = filters.district!;
      _seeded = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _district,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'District / city',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _update(
                  (f) => v.trim().isEmpty
                      ? f.copyWith(clearDistrict: true)
                      : f.copyWith(district: v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              avatar: _locating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 16),
              label: const Text('Near me'),
              selected: filters.isRadiusSearch,
              onSelected: _locating ? null : _toggleNearMe,
            ),
          ],
        ),
        if (filters.isRadiusSearch) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in SearchRadius.values) ...[
                  ChoiceChip(
                    label: Text(r.label),
                    selected: filters.radius == r,
                    onSelected: (_) => _update((f) => f.copyWith(radius: r)),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: const Text('All sports'),
                selected: filters.sportId == null,
                onSelected: (_) => _update((f) => f.copyWith(clearSport: true)),
              ),
              const SizedBox(width: 8),
              for (final s in SportCatalog.all) ...[
                ChoiceChip(
                  label: Text(s.name),
                  selected: filters.sportId == s.id,
                  onSelected: (_) => _update((f) => f.copyWith(sportId: s.id)),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (widget.showPeopleFilters) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final i in PlayerIntent.values) ...[
                  FilterChip(
                    label: Text(i.label),
                    selected: filters.intent == i,
                    onSelected: (on) => _update(
                      (f) => on
                          ? f.copyWith(intent: i)
                          : f.copyWith(clearIntent: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final band in AgeGroup.values) ...[
                  FilterChip(
                    label: Text(band.label),
                    selected: filters.ageGroup == band,
                    onSelected: (on) => _update(
                      (f) => on
                          ? f.copyWith(ageGroup: band)
                          : f.copyWith(clearAgeGroup: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final g in Gender.values)
                  if (g != Gender.preferNotToSay) ...[
                    FilterChip(
                      label: Text(g.label),
                      selected: filters.gender == g,
                      onSelected: (on) => _update(
                        (f) => on
                            ? f.copyWith(gender: g)
                            : f.copyWith(clearGender: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ClubResults extends ConsumerWidget {
  const _ClubResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(discoverClubsProvider);

    return AsyncView(
      value: clubs,
      skeleton: const PsListSkeleton(),
      builder: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.groups_2_outlined,
            title: 'No clubs match that',
            message: 'Try a wider area, or clear the sport. Clubs that keep '
                'themselves unlisted never appear in search — for those you '
                'still need an invite code.',
            action: FilledButton(
              onPressed: () => context.push(Routes.createOrg),
              child: const Text('Start a club instead'),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          itemCount: list.length,
          itemBuilder: (context, i) => ContentBounds(
            maxWidth: 820,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: _ClubCard(org: list[i]),
          ),
        );
      },
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.org});

  final Organization org;

  @override
  Widget build(BuildContext context) {
    final place = org.geo.areaLabel.isNotEmpty
        ? org.geo.areaLabel
        : [org.city, org.district]
            .where((p) => p != null && p.isNotEmpty)
            .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: PsCrest(
          name: org.name,
          logoUrl: org.logoUrl,
          seed: org.id,
          size: 44,
        ),
        title: Text(org.name),
        subtitle: Text(
          [
            org.orgType.label,
            if (place.isNotEmpty) place,
            org.memberCount == 1 ? '1 member' : '${org.memberCount} members',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        // Straight to the club's own page, which already has the join
        // affordance and the context to decide with. A "join" button here
        // would be asking somebody to commit to a club from a one-line
        // summary.
        onTap: () => context.push(Routes.org(org.id)),
      ),
    );
  }
}

class _PeopleResults extends ConsumerWidget {
  const _PeopleResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(discoverPlayersProvider);
    final mine = ref.watch(myPlayerListingProvider).valueOrNull;

    return AsyncView(
      value: people,
      skeleton: const PsListSkeleton(),
      onRetry: () => refreshDiscoverPlayers(ref),
      builder: (list) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            ContentBounds(
              maxWidth: 820,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The other half of every directory: being IN it. Shown
                  // above the results rather than hidden in a menu, because
                  // the person most likely to want to be found is the one
                  // currently looking for somebody.
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.person_pin_circle_outlined),
                      title: Text(
                        mine == null
                            ? 'Let people find you'
                            : 'You are listed here',
                      ),
                      subtitle: Text(
                        mine == null
                            ? 'Add yourself to the directory so clubs and '
                                'players nearby can reach you.'
                            : 'Edit what you show, or take yourself off.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(Routes.myPlayerListing),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Nobody here yet',
                      message: 'The directory is opt-in, so it fills up as '
                          'people add themselves. Widen the area, or list '
                          'yourself and be the first one somebody finds.',
                    ),
                  for (final hit in list) _PersonCard(hit: hit),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.hit});

  final PlayerNearby hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = hit.listing;
    final theme = Theme.of(context);
    final myUid = ref.watch(authUidProvider);
    final isMe = l.uid == myUid;

    // Everybody the directory surfaces is, by definition, somebody this
    // searcher went looking for rather than somebody they already know — so
    // the entitlement is asked here and nowhere else. Every existing route to
    // a profile (a club roster, a team sheet, a leaderboard, a scorecard) is
    // untouched and stays free. See `canOpenStrangerProfilesProvider` for why
    // this is an offer gate and not a security boundary.
    final canOpen = isMe || ref.watch(canOpenStrangerProfilesProvider);

    final where = [
      if (hit.distanceLabel != null) hit.distanceLabel!,
      if (l.geo.areaLabel.isNotEmpty) l.geo.areaLabel,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (canOpen) {
            context.push(Routes.profile(l.uid));
          } else {
            showPremiumRequired(
              context,
              title: 'Open anyone’s profile',
              message:
                  'Premium members can open the public career page of any '
                  'player they find here — their record, their form and the '
                  'sports they play. Profiles of people in your own clubs '
                  'stay open to everyone, free.',
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PsAvatar(
                name: l.displayName,
                photoUrl: l.photoUrl,
                seed: l.uid,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l.displayName + (isMe ? ' (you)' : ''),
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!canOpen) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: theme.hintColor,
                          ),
                        ],
                      ],
                    ),
                    if (where.isNotEmpty)
                      Text(
                        where,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in l.sportIds.take(3))
                          _MiniChip(label: SportCatalog.byId(id).name),
                        if (l.ageGroup != null)
                          _MiniChip(label: l.ageGroup!.label),
                        if (l.matchesPlayed > 0)
                          _MiniChip(label: '${l.matchesPlayed} matches'),
                      ],
                    ),
                    if (l.intents.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Looking for: '
                        '${l.intents.map((i) => i.label.toLowerCase()).join(', ')}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (l.note != null && l.note!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        l.note!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
