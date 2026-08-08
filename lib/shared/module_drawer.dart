import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/permissions/capability.dart';
import '../core/providers.dart';
import '../core/router/app_router.dart';
import '../features/home/home_providers.dart';
import '../features/settings/language_picker.dart';
import 'playsphere_logo.dart';

/// One entry in the module menu.
class ModuleEntry {
  const ModuleEntry({
    required this.icon,
    required this.label,
    required this.description,
    required this.path,
    this.requires,
    this.needsClub = false,
    this.badge,
  });

  final IconData icon;
  final String label;

  /// A line of plain English under the label. The menu is the one place a new
  /// member finds out what this product actually contains, and a bare list of
  /// nouns ("Challenges", "Registry") tells them nothing — CLAUDE.md §1 is a
  /// promise about breadth, and breadth nobody can find is breadth nobody has.
  final String description;

  final String path;

  /// Hidden entirely unless the caller holds this capability in the club the
  /// menu is currently pointed at. Hidden rather than disabled: a scorer's
  /// menu should contain what a scorer does, not a tour of what they cannot.
  final Capability? requires;

  /// Needs a club to point at. Shown but disabled when the user is in none,
  /// with a subtitle that says so — a member who has not joined anything yet
  /// should still be able to see that live scoring exists.
  final bool needsClub;

  final int? badge;
}

/// The "three lines" menu: every module in PlaySphere, in one place.
///
/// The bottom bar and the rail carry the four screens someone uses on a match
/// day. Everything else in the product — analytics, the rules library, the
/// looking-for board, the umpire registry, joining and creating clubs — lives
/// here, grouped by what a person is trying to do rather than by which part of
/// the codebase it came from.
class ModuleDrawer extends ConsumerWidget {
  const ModuleDrawer({super.key, this.orgId});

  /// The club whose screens the org-scoped entries point at. Null on the
  /// global screens (home, profile), where it falls back to the club the user
  /// most recently joined.
  final String? orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final fallbackOrgId = ref.watch(primaryOrgIdProvider);
    final activeOrgId = orgId ?? fallbackOrgId;
    final org = activeOrgId == null
        ? null
        : ref.watch(organizationProvider(activeOrgId)).valueOrNull;

    final caps = activeOrgId == null
        ? const <Capability>{}
        : ref.watch(myCapabilitiesProvider(activeOrgId));

    final incoming = activeOrgId == null
        ? 0
        : ref.watch(incomingChallengesProvider(activeOrgId)).valueOrNull?.length ??
            0;
    final pendingMembers = activeOrgId == null
        ? 0
        : ref.watch(pendingMembersProvider(activeOrgId)).valueOrNull?.length ?? 0;
    final liveCount = ref.watch(myLiveFixturesProvider).valueOrNull?.length ?? 0;
    final isPremium = ref.watch(isPremiumProvider);

    // Placeholder ids keep the declarations below readable; entries carrying
    // one are gated on [ModuleEntry.needsClub] and never navigated to.
    final id = activeOrgId ?? '-';

    final sections = <String, List<ModuleEntry>>{
      'Match day': [
        const ModuleEntry(
          icon: Icons.dashboard_outlined,
          label: 'Home',
          description: 'Your clubs, live matches and what needs you today',
          path: Routes.home,
        ),
        ModuleEntry(
          icon: Icons.sensors,
          label: 'Live now',
          description: 'Every match being played, ball by ball',
          path: Routes.live(id),
          needsClub: true,
          badge: liveCount == 0 ? null : liveCount,
        ),
        ModuleEntry(
          icon: Icons.emoji_events_outlined,
          label: 'Events & tournaments',
          description: 'Draws, fixtures, standings and results',
          path: Routes.org(id),
          needsClub: true,
        ),
        ModuleEntry(
          icon: Icons.add_circle_outline,
          label: 'Create an event',
          description: 'Pick a sport and format, open entries',
          path: Routes.createCompetition(id),
          requires: Capability.manageCompetitions,
          needsClub: true,
        ),
      ],
      'Clubs & people': [
        const ModuleEntry(
          icon: Icons.groups_2_outlined,
          label: 'My clubs',
          description: 'Switch between the clubs you belong to',
          path: Routes.orgs,
        ),
        ModuleEntry(
          icon: Icons.people_outline,
          label: 'Members',
          description: 'Roster, roles and join requests',
          path: Routes.members(id),
          requires: Capability.manageMembers,
          needsClub: true,
          badge: pendingMembers == 0 ? null : pendingMembers,
        ),
        ModuleEntry(
          icon: Icons.sports_kabaddi_outlined,
          label: 'Challenges',
          description: 'Play another club — propose, accept, schedule',
          path: Routes.challenges(id),
          // Bug #12: only event managers see challenges in the module menu.
          // Regular members reach the challenges screen through the bottom
          // nav bar where the screen itself already gates actions behind
          // canManage — but the drawer entry sitting alongside "Create an
          // event" implied a capability the member does not hold.
          requires: Capability.manageCompetitions,
          needsClub: true,
          badge: incoming == 0 ? null : incoming,
        ),
        ModuleEntry(
          icon: Icons.photo_library_outlined,
          label: 'Gallery',
          description: 'Every photo from every match this club has played',
          path: Routes.gallery(id),
          needsClub: true,
        ),
        ModuleEntry(
          icon: Icons.leaderboard_outlined,
          label: 'Rankings',
          description: 'Points won over the last 52 weeks, across every club',
          path: Routes.rankings(id),
          needsClub: true,
        ),
        ModuleEntry(
          icon: Icons.emoji_events_outlined,
          label: 'Tournaments',
          description: 'Many events, one set of courts, one timetable',
          path: Routes.tournaments(id),
          needsClub: true,
        ),
        ModuleEntry(
          icon: Icons.stadium_outlined,
          label: 'Venues',
          description: 'Halls, grounds and their courts — shared by every event',
          path: Routes.venues(id),
          needsClub: true,
        ),
        ModuleEntry(
          icon: Icons.folder_outlined,
          label: 'Files',
          description: 'Fixtures lists, rules, forms — shared with members',
          path: Routes.files(id),
          needsClub: true,
        ),
        const ModuleEntry(
          icon: Icons.vpn_key_outlined,
          label: 'Join a club',
          description: 'Enter the six-letter code your coach shared',
          path: Routes.joinOrg,
        ),
        const ModuleEntry(
          icon: Icons.add_business_outlined,
          label: 'Create a club',
          description: 'A school, college, village, academy or pickup group',
          path: Routes.createOrg,
        ),
      ],
      'Community': [
        const ModuleEntry(
          icon: Icons.campaign_outlined,
          label: 'Looking for',
          description: 'Players, teams, scorers, umpires and grounds near you',
          path: Routes.lookingFor,
        ),
        const ModuleEntry(
          icon: Icons.sports,
          label: 'Umpire & scorer registry',
          description: 'Register as an official, or find one for your match',
          path: Routes.umpireRegistry,
        ),
        // Deliberately org-free. Discovering a tournament to enter is the one
        // journey that must not start by picking which of your clubs you are
        // asking on behalf of — you are looking outward, not inward.
        const ModuleEntry(
          icon: Icons.public,
          label: 'Global events',
          description: 'Tournaments open to entries across the country',
          path: Routes.globalEvents,
        ),
        const ModuleEntry(
          icon: Icons.menu_book_outlined,
          label: 'Rules library',
          description: 'Official rules — ICC, FIFA, FIBA, BWF, PKL and more',
          path: Routes.rules,
        ),
      ],
      'Insights': [
        ModuleEntry(
          icon: Icons.insights_outlined,
          label: 'Analytics',
          description: 'Participation, sports, roles and event throughput',
          path: Routes.analytics(id),
          requires: Capability.viewAnalytics,
          needsClub: true,
        ),
        const ModuleEntry(
          icon: Icons.badge_outlined,
          label: 'My career profile',
          description: 'Every match, rating and memory — yours for life',
          path: Routes.myProfile,
        ),
      ],
      'Shop & more': [
        const ModuleEntry(
          icon: Icons.storefront_outlined,
          label: 'Shop',
          description: 'Rackets, balls, kit and shoes from Decathlon',
          path: Routes.shop,
        ),
        const ModuleEntry(
          icon: Icons.stadium_outlined,
          label: 'Grounds near you',
          description: 'Find and book a ground, court or turf by the hour',
          path: Routes.grounds,
        ),
        const ModuleEntry(
          icon: Icons.business_center_outlined,
          label: 'List your ground',
          description: 'Own a ground or a turf? Take bookings on PlaySphere',
          path: Routes.myGrounds,
        ),
        // The one entry whose subtitle depends on what the person already
        // holds. A member who is already paying should not be sold to every
        // time they open the menu — for them this is the page where they see
        // what they have and when it renews.
        ModuleEntry(
          icon: isPremium
              ? Icons.workspace_premium
              : Icons.workspace_premium_outlined,
          label: isPremium ? 'Premium — active' : 'Get Premium',
          description: isPremium
              ? 'Your membership, renewal date and receipts'
              : 'Full career history, analytics and no ads — ₹99 a year',
          path: Routes.premium,
        ),
      ],
    };

    final currentPath = GoRouterState.of(context).uri.path;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // --- Header: brand, then which club this menu is pointed at ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: PlaySphereLogo(markSize: 34, fontSize: 21),
                  ),
                  IconButton(
                    tooltip: 'Close menu',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                user == null
                    ? 'One place for every sport you play.'
                    : 'Hello ${user.displayName.split(' ').first} — one place '
                        'for every sport you play.',
                style: theme.textTheme.bodySmall,
              ),
            ),

            if (org != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: theme.colorScheme.primaryContainer,
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(org.name.characters.first.toUpperCase()),
                    ),
                    title: Text(
                      org.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      org.orgType.label,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: () => _go(context, Routes.orgs),
                      child: const Text('Switch'),
                    ),
                  ),
                ),
              ),
            const Divider(height: 8),

            for (final section in sections.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  section.key.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700,
                    color: theme.hintColor,
                  ),
                ),
              ),
              for (final entry in section.value)
                if (entry.requires == null || caps.contains(entry.requires))
                  _ModuleTile(
                    entry: entry,
                    selected: entry.path == currentPath,
                    enabled: !entry.needsClub || activeOrgId != null,
                  ),
            ],

            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('Language / భాష / भाषा'),
              onTap: () async {
                Navigator.of(context).pop();
                await showLanguagePicker(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authServiceProvider).signOut();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static void _go(BuildContext context, String path) {
    Navigator.of(context).pop();
    context.push(path);
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.entry,
    required this.selected,
    required this.enabled,
  });

  final ModuleEntry entry;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = entry.badge ?? 0;

    return ListTile(
      enabled: enabled,
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(
        alpha: 0.5,
      ),
      leading: badge > 0
          ? Badge.count(count: badge, child: Icon(entry.icon))
          : Icon(entry.icon),
      title: Text(entry.label),
      subtitle: Text(
        enabled ? entry.description : 'Join or create a club to use this',
        style: theme.textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: !enabled ? null : () => ModuleDrawer._go(context, entry.path),
    );
  }
}
