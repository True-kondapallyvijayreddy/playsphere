import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/tournament.dart';
import '../../core/models/venue.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Every tournament this club runs.
class TournamentsScreen extends ConsumerWidget {
  const TournamentsScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tournamentsProvider(orgId));
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Tournaments',
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.emoji_events_outlined),
              label: const Text('New tournament'),
            )
          : null,
      body: AsyncView(
        value: async,
        builder: (tournaments) {
          if (tournaments.isEmpty) {
            return EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No tournaments yet',
              message: canManage
                  ? 'A tournament holds many events — U-13 singles, senior '
                      'doubles, and the rest — sharing one set of courts and '
                      'one timetable. That sharing is what stops a day '
                      'overrunning.'
                  : 'This club has not run a tournament yet.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ContentBounds(
                maxWidth: 800,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in tournaments)
                      _TournamentCard(orgId: orgId, tournament: t),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => TournamentEditor(orgId: orgId),
      );
}

class _TournamentCard extends ConsumerWidget {
  const _TournamentCard({required this.orgId, required this.tournament});

  final String orgId;
  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = tournament;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push(Routes.tournament(orgId, t.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(t.grade.label)),
                  Chip(label: Text(t.status.label)),
                  if (t.eventCount > 0)
                    Chip(
                      label: Text(
                        '${t.eventCount} event${t.eventCount == 1 ? '' : 's'}',
                      ),
                    ),
                ],
              ),
              if (t.startDate != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.event_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _dateRange(t),
                      style: theme.textTheme.bodySmall,
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

  static String _dateRange(Tournament t) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final start = t.startDate;
    if (start == null) return 'Dates not set';
    final end = t.endDate;
    if (end == null || _sameDay(start, end)) return fmt(start);
    return '${fmt(start)} – ${fmt(end)}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Creates or edits a tournament.
class TournamentEditor extends ConsumerStatefulWidget {
  const TournamentEditor({super.key, required this.orgId, this.existing});

  final String orgId;
  final Tournament? existing;

  @override
  ConsumerState<TournamentEditor> createState() => _TournamentEditorState();
}

class _TournamentEditorState extends ConsumerState<TournamentEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');

  late TournamentGrade _grade = widget.existing?.grade ?? TournamentGrade.club;
  late DateTime? _start = widget.existing?.startDate;
  late DateTime? _end = widget.existing?.endDate;
  late final Set<String> _venueIds = {...?widget.existing?.venueIds};
  late int _matchMinutes = widget.existing?.matchMinutesDefault ?? 30;
  late int _changeover = widget.existing?.changeoverMinutes ?? 5;
  late int _restGap = widget.existing?.restGapMinutes ?? 20;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.existing == null;
    final venues = ref.watch(venuesProvider(widget.orgId)).valueOrNull ??
        const <Venue>[];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isNew ? 'New tournament' : 'Edit tournament',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: isNew,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Hyderabad District Championship 2026',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<TournamentGrade>(
              value: _grade,
              decoration: const InputDecoration(
                labelText: 'Grade',
                helperText: 'What winning here is worth. Recorded now so a '
                    'ranking table can be built later without arguing about '
                    'it retrospectively.',
                helperMaxLines: 3,
              ),
              items: [
                for (final g in TournamentGrade.values)
                  DropdownMenuItem(value: g, child: Text(g.label)),
              ],
              onChanged: (v) => setState(() => _grade = v ?? _grade),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Starts',
                    value: _start,
                    onChanged: (d) => setState(() {
                      _start = d;
                      if (_end != null && _end!.isBefore(d)) _end = d;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Ends',
                    value: _end,
                    firstDate: _start,
                    onChanged: (d) => setState(() => _end = d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text('Venues', style: theme.textTheme.labelLarge),
            if (venues.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No venues defined yet. Add one from the club menu first — '
                  'a tournament schedules onto real courts, and without them '
                  'there is nowhere to put a match.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            for (final v in venues)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _venueIds.contains(v.id),
                title: Text(v.name),
                subtitle: Text(
                  '${v.capacity} court${v.capacity == 1 ? '' : 's'} · '
                  '${v.openHour}:00–${v.closeHour}:00',
                ),
                onChanged: (on) => setState(() {
                  if (on == true) {
                    _venueIds.add(v.id);
                  } else {
                    _venueIds.remove(v.id);
                  }
                }),
              ),

            const SizedBox(height: 16),
            Text('Timing', style: theme.textTheme.labelLarge),
            _Stepper(
              label: 'Minutes per match',
              value: _matchMinutes,
              min: 5,
              max: 240,
              step: 5,
              onChanged: (v) => setState(() => _matchMinutes = v),
            ),
            _Stepper(
              label: 'Changeover',
              value: _changeover,
              min: 0,
              max: 30,
              step: 5,
              onChanged: (v) => setState(() => _changeover = v),
            ),
            _Stepper(
              label: 'Minimum rest per player',
              value: _restGap,
              min: 0,
              max: 120,
              step: 5,
              onChanged: (v) => setState(() => _restGap = v),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The rest gap holds across every event. Somebody in the '
                'singles, the doubles and the mixed will not be called '
                'straight from one court to the next.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(isNew ? 'Create' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave =>
      !_busy && _name.text.trim().isNotEmpty && _start != null;

  Future<void> _save() async {
    setState(() => _busy = true);
    final repo = ref.read(tournamentRepositoryProvider);
    final uid = ref.read(currentUidProvider);

    final t = Tournament(
      id: widget.existing?.id ?? '',
      orgId: widget.orgId,
      name: _name.text.trim(),
      status: widget.existing?.status ?? TournamentStatus.draft,
      grade: _grade,
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      venueIds: _venueIds.toList(),
      startDate: _start,
      endDate: _end ?? _start,
      eventCount: widget.existing?.eventCount ?? 0,
      matchMinutesDefault: _matchMinutes,
      changeoverMinutes: _changeover,
      restGapMinutes: _restGap,
      createdBy: widget.existing?.createdBy ?? uid,
      createdAt: widget.existing?.createdAt,
    );

    try {
      if (widget.existing == null) {
        await repo.createTournament(t);
      } else {
        await repo.updateTournament(t);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
  });

  final String label;
  final DateTime? value;
  final DateTime? firstDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: v ?? firstDate ?? now,
          firstDate: firstDate ?? DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text(
          v == null
              ? 'Pick a date'
              : '${v.day.toString().padLeft(2, '0')}/'
                  '${v.month.toString().padLeft(2, '0')}/${v.year}',
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
        ),
      ],
    );
  }
}
