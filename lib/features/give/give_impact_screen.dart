import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/give_impact_stats.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// The headline numbers. See `GiveImpactStats` for why these are
/// function-maintained counters, not a client-side scan of every donation.
class GiveImpactScreen extends ConsumerWidget {
  const GiveImpactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats =
        ref.watch(giveImpactStatsProvider).valueOrNull ?? GiveImpactStats.empty;
    // Cities active is derived from the curated centre list rather than
    // stored on the aggregate doc — see GiveImpactStats.hasActivity's doc
    // comment for why a distinct-city count can't be a simple increment.
    final centers = ref.watch(giveCollectionCentersProvider(null)).valueOrNull;
    final citiesActive = {for (final c in centers ?? const []) c.cityKey}.length;

    return AppScaffold(
      title: 'Impact so far',
      subtitle: 'What the Give network has moved',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!stats.hasActivity)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Just getting started — these numbers move as '
                      'donations are collected and delivered.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  crossAxisCount: context.windowSize.isCompact ? 2 : 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  children: [
                    _StatTile(
                      icon: Icons.volunteer_activism_outlined,
                      value: '${stats.donationsCount}',
                      label: 'Donations',
                    ),
                    _StatTile(
                      icon: Icons.inventory_2_outlined,
                      value: '${stats.itemsCollected}',
                      label: 'Items collected',
                    ),
                    _StatTile(
                      icon: Icons.local_shipping_outlined,
                      value: '${stats.itemsDistributed}',
                      label: 'Items delivered',
                    ),
                    _StatTile(
                      icon: Icons.checklist_rtl_outlined,
                      value: '${stats.needsFulfilled}',
                      label: 'Needs fulfilled',
                    ),
                    _StatTile(
                      icon: Icons.location_city_outlined,
                      value: '$citiesActive',
                      label: 'Cities active',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Every donated item is inspected, cleaned, safety-checked '
                    'and graded before it is packed and delivered — unsafe '
                    'items are rejected rather than passed on. See "My '
                    'donations" for a single item\'s own trail.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
