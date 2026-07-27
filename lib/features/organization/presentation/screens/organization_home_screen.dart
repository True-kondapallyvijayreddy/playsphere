import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/play_sphere_store.dart';
import '../../../../shared/widgets/portal_scaffold.dart';

class OrganizationHomeScreen extends ConsumerWidget {
  const OrganizationHomeScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(playSphereStoreProvider);
    final activeOrg = store.activeOrganization;
    final isAdmin = store.role == PortalRole.admin;

    return PortalScaffold(
      title: activeOrg.name,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF15803D), // Deep Turf Grass Green
                  Color(0xFF16A34A), // Vibrant Green
                  Color(0xFFDC2626), // Sports Crimson Red
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF15803D).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Chip(
                  label: Text(
                    store.organization.tier.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  backgroundColor: Colors.black.withValues(alpha: 0.25),
                  labelStyle: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  activeOrg.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  activeOrg.description ?? 'Federated sport operating system • One engine at every scale',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quick Stats
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Competitions',
                  value: store.competitions.length.toString(),
                  icon: Icons.emoji_events_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Live Matches',
                  value: store.fixtures.length.toString(),
                  icon: Icons.live_tv_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Registered',
                  value: store.playerProfiles.length.toString(),
                  icon: Icons.people_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Role Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAdmin ? 'Admin Operations' : 'Participant Hub',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: Text(isAdmin ? 'Switch to Participant' : 'Switch to Admin'),
                onPressed: () => store.toggleRole(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isAdmin) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('➕ Create Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => context.go('/org/$orgId/create-activity'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Trigger AI Team Shuffle'),
                  onPressed: () {
                    store.triggerAITeamShuffle('tt-2026');
                    context.go('/org/$orgId/events/tt-2026');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.gavel),
                  label: const Text('Franchise Auction Hub'),
                  onPressed: () => context.go('/org/$orgId/events/tt-2026'),
                ),
              ],
            ),
          ] else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('➕ Create Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => context.go('/org/$orgId/create-activity'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.how_to_reg),
                  label: const Text('Browse & Register Sports'),
                  onPressed: () => context.go('/org/$orgId/events'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.star_outline),
                  label: const Text('View My Career Resume'),
                  onPressed: () => context.go('/org/$orgId/members/${store.member.id}'),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),
          Text('Active Sport Competitions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          ...store.competitions.map((comp) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(Icons.sports_tennis),
                ),
                title: Text(comp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Format: ${comp.format.name} • Status: ${comp.status.name}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/org/$orgId/events/${comp.id}'),
              ),
            );
          }),
        ],
      ),
    );
  }
}
