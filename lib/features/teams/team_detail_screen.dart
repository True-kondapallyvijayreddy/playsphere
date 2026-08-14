import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/organization.dart';
import '../../core/models/team.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// One team's roster, live.
///
/// "Live" is the operative word: this reads straight off `teams/{teamId}`,
/// so a captain adding or dropping a player here is the same write that
/// changes what `myTeamsProvider` shows that player and what a competition's
/// [Entrant.teamId] link points back to for continuity. There is exactly one
/// roster document — this screen edits it, it does not keep a copy of it.
class TeamDetailScreen extends ConsumerWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamProvider(teamId));

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: AsyncView(
        value: teamAsync,
        onRetry: () => ref.invalidate(teamProvider(teamId)),
        builder: (team) {
          if (team == null) {
            return const EmptyState(
              icon: Icons.shield_outlined,
              title: 'Team not found',
              message: 'It may have been archived.',
            );
          }
          return _TeamBody(team: team);
        },
      ),
    );
  }
}

class _TeamBody extends ConsumerWidget {
  const _TeamBody({required this.team});
  final Team team;

  /// Whether the signed-in person may edit this roster.
  ///
  /// Mirrors `teamRuns()` in firestore.rules exactly — the creator, the
  /// captain, the manager, or the club's owner if this is a club team. A
  /// club admin who is none of those cannot edit a squad they did not raise
  /// and are not named on; only the owner outranks the roster itself.
  bool _canEdit(WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return false;
    if (uid == team.createdByUid ||
        uid == team.captainUid ||
        uid == team.managerUid) {
      return true;
    }
    if (team.clubId == null) return false;
    return ref
        .watch(myCapabilitiesProvider(team.clubId!))
        .contains(Capability.manageOrganization);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = SportCatalog.byId(team.sportId);
    final Organization? club = team.clubId == null
        ? null
        : ref.watch(organizationProvider(team.clubId!)).valueOrNull;
    final canEdit = _canEdit(ref);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentBounds(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: team.photoUrl != null
                        ? NetworkImage(team.photoUrl!)
                        : null,
                    child: team.photoUrl == null
                        ? Text(sport.icon, style: const TextStyle(fontSize: 22))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(team.name,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          [
                            sport.name,
                            team.type.label,
                            if (club != null) club.name,
                            if (team.homeArea != null) team.homeArea!,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Players (${team.memberUids.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (canEdit && team.clubId != null)
                    TextButton.icon(
                      onPressed: () => _openAddPlayers(context, team),
                      icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                      label: const Text('Add players'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final uid in team.memberUids)
                _PlayerRow(
                  uid: uid,
                  team: team,
                  canEdit: canEdit,
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _openAddPlayers(BuildContext context, Team team) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _AddPlayersSheet(team: team),
    );
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({
    required this.uid,
    required this.team,
    required this.canEdit,
  });

  final String uid;
  final Team team;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(userProfileProvider(uid)).valueOrNull;
    final isCaptain = uid == team.captainUid;
    final isManager = uid == team.managerUid;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
          child: user?.photoUrl == null
              ? Text((user?.displayName ?? '?').characters.first.toUpperCase())
              : null,
        ),
        title: Text(user?.displayName ?? 'Loading…'),
        subtitle: isCaptain || isManager
            ? Text(isCaptain ? 'Captain' : 'Manager')
            : null,
        trailing: canEdit
            ? IconButton(
                tooltip: 'Remove from team',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () async {
                  try {
                    await ref
                        .read(teamRepositoryProvider)
                        .removeMember(teamId: team.id, uid: uid);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              )
            : const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.profile(uid)),
      ),
    );
  }
}

/// Picks club members not already on the roster and adds them, one write
/// per tap. Live — a member added by someone else while this sheet is open
/// simply disappears from the "not yet on the team" list, because both
/// sides read the same [orgMembersProvider] / [Team.memberUids] streams.
class _AddPlayersSheet extends ConsumerStatefulWidget {
  const _AddPlayersSheet({required this.team});
  final Team team;

  @override
  ConsumerState<_AddPlayersSheet> createState() => _AddPlayersSheetState();
}

class _AddPlayersSheetState extends ConsumerState<_AddPlayersSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider(widget.team.id)).valueOrNull ?? widget.team;
    final members = ref.watch(orgMembersProvider(team.clubId!));
    final query = _search.text.trim().toLowerCase();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add players', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search members',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: members,
                builder: (all) {
                  final onRoster = team.memberUids.toSet();
                  final candidates = all.where((m) {
                    if (!m.isActive) return false;
                    if (onRoster.contains(m.uid)) return false;
                    if (query.isEmpty) return true;
                    return m.displayName.toLowerCase().contains(query);
                  }).toList();

                  if (candidates.isEmpty) {
                    return const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Nobody left to add',
                      message: 'Every matching club member is already on '
                          'this team.',
                    );
                  }

                  return ListView.builder(
                    controller: controller,
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final m = candidates[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: m.photoUrl != null
                              ? NetworkImage(m.photoUrl!)
                              : null,
                          child: m.photoUrl == null
                              ? Text(m.displayName.characters.first.toUpperCase())
                              : null,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(m.role.label),
                        trailing: IconButton(
                          tooltip: 'Add to team',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () async {
                            try {
                              await ref
                                  .read(teamRepositoryProvider)
                                  .addMember(teamId: team.id, uid: m.uid);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('${m.displayName} added.'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
