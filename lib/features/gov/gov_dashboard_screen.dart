import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/gov_aggregate_row.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// A rollup a district or state official could actually open — see
/// `functions/gov.js` for what this deliberately does and does not compute,
/// and `docs/` for the fuller cube this is a first, honest slice of.
class GovDashboardScreen extends ConsumerStatefulWidget {
  const GovDashboardScreen({super.key});

  @override
  ConsumerState<GovDashboardScreen> createState() =>
      _GovDashboardScreenState();
}

class _GovDashboardScreenState extends ConsumerState<GovDashboardScreen> {
  bool _recomputing = false;

  Future<void> _recompute() async {
    setState(() => _recomputing = true);
    try {
      final count = await ref.read(govRepositoryProvider).recompute();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recomputed $count district${count == 1 ? '' : 's'}.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isPlatformAdminProvider);

    return AppScaffold(
      title: 'Government dashboard',
      subtitle: 'Clubs, members and matches by district',
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _Denied(),
        data: (allowed) => allowed ? _body(context) : const _Denied(),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final rows = ref.watch(govAggregatesProvider);
    final theme = Theme.of(context);

    return AsyncView(
      value: rows,
      onRetry: () => ref.invalidate(govAggregatesProvider),
      builder: (list) {
        final totalClubs = list.fold<int>(0, (a, r) => a + r.clubCount);
        final totalMembers = list.fold<int>(0, (a, r) => a + r.memberCount);
        final totalMatches =
            list.fold<int>(0, (a, r) => a + r.completedMatchCount);
        final computedAt = list.isEmpty
            ? null
            : list
                .map((r) => r.computedAt)
                .whereType<DateTime>()
                .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 980,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            computedAt == null
                                ? 'Never computed'
                                : 'Last computed '
                                    '${DateFormat('d MMM, h:mm a').format(computedAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _recomputing ? null : _recompute,
                          icon: _recomputing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('Recompute'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Clubs & organizations',
                            value: totalClubs,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child:
                              _StatCard(label: 'Members', value: totalMembers),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Completed matches',
                            value: totalMatches,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (list.isEmpty)
                      const EmptyState(
                        icon: Icons.query_stats_outlined,
                        title: 'No rollup yet',
                        message: 'Tap Recompute to build the first one.',
                      )
                    else ...[
                      Text('By district', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _Table(rows: list),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              NumberFormat.decimalPattern('en_IN').format(value),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows});
  final List<GovAggregateRow> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('District')),
          DataColumn(label: Text('State')),
          DataColumn(label: Text('Clubs'), numeric: true),
          DataColumn(label: Text('Members'), numeric: true),
          DataColumn(label: Text('Events'), numeric: true),
          DataColumn(label: Text('Completed matches'), numeric: true),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(Text(r.district)),
              DataCell(Text(r.state)),
              DataCell(Text('${r.clubCount}')),
              DataCell(Text('${r.memberCount}')),
              DataCell(Text('${r.competitionCount}')),
              DataCell(Text('${r.completedMatchCount}')),
            ]),
        ],
      ),
    );
  }
}

class _Denied extends StatelessWidget {
  const _Denied();

  @override
  Widget build(BuildContext context) => const EmptyState(
        icon: Icons.lock_outline,
        title: 'Restricted',
        message: 'This dashboard is only visible to PlaySphere platform staff.',
      );
}
