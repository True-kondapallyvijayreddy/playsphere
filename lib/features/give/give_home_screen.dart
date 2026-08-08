import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/give_impact_stats.dart';
import '../../core/providers.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// The Give network's front door — "Give a Kit. Build a Player."
///
/// Deliberately org-free, same reasoning as [Routes.shop]: a person gives as
/// themselves, and a village club raising a need is reached from its own
/// dashboard, not from here. This screen is a hub, not a feed — it exists to
/// route a donor to exactly one of "give equipment", "see what's needed" or
/// "see the impact", plus their own donation trail if they have one.
class GiveHomeScreen extends ConsumerWidget {
  const GiveHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myDonations = ref.watch(myDonationsProvider).valueOrNull ?? const [];
    final stats = ref.watch(giveImpactStatsProvider).valueOrNull ??
        GiveImpactStats.empty;

    return AppScaffold(
      title: 'PlaySphere Give',
      subtitle: 'Give a kit. Build a player.',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'A talented player rarely lacks talent — they lack '
                    'shoes, a bat, a helmet. Give unused equipment a second '
                    'season, or point a donor straight at a club that needs '
                    'it.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
                const SizedBox(height: 12),

                _GiveTile(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Donate equipment',
                  subtitle:
                      'Bats, shoes, jerseys, kits — tell us what you have',
                  onTap: () => context.push(Routes.giveDonate),
                ),
                _GiveTile(
                  icon: Icons.checklist_outlined,
                  title: 'Needs board',
                  subtitle: 'Verified requests from real clubs and players',
                  onTap: () => context.push(Routes.giveNeeds),
                ),
                _GiveTile(
                  icon: Icons.storefront_outlined,
                  title: 'Collection centres',
                  subtitle: 'Find a drop-off point near you',
                  onTap: () => context.push(Routes.giveCollectionCenters),
                ),
                if (myDonations.isNotEmpty)
                  _GiveTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'My donations',
                    subtitle:
                        '${myDonations.length} donation${myDonations.length == 1 ? '' : 's'} '
                        '— track where they ended up',
                    onTap: () => context.push(Routes.giveMyDonations),
                  ),
                _GiveTile(
                  icon: Icons.bar_chart_outlined,
                  title: 'Impact so far',
                  subtitle: stats.hasActivity
                      ? '${stats.itemsDistributed} items delivered'
                      : 'Just getting started',
                  onTap: () => context.push(Routes.giveImpact),
                ),

                const SizedBox(height: 20),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Running a club?',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          'If your club or one of your players needs '
                          'equipment, raise a verified need and donors can '
                          'act on it directly.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () =>
                              context.push(Routes.giveRaiseNeed),
                          child: const Text('Raise a need'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiveTile extends StatelessWidget {
  const _GiveTile({
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
