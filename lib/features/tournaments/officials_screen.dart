import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/match_official.dart';
import '../../core/models/tournament_official.dart';
import '../../core/providers.dart';
import '../../domain/draw/officials_roster.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../domain/tournament/officiating_demand.dart';
import '../../shared/app_scaffold.dart';
import '../competitions/widgets/season_officials_field.dart'
    show AddOfficialSheet;

/// The season owner's officiating panel — added ahead of the tournament,
/// ICC-style, so nobody is chasing an umpire at the gate.
///
/// Three things happen here, in the order an organizer actually needs them:
/// build the panel (from the open registry, or by hand), run the neutral
/// bulk assignment once the bracket is scheduled, and fix by hand whatever
/// it could not place. The bulk step never overwrites a hand fix — see
/// [TournamentRepository.assignOfficialsAcrossTournament].
class OfficialsScreen extends ConsumerWidget {
  const OfficialsScreen({
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

    return AppScaffold(
      orgId: orgId,
      title: 'Officials',
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add_alt_outlined),
          tooltip: 'Add an official',
          onPressed: () => _addOfficial(context, ref),
        ),
      ],
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }

          final rosterAsync = ref.watch(tournamentOfficialsProvider(key));
          final roster = rosterAsync.valueOrNull ?? const <TournamentOfficial>[];
          final fixturesAsync = ref.watch(tournamentFixturesProvider(key));
          final fixtures = fixturesAsync.valueOrNull ?? const <Fixture>[];
          final unofficiated = [
            for (final f in fixtures)
              if (f.officials.isEmpty && f.status == FixtureStatus.scheduled)
                f,
          ];

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    AsyncErrorStrip(value: rosterAsync, what: 'the panel'),
                    AsyncErrorStrip(
                      value: fixturesAsync,
                      what: 'the matches',
                    ),
                    // Above the panel, because it is the question the panel
                    // is the answer to. An organizer opening this screen is
                    // deciding who else to call, and "kabaddi: 12 matches,
                    // nobody on the panel" is that decision made.
                    _CoverageBySport(
                      demand: officiatingDemand(
                        events: ref
                                .watch(tournamentEventsProvider(key))
                                .valueOrNull ??
                            const [],
                        fixtures: fixtures,
                        roster: roster,
                      ),
                    ),
                    if (roster.isEmpty)
                      const EmptyState(
                        icon: Icons.sports_outlined,
                        title: 'No officials added yet',
                        message: 'Add umpires and referees to this '
                            "tournament's panel before the draw goes live — "
                            'pick from the open registry, or add someone by '
                            'hand.',
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Text(
                          'Panel (${roster.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final o in roster)
                        _OfficialTile(
                          orgId: orgId,
                          tournamentId: tournamentId,
                          official: o,
                          seasonDays: seasonDayKeys(fixtures),
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.rule_outlined),
                        label: const Text(
                          'Assign officials across the bracket',
                        ),
                        onPressed: () => _runBulkAssign(context, ref),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Neutral by construction — nobody is placed on a '
                          "match their own club is playing. What can't be "
                          'placed is reported below, not silently skipped.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                    if (unofficiated.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Text(
                          'Still need an official (${unofficiated.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final f in unofficiated)
                        _UnstaffedFixtureTile(
                          orgId: orgId,
                          fixture: f,
                          roster: roster,
                        ),
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

  /// Adds somebody to the panel, through the same sheet season creation uses.
  ///
  /// One sheet, not two: this screen had its own, which could reach the
  /// umpire registry and this club's members and nothing else — no PlaySphere
  /// ID for an umpire from another club, and no way at all to add the
  /// treasurer's uncle, who has never opened the app and is umpiring the
  /// final. It also took none of the three answers the assigner needs, so
  /// every name added here arrived as "anyone, any sport, any day".
  Future<void> _addOfficial(BuildContext context, WidgetRef ref) async {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tournament = ref.read(tournamentProvider(key)).valueOrNull;
    final roster =
        ref.read(tournamentOfficialsProvider(key)).valueOrNull ?? const [];
    final events = ref.read(tournamentEventsProvider(key)).valueOrNull ?? const [];
    final addedBy = ref.read(currentUidProvider);
    if (addedBy == null) return;

    final added = await showModalBottomSheet<TournamentOfficial>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AddOfficialSheet(
        orgId: orgId,
        seasonSportIds: {for (final e in events) e.sportId}.toList(),
        seasonStart: tournament?.startDate,
        seasonEnd: tournament?.endDate,
        alreadyOn: {for (final o in roster) o.uid},
      ),
    );
    if (added == null) return;

    try {
      await ref.read(tournamentRepositoryProvider).addOfficialToRoster(
            orgId: orgId,
            tournamentId: tournamentId,
            official: added,
            addedByUid: addedBy,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${added.name} added to the panel.')),
        );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _runBulkAssign(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    late final OfficialsRoster result;
    try {
      result = await ref.read(tournamentRepositoryProvider).assignOfficialsAcrossTournament(
            orgId: orgId,
            tournamentId: tournamentId,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
      return;
    }
    if (!context.mounted) return;

    if (result.isComplete) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${result.assignments.length} match'
              '${result.assignments.length == 1 ? '' : 'es'} staffed. '
              'Every match has a neutral official.',
            ),
          ),
        );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Some matches still need an official'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.assignments.length} placed, '
                '${result.unstaffed.length} could not be.',
              ),
              const SizedBox(height: 12),
              // Grouped by event rather than listed flat. Forty unstaffed
              // matches under one heading is a wall an organizer scrolls
              // past; the same forty under "Kabaddi U-14 (12)" is a phone
              // call to one person.
              for (final entry in result.unstaffedByEvent.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    '${entry.key} (${entry.value.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                // One reason per event, not per match: every match in a draw
                // that has no certified official fails for the same reason,
                // and printing it twelve times buries the eleven other draws.
                Text(
                  entry.value.first.reason,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                for (final u in entry.value.take(4))
                  Text(
                    '· ${u.slot.label.isEmpty ? u.slot.fixtureId : u.slot.label}'
                    '${u.slot.groupId == null ? '' : '  (Group ${u.slot.groupId})'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (entry.value.length > 4)
                  Text(
                    '· and ${entry.value.length - 4} more',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// What each sport needs, and whether the panel can cover it.
///
/// The screen used to open on a flat panel list and a flat list of unstaffed
/// matches, which between them could not answer the only question an organizer
/// opens this screen with: which sport is short. See [officiatingDemand].
class _CoverageBySport extends StatelessWidget {
  const _CoverageBySport({required this.demand});

  final List<SportDemand> demand;

  @override
  Widget build(BuildContext context) {
    if (demand.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final short = demand.where((d) => d.hasNobody).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('What needs officiating',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    short == 0
                        ? 'every sport covered'
                        : '$short with nobody',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: short == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Assignment is per sport — somebody on the panel for kabaddi '
                'is never put on a badminton court.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              for (final d in demand) _SportDemandRow(demand: d),
            ],
          ),
        ),
      ),
    );
  }
}

class _SportDemandRow extends StatelessWidget {
  const _SportDemandRow({required this.demand});

  final SportDemand demand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = demand;
    final colour = d.hasNobody
        ? theme.colorScheme.error
        : d.isCovered
            ? theme.colorScheme.primary
            : theme.colorScheme.tertiary;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 22, bottom: 8),
        leading: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
        ),
        title: Text(d.sportName, style: theme.textTheme.bodyMedium),
        subtitle: Text(
          d.hasNobody
              ? '${d.needed} ${d.needed == 1 ? 'match' : 'matches'} · nobody '
                  'on the panel officiates this'
              : [
                  '${d.staffed}/${d.total} staffed',
                  if (d.unscheduled > 0) '${d.unscheduled} not yet timed',
                  '${d.panelCount} on the panel',
                ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: d.hasNobody ? colour : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final name in d.events)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(name, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          // Groups are where the volume is, so they get counted rather than
          // folded into the event total an organizer then has to divide up.
          if (d.groups.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Groups still needing somebody',
              style: theme.textTheme.labelSmall,
            ),
            for (final g in d.groups.entries)
              Text(
                '${g.key} — ${g.value}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
          if (d.dayKeys.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Plays on ${d.dayKeys.map(prettyDay).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `2026-08-22` as `Sat 22 Aug`. Falls back to the key itself rather than
/// throwing on anything unparseable.
String prettyDay(String dayKey) {
  try {
    return DateFormat('EEE d MMM').format(DateTime.parse(dayKey));
  } catch (_) {
    return dayKey;
  }
}

class _OfficialTile extends ConsumerWidget {
  const _OfficialTile({
    required this.orgId,
    required this.tournamentId,
    required this.official,
    required this.seasonDays,
  });

  final String orgId;
  final String tournamentId;
  final TournamentOfficial official;

  /// The days this season actually plays on, offered as the availability
  /// choices. Empty before anything is scheduled, which is why the editor
  /// says so rather than showing an empty list.
  final List<String> seasonDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = official;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.sports_outlined),
        title: Text(o.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                _roleLabel(o.role),
                o.sports.isEmpty ? 'any sport' : o.sports.join(', '),
                'up to ${o.maxMatchesPerDay}/day',
                if (!o.scoringRightsGranted) 'scoring rights not granted',
              ].join(' · '),
            ),
            Text(
              o.availableDates.isEmpty
                  ? 'Available every day'
                  : 'Available ${o.availableDates.map(prettyDay).join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.event_available_outlined),
              tooltip: 'Sports & availability',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _AvailabilitySheet(
                  orgId: orgId,
                  tournamentId: tournamentId,
                  official: o,
                  seasonDays: seasonDays,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove from panel',
              onPressed: () async {
                try {
                  await ref
                      .read(tournamentRepositoryProvider)
                      .removeOfficialFromRoster(
                        orgId: orgId,
                        tournamentId: tournamentId,
                        uid: o.uid,
                      );
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String role) => switch (role) {
        'square_leg_umpire' => 'Square leg umpire',
        'referee' => 'Referee',
        'third_umpire' => 'Third umpire',
        'linesman' => 'Linesman',
        _ => 'Umpire',
      };
}

/// Which sports one official will take, which days they can come, and how
/// many matches they will stand for in a day.
///
/// All three are what the bulk assigner reads. Before they existed it read
/// only the panel, so it produced a roster that was even, neutral, clash-free
/// and wrong — a badminton umpire on the kabaddi mat, and a Saturday-only
/// volunteer down for the Sunday final.
class _AvailabilitySheet extends ConsumerStatefulWidget {
  const _AvailabilitySheet({
    required this.orgId,
    required this.tournamentId,
    required this.official,
    required this.seasonDays,
  });

  final String orgId;
  final String tournamentId;
  final TournamentOfficial official;
  final List<String> seasonDays;

  @override
  ConsumerState<_AvailabilitySheet> createState() => _AvailabilitySheetState();
}

class _AvailabilitySheetState extends ConsumerState<_AvailabilitySheet> {
  late final Set<String> _sports = widget.official.sports.toSet();
  late final Set<String> _days = widget.official.availableDates.toSet();
  late int _cap = widget.official.maxMatchesPerDay;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.official.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                'Only what is set here is used when matches are assigned '
                'automatically.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),

              const SizedBox(height: 20),
              Text('Sports they will officiate',
                  style: theme.textTheme.titleSmall),
              Text(
                _sports.isEmpty
                    ? 'None picked — they will be offered any sport.'
                    : 'They will only be put on these.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sport in SportCatalog.all)
                    FilterChip(
                      label: Text('${sport.icon}  ${sport.name}'),
                      selected: _sports.contains(sport.id),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _sports.add(sport.id);
                        } else {
                          _sports.remove(sport.id);
                        }
                      }),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              Text('Days they can come', style: theme.textTheme.titleSmall),
              Text(
                widget.seasonDays.isEmpty
                    ? 'Nothing is scheduled yet, so there are no days to pick '
                        'from. Generate the schedule and come back.'
                    : _days.isEmpty
                        ? 'None picked — they are treated as available every '
                            'day.'
                        : 'They will not be put on a match outside these.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final day in widget.seasonDays)
                    FilterChip(
                      label: Text(prettyDay(day)),
                      selected: _days.contains(day),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _days.add(day);
                        } else {
                          _days.remove(day);
                        }
                      }),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              Text('Most matches in one day',
                  style: theme.textTheme.titleSmall),
              Text(
                'An umpire who stands for fourteen matches is not officiating '
                'the last four.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _cap.toDouble().clamp(1, 20),
                      min: 1,
                      max: 20,
                      divisions: 19,
                      label: '$_cap',
                      onChanged: (v) => setState(() => _cap = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('$_cap', style: theme.textTheme.titleMedium),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(tournamentRepositoryProvider).updateOfficialOnRoster(
            orgId: widget.orgId,
            tournamentId: widget.tournamentId,
            official: widget.official.copyWith(
              sports: _sports.toList()..sort(),
              availableDates: _days.toList()..sort(),
              maxMatchesPerDay: _cap,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}

/// A scheduled match with no official yet — the manual fallback for whatever
/// the bulk run above could not place, or hasn't been run yet.
class _UnstaffedFixtureTile extends ConsumerWidget {
  const _UnstaffedFixtureTile({
    required this.orgId,
    required this.fixture,
    required this.roster,
  });

  final String orgId;
  final Fixture fixture;
  final List<TournamentOfficial> roster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = fixture;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${f.entrantAName} vs ${f.entrantBName}'),
        subtitle: Text([
          if (f.roundLabel != null) f.roundLabel!,
          if (f.scheduledAt != null) _fmt(f.scheduledAt!),
          if (f.venue != null) f.venue!,
        ].join(' · ')),
        trailing: TextButton(
          onPressed: roster.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => _AssignToFixtureSheet(
                      orgId: orgId,
                      fixture: f,
                      roster: roster,
                    ),
                  ),
          child: const Text('Assign'),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _AssignToFixtureSheet extends ConsumerStatefulWidget {
  const _AssignToFixtureSheet({
    required this.orgId,
    required this.fixture,
    required this.roster,
  });

  final String orgId;
  final Fixture fixture;
  final List<TournamentOfficial> roster;

  @override
  ConsumerState<_AssignToFixtureSheet> createState() =>
      _AssignToFixtureSheetState();
}

class _AssignToFixtureSheetState extends ConsumerState<_AssignToFixtureSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${f.entrantAName} vs ${f.entrantBName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final o in widget.roster)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sports_outlined),
                title: Text(o.name),
                enabled: !_busy,
                onTap: () => _assign(o),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign(TournamentOfficial o) async {
    setState(() => _busy = true);
    try {
      await ref.read(umpireRepositoryProvider).assignOfficialToFixture(
            orgId: widget.orgId,
            compId: widget.fixture.compId,
            fixtureId: widget.fixture.id,
            official: MatchOfficial(
              uid: o.uid,
              name: o.name,
              role: o.role,
              grantedScoringAccess: o.scoringRightsGranted,
            ),
            grantScoringAccess: o.scoringRightsGranted,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }
}
