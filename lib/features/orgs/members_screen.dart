import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/models/team.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/invite_card.dart';
import 'widgets/ownership_actions.dart';

/// Roster and approval queue.
///
/// Both live on one screen because they are the same job: deciding who is in
/// this organization and what they may do. Splitting them tends to leave the
/// approval queue unvisited, and applicants waiting for days.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final canManage = caps.contains(Capability.manageMembers);
    // Raising a team reshapes the club's roster into a squad, which is why
    // it takes the same authority as the rules give `canManageOrg` — the
    // owner alone, not every admin. See `teamRuns()` in firestore.rules.
    final canCreateTeam = caps.contains(Capability.manageOrganization);
    final members = ref.watch(orgMembersProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final teams = ref.watch(clubTeamsProvider(orgId));

    return AppScaffold(
      orgId: orgId,
      title: 'Members',
      body: AsyncView(
        value: members,
        builder: (all) {
          final pending = all.where((m) => m.isPending).toList();
          final active = all.where((m) => m.isActive).toList();

          return ListView(
            children: [
              ContentBounds(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (org != null && canManage) InviteCard(org: org),
                    const SizedBox(height: 20),
                    _TeamsSection(
                      orgId: orgId,
                      teams: teams.valueOrNull ?? const [],
                      canCreate: canCreateTeam,
                    ),
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionTitle(
                        'Waiting for approval (${pending.length})',
                      ),
                      for (final m in pending)
                        _PendingTile(
                          orgId: orgId,
                          member: m,
                          canManage: canManage,
                        ),
                    ],
                    const SizedBox(height: 20),
                    _SectionTitle('Members (${active.length})'),
                    for (final m in active)
                      _MemberTile(
                        orgId: orgId,
                        member: m,
                        canManage: canManage,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The club's raised squads, with a way to raise another.
///
/// Lives right above the member list on purpose: a team is picked FROM this
/// roster, so the person about to pick eleven names should not have to leave
/// the page that has all of them to go find where "new team" lives.
class _TeamsSection extends StatelessWidget {
  const _TeamsSection({
    required this.orgId,
    required this.teams,
    required this.canCreate,
  });

  final String orgId;
  final List<Team> teams;
  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty && !canCreate) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Teams (${teams.length})',
                  style: theme.textTheme.titleSmall),
            ),
            if (canCreate)
              TextButton.icon(
                onPressed: () => context.push(Routes.createTeam(orgId)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New team'),
              ),
          ],
        ),
        for (final team in teams) _TeamChipTile(team: team),
        if (teams.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'No teams yet. Pick players from the list below and raise one '
              'for a tournament, a fixture, or the season.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _TeamChipTile extends StatelessWidget {
  const _TeamChipTile({required this.team});
  final Team team;

  @override
  Widget build(BuildContext context) {
    final sport = SportCatalog.byId(team.sportId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Text(sport.icon)),
        title: Text(team.name),
        subtitle: Text('${sport.name} · ${team.memberUids.length} players'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.team(team.id)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _PendingTile extends ConsumerWidget {
  const _PendingTile({
    required this.orgId,
    required this.member,
    required this.canManage,
  });

  final String orgId;
  final Membership member;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> decide(MembershipStatus status) async {
      final uid = ref.read(currentUidProvider);
      if (uid == null) return;
      try {
        await ref.read(orgRepositoryProvider).decideMembership(
              orgId: orgId,
              uid: member.uid,
              status: status,
              decidedByUid: uid,
            );
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              member.photoUrl != null ? NetworkImage(member.photoUrl!) : null,
          child: member.photoUrl == null
              ? Text(member.displayName.characters.first.toUpperCase())
              : null,
        ),
        title: Text(member.displayName),
        subtitle: const Text('Wants to join'),
        trailing: !canManage
            ? null
            : Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: () => decide(MembershipStatus.active),
                  ),
                  IconButton(
                    tooltip: 'Decline',
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () => decide(MembershipStatus.removed),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.orgId,
    required this.member,
    required this.canManage,
  });

  final String orgId;
  final Membership member;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(currentUidProvider);
    final myRole =
        ref.watch(myMembershipProvider(orgId)).valueOrNull?.role;
    final isSelf = member.uid == myUid;

    // Nobody edits their own role, and nobody edits someone at or above their
    // own rank. Both rules are enforced again in the security rules — this
    // just avoids offering an action that would be rejected.
    final assignable =
        myRole == null ? <MembershipRole>[] : PermissionMatrix.assignableBy(myRole);
    final iAmOwner = myRole == MembershipRole.owner;
    final targetIsOwner = member.role == MembershipRole.owner;

    // An owner's role is not changed by a menu pick. Appointing one is
    // ordinary (it is in `assignable` now), but removing one takes a vote —
    // see `OwnerVote` — and stepping down is the person's own decision. So an
    // owner row gets its own controls rather than the role dropdown.
    final editable = canManage &&
        !isSelf &&
        !targetIsOwner &&
        assignable.isNotEmpty;

    // Only another owner can move a motion, and only against somebody who is
    // actually an owner.
    final canProposeRemoval = iAmOwner && targetIsOwner && !isSelf;
    final canStepDown = iAmOwner && targetIsOwner && isSelf;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              member.photoUrl != null ? NetworkImage(member.photoUrl!) : null,
          child: member.photoUrl == null
              ? Text(member.displayName.characters.first.toUpperCase())
              : null,
        ),
        title: Text(member.displayName + (isSelf ? ' (you)' : '')),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoleDot(isOwner: targetIsOwner),
            const SizedBox(width: 6),
            Text(member.role.label),
          ],
        ),
        trailing: canProposeRemoval || canStepDown
            ? OwnershipActions(
                orgId: orgId,
                member: member,
                isSelf: isSelf,
              )
            : !editable
            ? Chip(
                label: Text(member.role.label),
                visualDensity: VisualDensity.compact,
              )
            : PopupMenuButton<MembershipRole>(
                tooltip: 'Change role',
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  for (final r in assignable)
                    PopupMenuItem(
                      value: r,
                      child: Text('Make ${r.label}'),
                    ),
                ],
                onSelected: (role) async {
                  try {
                    await ref.read(orgRepositoryProvider).changeRole(
                          orgId: orgId,
                          uid: member.uid,
                          role: role,
                        );
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
        onTap: () => context.push(Routes.profile(member.uid)),
      ),
    );
  }
}

/// Owner or not, at a glance. Green for the one role that can delete this
/// club or hand it away; blue for everyone else, regardless of whether they
/// can score matches or just showed up to play — the distinction a roster
/// scan actually needs is "whose club is this", not the full role ladder.
class _RoleDot extends StatelessWidget {
  const _RoleDot({required this.isOwner});
  final bool isOwner;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isOwner ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
        ),
      );
}
