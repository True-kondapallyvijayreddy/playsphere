import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/play_sphere_store.dart';

class PortalScaffold extends ConsumerWidget {
  const PortalScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(playSphereStoreProvider);
    final member = store.member;
    final activeOrg = store.activeOrganization;
    final isAdmin = store.role == PortalRole.admin;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context) || GoRouter.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                tooltip: 'Go Back',
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    context.go('/org/${activeOrg.id}');
                  }
                },
              )
            : null,
        title: InkWell(
          onTap: () => context.go('/org/${activeOrg.id}'),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // PlaySphere Brand Logo Badge
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF16A34A), Color(0xFF15803D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.sports_soccer,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                children: [
                                  TextSpan(
                                    text: 'Play',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'Sphere',
                                    style: TextStyle(color: Color(0xFFDC2626)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                'SPORTS OS',
                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$title • ${activeOrg.name}',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ...?actions,
          OutlinedButton.icon(
            icon: const Icon(Icons.groups, size: 16),
            label: const Text('➕ Create Club'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onPressed: () => context.go('/org/${activeOrg.id}/create-club'),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, size: 20),
            tooltip: 'Join Club by Code / Invite Link',
            onPressed: () => context.go('/org/${activeOrg.id}/join-club'),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('➕ Create Event'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () => context.go('/org/${activeOrg.id}/create-activity'),
          ),
          const SizedBox(width: 8),
          // Role Quick Toggle Switcher (Admin vs Participant)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: FilterChip(
              avatar: Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.person,
                size: 16,
                color: isAdmin ? Colors.amber : Theme.of(context).colorScheme.primary,
              ),
              label: Text(isAdmin ? 'ADMIN' : 'PARTICIPANT'),
              selected: isAdmin,
              onSelected: (_) {
                store.toggleRole();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched to ${!isAdmin ? "Admin Portal" : "Participant Portal"}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'My Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.go('/org/${activeOrg.id}/members/${member.id}'),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sports_basketball, size: 32, color: Colors.white),
                        const SizedBox(width: 12),
                        Text(
                          'PlaySphere',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      store.organization.name,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              // Org Tier Selector
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ACTIVE ORGANIZATION TIER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: store.activeOrgId,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: store.organizations.map((org) {
                        return DropdownMenuItem(
                          value: org.id,
                          child: Text(
                            org.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          store.switchOrganization(val);
                          Navigator.of(context).pop();
                          context.go('/org/$val');
                        }
                      },
                    ),
                  ],
                ),
              ),

              const Divider(),
              _navTile(context, Icons.home_outlined, 'Home Dashboard', '/org/${activeOrg.id}'),
              _navTile(context, Icons.directions_run_outlined, 'Player Participant Hub', '/org/${activeOrg.id}/participant'),
              _navTile(context, Icons.gavel_outlined, 'Scorer Assignments', '/org/${activeOrg.id}/scoring-assignments'),
              _navTile(context, Icons.shield_outlined, 'Owner Settings', '/org/${activeOrg.id}/settings'),
              _navTile(context, Icons.emoji_events_outlined, 'Seasons & Competitions', '/org/${activeOrg.id}/events'),
              _navTile(context, Icons.live_tv_outlined, 'Live Scoring Studio', '/org/${activeOrg.id}/events/tt-2026/live'),
              _navTile(context, Icons.search_outlined, 'Talent Graph & Scouts', '/org/${activeOrg.id}/discovery'),
              _navTile(context, Icons.stadium_outlined, 'Venue Infrastructure', '/org/${activeOrg.id}/venues'),
              _navTile(context, Icons.verified_user_outlined, 'Officials & Volunteers', '/org/${activeOrg.id}/officials'),
              _navTile(context, Icons.account_balance_outlined, 'State CM Governance', '/org/${activeOrg.id}/governance'),
              _navTile(context, Icons.person_outline, 'My Player Profile', '/org/${activeOrg.id}/members/${member.id}'),
            ],
          ),
        ),
      ),
      body: SafeArea(child: child),
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _navTile(BuildContext context, IconData icon, String label, String path) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        context.go(path);
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}
