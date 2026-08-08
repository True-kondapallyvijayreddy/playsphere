import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
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
    final members = ref.watch(orgMembersProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;

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
                    if (org != null && canManage) _InviteCard(org: org),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// How a club actually grows.
///
/// A six-character code that has to be read out over a phone, retyped, and
/// got wrong is the narrowest possible door into a club — and it was the only
/// one. This gives the same invite three shapes: a code for someone standing
/// next to you, a link to paste into a WhatsApp group, and a QR to hold up in
/// front of a classroom or print on a poster at the ground.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = Routes.inviteUrl(org.inviteCode);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invite code',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        org.inviteCode,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          letterSpacing: 6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scan, tap the link, or type the code.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // White plate behind the QR regardless of theme: a scanner
                // needs the quiet zone and the contrast, and a dark-mode QR
                // rendered on a dark card does not scan.
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: link,
                    size: 108,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    // A club name under the code would be nice and is
                    // deliberately absent: embedded text costs error
                    // correction, and this gets scanned off a phone screen in
                    // sunlight.
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: 'Join ${org.name} on PlaySphere: $link',
                      subject: 'Join ${org.name}',
                    ),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share invite'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite link copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Copy link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
        subtitle: Text(member.role.label),
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
      ),
    );
  }
}
