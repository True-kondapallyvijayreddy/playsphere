import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Landing screen: the organizations this person actually belongs to.
///
/// Deliberately not an auto-redirect into the first org. Many real users
/// belong to several — a student is in their college, their hostel block and
/// a district academy — and silently picking one for them makes the other two
/// feel missing.
class OrgPickerScreen extends ConsumerWidget {
  const OrgPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(myMembershipsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;

    // Housekeeping, not UI: keeps the club mirror on this user's profile in
    // step with their real memberships so club-mates can open their profile.
    // Mounted here because this is the screen every signed-in user lands on.
    ref.watch(profileOrgMirrorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My organizations'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AsyncView(
        value: memberships,
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'You are not in any organization yet',
              message: 'Join your school, college or club with an invite code '
                  '— or create one of your own.',
              action: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push(Routes.joinOrg),
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Join with a code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push(Routes.createOrg),
                    icon: const Icon(Icons.add),
                    label: const Text('Create one'),
                  ),
                ],
              ),
            );
          }

          final active = list.where((m) => m.isActive).toList();
          final pending = list.where((m) => m.isPending).toList();

          return SingleChildScrollView(
            child: ContentBounds(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (user != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Hello, ${user.displayName.split(' ').first}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  for (final m in active)
                    _OrgTile(orgId: m.orgId, role: m.role),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Awaiting approval',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final m in pending)
                      _OrgTile(orgId: m.orgId, role: m.role, pending: true),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(Routes.joinOrg),
                          icon: const Icon(Icons.vpn_key_outlined),
                          label: const Text('Join'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(Routes.createOrg),
                          icon: const Icon(Icons.add),
                          label: const Text('Create'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrgTile extends ConsumerWidget {
  const _OrgTile({
    required this.orgId,
    required this.role,
    this.pending = false,
  });

  final String orgId;
  final MembershipRole role;
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            (org?.name ?? '?').characters.first.toUpperCase(),
          ),
        ),
        title: Text(org?.name ?? 'Loading…'),
        subtitle: Text(
          pending
              ? 'Waiting for an admin to approve you'
              : '${org?.orgType.label ?? ''} · ${role.label}',
        ),
        trailing: pending
            ? const Icon(Icons.hourglass_empty, size: 20)
            : const Icon(Icons.chevron_right),
        enabled: !pending,
        onTap: pending ? null : () => context.push(Routes.org(orgId)),
      ),
    );
  }
}
