import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/tournament.dart';
import '../../core/models/venue.dart';
import '../../core/models/venue_plan.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../domain/draw/season_capacity.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';

/// The step where an organizer describes the *real world*, and the app does
/// the timetabling.
///
/// ## What this screen is for
///
/// Everything a season needs in order to be schedulable is a fact about a
/// place and a day: which grounds, which of their playing areas, which dates,
/// which hours of those dates, what is blacked out, how long a match takes
/// there, and how many the organizer is willing to run. Until this existed
/// the app asked for one of those seven — a list of venue ids — and inferred
/// the rest, which is why a schedule could put a match on a locked ground at
/// seven in the morning.
///
/// It deliberately shows the arithmetic beside every answer. An organizer who
/// types "4 matches a day" into a window that holds 3 has not created a
/// fourth slot, and being told so here is the difference between fixing it now
/// and discovering it at the venue.
class VenuePlannerScreen extends ConsumerWidget {
  const VenuePlannerScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tournamentAsync = ref.watch(tournamentProvider(key));
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Venue Planner',
      body: AsyncView(
        value: tournamentAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This season no longer exists',
            );
          }
          if (tournament.startDate == null) {
            return const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'Set the season dates first',
              message: 'Availability is described day by day, so the season '
                  'needs a start and an end before a ground can be planned.',
            );
          }

          final venuesAsync = ref.watch(venuesProvider(orgId));
          final plansAsync = ref.watch(venuePlansProvider(key));
          final linesAsync = ref.watch(venueCapacityLinesProvider(key));

          return AsyncView(
            value: venuesAsync,
            builder: (venues) {
              final inSeason = [
                for (final v in venues)
                  if (tournament.venueIds.contains(v.id)) v,
              ];
              if (inSeason.isEmpty) {
                return const EmptyState(
                  icon: Icons.stadium_outlined,
                  title: 'No grounds on this season yet',
                  message: 'Add a venue to the season before planning when it '
                      'is available.',
                );
              }

              final plans = plansAsync.valueOrNull ?? const <String, VenuePlan>{};
              final lines = <String, VenueCapacityLine>{
                for (final l in linesAsync.valueOrNull ?? const [])
                  l.venueId: l,
              };

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _SeasonRulesCard(
                    tournament: tournament,
                    canManage: canManage,
                    lines: lines.values.toList(),
                  ),
                  const SizedBox(height: 16),
                  for (final venue in inSeason) ...[
                    _VenueCard(
                      orgId: orgId,
                      tournamentId: tournamentId,
                      tournament: tournament,
                      venue: venue,
                      plan: plans[venue.id] ?? VenuePlan(venueId: venue.id),
                      line: lines[venue.id],
                      canManage: canManage,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The two numbers that belong to the whole season rather than to any one
/// ground: how long a person rests between their own matches, and how long it
/// takes them to get from one venue to another.
class _SeasonRulesCard extends ConsumerWidget {
  const _SeasonRulesCard({
    required this.tournament,
    required this.canManage,
    required this.lines,
  });

  final Tournament tournament;
  final bool canManage;
  final List<VenueCapacityLine> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    var totalSlots = 0;
    for (final l in lines) {
      totalSlots += l.totalMatchSlots;
    }

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Season-wide rules', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'These apply to a person wherever they are playing, so they live '
            'here rather than on one ground.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _RuleRow(
            label: 'Rest between a person\'s own matches',
            value: '${tournament.restGapMinutes} min',
            onTap: canManage
                ? () => _editSeasonRule(
                      context,
                      ref,
                      title: 'Minimum rest',
                      helper: 'Between two matches of the same player or team, '
                          'across every event they entered.',
                      initial: tournament.restGapMinutes,
                      options: const [0, 10, 15, 20, 30, 45, 60],
                      onSave: (v) => ref
                          .read(tournamentRepositoryProvider)
                          .updateTournament(
                            tournament.copyWith(restGapMinutes: v),
                          ),
                    )
                : null,
          ),
          _RuleRow(
            label: 'Travel between two venues',
            value: tournament.venueTransitionMinutes == 0
                ? 'Not set'
                : '${tournament.venueTransitionMinutes} min',
            onTap: canManage
                ? () => _editSeasonRule(
                      context,
                      ref,
                      title: 'Venue transition',
                      helper: 'Added on top of the rest gap when a person\'s '
                          'next match is at a different ground.',
                      initial: tournament.venueTransitionMinutes,
                      options: const [0, 10, 15, 20, 30, 45, 60],
                      onSave: (v) => ref
                          .read(tournamentRepositoryProvider)
                          .updateTournament(
                            tournament.copyWith(venueTransitionMinutes: v),
                          ),
                    )
                : null,
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Icon(Icons.event_available_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$totalSlots match slots across ${lines.length} '
                  '${lines.length == 1 ? 'ground' : 'grounds'}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editSeasonRule(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String helper,
    required int initial,
    required List<int> options,
    required Future<void> Function(int) onSave,
  }) async {
    final choice = await _pickMinutes(
      context,
      title: title,
      helper: helper,
      initial: initial,
      options: options,
    );
    if (choice == null || choice == initial) return;
    try {
      await onSave(choice);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// One ground, everything the season knows about it, and what that adds up to.
class _VenueCard extends ConsumerWidget {
  const _VenueCard({
    required this.orgId,
    required this.tournamentId,
    required this.tournament,
    required this.venue,
    required this.plan,
    required this.line,
    required this.canManage,
  });

  final String orgId;
  final String tournamentId;
  final Tournament tournament;
  final Venue venue;
  final VenuePlan plan;
  final VenueCapacityLine? line;
  final bool canManage;

  Future<void> _save(BuildContext context, WidgetRef ref, VenuePlan next) async {
    try {
      await ref.read(tournamentRepositoryProvider).saveVenuePlan(
            orgId: orgId,
            tournamentId: tournamentId,
            plan: next.copyWith(venueName: venue.name),
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = plan.sessionsFor(venue);
    final courts = [for (final c in venue.courts) if (plan.allowsCourt(c)) c];
    final days = _seasonDays(tournament);
    final openDays = [for (final d in days) if (plan.servesDay(d)) d];

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stadium_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(venue.name, style: theme.textTheme.titleMedium),
              ),
              if (!plan.isUnrestricted)
                const Chip(
                  label: Text('Planned', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Playing areas ----
          _PlanRow(
            icon: Icons.grid_view_outlined,
            label: 'Playing areas',
            value: '${courts.length} of ${venue.courts.length}'
                '${courts.isEmpty ? '' : ' · ${courts.map((c) => c.name).join(', ')}'}',
            onTap: canManage && venue.courts.isNotEmpty
                ? () async {
                    final picked = await _pickCourts(
                      context,
                      venue: venue,
                      selected: plan.courtIds,
                    );
                    if (picked == null || !context.mounted) return;
                    await _save(context, ref, plan.copyWith(courtIds: picked));
                  }
                : null,
          ),

          // ---- Which sports may use it ----
          _PlanRow(
            icon: Icons.sports_outlined,
            label: 'Sports allowed here',
            value: plan.sportIds.isEmpty
                ? 'Any sport'
                : plan.sportIds.join(', '),
            onTap: canManage
                ? () async {
                    final picked = await _pickSports(
                      context,
                      ref,
                      orgId: orgId,
                      tournamentId: tournamentId,
                      selected: plan.sportIds,
                    );
                    if (picked == null || !context.mounted) return;
                    await _save(context, ref, plan.copyWith(sportIds: picked));
                  }
                : null,
          ),

          // ---- Dates ----
          _PlanRow(
            icon: Icons.calendar_month_outlined,
            label: 'Available dates',
            value: '${openDays.length} of ${days.length} days',
            onTap: canManage
                ? () async {
                    final blackouts = await _pickDates(
                      context,
                      days: days,
                      plan: plan,
                    );
                    if (blackouts == null || !context.mounted) return;
                    await _save(
                      context,
                      ref,
                      plan.copyWith(blackouts: blackouts),
                    );
                  }
                : null,
          ),

          // ---- Sessions ----
          _PlanRow(
            icon: Icons.schedule_outlined,
            label: 'Playing sessions',
            value: plan.sessions.isEmpty
                ? '${sessions.first.timeLabel} (venue hours)'
                : [for (final s in plan.sessions) s.timeLabel].join('  ·  '),
            onTap: canManage
                ? () async {
                    final next = await _editSessions(
                      context,
                      venue: venue,
                      plan: plan,
                    );
                    if (next == null || !context.mounted) return;
                    await _save(context, ref, plan.copyWith(sessions: next));
                  }
                : null,
          ),

          // ---- Blackouts (part-day only; whole days are the date picker) ----
          _PlanRow(
            icon: Icons.block_outlined,
            label: 'Blackout periods',
            value: () {
              final partial = [
                for (final b in plan.blackouts)
                  if (!b.isWholeDay) b,
              ];
              if (partial.isEmpty) return 'None';
              return [
                for (final b in partial)
                  '${DateFormat('d MMM').format(b.date)} ${b.timeLabel}',
              ].join('  ·  ');
            }(),
            onTap: canManage
                ? () async {
                    final next = await _editBlackouts(
                      context,
                      days: days,
                      plan: plan,
                    );
                    if (next == null || !context.mounted) return;
                    await _save(context, ref, plan.copyWith(blackouts: next));
                  }
                : null,
          ),

          const Divider(height: 24),

          // ---- Match rules ----
          _PlanRow(
            icon: Icons.timer_outlined,
            label: 'Match duration',
            value: '${plan.matchMinutes ?? tournament.matchMinutesDefault} min'
                '${plan.matchMinutes == null ? ' (season default)' : ''}',
            onTap: canManage
                ? () async {
                    final v = await _pickMinutes(
                      context,
                      title: 'Match duration here',
                      helper: 'How long one match takes at ${venue.name}. A '
                          'cricket ground and a table-tennis hall are not the '
                          'same number.',
                      initial:
                          plan.matchMinutes ?? tournament.matchMinutesDefault,
                      options: const [15, 20, 30, 45, 60, 90, 120, 180, 240],
                    );
                    if (v == null || !context.mounted) return;
                    await _save(context, ref, plan.copyWith(matchMinutes: v));
                  }
                : null,
          ),
          _PlanRow(
            icon: Icons.refresh_outlined,
            label: 'Turnaround between matches',
            value:
                '${plan.turnaroundMinutes ?? tournament.changeoverMinutes} min'
                '${plan.turnaroundMinutes == null ? ' (season default)' : ''}',
            onTap: canManage
                ? () async {
                    final v = await _pickMinutes(
                      context,
                      title: 'Turnaround here',
                      helper: 'Players off, ground reset, next pair on.',
                      initial: plan.turnaroundMinutes ??
                          tournament.changeoverMinutes,
                      options: const [0, 5, 10, 15, 20, 30, 45, 60],
                    );
                    if (v == null || !context.mounted) return;
                    await _save(
                      context,
                      ref,
                      plan.copyWith(turnaroundMinutes: v),
                    );
                  }
                : null,
          ),
          _PlanRow(
            icon: Icons.numbers_outlined,
            label: 'Maximum matches per area per day',
            value: plan.maxMatchesPerCourtPerDay == 0
                ? 'No limit'
                : '${plan.maxMatchesPerCourtPerDay}',
            onTap: canManage
                ? () async {
                    final v = await _pickMinutes(
                      context,
                      title: 'Maximum matches a day',
                      helper: 'Your own ceiling for one playing area. The '
                          'schedule uses whichever is stricter — this, or what '
                          'the sessions physically hold.',
                      initial: plan.maxMatchesPerCourtPerDay,
                      options: const [0, 1, 2, 3, 4, 5, 6, 8, 10, 12],
                      zeroLabel: 'No limit',
                      unit: '',
                    );
                    if (v == null || !context.mounted) return;
                    await _save(
                      context,
                      ref,
                      plan.copyWith(maxMatchesPerCourtPerDay: v),
                    );
                  }
                : null,
          ),

          if (line != null) ...[
            const SizedBox(height: 12),
            _CapacityStrip(line: line!),
          ],

          if (canManage && !plan.isUnrestricted) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear this plan?'),
                      content: Text(
                        '${venue.name} goes back to its own opening hours, '
                        'every day of the season, with no limits.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true || !context.mounted) return;
                  try {
                    await ref
                        .read(tournamentRepositoryProvider)
                        .clearVenuePlan(
                          orgId: orgId,
                          tournamentId: tournamentId,
                          venueId: venue.id,
                        );
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Clear plan'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The organizer's ceiling and the arithmetic, side by side.
///
/// Showing both is the point: they are different facts and the scheduler uses
/// the stricter one. Collapsing them into a single "matches per day" is what
/// produced timetables that could not be played.
class _CapacityStrip extends StatelessWidget {
  const _CapacityStrip({required this.line});

  final VenueCapacityLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = line.limitExceedsReality;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'You allow',
                  value: line.organiserLimitPerCourtPerDay == 0
                      ? '—'
                      : '${line.organiserLimitPerCourtPerDay}/day',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Actually fits',
                  value: '${line.computedPerCourtPerDay}/day',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Total slots',
                  value: '${line.totalMatchSlots}',
                ),
              ),
            ],
          ),
          if (over) ...[
            const SizedBox(height: 8),
            Text(
              'You allow ${line.organiserLimitPerCourtPerDay} a day but a '
              '${line.matchMinutes}-minute match with a '
              '${line.turnaroundMinutes}-minute turnaround only fits '
              '${line.computedPerCourtPerDay} in these sessions. The schedule '
              'will use ${line.effectivePerCourtPerDay}.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          if (line.playableDays == 0) ...[
            const SizedBox(height: 8),
            Text(
              'This ground is not open on any day of the season.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

// --- Editors ---------------------------------------------------------------

/// Every day of the season, inclusive.
List<DateTime> _seasonDays(Tournament tournament) {
  final start = tournament.startDate;
  if (start == null) return const [];
  return [
    for (var i = 0; i < tournament.dayCount; i++)
      DateTime(start.year, start.month, start.day + i),
  ];
}

Future<int?> _pickMinutes(
  BuildContext context, {
  required String title,
  required String helper,
  required int initial,
  required List<int> options,
  String unit = ' min',
  String? zeroLabel,
}) {
  // Whatever is stored has to be offered, or opening the sheet silently
  // changes the value it was opened to inspect.
  final values = ({...options, initial}.toList()..sort());
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(helper, style: Theme.of(ctx).textTheme.bodySmall),
        ),
        for (final v in values)
          RadioListTile<int>(
            value: v,
            groupValue: initial,
            title: Text(v == 0 && zeroLabel != null ? zeroLabel : '$v$unit'),
            onChanged: (picked) => Navigator.of(ctx).pop(picked),
          ),
      ],
    ),
  );
}

Future<Set<String>?> _pickCourts(
  BuildContext context, {
  required Venue venue,
  required Set<String> selected,
}) {
  final chosen = selected.isEmpty
      ? {for (final c in venue.usableCourts) c.id}
      : {...selected};
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Playing areas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each area can hold a match at the same time — six tables is '
                'six simultaneous matches.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final court in venue.courts)
                CheckboxListTile(
                  value: chosen.contains(court.id),
                  title: Text(court.name),
                  subtitle: court.isAvailable
                      ? null
                      : const Text('Marked unavailable at this venue'),
                  onChanged: court.isAvailable
                      ? (v) => setDialogState(() {
                            if (v == true) {
                              chosen.add(court.id);
                            } else {
                              chosen.remove(court.id);
                            }
                          })
                      : null,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            // "All of them" is stored as the empty set, so adding a court to
            // the venue later is automatically available to the season rather
            // than silently excluded by a list written before it existed.
            onPressed: () => Navigator.of(ctx).pop(
              chosen.length == venue.usableCourts.length
                  ? <String>{}
                  : chosen,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<Set<String>?> _pickSports(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
  required String tournamentId,
  required Set<String> selected,
}) async {
  final events = ref
          .read(tournamentEventsProvider(
            (orgId: orgId, tournamentId: tournamentId),
          ))
          .valueOrNull ??
      const [];
  final sports = <String, String>{
    for (final e in events) e.sportId: e.sportName,
  };
  if (sports.isEmpty) return null;

  final chosen = {...selected};
  if (!context.mounted) return null;
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Sports allowed here'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Leave everything unticked to let any of this season\'s sports '
                'use the ground.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final entry in sports.entries)
                CheckboxListTile(
                  value: chosen.contains(entry.key),
                  title: Text(entry.value),
                  onChanged: (v) => setDialogState(() {
                    if (v == true) {
                      chosen.add(entry.key);
                    } else {
                      chosen.remove(entry.key);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              chosen.length == sports.length ? <String>{} : chosen,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// The date checklist. Ticking a day off writes a whole-day blackout, which is
/// the same concept the part-day editor uses — two ways to say a ground is
/// shut is two ways for them to disagree.
Future<List<VenueBlackout>?> _pickDates(
  BuildContext context, {
  required List<DateTime> days,
  required VenuePlan plan,
}) {
  final off = <String>{
    for (final b in plan.blackouts)
      if (b.isWholeDay) _dayKey(b.date),
  };
  final partial = [
    for (final b in plan.blackouts)
      if (!b.isWholeDay) b,
  ];

  return showDialog<List<VenueBlackout>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Available dates'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final day in days)
                  CheckboxListTile(
                    value: !off.contains(_dayKey(day)),
                    title: Text(DateFormat('EEE, d MMM').format(day)),
                    onChanged: (v) => setDialogState(() {
                      if (v == true) {
                        off.remove(_dayKey(day));
                      } else {
                        off.add(_dayKey(day));
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop([
              ...partial,
              for (final day in days)
                if (off.contains(_dayKey(day))) VenueBlackout(date: day),
            ]),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<List<DaySession>?> _editSessions(
  BuildContext context, {
  required Venue venue,
  required VenuePlan plan,
}) {
  final sessions = [...plan.sessionsFor(venue)];

  return showDialog<List<DaySession>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Playing sessions'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matches are only placed inside these windows. Two sessions '
                  'with a gap between them is how a lunch break is stated.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < sessions.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(sessions[i].timeLabel),
                    subtitle: Text(
                      sessions[i].label.isEmpty
                          ? '${sessions[i].minutes ~/ 60}h '
                              '${sessions[i].minutes % 60}m'
                          : sessions[i].label,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () async {
                            final edited = await _editOneSession(
                              ctx,
                              sessions[i],
                            );
                            if (edited == null) return;
                            setDialogState(() => sessions[i] = edited);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: sessions.length > 1
                              ? () => setDialogState(() => sessions.removeAt(i))
                              : null,
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final added = await _editOneSession(
                      ctx,
                      const DaySession(
                        startMinute: 14 * 60,
                        endMinute: 19 * 60,
                        label: 'Evening',
                      ),
                    );
                    if (added == null) return;
                    setDialogState(() => sessions.add(added));
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add a session'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final sorted = [...sessions]
                ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
              Navigator.of(ctx).pop(sorted);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<DaySession?> _editOneSession(
  BuildContext context,
  DaySession initial,
) async {
  var start = initial.startMinute;
  var end = initial.endMinute;
  final label = TextEditingController(text: initial.label);

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Morning',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts'),
              trailing: Text(DaySession.formatMinutes(start)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
                );
                if (picked == null) return;
                setDialogState(() => start = picked.hour * 60 + picked.minute);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ends'),
              trailing: Text(DaySession.formatMinutes(end)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
                );
                if (picked == null) return;
                setDialogState(() => end = picked.hour * 60 + picked.minute);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: end > start ? () => Navigator.of(ctx).pop(true) : null,
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  final labelText = label.text.trim();
  label.dispose();
  if (saved != true) return null;
  return DaySession(
    startMinute: start,
    endMinute: end,
    label: labelText,
  );
}

Future<List<VenueBlackout>?> _editBlackouts(
  BuildContext context, {
  required List<DateTime> days,
  required VenuePlan plan,
}) {
  final wholeDay = [
    for (final b in plan.blackouts)
      if (b.isWholeDay) b,
  ];
  final partial = [
    for (final b in plan.blackouts)
      if (!b.isWholeDay) b,
  ];

  return showDialog<List<VenueBlackout>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Blackout periods'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Part of a day the ground cannot be used. For a whole day '
                  'off, untick it under Available dates instead.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < partial.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${DateFormat('EEE, d MMM').format(partial[i].date)} · '
                      '${partial[i].timeLabel}',
                    ),
                    subtitle: partial[i].reason == null
                        ? null
                        : Text(partial[i].reason!),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () =>
                          setDialogState(() => partial.removeAt(i)),
                    ),
                  ),
                if (days.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final added = await _newBlackout(ctx, days: days);
                      if (added == null) return;
                      setDialogState(() => partial.add(added));
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add a blackout'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop([...wholeDay, ...partial]),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<VenueBlackout?> _newBlackout(
  BuildContext context, {
  required List<DateTime> days,
}) async {
  var date = days.first;
  var start = 12 * 60;
  var end = 14 * 60;
  final reason = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Blackout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _dayKey(date),
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final d in days)
                  DropdownMenuItem(
                    value: _dayKey(d),
                    child: Text(DateFormat('EEE, d MMM').format(d)),
                  ),
              ],
              onChanged: (v) {
                for (final d in days) {
                  if (_dayKey(d) == v) setDialogState(() => date = d);
                }
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('From'),
              trailing: Text(DaySession.formatMinutes(start)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60),
                );
                if (picked == null) return;
                setDialogState(() => start = picked.hour * 60 + picked.minute);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Until'),
              trailing: Text(DaySession.formatMinutes(end)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: ctx,
                  initialTime: TimeOfDay(hour: end ~/ 60, minute: end % 60),
                );
                if (picked == null) return;
                setDialogState(() => end = picked.hour * 60 + picked.minute);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'School exams',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: end > start ? () => Navigator.of(ctx).pop(true) : null,
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );

  final reasonText = reason.text.trim();
  reason.dispose();
  if (saved != true) return null;
  return VenueBlackout(
    date: date,
    startMinute: start,
    endMinute: end,
    reason: reasonText.isEmpty ? null : reasonText,
  );
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
