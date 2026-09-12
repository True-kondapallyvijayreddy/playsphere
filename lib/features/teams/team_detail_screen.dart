import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/app_user.dart';
import '../../core/models/organization.dart';
import '../../core/models/team.dart';
import '../../core/models/team_join_request.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/image_composer.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/glicko.dart';
import '../../shared/identity.dart';
import '../../shared/image_upload.dart';

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

  /// `Team.photoUrl` was read by this screen, the team list and the career
  /// profile, and written by nothing at all. This is the write.
  Future<void> _changeCrest(BuildContext context, WidgetRef ref) {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return Future.value();
    final repo = ref.read(teamRepositoryProvider);
    return pickAndUploadImage(
      context: context,
      title: 'Team crest',
      shape: ImageShape.square,
      successMessage: 'Crest updated.',
      removedMessage: 'Crest removed.',
      onUpload: (image) => repo.uploadTeamCrest(
        teamId: team.id,
        uid: uid,
        bytes: image.bytes,
        contentType: image.contentType,
      ),
      onRemove:
          team.photoUrl == null ? null : () => repo.removeTeamCrest(team.id),
    );
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
                  EditableImage(
                    tooltip: 'Change the team crest',
                    badgeSize: 24,
                    // Same authority as every other edit on this page:
                    // the captain, the manager, the creator, or an admin of
                    // the club the squad belongs to.
                    onTap: canEdit ? () => _changeCrest(context, ref) : null,
                    child: PsCrest(
                      name: team.name,
                      logoUrl: team.photoUrl,
                      seed: team.id,
                      size: 56,
                    ),
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

              // Independent teams only. A club squad is picked off the
              // club's member list and has no use for either of these; an
              // independent one has no list to be picked from, so the code
              // and the requests ARE how it fills up.
              if (team.isIndependent) ...[
                if (canEdit && team.joinCode != null)
                  _JoinCodeCard(code: team.joinCode!),
                if (canEdit) _JoinRequests(team: team),
                if (!canEdit) _AskToJoin(team: team),
                const SizedBox(height: 12),
              ],

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

    final subtitleParts = <Widget>[
      if (isCaptain || isManager)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(isCaptain ? 'Captain' : 'Manager'),
        ),
      if (GlickoChip.forSport(user?.glicko, team.sportId) case final chip?)
        chip,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: PsAvatar(
          name: user?.displayName ?? '?',
          photoUrl: user?.photoUrl,
          seed: uid,
        ),
        title: Text(user?.displayName ?? 'Loading…'),
        // A roster is a team sheet, and a team sheet without standings is the
        // thing every captain in the country currently keeps in a separate
        // notebook. The rating shown is this TEAM's sport where the profile
        // carries it — see `GlickoChip.forSport` — because "how good is this
        // player at the game we are picking them for" is the only question a
        // roster is asked.
        subtitle: subtitleParts.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: subtitleParts),
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
                        leading: PsAvatar(
                          name: m.displayName,
                          photoUrl: m.photoUrl,
                          seed: m.uid,
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

// ---------------------------------------------------------------------------
// Independent teams: the code, the queue, and the way in
// ---------------------------------------------------------------------------

/// The code a captain reads out.
///
/// Shown only to the people who run the team, which is not a security
/// boundary — any signed-in reader can read the field off the document — but
/// is the honest presentation: the code is the captain's to give out, and
/// putting it on a stranger's view of the page implies it does something it
/// does not.
class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.key_outlined),
        title: Text(
          code,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
        subtitle: const Text(
          'Give this to players you want. They enter it under '
          '“Join with a code”, then ask — you decide who gets on.',
        ),
      ),
    );
  }
}

/// Everybody waiting on this captain to say yes.
class _JoinRequests extends ConsumerWidget {
  const _JoinRequests({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests =
        ref.watch(teamJoinRequestsProvider(team.id)).valueOrNull ??
            const <TeamJoinRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              '${requests.length} '
              '${requests.length == 1 ? 'player wants' : 'players want'} to '
              'join',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final r in requests)
            ListTile(
              leading: PsAvatar(
                name: r.displayName,
                photoUrl: r.photoUrl,
                seed: r.uid,
              ),
              title: Text(r.displayName),
              subtitle: r.message == null ? null : Text(r.message!),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Decline',
                    icon: const Icon(Icons.close),
                    onPressed: () => ref
                        .read(teamRepositoryProvider)
                        .cancelJoinRequest(teamId: team.id, uid: r.uid),
                  ),
                  IconButton(
                    tooltip: 'Let them in',
                    icon: const Icon(Icons.check),
                    onPressed: () => ref
                        .read(teamRepositoryProvider)
                        .approveJoinRequest(teamId: team.id, uid: r.uid),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The button somebody who is not on this team sees.
class _AskToJoin extends ConsumerWidget {
  const _AskToJoin({required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The acting profile — the guardian themselves, or a managed child
    // they're currently "managing as" (see actingProfileProvider). Joining
    // a team is exactly the kind of participation action a guardian takes
    // on a child's behalf, so this asks on whoever is currently active,
    // not always the signed-in account.
    final me = ref.watch(actingProfileProvider);
    if (me == null) return const SizedBox.shrink();
    // Already on the roster: there is nothing to ask for.
    if (team.memberUids.contains(me.uid)) return const SizedBox.shrink();

    final asked = ref.watch(hasAskedToJoinProvider(team.id)).valueOrNull ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: asked
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => ref
                  .read(teamRepositoryProvider)
                  .cancelJoinRequest(teamId: team.id, uid: me.uid),
              icon: const Icon(Icons.hourglass_top_outlined),
              label: const Text('Asked — tap to withdraw'),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _ask(context, ref, me),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Ask to join'),
            ),
    );
  }

  Future<void> _ask(BuildContext context, WidgetRef ref, AppUser me) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Ask to join ${team.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Say something (optional)',
            hintText: 'I keep wicket — played for St Xavier’s last season.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || !context.mounted) return;

    try {
      await ref.read(teamRepositoryProvider).requestToJoin(
            teamId: team.id,
            uid: me.uid,
            displayName: me.displayName,
            photoUrl: me.photoUrl,
            message: message.trim().isEmpty ? null : message.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Asked to join ${team.name}.')),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
