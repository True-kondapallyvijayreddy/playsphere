import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/career/club_stats.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_context_banner.dart';
import '../../shared/ui_kit.dart';

/// A club's record, one row per sport it has played — the club-scoped
/// counterpart to [MySportsScreen], reached from the "Sports" counter on the
/// club's own home screen the same way that counter reaches [MySportsScreen]
/// from a player's profile.
class ClubStatsScreen extends ConsumerWidget {
  const ClubStatsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId));
    final fixtures = ref.watch(orgFixturesProvider(orgId));

    return Scaffold(
      appBar: AppBar(
        title: Text(org.valueOrNull?.name ?? 'Club stats'),
      ),
      body: AsyncView(
        value: fixtures,
        onRetry: () => ref.invalidate(orgFixturesProvider(orgId)),
        builder: (allFixtures) {
          final rows = ClubSportStats.forFixtures(allFixtures);
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No matches yet',
              message: 'A finished match credits this club automatically — '
                  'play one and its sport appears here.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // The app bar carries the club's name; this carries its
                    // id. A district with two "Sunrise" clubs is exactly
                    // where somebody screenshots the wrong one's numbers.
                    ClubContextBanner(orgId: orgId, label: 'Analytics for'),
                    for (final row in rows)
                      _ClubSportRow(orgId: orgId, stats: row),
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

class _ClubSportRow extends StatelessWidget {
  const _ClubSportRow({required this.orgId, required this.stats});

  final String orgId;
  final ClubSportStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = SportCatalog.byId(stats.sportId);
    final topCounters = stats.tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push(Routes.clubSportStats(orgId, stats.sportId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(sport.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sport.name, style: theme.textTheme.titleMedium),
                        Text(
                          '${stats.matches} '
                          '${stats.matches == 1 ? 'match' : 'matches'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: theme.hintColor),
                ],
              ),
              if (topCounters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in topCounters.take(6))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        label: Text(
                          '${psHumanizeCounter(e.key)} ${_format(e.value)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _format(num v) =>
      v is int || v == v.roundToDouble() ? psGrouped(v.round()) : v.toStringAsFixed(2);
}
