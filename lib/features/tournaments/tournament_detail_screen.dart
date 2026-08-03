import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/tournament.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/tournament/tournament_overview.dart';
import '../../shared/app_scaffold.dart';
import 'tournaments_screen.dart' show TournamentEditor;
import 'widgets/running_late_card.dart';

/// One tournament at a glance: how far through it is, what is on court right
/// now, what is next, every event with its table, and who has won what.
///
/// The screen an organizer keeps open all weekend and a parent refreshes from
/// the car park. Everything on it is derived from the matches — nothing here
/// is a stored figure that could drift from the results it summarises.
class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tAsync = ref.watch(tournamentProvider(key));
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Tournament',
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }

          final overview = ref.watch(tournamentOverviewProvider(key));

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 960,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      orgId: orgId,
                      tournament: tournament,
                      canManage: canManage,
                    ),
                    const SizedBox(height: 16),
                    if (overview.hasError)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: const Text('Could not load the matches'),
                          subtitle: Text(errorMessage(overview.error!)),
                        ),
                      )
                    else ...[
                      _Progress(
                        tournament: tournament,
                        overview: overview.valueOrNull,
                      ),
                      const SizedBox(height: 16),
                      if (canManage)
                        _ScheduleCard(
                          orgId: orgId,
                          tournament: tournament,
                          overview: overview.valueOrNull,
                        ),
                      if (canManage)
                        RunningLateCard(
                          fixtures: ref
                                  .watch(tournamentFixturesProvider(
                                      tournamentId))
                                  .valueOrNull ??
                              const [],
                          onShift: ({by, newStart}) => ref
                              .read(tournamentRepositoryProvider)
                              .shiftSchedule(
                                orgId: orgId,
                                tournamentId: tournamentId,
                                by: by,
                                newStart: newStart,
                              ),
                        ),
                      _OnCourtNow(
                        orgId: orgId,
                        overview: overview.valueOrNull,
                      ),
                      _UpNext(orgId: orgId, overview: overview.valueOrNull),
                      _Events(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        canManage: canManage,
                        overview: overview.valueOrNull,
                      ),
                      _Honours(overview: overview.valueOrNull),
                    ],
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

class _Header extends ConsumerWidget {
  const _Header({
    required this.orgId,
    required this.tournament,
    required this.canManage,
  });

  final String orgId;
  final Tournament tournament;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = tournament;
    final venues = ref.watch(venuesProvider(orgId)).valueOrNull ?? const [];
    final named = [
      for (final v in venues)
        if (t.venueIds.contains(v.id)) v,
    ];
    final courtCount =
        named.fold<int>(0, (sum, v) => sum + v.capacity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      Text(t.name, style: theme.textTheme.headlineSmall),
                ),
                if (canManage)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) =>
                          TournamentEditor(orgId: orgId, existing: t),
                    ),
                  ),
              ],
            ),
            if (t.description != null) ...[
              const SizedBox(height: 4),
              Text(t.description!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(t.grade.label)),
                Chip(label: Text(t.status.label)),
                Chip(
                  avatar: const Icon(Icons.event_outlined, size: 16),
                  label: Text(_dateRange(t)),
                ),
                if (courtCount > 0)
                  Chip(
                    avatar: const Icon(Icons.grid_view_outlined, size: 16),
                    label: Text('$courtCount courts'),
                  ),
              ],
            ),
            if (named.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      named.map((v) => v.name).join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _dateRange(Tournament t) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final start = t.startDate;
    if (start == null) return 'Dates not set';
    final end = t.endDate;
    if (end == null ||
        (end.year == start.year &&
            end.month == start.month &&
            end.day == start.day)) {
      return '${fmt(start)}/${start.year}';
    }
    return '${fmt(start)} – ${fmt(end)}/${end.year}';
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.tournament, required this.overview});

  final Tournament tournament;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    if (o == null || o.totalMatches == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: o.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _Stat(label: 'Matches played', value: '${o.playedMatches}'),
                _Stat(label: 'Remaining', value: '${o.remainingMatches}'),
                _Stat(
                  label: 'Events',
                  value: '${o.completedEvents} / ${o.events.length} done',
                ),
                if (o.liveMatches > 0)
                  _Stat(label: 'Live now', value: '${o.liveMatches}'),
                if (o.scheduledThrough != null)
                  _Stat(
                    label: 'Last match starts',
                    value: _stamp(o.scheduledThrough!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Lays every event's matches onto the shared courts, in one pass.
class _ScheduleCard extends ConsumerStatefulWidget {
  const _ScheduleCard({
    required this.orgId,
    required this.tournament,
    required this.overview,
  });

  final String orgId;
  final Tournament tournament;
  final TournamentOverview? overview;

  @override
  ConsumerState<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends ConsumerState<_ScheduleCard> {
  bool _busy = false;
  String? _summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.tournament;
    final blocked = t.venueIds.isEmpty
        ? 'Pick at least one venue before generating a schedule.'
        : (widget.overview?.events.isEmpty ?? true)
            ? 'Add events to this tournament first.'
            : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order of play', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                blocked ??
                    'Lays every event onto the shared courts at once — so two '
                        'draws can never take the same court, and nobody '
                        'entered in three events is called to two of them at '
                        'the same minute.',
                style: theme.textTheme.bodySmall,
              ),
              if (_summary != null) ...[
                const SizedBox(height: 10),
                Text(_summary!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _busy || blocked != null ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.calendar_month_outlined),
                label: const Text('Generate the schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _summary = null;
    });
    try {
      final report =
          await ref.read(tournamentRepositoryProvider).generateSchedule(
                orgId: widget.orgId,
                tournamentId: widget.tournament.id,
              );
      if (!mounted) return;
      final finish = report.finishesAt;
      setState(() {
        _summary = [
          '${report.scheduled} matches placed across ${report.courts} courts '
              'in ${report.events} events.',
          if (finish != null)
            'Last match starts '
                '${finish.day.toString().padLeft(2, '0')}/'
                '${finish.month.toString().padLeft(2, '0')} at '
                '${finish.hour.toString().padLeft(2, '0')}:'
                '${finish.minute.toString().padLeft(2, '0')}.',
          if (report.unscheduled > 0)
            '${report.unscheduled} could not be placed:',
          ...report.problems,
        ].join('\n');
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _OnCourtNow extends StatelessWidget {
  const _OnCourtNow({required this.orgId, required this.overview});

  final String orgId;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final live = overview?.onCourtNow ?? const <Fixture>[];
    if (live.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text('On court now', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          for (final f in live) _MatchRow(orgId: orgId, fixture: f),
        ],
      ),
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.orgId, required this.overview});

  final String orgId;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final next = overview?.upNext ?? const <Fixture>[];
    if (next.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Up next', style: theme.textTheme.titleMedium),
          ),
          for (final f in next) _MatchRow(orgId: orgId, fixture: f),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.orgId, required this.fixture});

  final String orgId;
  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fixture;
    final when = f.scheduledAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: () =>
            context.push(Routes.competition(orgId, f.compId)),
        title: Text(
          // The qualifier label rather than "To be decided": a bracket slot
          // waiting on a group should say which group.
          '${f.displayNameA()}  v  ${f.displayNameB()}',
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Text(
          [
            if (f.roundLabel != null) f.roundLabel!,
            if (f.courtId != null) f.courtId! else if (f.venue != null) f.venue!,
            if (when != null)
              '${when.hour.toString().padLeft(2, '0')}:'
                  '${when.minute.toString().padLeft(2, '0')}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: f.isLive
            ? Icon(Icons.circle, size: 10, color: theme.colorScheme.error)
            : null,
      ),
    );
  }
}

/// Every event, with its own points table where the format has one.
class _Events extends ConsumerWidget {
  const _Events({
    required this.orgId,
    required this.tournamentId,
    required this.canManage,
    required this.overview,
  });

  final String orgId;
  final String tournamentId;
  final bool canManage;
  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = overview?.events ?? const <EventSummary>[];
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  events.isEmpty ? 'Events' : 'Events (${events.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (canManage)
                  TextButton.icon(
                    onPressed: () => _attach(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add events'),
                  ),
              ],
            ),
          ),
          if (events.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.playlist_add_outlined),
                title: Text('No events yet'),
                subtitle: Text(
                  'A tournament holds many draws — U-13 singles, senior '
                  'doubles, and the rest. Create them as events for this '
                  'club, then attach them here so they share courts and one '
                  'timetable.',
                ),
              ),
            )
          else
            for (final e in events) _EventTile(orgId: orgId, summary: e),
        ],
      ),
    );
  }

  Future<void> _attach(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _AttachEventsSheet(
          orgId: orgId,
          tournamentId: tournamentId,
        ),
      );
}

/// Picks which of the club's existing events belong to this tournament.
///
/// Only events not already attached elsewhere are offered — an event belongs
/// to one tournament, because its matches are scheduled against one shared
/// pool of courts and being in two timetables at once is not a state that
/// means anything.
class _AttachEventsSheet extends ConsumerStatefulWidget {
  const _AttachEventsSheet({
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  ConsumerState<_AttachEventsSheet> createState() =>
      _AttachEventsSheetState();
}

class _AttachEventsSheetState extends ConsumerState<_AttachEventsSheet> {
  final _picked = <String>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(competitionsProvider(widget.orgId)).valueOrNull ??
        const <Competition>[];
    final free = [
      for (final c in all)
        if (c.tournamentId == null) c,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add events', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Events already in another tournament are not listed — one '
              'event belongs to one timetable.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (free.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No unattached events. Create one from the club first.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final c in free)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _picked.contains(c.id),
                title: Text(c.name),
                subtitle: Text(
                  '${c.sportName} · ${c.category.label} · ${c.format.label}',
                ),
                onChanged: (on) => setState(() {
                  if (on == true) {
                    _picked.add(c.id);
                  } else {
                    _picked.remove(c.id);
                  }
                }),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _picked.isEmpty || _busy ? null : _save,
                  child: Text('Add ${_picked.length}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final repo = ref.read(tournamentRepositoryProvider);
    try {
      for (final compId in _picked) {
        await repo.addEvent(
          orgId: widget.orgId,
          tournamentId: widget.tournamentId,
          compId: compId,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.orgId, required this.summary});

  final String orgId;
  final EventSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = summary.competition;
    final showsTable = _tableFormats.contains(c.format);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(c.name),
        subtitle: Text(
          '${c.format.label} · ${c.category.label} · '
          '${summary.played}/${summary.total} played'
          '${summary.champion != null ? ' · ${summary.champion}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        leading: summary.isComplete
            ? Icon(Icons.emoji_events, color: theme.colorScheme.primary)
            : summary.live > 0
                ? Icon(Icons.circle, size: 12, color: theme.colorScheme.error)
                : const Icon(Icons.schedule_outlined),
        children: [
          if (showsTable)
            _EventTable(orgId: orgId, competition: c)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'A ${c.format.label.toLowerCase()} has no points table — '
                'progress is the bracket itself.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    context.push(Routes.competition(orgId, c.id)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open the event'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _tableFormats = {
    CompetitionFormat.roundRobin,
    CompetitionFormat.leagueTable,
    CompetitionFormat.swiss,
    CompetitionFormat.groupThenKnockout,
  };
}

/// The points table for one event, inline.
///
/// A groups draw gets one table per group with the qualifying line drawn; a
/// league gets a single table. Both come from the same calculator the event
/// screen uses, so the tournament view can never disagree with the event view.
class _EventTable extends ConsumerWidget {
  const _EventTable({required this.orgId, required this.competition});

  final String orgId;
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = CompRef(orgId, competition.id);

    if (competition.format == CompetitionFormat.groupThenKnockout) {
      final groups = ref.watch(groupStandingsProvider(key)).valueOrNull ??
          const <String, List<Standing>>{};
      if (groups.isEmpty) return const SizedBox.shrink();
      final ids = groups.keys.toList()..sort();
      return Column(
        children: [
          for (final id in ids)
            _Table(
              caption: 'Group $id',
              rows: groups[id]!,
              qualifiers: competition.drawConfig.qualifiersPerGroup,
            ),
        ],
      );
    }

    final table = ref.watch(standingsProvider(key)).valueOrNull ??
        const <Standing>[];
    if (table.isEmpty) return const SizedBox.shrink();
    return _Table(caption: null, rows: table, qualifiers: 0);
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.caption,
    required this.rows,
    required this.qualifiers,
  });

  final String? caption;
  final List<Standing> rows;
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(caption!, style: theme.textTheme.labelLarge),
            ),
          Row(
            children: [
              const SizedBox(width: 22),
              Expanded(child: Text('Team', style: theme.textTheme.labelSmall)),
              SizedBox(
                width: 26,
                child: Text('P',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 26,
                child: Text('W',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 26,
                child: Text('L',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
              SizedBox(
                width: 32,
                child: Text('Pts',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall),
              ),
            ],
          ),
          const Divider(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: qualifiers > 0 && i < qualifiers
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: qualifiers > 0 && i < qualifiers
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].displayName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: Text('${rows[i].played}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall),
                  ),
                  SizedBox(
                    width: 26,
                    child: Text('${rows[i].won}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall),
                  ),
                  SizedBox(
                    width: 26,
                    child: Text('${rows[i].lost}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${rows[i].points}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            if (qualifiers > 0 &&
                i == qualifiers - 1 &&
                i < rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: theme.colorScheme.primary)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'qualify',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                    Expanded(child: Divider(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Who has won what — the board that replaces a Telegram message.
class _Honours extends StatelessWidget {
  const _Honours({required this.overview});

  final TournamentOverview? overview;

  @override
  Widget build(BuildContext context) {
    final champions = overview?.champions ?? const <EventSummary>[];
    if (champions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Champions', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in champions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.competition.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      e.champion!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
