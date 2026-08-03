import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/ranking_entry.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// The ranking list — what people have won, over a rolling year.
///
/// Distinct from a rating, and the distinction matters. Glicko says how good
/// somebody is right now; this says what they have achieved and is what every
/// selection meeting in the world actually runs on. It is also the mechanism
/// that makes a district tournament worth entering: win one and your position
/// on this list moves that night, visibly, where a Telegram message vanishes.
class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key, this.orgId});

  /// Present when reached from inside a club, so the shell can show its
  /// navigation. The list itself spans every club — a ranking confined to one
  /// club is a club ladder, not a ranking.
  final String? orgId;

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  late String _sportId = SportCatalog.all.first.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(rankingProvider(_sportId));

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<String>(
            value: _sportId,
            decoration: const InputDecoration(
              labelText: 'Sport',
              isDense: true,
            ),
            items: [
              for (final sport in SportCatalog.all)
                DropdownMenuItem(value: sport.id, child: Text(sport.name)),
            ],
            onChanged: (v) => setState(() => _sportId = v ?? _sportId),
          ),
        ),
        Expanded(
          child: AsyncView(
            value: async,
            builder: (rows) {
              if (rows.isEmpty) {
                return const EmptyState(
                  icon: Icons.leaderboard_outlined,
                  title: 'No rankings yet',
                  message: 'Points are awarded when a tournament is closed. '
                      'Finish one and it appears here.',
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  ContentBounds(
                    maxWidth: 760,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Text(
                            'Points from the last 52 weeks. A result drops off '
                            'a year after it was won, so a ranking has to be '
                            'defended rather than banked.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final row in rows) _RankingTile(row: row),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );

    final orgId = widget.orgId;
    if (orgId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rankings')),
        body: body,
      );
    }
    return AppScaffold(orgId: orgId, title: 'Rankings', body: body);
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.row});

  final RankingRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        leading: SizedBox(
          width: 34,
          child: Center(
            child: Text(
              '${row.rank}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: row.rank <= 3
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(row.displayName),
        subtitle: Text(
          '${row.eventsCounted} result'
          '${row.eventsCounted == 1 ? '' : 's'} counting',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Text(
          '${row.points}',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        children: [
          // Every result carrying this ranking, and when each drops off. A
          // ranking nobody can account for is one people argue with.
          for (final e in row.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.tournamentName} · ${e.eventName}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          _describe(e, now),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${e.points}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _describe(RankingEntry e, DateTime now) {
    final label = e.round
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
    final days = e.daysRemainingAt(now);
    if (days == null) return label;
    if (days <= 0) return '$label · expired';
    if (days <= 30) return '$label · drops off in $days days';
    return label;
  }
}
