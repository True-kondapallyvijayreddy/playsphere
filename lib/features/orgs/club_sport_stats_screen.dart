import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/career/club_stats.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart' show friendlyDate;
import '../../shared/ui_kit.dart';
import '../../core/l10n/result_labels.dart';

/// One sport within a club's record — its full stat tally and its match
/// list, the club-scoped counterpart to [PlayerSportScreen].
///
/// No won/lost card, unlike the player version — see [ClubSportStats]'s own
/// doc for why a club's win/loss record is out of scope for now.
class ClubSportStatsScreen extends ConsumerWidget {
  const ClubSportStatsScreen({
    super.key,
    required this.orgId,
    required this.sportId,
  });

  final String orgId;
  final String sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(organizationProvider(orgId));
    final fixturesAsync =
        ref.watch(orgSportFixturesProvider((orgId: orgId, sportId: sportId)));
    final sport = SportCatalog.byId(sportId);

    return Scaffold(
      appBar: AppBar(
        title: Text('${sport.name} · ${org.valueOrNull?.name ?? 'Club'}'),
      ),
      body: AsyncView(
        value: fixturesAsync,
        onRetry: () => ref.invalidate(orgFixturesProvider(orgId)),
        builder: (fixtures) {
          final rows = ClubSportStats.forFixtures(fixtures);
          final stats = rows.isEmpty
              ? ClubSportStats(sportId: sportId, matches: 0, tally: const {})
              : rows.first;

          if (stats.isEmpty) {
            return EmptyState(
              icon: Icons.query_stats_outlined,
              title: 'No ${sport.name} matches yet',
              message: 'A finished match credits this club automatically.',
            );
          }

          final finished = fixtures.where((f) => f.countsTowardsRecords).toList()
            ..sort((a, b) {
              final at = a.completedAt ?? a.startedAt ?? a.scheduledAt;
              final bt = b.completedAt ?? b.startedAt ?? b.scheduledAt;
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;
              return bt.compareTo(at);
            });

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 900,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    PsCard(
                      child: PsStatRow(
                        stats: [
                          PsStat(
                            value: psGrouped(stats.matches),
                            label: 'Matches',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TallyCard(tally: stats.tally),
                    const SizedBox(height: 20),
                    Text(
                      'Matches',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    for (final f in finished) _ClubMatchTile(fixture: f),
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

class _TallyCard extends StatelessWidget {
  const _TallyCard({required this.tally});

  final Map<String, num> tally;

  @override
  Widget build(BuildContext context) {
    final entries = tally.entries.where((e) => e.value != 0).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    if (entries.isEmpty) return const SizedBox.shrink();

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Figures',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Ps.ink),
          ),
          const SizedBox(height: 10),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      psHumanizeCounter(entry.key),
                      style: const TextStyle(fontSize: 13, color: Ps.muted),
                    ),
                  ),
                  Text(
                    _format(entry.value),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Ps.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _format(num v) =>
      v is int || v == v.roundToDouble() ? psGrouped(v.round()) : v.toStringAsFixed(2);
}

/// One match on a club's list — told without taking either side, unlike
/// [PlayerMatchTile], which frames a result from one specific player's
/// side. A club match list has no single perspective to frame from: plenty
/// of these are the club's own teams playing each other.
class _ClubMatchTile extends StatelessWidget {
  const _ClubMatchTile({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = SportCatalog.byId(fixture.sport.split(':').first);
    final when = fixture.completedAt ?? fixture.startedAt ?? fixture.scheduledAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(sport.icon, style: const TextStyle(fontSize: 24)),
        title: Text(
          '${fixture.displayNameA()} v ${fixture.displayNameB()}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            fixture.resolvedSource.label,
            if (when != null) friendlyDate(when),
            if (fixture.summary.isNotEmpty)
              localizedSummary(context, fixture.summary),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Icon(Icons.chevron_right, color: theme.hintColor),
        onTap: () => context.push(
          Routes.watch(fixture.orgId, fixture.compId, fixture.id),
        ),
      ),
    );
  }
}
