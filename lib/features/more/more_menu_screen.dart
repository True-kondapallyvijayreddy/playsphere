import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../home/home_providers.dart';

/// Screen version of the "More" menu for single-tap navigation (PS-010, PS-020).
class MoreMenuScreen extends ConsumerWidget {
  const MoreMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final primaryOrgId = ref.watch(primaryOrgIdProvider);

    return AppScaffold(
      title: 'More',
      subtitle: 'All modules & quick navigation',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Card
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  user?.displayName.substring(0, 1).toUpperCase() ?? 'P',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                user?.displayName ?? 'Sports Person',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(user?.playerCode != null
                  ? 'Code: ${user!.playerCode}'
                  : user?.email ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.myProfile),
            ),
          ),
          const SizedBox(height: 16),

          const _MenuSectionHeader(title: 'ORGANIZATION & CLUB'),
          if (primaryOrgId != null) ...[
            _MenuItemTile(
              icon: Icons.shield_outlined,
              title: 'Club Dashboard',
              subtitle: 'Manage club feed, events, and members',
              onTap: () => context.push(Routes.org(primaryOrgId)),
            ),
            _MenuItemTile(
              icon: Icons.emoji_events_outlined,
              title: 'Tournaments & Multi-Sport Seasons',
              subtitle: 'League fixtures, standings, and brackets',
              onTap: () => context.push(Routes.tournaments(primaryOrgId)),
            ),
            _MenuItemTile(
              icon: Icons.sports_kabaddi_outlined,
              title: 'Inter-Club Challenges',
              subtitle: 'Challenge rival clubs & track scorecards',
              onTap: () => context.push(Routes.challenges(primaryOrgId)),
            ),
            _MenuItemTile(
              icon: Icons.collections_outlined,
              title: 'Club Gallery',
              subtitle: 'Match photos and video highlights',
              onTap: () => context.push(Routes.gallery(primaryOrgId)),
            ),
            _MenuItemTile(
              icon: Icons.people_alt_outlined,
              title: 'Club Members',
              subtitle: 'View roster and squad roles',
              onTap: () => context.push(Routes.members(primaryOrgId)),
            ),
            _MenuItemTile(
              icon: Icons.storefront_outlined,
              title: 'Club Store',
              subtitle: 'Official jerseys and merchandise',
              onTap: () => context.push('/org/$primaryOrgId/store'),
            ),
          ],
          _MenuItemTile(
            icon: Icons.groups_outlined,
            title: 'Browse All Clubs',
            subtitle: 'Find and join local sports clubs',
            onTap: () => context.push(Routes.orgs),
          ),

          const SizedBox(height: 16),
          const _MenuSectionHeader(title: 'COMMUNITY & RULES'),
          _MenuItemTile(
            icon: Icons.volunteer_activism_outlined,
            title: 'PlaySphere Give',
            subtitle: 'Donate equipment, or find what a club needs',
            onTap: () => context.push(Routes.give),
          ),
          _MenuItemTile(
            icon: Icons.handshake_outlined,
            title: 'Sponsor an Athlete / Team',
            subtitle: 'Back a rising player or team, directly and by name',
            onTap: () => context.push(Routes.sponsor),
          ),
          // Discovery sits above search deliberately: it is the one that
          // answers a question the visitor has not already had to formulate.
          _MenuItemTile(
            icon: Icons.trending_up_outlined,
            title: 'Rising Talent',
            subtitle: 'Players and clubs improving fastest near you',
            onTap: () => context.push(Routes.risingTalent),
          ),
          _MenuItemTile(
            icon: Icons.travel_explore_outlined,
            title: 'Talent Search',
            subtitle: 'Search players by sport, age, district and form',
            onTap: () => context.push(Routes.scoutSearch),
          ),
          _MenuItemTile(
            icon: Icons.shopping_bag_outlined,
            title: 'My Orders',
            subtitle: 'Everything you\'ve bought from a club store',
            onTap: () => context.push(Routes.myClubOrders),
          ),
          _MenuItemTile(
            icon: Icons.campaign_outlined,
            title: 'Advertise on PlaySphere',
            subtitle: 'Reach players by sport, club and ground',
            onTap: () => context.push(Routes.adConsole),
          ),
          _MenuItemTile(
            icon: Icons.fastfood_outlined,
            title: 'My Food Orders',
            subtitle: 'Water, snacks and meals ordered at a ground',
            onTap: () => context.push(Routes.myFoodOrders),
          ),
          // Platform staff only — hidden rather than shown-and-denied for
          // everyone else, the same call `AdConsoleScreen`'s own entry point
          // does not make (that one is for anybody). A menu item that leads
          // to "Restricted" for 99.9% of accounts is worse than no item.
          if (ref.watch(isPlatformAdminProvider).valueOrNull == true)
            _MenuItemTile(
              icon: Icons.query_stats_outlined,
              title: 'Government Dashboard',
              subtitle: 'Clubs, members and matches by district',
              onTap: () => context.push(Routes.govDashboard),
            ),
          _MenuItemTile(
            icon: Icons.person_search_outlined,
            title: 'Looking For Board',
            subtitle: 'Find players, teams, or match partners',
            onTap: () => context.push(Routes.lookingFor),
          ),
          _MenuItemTile(
            icon: Icons.verified_user_outlined,
            title: 'Official Registry',
            subtitle: 'Certified umpires, referees & judges',
            onTap: () => context.push(Routes.umpireRegistry),
          ),
          _MenuItemTile(
            icon: Icons.menu_book_outlined,
            title: 'Sport Rulebook',
            subtitle: 'Cricket, Badminton, Kabaddi, Football rules',
            onTap: () => context.push(Routes.rules),
          ),
        ],
      ),
    );
  }
}

class _MenuSectionHeader extends StatelessWidget {
  const _MenuSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }
}
