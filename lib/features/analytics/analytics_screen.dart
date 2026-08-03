import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// What a club's own data says about it.
///
/// Everything here is derived from documents the screen is already entitled to
/// read — the roster, the competitions, the live fixtures — and nothing is
/// stored. That is a deliberate limit rather than a shortcut: a stored
/// aggregate that nobody rebuilds drifts from the matches underneath it, and a
/// participation number an organizer cannot reconcile against their own
/// fixture list is a number they will not trust twice.
///
/// The district → mandal → village rollups CLAUDE.md §6 Module D describes are
/// a different thing and are NOT here. They span clubs, which means they need a
/// server tier that can read across tenants; a client that could compute them
/// would be a client that could read every club in the state. The engine for
/// them already exists and is tested in `lib/domain/gov/`.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final membersAsync = ref.watch(orgMembersProvider(orgId));
    final compsAsync = ref.watch(competitionsProvider(orgId));
    final liveAsync = ref.watch(liveFixturesProvider(orgId));

    if (!caps.contains(Capability.viewAnalytics)) {
      return AppScaffold(
        orgId: orgId,
        title: 'Analytics',
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Analytics is for club organizers',
          message: 'An owner, admin or event manager of this club can open '
              'this. Your own record is on your career profile instead.',
        ),
      );
    }

    return AppScaffold(
      orgId: orgId,
      title: 'Analytics',
      body: AsyncView(
        value: compsAsync,
        onRetry: () => ref.invalidate(competitionsProvider(orgId)),
        builder: (comps) {
          final members = membersAsync.valueOrNull ?? const <Membership>[];
          final live = liveAsync.valueOrNull ?? const [];

          final active = members.where((m) => m.isActive).toList();
          final pending = members.where((m) => m.isPending).length;
          final entries = comps.fold<int>(0, (s, c) => s + c.entrantCount);
          final matches = comps.fold<int>(0, (s, c) => s + c.fixtureCount);

          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              ContentBounds(
                maxWidth: 1000,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AsyncErrorStrip(value: membersAsync, what: 'the roster'),
                    AsyncErrorStrip(value: liveAsync, what: 'live matches'),

                    Text(
                      'Everything below is counted from this club\'s own '
                      'roster and events, live.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),

                    AdaptiveGrid(
                      minTileWidth: 170,
                      childAspectRatio: 1.9,
                      children: [
                        _Kpi(value: '${active.length}', label: 'Active members'),
                        _Kpi(value: '$pending', label: 'Waiting to join'),
                        _Kpi(value: '${comps.length}', label: 'Events'),
                        _Kpi(value: '$entries', label: 'Entries taken'),
                        _Kpi(value: '$matches', label: 'Matches drawn'),
                        _Kpi(value: '${live.length}', label: 'Live right now'),
                      ],
                    ),
                    const SizedBox(height: 26),

                    _Breakdown(
                      title: 'Entries by sport',
                      caption: 'Where this club actually plays. One bar per '
                          'sport, longest first.',
                      empty: 'No entries yet.',
                      rows: _bySport(comps),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Events by stage',
                      caption: 'How much is in flight versus finished.',
                      empty: 'No events yet.',
                      rows: _byStatus(comps),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Entries by category',
                      caption: 'Age and gender categories entries were taken '
                          'in — the split Khelo India age bands are read from.',
                      empty: 'No entries yet.',
                      rows: _byCategory(comps),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Roster by role',
                      caption: 'Who can do what in this club today.',
                      empty: 'No members yet.',
                      rows: _byRole(active),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Joined recently',
                      caption: 'Members who joined within each window.',
                      empty: 'No members yet.',
                      rows: _byRecency(active),
                    ),
                    const SizedBox(height: 26),

                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.public_outlined),
                        title: Text('District and state rollups'),
                        subtitle: Text(
                          'Participation across clubs — mandal, district and '
                          'state — is computed on the server, not here. A '
                          'client that could add up other clubs would be a '
                          'client that could read them.',
                        ),
                        isThreeLine: true,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Aggregations — pure functions over what the screen already streams
// ---------------------------------------------------------------------------

List<_Row> _bySport(List<Competition> comps) {
  final totals = <String, int>{};
  for (final c in comps) {
    // Entries rather than events: two clubs each running one cricket event is
    // not the same fact as one of them entering ninety players into it.
    totals[c.sportId] = (totals[c.sportId] ?? 0) + c.entrantCount;
  }
  return _sorted({
    for (final e in totals.entries)
      '${SportCatalog.byId(e.key).icon}  ${SportCatalog.byId(e.key).name}':
          e.value,
  });
}

List<_Row> _byStatus(List<Competition> comps) {
  final totals = <String, int>{};
  for (final c in comps) {
    totals[c.status.label] = (totals[c.status.label] ?? 0) + 1;
  }
  return _sorted(totals);
}

List<_Row> _byCategory(List<Competition> comps) {
  final totals = <String, int>{};
  for (final c in comps) {
    if (c.entrantCount == 0) continue;
    totals[c.category.label] = (totals[c.category.label] ?? 0) + c.entrantCount;
  }
  return _sorted(totals);
}

List<_Row> _byRole(List<Membership> members) {
  final totals = <String, int>{};
  for (final m in members) {
    totals[m.role.label] = (totals[m.role.label] ?? 0) + 1;
  }
  return _sorted(totals);
}

List<_Row> _byRecency(List<Membership> members) {
  final now = DateTime.now();
  int within(int days) => members
      .where((m) =>
          m.joinedAt != null && now.difference(m.joinedAt!).inDays <= days)
      .length;

  final rows = [
    _Row('Last 7 days', within(7)),
    _Row('Last 30 days', within(30)),
    _Row('Last 90 days', within(90)),
    _Row('Last year', within(365)),
  ];
  return rows.every((r) => r.value == 0) ? const [] : rows;
}

List<_Row> _sorted(Map<String, int> totals) {
  final rows = [
    for (final e in totals.entries)
      if (e.value > 0) _Row(e.key, e.value),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return rows;
}

class _Row {
  const _Row(this.label, this.value);
  final String label;
  final int value;
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal bar breakdown.
///
/// One measure, one colour. The categories are named on their own rows, so
/// giving each bar a different hue would encode nothing that the label does not
/// already say — and it would make the eye read rank as identity. Bars are
/// sorted longest-first and every bar carries its number, which removes the
/// need for an axis at this size.
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.caption,
    required this.rows,
    required this.empty,
  });

  final String title;
  final String caption;
  final List<_Row> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = rows.isEmpty
        ? 1
        : rows.map((r) => r.value).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(caption, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Text(
            empty,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _Bar(row: r, max: max),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.row, required this.max});

  final _Row row;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max == 0 ? 0.0 : (row.value / max).clamp(0.02, 1.0);

    return Semantics(
      label: '${row.label}: ${row.value}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${row.value}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // The track is what makes a short bar legible as "small" rather than
          // as a rendering failure, so it stays visible but recessive.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 10,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                FractionallySizedBox(
                  widthFactor: fraction.toDouble(),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
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
