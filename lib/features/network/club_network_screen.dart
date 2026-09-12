import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/club_thread.dart';
import '../../core/models/organization.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/discovery_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/location_fields.dart';
import '../../shared/ui_kit.dart';
import 'club_network_providers.dart';

/// The club owners' network: an inbox of conversations with other clubs, and
/// a directory of the clubs there are still to talk to.
///
/// ## The gap this closes
///
/// Every other surface in PlaySphere connects a club to its own members. The
/// relationship grassroots sport actually runs on is the other one — the club
/// down the road. A school needs a fixture; an academy has three unfilled
/// slots in next month's tournament; a village club wants to know who else
/// plays leather-ball within an hour's drive. Today that conversation happens
/// in a WhatsApp group somebody's uncle administers, and the season it
/// produces never reaches the app: the fixtures are agreed in a place the
/// scoreboard, the draw and the career record cannot see.
///
/// So the directory and the thread sit in the same screen on purpose. Finding
/// a club and writing to it is one motion, not two features — the moment a
/// club is worth talking to is the moment you have found it.
///
/// ## Owners only, and why the club is a choice on the screen
///
/// Committing a club to another club's season is the same class of decision
/// as accepting a challenge, so this is an owner's surface — see
/// `myOwnedOrgIdsProvider` and the matching rule. An owner who runs several
/// clubs has ONE inbox and picks which club they are speaking as, rather than
/// three inboxes to check; see `actingClubIdProvider`.
class ClubNetworkScreen extends ConsumerStatefulWidget {
  const ClubNetworkScreen({super.key, this.initialTab = 0});

  /// 0 = conversations, 1 = find a club.
  final int initialTab;

  @override
  ConsumerState<ClubNetworkScreen> createState() => _ClubNetworkScreenState();
}

class _ClubNetworkScreenState extends ConsumerState<ClubNetworkScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owned = ref.watch(myOwnedOrgIdsProvider);
    final acting = ref.watch(actingClubProvider);
    final unread = ref.watch(unreadClubThreadCountProvider);

    if (owned.isEmpty) {
      return AppScaffold(
        title: 'Club network',
        body: EmptyState(
          icon: Icons.handshake_outlined,
          title: 'For club owners',
          message: 'The network is where a club arranges fixtures, seasons '
              'and tournaments with other clubs. It opens once you own a '
              'club — an admin or an event manager sees their own club\'s '
              'threads through the owner who runs it.',
          action: FilledButton(
            onPressed: () => context.push(Routes.createOrg),
            child: const Text('Start a club'),
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Club network',
      subtitle: acting == null
          ? 'Talk to other clubs'
          : 'Speaking as ${acting.name}',
      body: Column(
        children: [
          if (owned.length > 1)
            ContentBounds(
              maxWidth: 820,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _ActingClubPicker(ownedOrgIds: owned),
            ),
          TabBar(
            controller: _tabs,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Conversations'),
                    if (unread > 0) ...[
                      const SizedBox(width: 6),
                      _UnreadDot(count: unread),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'Find a club'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const _Inbox(),
                _Directory(onEmptyCta: () => _tabs.animateTo(0)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which of the owner's clubs is speaking. Renders only for the handful of
/// people who own more than one.
class _ActingClubPicker extends ConsumerWidget {
  const _ActingClubPicker({required this.ownedOrgIds});

  final List<String> ownedOrgIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acting = ref.watch(actingClubIdProvider);
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final id in ownedOrgIds) ...[
            ChoiceChip(
              avatar: const Icon(Icons.shield_outlined, size: 16),
              label: Text(
                ref.watch(organizationProvider(id)).valueOrNull?.name ??
                    'Club',
              ),
              selected: acting == id,
              onSelected: (_) =>
                  ref.read(actingClubOverrideProvider.notifier).state = id,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Inbox extends ConsumerWidget {
  const _Inbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(clubThreadsProvider);

    return AsyncView(
      value: threads,
      skeleton: const PsListSkeleton(),
      builder: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_outlined,
            title: 'No conversations yet',
            message: 'Open "Find a club" to search by sport and by area, '
                'then write to the clubs you want fixtures with. Seasons and '
                'events attach straight to a message, so an invitation is one '
                'tap to open rather than a link to paste.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          itemCount: list.length,
          itemBuilder: (context, i) => ContentBounds(
            maxWidth: 820,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ThreadRow(thread: list[i]),
          ),
        );
      },
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final ClubThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = thread.isUnread;
    final at = thread.lastMessageAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: PsCrest(
          name: thread.otherOrgName,
          logoUrl: thread.otherOrgLogoUrl,
          seed: thread.otherOrgId,
          size: 44,
        ),
        title: Text(
          thread.otherOrgName,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          thread.lastMessage ?? 'No messages yet',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: unread ? theme.colorScheme.onSurface : theme.hintColor,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (at != null)
              Text(
                _relative(at),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            if (unread) ...[
              const SizedBox(height: 6),
              const _UnreadDot(count: 1),
            ],
          ],
        ),
        onTap: () => context.push(Routes.clubThread(thread.id)),
      ),
    );
  }
}

/// "4m", "3h", "Tue", "12 Mar". An inbox needs the age of a message, not its
/// timestamp — and at a glance, not after reading a date.
String _relative(DateTime at) {
  final now = DateTime.now();
  final gap = now.difference(at);
  if (gap.inMinutes < 1) return 'now';
  if (gap.inHours < 1) return '${gap.inMinutes}m';
  if (gap.inDays < 1) return '${gap.inHours}h';
  if (gap.inDays < 7) return DateFormat('EEE').format(at);
  return DateFormat('d MMM').format(at);
}

/// The directory: every public club, narrowed by sport and by area.
///
/// The same bounded page and the same pure filter the discovery screen uses —
/// see `clubDirectoryProvider`. What is different here is the destination:
/// tapping a club opens the conversation with it rather than its public page,
/// because an owner who has just searched for "cricket clubs in Warangal" is
/// not browsing, they are looking for somebody to write to.
class _Directory extends ConsumerStatefulWidget {
  const _Directory({required this.onEmptyCta});

  final VoidCallback onEmptyCta;

  @override
  ConsumerState<_Directory> createState() => _DirectoryState();
}

class _DirectoryState extends ConsumerState<_Directory> {
  final _query = TextEditingController();
  final _area = TextEditingController();
  bool _seeded = false;
  bool _locating = false;

  @override
  void dispose() {
    _query.dispose();
    _area.dispose();
    super.dispose();
  }

  void _update(DiscoveryFilters Function(DiscoveryFilters) f) =>
      ref.read(clubDirectoryFiltersProvider.notifier).update(f);

  /// Puts the acting club's own district in the box the first time.
  ///
  /// Watched by the caller rather than read here, for the reason
  /// `DiscoverScreen._seedFromProfile` spells out: the club arrives over a
  /// stream, so a `ref.read` on the first frame sees nothing and the seed
  /// would never happen on a real device.
  void _seed(String? home) {
    if (_seeded || home == null) return;
    _seeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(clubDirectoryFiltersProvider.notifier);
      if (notifier.state.district == null) {
        notifier.state = notifier.state.copyWith(district: home);
        _area.text = home;
      }
    });
  }

  Future<void> _toggleNearMe(bool on) async {
    if (!on) {
      _update((f) => f.copyWith(useMyLocation: false));
      return;
    }
    final filters = ref.read(clubDirectoryFiltersProvider);
    if (filters.hasPoint) {
      _update((f) => f.copyWith(useMyLocation: true));
      return;
    }
    // The club's own point first — a club that said where it plays should not
    // have to hand over the phone's GPS to search around itself.
    final club = ref.read(actingClubProvider);
    final lat = club?.geo.lat;
    final lng = club?.geo.lng;
    if (lat != null && lng != null) {
      _update((f) => f.copyWith(lat: lat, lng: lng, useMyLocation: true));
      return;
    }
    setState(() => _locating = true);
    try {
      final fix = await currentSearchPoint();
      if (!mounted) return;
      _update((f) => f.copyWith(lat: fix.$1, lng: fix.$2, useMyLocation: true));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _seed(ref.watch(actingClubDistrictProvider));
    final filters = ref.watch(clubDirectoryFiltersProvider);
    final results = ref.watch(clubDirectoryProvider);

    return Column(
      children: [
        ContentBounds(
          maxWidth: 820,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PsSearchField(
                hint: 'Search clubs by name',
                controller: _query,
                onChanged: (v) => _update((f) => f.copyWith(query: v)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _area,
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
                    label: const Text('Near us'),
                    selected: filters.isRadiusSearch,
                    onSelected: _locating ? null : _toggleNearMe,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('All sports'),
                      selected: filters.sportId == null,
                      onSelected: (_) =>
                          _update((f) => f.copyWith(clearSport: true)),
                    ),
                    const SizedBox(width: 8),
                    for (final s in SportCatalog.all) ...[
                      ChoiceChip(
                        label: Text(s.name),
                        selected: filters.sportId == s.id,
                        onSelected: (_) =>
                            _update((f) => f.copyWith(sportId: s.id)),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(
            value: results,
            skeleton: const PsListSkeleton(),
            builder: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.travel_explore_outlined,
                  title: 'No clubs match that',
                  message: 'Try a wider area, or clear the sport. A club that '
                      'keeps itself unlisted never appears in a search, so '
                      'the club you have in mind may simply not be public.',
                  action: TextButton(
                    onPressed: widget.onEmptyCta,
                    child: const Text('Back to conversations'),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
                itemCount: list.length,
                itemBuilder: (context, i) => ContentBounds(
                  maxWidth: 820,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _DirectoryRow(club: list[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DirectoryRow extends ConsumerWidget {
  const _DirectoryRow({required this.club});

  final Organization club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myOrgId = ref.watch(actingClubIdProvider);
    final place = club.geo.areaLabel.isNotEmpty
        ? club.geo.areaLabel
        : [club.city, club.district]
            .where((p) => p != null && p.isNotEmpty)
            .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: PsCrest(
          name: club.name,
          logoUrl: club.logoUrl,
          seed: club.id,
          size: 44,
        ),
        title: Text(club.name),
        subtitle: Text(
          [
            club.orgType.label,
            if (place.isNotEmpty) place,
            club.memberCount == 1 ? '1 member' : '${club.memberCount} members',
          ].join(' · '),
        ),
        // Two destinations, because there are two questions. The club's page
        // answers "who are they"; the chevron answers "let's talk".
        trailing: IconButton(
          tooltip: 'Message this club',
          icon: const Icon(Icons.chat_bubble_outline),
          onPressed: myOrgId == null
              ? null
              : () => context.push(Routes.clubThreadWith(myOrgId, club.id)),
        ),
        onTap: () => context.push(Routes.org(club.id)),
      ),
    );
  }
}
