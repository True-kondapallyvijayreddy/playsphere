import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
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
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
            children: [
              ContentBounds(
                maxWidth: 1000,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AsyncErrorStrip(value: membersAsync, what: 'the roster'),
                    AsyncErrorStrip(value: liveAsync, what: 'live matches'),

                    Text(
                      'Counted from this club\'s own roster and events, live. '
                      'Every number here opens the list it was counted from.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),

                    // The one number on this screen that is an OBLIGATION
                    // rather than an observation, promoted out of the grid
                    // when it is not zero. A pending join request is somebody
                    // waiting on a human, and it used to be the second tile in
                    // a row of six identical grey cards — indistinguishable
                    // from "matches drawn", which nobody has to do anything
                    // about.
                    if (pending > 0) ...[
                      _PendingBanner(orgId: orgId, pending: pending),
                      const SizedBox(height: 14),
                    ],

                    const _SectionTitle(
                      'The club today',
                      caption: 'Where the roster and the fixture list stand '
                          'right now.',
                    ),
                    AdaptiveGrid(
                      minTileWidth: 170,
                      // A fixed height rather than a ratio, on the grid's own
                      // advice: a tile holding a number, a label and up to two
                      // lines of hint needs the same height whether it is one
                      // of four on a laptop or one of two on a phone, and a
                      // ratio ties it to a width that changes with the column
                      // count.
                      tileHeight: 148,
                      children: [
                        _Kpi(
                          value: '${active.length}',
                          label: 'Active members',
                          hint: 'Approved and able to play',
                          icon: Icons.groups_outlined,
                          onTap: () => context.push(Routes.members(orgId)),
                        ),
                        _Kpi(
                          value: '$pending',
                          label: 'Waiting to join',
                          hint: pending == 0
                              ? 'Nothing to approve'
                              : 'Tap to approve or decline',
                          icon: Icons.person_add_alt_outlined,
                          emphasis: pending > 0,
                          onTap: () => context.push(Routes.members(orgId)),
                        ),
                        _Kpi(
                          value: '${comps.length}',
                          label: 'Events',
                          hint: 'Tournaments, seasons and one-off matches',
                          icon: Icons.emoji_events_outlined,
                          onTap: () => context.push(Routes.org(orgId)),
                        ),
                        _Kpi(
                          value: '$entries',
                          label: 'Entries taken',
                          hint: 'Players and teams entered across all events',
                          icon: Icons.how_to_reg_outlined,
                          onTap: () => context.push(Routes.org(orgId)),
                        ),
                        _Kpi(
                          value: '$matches',
                          label: 'Matches drawn',
                          hint: 'Fixtures created by the draws',
                          icon: Icons.account_tree_outlined,
                          onTap: () => context.push(Routes.org(orgId)),
                        ),
                        _Kpi(
                          value: '${live.length}',
                          label: 'Live right now',
                          hint: live.isEmpty
                              ? 'Nothing being scored'
                              : 'Tap to watch or score',
                          icon: Icons.sensors,
                          emphasis: live.isNotEmpty,
                          onTap: () => context.push(Routes.live(orgId)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    const _SectionTitle(
                      'What this club plays',
                      caption: 'Entries, not events: one cricket tournament '
                          'with ninety players in it is ninety.',
                    ),
                    _Breakdown(
                      title: 'Entries by sport',
                      caption: 'Longest first. Tap a sport for this club\'s '
                          'record in it.',
                      empty: 'No entries yet. Numbers appear here as soon as '
                          'an event takes its first entry.',
                      rows: _bySport(comps, orgId),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Entries by category',
                      caption: 'The age and gender splits entries were taken '
                          'in — the bands Khelo India reporting is read from.',
                      empty: 'No entries yet.',
                      rows: _byCategory(comps),
                    ),
                    const SizedBox(height: 28),

                    const _SectionTitle(
                      'Where the work is',
                      caption: 'How much is still in flight, and who is here '
                          'to run it.',
                    ),
                    _Breakdown(
                      title: 'Events by stage',
                      caption: 'One bar per stage, counting events rather '
                          'than entries.',
                      empty: 'No events yet.',
                      rows: _byStatus(comps),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Roster by role',
                      caption: 'Who can do what in this club today. Tap any '
                          'row to open the roster.',
                      empty: 'No members yet.',
                      rows: _byRole(active, orgId),
                    ),
                    const SizedBox(height: 22),

                    _Breakdown(
                      title: 'Joined recently',
                      caption: 'How fast the club is growing. The windows '
                          'overlap — the last 7 days are inside the last 30.',
                      empty: 'No members yet.',
                      rows: _byRecency(active),
                    ),
                    const SizedBox(height: 28),

                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.public_outlined),
                        title: const Text('District and state rollups'),
                        subtitle: const Text(
                          'Participation across clubs — mandal, district and '
                          'state — is computed on the server, not here. A '
                          'client that could add up other clubs would be a '
                          'client that could read them.',
                        ),
                        isThreeLine: true,
                        // Not a dead tile any more: the club's own multi-sport
                        // record is the nearest thing this screen can actually
                        // show, and an organizer reading about rollups they
                        // cannot have should be handed the one they can.
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(Routes.clubStats(orgId)),
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

List<_Row> _bySport(List<Competition> comps, String orgId) {
  final totals = <String, int>{};
  for (final c in comps) {
    // Entries rather than events: two clubs each running one cricket event is
    // not the same fact as one of them entering ninety players into it.
    totals[c.sportId] = (totals[c.sportId] ?? 0) + c.entrantCount;
  }
  final rows = [
    for (final e in totals.entries)
      if (e.value > 0)
        _Row(
          '${SportCatalog.byId(e.key).icon}  ${SportCatalog.byId(e.key).name}',
          e.value,
          // The sportId is kept rather than dissolved into the label, which is
          // what made these bars unclickable before: the screen had a pretty
          // string and no way back to the sport it named.
          route: Routes.clubSportStats(orgId, e.key),
        ),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return rows;
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

List<_Row> _byRole(List<Membership> members, String orgId) {
  final totals = <String, int>{};
  for (final m in members) {
    totals[m.role.label] = (totals[m.role.label] ?? 0) + 1;
  }
  return _sorted(totals, route: Routes.members(orgId));
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

List<_Row> _sorted(Map<String, int> totals, {String? route}) {
  final rows = [
    for (final e in totals.entries)
      if (e.value > 0) _Row(e.key, e.value, route: route),
  ]..sort((a, b) => b.value.compareTo(a.value));
  return rows;
}

class _Row {
  const _Row(this.label, this.value, {this.route});

  final String label;
  final int value;

  /// Where this bar leads, or null for a bar that is only a number.
  ///
  /// Not every breakdown has an honest destination — "Joined recently" is a
  /// window, not a place — and a row that looks tappable and does nothing is
  /// worse than one that plainly is not. So the affordance is drawn from
  /// this: rows with a route get a chevron and a ripple, rows without get
  /// neither.
  final String? route;
}

// ---------------------------------------------------------------------------
// Presentation
// ---------------------------------------------------------------------------

/// A heading with the sentence that says what the numbers under it mean.
///
/// The screen used to be six grey tiles and five bar charts with nothing
/// between them, so an organizer had to infer from the titles alone whether
/// "Entries taken" and "Entries by sport" counted the same thing (they do) or
/// whether "Events by stage" counted events or entries (events). Grouping them
/// under a named section with one plain sentence is most of what "make it
/// clearer" is.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(caption, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The join requests, pulled out of the grid because somebody is waiting.
class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.orgId, required this.pending});

  final String orgId;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.person_add_alt, color: scheme.onPrimaryContainer),
        title: Text(
          '$pending ${pending == 1 ? 'person is' : 'people are'} waiting to '
          'join',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: scheme.onPrimaryContainer,
          ),
        ),
        subtitle: Text(
          'They cannot be entered into anything until somebody approves them.',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
        onTap: () => context.push(Routes.members(orgId)),
      ),
    );
  }
}

/// One headline number, and the list it was counted from.
///
/// Every tile leads somewhere. That is the fix rather than a flourish: a
/// dashboard whose numbers are dead ends makes the organizer who spots
/// something wrong — nine entries where there should be ninety — go and find
/// the screen that could show them why, and the number they were looking at
/// is the best possible link to it.
class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.value,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.emphasis = false,
  });

  final String value;
  final String label;

  /// The half-sentence that says what was counted, or what tapping does.
  final String hint;

  final IconData icon;
  final VoidCallback onTap;

  /// Whether this number is asking for something. Colours the tile rather
  /// than adding a badge — there are six of these on a phone screen and a row
  /// of badges is noise.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = emphasis ? scheme.primary : scheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      color: emphasis ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Semantics(
            button: true,
            label: '$value $label. $hint',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: tint),
                    const Spacer(),
                    Icon(Icons.chevron_right, size: 18, color: tint),
                  ],
                ),
                const Spacer(),
                Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(color: tint),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final r in rows) _Bar(row: r, max: max),
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

    final route = row.route;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(14, 10, route == null ? 14 : 6, 10),
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
              if (route != null)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 6),
          // The track is what makes a short bar legible as "small" rather than
          // as a rendering failure, so it stays visible but recessive.
          Padding(
            padding: EdgeInsets.only(right: route == null ? 0 : 18),
            child: ClipRRect(
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
          ),
        ],
      ),
    );

    return Semantics(
      button: route != null,
      label: '${row.label}: ${row.value}',
      excludeSemantics: true,
      child: route == null
          ? content
          : InkWell(onTap: () => context.push(route), child: content),
    );
  }
}
