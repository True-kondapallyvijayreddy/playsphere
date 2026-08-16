import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/models/draw_slot.dart';
import '../../domain/draw/seeding.dart';
import '../../domain/standings/standings_calculator.dart';
import '../../domain/standings/tiebreak.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'widgets/cancel_event_sheet.dart';
import 'widgets/competition_rule_editor.dart';
import 'widgets/draw_setup_sheet.dart';
import 'widgets/group_entry_sheet.dart';
import 'widgets/move_match_sheet.dart';
import 'widgets/team_builder_sheet.dart';
import '../tournaments/widgets/running_late_card.dart';
import 'widgets/squad_call_card.dart';
import 'widgets/start_early_sheet.dart';
import '../scoring/widgets/live_score_card.dart';
import '../scoring/widgets/share_match_button.dart';

/// The event's control room: entries, the draw, and every fixture.
///
/// The organizer's path through a competition is linear — open entries,
/// approve people, close entries, make the draw, play — so the screen shows
/// exactly one primary action at a time rather than a wall of buttons where
/// most are invalid.
class CompetitionDetailScreen extends ConsumerWidget {
  const CompetitionDetailScreen({
    super.key,
    required this.orgId,
    required this.compId,
  });

  final String orgId;
  final String compId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = CompRef(orgId, compId);
    final compAsync = ref.watch(competitionProvider(key));
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final canManage = caps.contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Event',
      body: AsyncView(
        value: compAsync,
        builder: (comp) {
          if (comp == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This event no longer exists',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 960,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(competition: comp),
                    const SizedBox(height: 16),
                    if (canManage) _OrganizerActions(competition: comp),
                    // Before real entries close there is nothing to draw a
                    // real bracket from, but an organizer still wants to see
                    // its shape — rounds, groups, quarters and semis — and
                    // start lining up venues, times and officials against it.
                    // Gone once entries close: from there on
                    // `_OrganizerActions` offers the real draw, over real
                    // entrants, and the two must not be on screen together.
                    if (canManage &&
                        !comp.format.isSingleMatch &&
                        (comp.status == CompetitionStatus.draft ||
                            comp.status == CompetitionStatus.registrationOpen))
                      _DraftScheduleCard(competition: comp),
                    if (canManage) _QualifierCard(competition: comp),
                    // Only for a standalone event: one inside a tournament is
                    // shifted from the tournament screen, because its matches
                    // share courts with fourteen other draws and moving it
                    // alone would tear the shared timetable.
                    if (canManage && comp.tournamentId == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: RunningLateCard(
                          // Draft placeholders are never "running late" —
                          // see `Fixture.isDraft`.
                          fixtures: (ref
                                      .watch(fixturesProvider(
                                          CompRef(comp.orgId, comp.id)))
                                      .valueOrNull ??
                                  const [])
                              .where((f) => !f.isDraft)
                              .toList(),
                          onShift: ({by, newStart}) => ref
                              .read(competitionRepositoryProvider)
                              .shiftSchedule(
                                orgId: comp.orgId,
                                compId: comp.id,
                                by: by,
                                newStart: newStart,
                              ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Bug #10: a single match names both sides at creation
                    // and has no registration phase. Showing "Entries (0)" and
                    // "Nobody has entered yet" was confusing and incorrect.
                    if (!comp.format.isSingleMatch) ...[
                      _Entries(competition: comp, canManage: canManage),
                      GroupEntriesSection(
                        competition: comp,
                        canManage: canManage,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _StandingsTable(competition: comp),
                    // A challenge is one fixture and two independently-owned
                    // squads, so the squad call belongs next to the match
                    // rather than inside the competition-level entry list.
                    if (comp.isInterClub) _InterClubSquads(competition: comp),
                    _Fixtures(competition: comp, canManage: canManage),
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

/// The event's name and its four facts.
///
/// The facts were four Material [Chip]s in a [Wrap]. Four chips do not fit
/// one phone line, so the header opened with a name and then two rows of
/// pill-shaped things that look pressable and are not — 96pt of header before
/// any of the screen's actual content. As one muted dot-separated line they
/// take 18pt and read faster, because a sentence is read faster than four
/// boxes are scanned.
class _Header extends StatelessWidget {
  const _Header({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    return PsCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.name,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          PsMetaRow(
            items: [
              c.sportName,
              c.category.label,
              c.format.label,
              // Derived, not stored: nothing writes the status field when a
              // registration deadline passes, so a closed event went on
              // advertising "Registration Open" (Bug #6).
              c.displayStatus().label,
              c.venue,
            ],
          ),
        ],
      ),
    );
  }
}

/// One primary action, chosen by where the competition is in its lifecycle.
class _OrganizerActions extends ConsumerWidget {
  const _OrganizerActions({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final repo = ref.read(competitionRepositoryProvider);
    final entrants =
        ref.watch(entrantsProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const [];

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    final (label, onPressed) = switch (c.status) {
      CompetitionStatus.draft => (
          'Open entries',
          () => run(() => repo.setStatus(
                orgId: c.orgId,
                compId: c.id,
                status: CompetitionStatus.registrationOpen,
              )),
        ),
      CompetitionStatus.registrationOpen => (
          'Close entries',
          () => run(() async {
                final count = await repo.lockFieldAndCreateEntrants(
                  orgId: c.orgId,
                  compId: c.id,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$count entrants confirmed.')),
                  );
                }
              }),
        ),
      CompetitionStatus.registrationClosed => (
          'Make the draw',
          () => run(() async {
                // The organizer's choices are collected BEFORE generating,
                // because the draw's shape and its timetable are both fixed
                // the moment the fixtures are written — regenerating
                // afterwards is only possible while nothing has been scored.
                final choices = await DrawSetupSheet.show(
                  context,
                  competition: c,
                  entrantCount: entrants.where((e) => !e.withdrawn).length,
                  venues: ref.read(venuesProvider(c.orgId)).valueOrNull ??
                      const [],
                );
                if (choices == null) return;

                final configured = c.withDrawSetup(
                  drawConfig: choices.draw,
                  scheduleConfig: choices.schedule,
                );
                // Persisted first, so the draw can be explained — and
                // reproduced identically — after the fact.
                await repo.updateCompetition(configured);

                final uid = ref.read(currentUidProvider);
                final made = await repo.generateDraw(
                  competition: configured,
                  entrants: entrants,
                  defaultScorerUids: uid == null ? const [] : [uid],
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${made.written} matches created'
                      '${choices.schedule.hasCourts ? ' and scheduled' : ''}.'
                      // "38 matches created" was the whole message, even when
                      // six of them had nowhere to be played. The scheduler
                      // knew; nothing asked it.
                      //
                      // Counted as problems, not as matches: a draw with no
                      // courts configured at all reports ONE problem covering
                      // every match, and the old wording turned that into
                      // "1 could not be given a court" — a reassuring
                      // undercount of a schedule where nothing was placed.
                      // The dialog below says what actually happened.
                      '${made.hasScheduleProblems ? ' Tap for ${made.scheduleProblems.length} scheduling ${made.scheduleProblems.length == 1 ? 'problem' : 'problems'}.' : ''}',
                    ),
                  ),
                );
                if (made.hasScheduleProblems) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _ScheduleProblemsDialog(
                      problems: made.scheduleProblems,
                    ),
                  );
                  if (!context.mounted) return;
                }
                // The seeding list, with a reason per player. A draw an
                // organizer has to defend needs an answer to "why am I not
                // seeded?" that is better than a shrug.
                if (made.seeding.isNotEmpty) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _SeedingDialog(verdicts: made.seeding),
                  );
                }
              }),
        ),
      CompetitionStatus.scheduled => (
          'Start the event',
          () => run(() => repo.setStatus(
                orgId: c.orgId,
                compId: c.id,
                status: CompetitionStatus.inProgress,
              )),
        ),
      CompetitionStatus.inProgress => (
          'Finish the event',
          () => run(() => repo.setStatus(
                orgId: c.orgId,
                compId: c.id,
                status: CompetitionStatus.completed,
              )),
        ),
      _ => ('', null),
    };

    // A cancelled event still has a card, and it is the most important one it
    // will ever show: the reason. Entrants arriving from the push land here.
    if (c.isCancelled) {
      final error = Theme.of(context).colorScheme.error;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: PsCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: Theme.of(context).colorScheme.errorContainer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_busy_outlined, size: 20, color: error),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cancelled',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                      ),
                    ),
                    if (c.cancelReason != null)
                      Text(
                        c.cancelReason!,
                        style: const TextStyle(fontSize: 13, color: Ps.ink),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // A completed event has no primary action left, but calling it off is not
    // the only thing an organizer can still do — and neither is nothing.
    final canStillCancel = c.status != CompetitionStatus.completed;

    if (onPressed == null && !canStillCancel) return const SizedBox.shrink();

    // One button and a `⋮`, where there were four controls and a paragraph
    // telling the organizer which to press. The paragraph is gone because the
    // button it explained is now the only one: `Close entries` needs no
    // sentence saying that closing entries freezes the field. Rules, notes
    // and cancellation moved into the menu — an organizer edits the rules once
    // per event and cancels one event in fifty, and both were taking permanent
    // space beside the action they take every time they open this screen.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: PsActionBar(
        primaryLabel: onPressed == null ? null : label,
        onPrimary: onPressed,
        actions: [
          PsAction(
            label: 'Rules',
            icon: Icons.settings_outlined,
            onSelected: () =>
                CompetitionRuleEditor.show(context, competition: c),
          ),
          PsAction(
            label: 'Send a note',
            icon: Icons.campaign_outlined,
            onSelected: () => EventNoteSheet.show(context, competition: c),
          ),
          if (canStillCancel)
            PsAction(
              label: 'Cancel event',
              icon: Icons.event_busy_outlined,
              destructive: true,
              onSelected: () => CancelEventSheet.show(context, competition: c),
            ),
        ],
      ),
    );
  }
}

/// Lets an organizer see the shape of the draw — rounds, groups, quarters
/// and semis — before real entries exist, using placeholder teams instead of
/// waiting for registration to close. See
/// `CompetitionRepository.generateDraftSchedule`.
class _DraftScheduleCard extends ConsumerWidget {
  const _DraftScheduleCard({required this.competition});
  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final fixtures =
        ref.watch(fixturesProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const <Fixture>[];
    final hasDraft = fixtures.any((f) => f.isDraft);
    final rawEntrants = ref
            .watch(entrantsProvider(CompRef(c.orgId, c.id)))
            .valueOrNull ??
        const <Entrant>[];
    final rawRegistrations = ref
            .watch(registrationsProvider(CompRef(c.orgId, c.id)))
            .valueOrNull ??
        const <Registration>[];

    final registered = [
      for (final e in rawEntrants)
        if (!e.withdrawn) e,
      if (rawEntrants.isEmpty)
        for (final r in rawRegistrations)
          if (r.status == RegistrationStatus.confirmed ||
              r.status == RegistrationStatus.pending)
            Entrant(
              id: r.uid,
              displayName: r.displayName.isNotEmpty ? r.displayName : 'Player',
              entrantType: c.entrantType,
              uid: r.uid,
            ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasDraft ? 'Draft schedule' : 'Plan the schedule early',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              registered.isNotEmpty
                  ? '${registered.length} ${registered.length == 1 ? "entry" : "entries"} '
                      'so far. They are placed into the draw by name and the '
                      'rest of the field is left as open slots, so the '
                      'timetable can be built now and filled in as more '
                      'people register.'
                  : hasDraft
                      ? 'Placeholder teams stand in for real entrants until '
                          'registration closes. Edit the venue, time and '
                          'official on any match below — regenerating replaces '
                          'every placeholder match with a fresh set.'
                      : 'See the shape of a ${c.format.label.toLowerCase()} — '
                          'rounds, groups, quarters and semis — and start '
                          'lining up venues, times and officials before '
                          'anyone has registered.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _open(context, ref, registered),
                  icon: const Icon(Icons.auto_awesome_motion_outlined),
                  label: Text(
                      hasDraft ? 'Regenerate the draft' : 'Create a schedule'),
                ),
                if (hasDraft)
                  FilledButton.icon(
                    onPressed: () => _publish(context, ref),
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: const Text('Lock & Publish Schedule'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    List<Entrant> registered,
  ) async {
    final plan = await _DraftScheduleSheet.show(
      context,
      competition: competition,
      registeredCount: registered.length,
    );
    if (plan == null) return;
    try {
      final outcome =
          await ref.read(competitionRepositoryProvider).generateDraftSchedule(
                competition: competition,
                teamCount: plan.teamCount,
                teamsPerGroup: plan.teamsPerGroup,
                seedWith: registered,
              );
      if (context.mounted) {
        final open = plan.teamCount - registered.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              registered.isEmpty
                  ? '${outcome.written} placeholder matches created below — '
                      'edit any of them freely.'
                  : '${outcome.written} matches created — '
                      '${registered.length} entered'
                      '${open > 0 ? ', $open slots still open' : ''}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lock & Publish Schedule?'),
        content: const Text(
          'This will publish the official match schedule with assigned courts '
          'and timeslots. It will become visible to all participants and visiting clubs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publish Schedule'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(competitionRepositoryProvider).publishDraftSchedule(
            orgId: competition.orgId,
            compId: competition.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Schedule locked and published! Official fixtures are now live.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// Asks only what a draft schedule genuinely needs: how many teams to plan
/// for, and — for a groups format — how big a group is. Everything else
/// (venue, time, court, officials) is set afterwards, per match, once the
/// organizer can see the actual bracket rather than guessing at it blind.
class _DraftScheduleSheet extends StatefulWidget {
  const _DraftScheduleSheet({
    required this.competition,
    required this.registeredCount,
  });

  final Competition competition;

  /// How many have actually entered. The field can never be planned smaller
  /// than this — a bracket that does not hold everyone who registered is not
  /// a schedule, it is a mistake waiting to be found on the day.
  final int registeredCount;

  static Future<({int teamCount, int? teamsPerGroup})?> show(
    BuildContext context, {
    required Competition competition,
    int registeredCount = 0,
  }) =>
      showModalBottomSheet<({int teamCount, int? teamsPerGroup})>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _DraftScheduleSheet(
          competition: competition,
          registeredCount: registeredCount,
        ),
      );

  @override
  State<_DraftScheduleSheet> createState() => _DraftScheduleSheetState();
}

class _DraftScheduleSheetState extends State<_DraftScheduleSheet> {
  /// Never below the number already entered, so nobody is drawn out of their
  /// own event by a stepper.
  int get _minTeams {
    final floor = widget.registeredCount < 2 ? 2 : widget.registeredCount;
    return floor > 64 ? 64 : floor;
  }

  // The registration limit set when the event was created, when there is
  // one — an organizer who already said "32 teams" should not be asked
  // again. Otherwise a small, typical field, easy to change with the
  // stepper below.
  late int _teamCount =
      (widget.competition.maxEntrants ?? 8).clamp(_minTeams, 64);
  int _teamsPerGroup = 4;

  bool get _isGroups =>
      widget.competition.format == CompetitionFormat.groupThenKnockout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Plan a schedule', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.registeredCount > 0
                  ? '${widget.competition.format.label} · '
                      '${widget.registeredCount} already entered, the rest of '
                      'the field left as open slots'
                  : '${widget.competition.format.label} · placeholder teams '
                      'stand in until real entries close',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _CountStepper(
              label: 'Teams to plan for',
              value: _teamCount,
              min: _minTeams,
              max: 64,
              onChanged: (v) => setState(() => _teamCount = v),
            ),
            if (widget.registeredCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _teamCount > widget.registeredCount
                      ? '${widget.registeredCount} entered · '
                          '${_teamCount - widget.registeredCount} open slots'
                      : 'Every place taken — no open slots',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (_isGroups) ...[
              const SizedBox(height: 4),
              _CountStepper(
                label: 'Teams per group',
                value: _teamsPerGroup,
                min: 2,
                max: 4,
                onChanged: (v) => setState(() => _teamsPerGroup = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((
                teamCount: _teamCount,
                teamsPerGroup: _isGroups ? _teamsPerGroup : null,
              )),
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _Entries extends ConsumerWidget {
  const _Entries({required this.competition, required this.canManage});
  final Competition competition;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final key = CompRef(c.orgId, c.id);
    final regsAsync = ref.watch(registrationsProvider(key));
    final regs = regsAsync.valueOrNull ?? const [];
    final me = ref.watch(currentUserProvider).valueOrNull;
    // If the read failed, `myReg` is null for the wrong reason and the screen
    // would offer "Enter" to someone already entered — a duplicate the rules
    // then reject, which reads to the user as the button being broken.
    final myReg = me == null
        ? null
        : regs.where((r) => r.uid == me.uid).firstOrNull;

    // Whether the person about to tap the button is entering as a guest —
    // signed in, but not a member of this club at all. Only meaningful when
    // the organizer has actually opened the door (`openToNonMembers`); a
    // pending/removed membership on a closed event is still just "not
    // eligible", not "entering as a guest".
    final membership = me == null
        ? null
        : ref.watch(myMembershipProvider(c.orgId)).valueOrNull;
    final enteringAsGuest =
        c.openToNonMembers && me != null && membership?.isActive != true;

    Future<void> executeRegistration({
      String? houseName,
      String? partnerName,
      bool isSoloDoubles = false,
      String? teamName,
    }) async {
      if (me == null) return;
      try {
        final outcome = await ref
            .read(competitionRepositoryProvider)
            .register(
              competition: c,
              user: me,
              houseName: houseName,
              partnerName: partnerName,
              isSoloDoubles: isSoloDoubles,
              teamName: teamName,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(switch (outcome) {
              RegistrationStatus.confirmed => 'You are in. See you there.',
              RegistrationStatus.waitlisted =>
                'Event is full — you are on the waitlist. '
                    'You move up automatically if someone drops out.',
              _ when enteringAsGuest =>
                "You're entering as a guest, outside this club. "
                    'The organizer will review and confirm your entry.',
              _ => 'Entry submitted. The organizer will confirm it.',
            })),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> enter() async {
      if (me == null) return;

      // School House selection
      if (c.teamEntryMode == TeamEntryMode.houseBatch) {
        final houses = c.presetHouses.isNotEmpty
            ? c.presetHouses
            : ['Red House', 'Blue House', 'Green House', 'Yellow House'];
        String selectedHouse = houses.first;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.school_outlined),
                  SizedBox(width: 8),
                  Text('Select Your House'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Which house or section are you representing?'),
                  const SizedBox(height: 12),
                  for (final h in houses)
                    RadioListTile<String>(
                      dense: true,
                      title: Text(h),
                      value: h,
                      groupValue: selectedHouse,
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedHouse = v);
                        }
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
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Confirm Entry'),
                ),
              ],
            ),
          ),
        );

        if (confirmed == true) {
          await executeRegistration(houseName: selectedHouse);
        }
        return;
      }

      // Doubles Partner selection
      if (c.teamEntryMode == TeamEntryMode.doubles) {
        bool hasPartner = true;
        final partnerCtrl = TextEditingController();

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.people_outline),
                  SizedBox(width: 8),
                  Text('Doubles Entry'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Have Partner')),
                      ButtonSegment(value: false, label: Text('Need Partner (Solo)')),
                    ],
                    selected: {hasPartner},
                    onSelectionChanged: (s) =>
                        setDialogState(() => hasPartner = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (hasPartner)
                    TextField(
                      controller: partnerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Partner Name',
                        hintText: 'Enter partner full name',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    const Text(
                      'You will join the solo pool and be paired automatically before the draw.',
                      style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Enter Doubles'),
                ),
              ],
            ),
          ),
        );

        if (confirmed == true) {
          await executeRegistration(
            partnerName: hasPartner ? partnerCtrl.text.trim() : null,
            isSoloDoubles: !hasPartner,
          );
        }
        return;
      }

      // Standard 1-tap entry
      await executeRegistration();
    }

    // What the button will actually do, said before it is pressed.
    final actionLabel = switch (c.outcomeOfRegisteringNow) {
      RegistrationStatus.confirmed => 'Register',
      RegistrationStatus.waitlisted => 'Join waitlist',
      _ => enteringAsGuest ? 'Apply as guest' : 'Apply',
    };

    final eligibility =
        me == null ? null : c.category.check(me, competitionStart: c.startDate);
    final theme = Theme.of(context);

    // What used to be implicit in whether the Enter/Apply button happened to
    // be showing — an organizer or a spectator had to infer "closed" from a
    // missing button, and nothing at all said how the field currently splits
    // between confirmed, pending and waitlisted.
    final confirmedCount =
        regs.where((r) => r.status == RegistrationStatus.confirmed).length;
    final pendingCount =
        regs.where((r) => r.status == RegistrationStatus.pending).length;
    final waitlistedCount =
        regs.where((r) => r.status == RegistrationStatus.waitlisted).length;
    final breakdown = [
      if (confirmedCount > 0) '$confirmedCount confirmed',
      if (pendingCount > 0) '$pendingCount pending',
      if (waitlistedCount > 0) '$waitlistedCount waitlisted',
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Entries (${regs.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (canManage && regs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton.icon(
                      onPressed: () => TeamBuilderSheet.show(
                        context,
                        competition: c,
                        registrations: regs,
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Team Builder & Draft'),
                    ),
                  ),
                if (myReg != null)
                  Chip(
                    label: Text(
                      myReg.status == RegistrationStatus.waitlisted &&
                              myReg.waitlistPosition != null
                          ? 'Waitlist #${myReg.waitlistPosition}'
                          : myReg.status.label,
                    ),
                  )
                else if (c.registrationIsOpen && me != null)
                  Wrap(
                    spacing: 6,
                    children: [
                      FilledButton.tonal(
                        onPressed:
                            eligibility?.isEligible == true ? enter : null,
                        child: Text(actionLabel),
                      ),
                      if (c.teamEntryMode == TeamEntryMode.preformedTeam ||
                          c.entrantType == EntrantType.team)
                        OutlinedButton.icon(
                          onPressed: eligibility?.isEligible == true
                              ? () => GroupEntrySheet.show(
                                    context,
                                    competition: c,
                                  )
                              : null,
                          icon: const Icon(Icons.groups_outlined, size: 16),
                          label: const Text('Enter Team / Group'),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  c.registrationIsOpen
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                  size: 16,
                  color: c.registrationIsOpen
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  c.registrationIsOpen
                      ? 'Registration open'
                      : 'Registration closed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.registrationIsOpen
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (breakdown.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '· $breakdown',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            _SlotsLine(competition: c),
            // Telling someone exactly why they cannot enter is the difference
            // between a fair rule and an unexplained refusal.
            if (myReg == null &&
                eligibility != null &&
                !eligibility.isEligible) ...[
              const SizedBox(height: 6),
              Text(
                eligibility.reason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            AsyncErrorStrip(value: regsAsync, what: 'the entry list'),
            if (regs.isEmpty && !regsAsync.hasError)
              Text('Nobody has entered yet.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              for (final r in regs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundImage:
                        r.photoUrl != null ? NetworkImage(r.photoUrl!) : null,
                    child: r.photoUrl == null
                        ? Text(r.displayName.characters.first.toUpperCase())
                        : null,
                  ),
                  title: Text(r.displayName),
                  subtitle: Text(
                    [
                      if (r.status == RegistrationStatus.waitlisted &&
                          r.waitlistPosition != null)
                        'Waitlist #${r.waitlistPosition}'
                      else
                        r.status.label,
                      // Marked so the open registrants can see which slots
                      // were ever really available to them.
                      if (r.preselected) 'picked by organizer',
                    ].join(' · '),
                  ),
                  trailing: !canManage ||
                          r.status != RegistrationStatus.pending
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Confirm',
                              icon: const Icon(Icons.check),
                              onPressed: () => _decide(
                                context,
                                ref,
                                c,
                                r.uid,
                                RegistrationStatus.confirmed,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Reject',
                              icon: const Icon(Icons.close),
                              onPressed: () => _decide(
                                context,
                                ref,
                                c,
                                r.uid,
                                RegistrationStatus.rejected,
                              ),
                            ),
                          ],
                        ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Competition c,
    String uid,
    RegistrationStatus status,
  ) async {
    final me = ref.read(currentUidProvider);
    if (me == null) return;
    try {
      await ref.read(competitionRepositoryProvider).decideRegistration(
            orgId: c.orgId,
            compId: c.id,
            uid: uid,
            status: status,
            decidedByUid: me,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// How the field stands, in one line.
///
/// A registration limit that is only enforced at the moment someone taps
/// Register is a limit nobody can plan around. Saying "4 of 13 slots left"
/// up front is what lets a member decide to register now rather than
/// discovering on Saturday night that they are third reserve.
class _SlotsLine extends StatelessWidget {
  const _SlotsLine({required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    final theme = Theme.of(context);
    final parts = <String>[];

    final left = c.slotsRemaining;
    if (left == null) {
      parts.add('No limit on entries');
    } else if (left > 0) {
      parts.add('$left of ${c.openSlots} slots left');
    } else {
      parts.add('Field is full');
    }

    if (c.participationModel == ParticipationModel.hybrid &&
        c.preselectedSlots > 0) {
      parts.add('${c.preselectedSlots} picked by the organizer');
    }

    if (c.waitlistCount > 0) {
      parts.add('${c.waitlistCount} on the waitlist');
    } else if (c.waitlistEnabled && (left == null || left == 0)) {
      parts.add('waitlist open');
    }

    if (!c.isFree) parts.add('₹${c.entryFeeRupees} entry');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.join(' · '),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (c.rulesNote != null && c.rulesNote!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(c.rulesNote!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// The league table.
///
/// Shown only for formats where a table means something. A knockout bracket
/// has no standings — presenting one implies a league that is not being
/// played, and an organizer reading it would draw the wrong conclusion.
/// Promotes finished group winners into the knockout bracket.
///
/// The step that used to be done on paper. The draw has always carried, on
/// every knockout fixture, the table position that will fill it — "winner of
/// Group B" — and nothing ever read those tags, so the quarter-finals of a
/// groups+knockout tournament said "To be decided" until the organizer
/// rewrote them by hand.
///
/// Shown only while there is something left to promote, so it disappears once
/// the bracket is full rather than sitting there as a permanent button.
class _QualifierCard extends ConsumerStatefulWidget {
  const _QualifierCard({required this.competition});
  final Competition competition;

  @override
  ConsumerState<_QualifierCard> createState() => _QualifierCardState();
}

class _QualifierCardState extends ConsumerState<_QualifierCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.competition;
    if (c.format != CompetitionFormat.groupThenKnockout) {
      return const SizedBox.shrink();
    }

    final fixtures =
        ref.watch(fixturesProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const <Fixture>[];

    // Knockout slots still waiting on a group they can name.
    final pending = fixtures.where((f) =>
        (f.qualifierA != null && f.entrantAId.isEmpty) ||
        (f.qualifierB != null && f.entrantBId.isEmpty));
    if (pending.isEmpty) return const SizedBox.shrink();

    const groupsDone = StandingsCalculator();
    final readyGroups = <String>{
      for (final f in fixtures)
        if (f.bracket == Bracket.group && f.groupId != null) f.groupId!,
    }.where((g) => groupsDone.isGroupComplete(g, fixtures)).toList()
      ..sort();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fill the knockout stage',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                readyGroups.isEmpty
                    ? 'No group has finished yet. A group only promotes once '
                        'every one of its matches has a result — half a group '
                        'has a leader, not a winner.'
                    : '${readyGroups.length} group'
                        '${readyGroups.length == 1 ? '' : 's'} finished '
                        '(${readyGroups.join(', ')}). '
                        '${pending.length} knockout '
                        '${pending.length == 1 ? 'match is' : 'matches are'} '
                        'still waiting on a name.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _busy || readyGroups.isEmpty ? null : _resolve,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_tree_outlined),
                label: const Text('Update the bracket'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    final c = widget.competition;
    try {
      final outcome = await ref.read(competitionRepositoryProvider)
          .resolveQualifiers(orgId: c.orgId, compId: c.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.slotsResolved == 0
                ? 'Nothing to promote yet — still waiting on '
                    '${outcome.groupsPending.join(', ')}.'
                : '${outcome.slotsResolved} knockout '
                    '${outcome.slotsResolved == 1 ? 'match' : 'matches'} '
                    'filled in.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// One group's table, with the qualifying places marked.
///
/// The line under the last qualifying position is the whole point: a group
/// table is read to answer one question — am I going through? — and a table
/// that does not answer it makes everyone ask the organizer instead.
class _GroupTable extends StatelessWidget {
  const _GroupTable({
    required this.orgId,
    required this.compId,
    required this.groupId,
    required this.rows,
    required this.qualifiers,
  });

  final String orgId;
  final String compId;
  final String groupId;
  final List<Standing> rows;
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group $groupId', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < rows.length; i++) ...[
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: i < qualifiers
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            i < qualifiers ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push(
                        Routes.entrant(orgId, compId, rows[i].entrantId),
                      ),
                      child: Text(rows[i].displayName),
                    ),
                  ),
                  Text('${rows[i].played}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${rows[i].points}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (i == qualifiers - 1 && i < rows.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(color: theme.colorScheme.primary),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'qualify',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Who was seeded, who was not, and why.
///
/// Shown once, straight after a draw that seeded from ratings. The reasons
/// are the point: "you have played two of the five rated matches we need"
/// is something an organizer can say to a player at the desk. A bracket that
/// cannot explain itself gets argued with.
/// Matches the scheduler could not place, and why.
///
/// The generator has always produced this list and `generateDraw` has always
/// discarded it, so an organizer was told "38 matches created" and found out at
/// the ground that six of them had a provisional time and no court. A draw that
/// does not fit the courts and hours available is a normal thing to happen —
/// what is not acceptable is finding out on the day.
class _ScheduleProblemsDialog extends StatelessWidget {
  const _ScheduleProblemsDialog({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Some matches have no court'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'These matches were created and carry a provisional "not before" '
              'time, but the scheduler could not fit them onto a court within '
              'the hours you set. Add a court, lengthen the day, or move them '
              'by hand.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final p in problems)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_outlined, size: 18),
                title: Text(p, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _SeedingDialog extends StatelessWidget {
  const _SeedingDialog({required this.verdicts});

  final List<SeedVerdict> verdicts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seeded = [
      for (final v in verdicts)
        if (v.isSeeded) v,
    ]..sort((a, b) => a.seed!.compareTo(b.seed!));
    final rest = [
      for (final v in verdicts)
        if (!v.isSeeded) v,
    ];

    return AlertDialog(
      title: const Text('Seeding'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final v in seeded)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${v.seed}',
                      style: theme.textTheme.labelMedium),
                ),
                title: Text(v.entrantId),
                subtitle: Text(v.reason, style: theme.textTheme.bodySmall),
              ),
            if (rest.isNotEmpty) ...[
              const Divider(),
              Text(
                'Unseeded — drawn at random',
                style: theme.textTheme.labelLarge,
              ),
              for (final v in rest)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.entrantId),
                  subtitle: Text(v.reason, style: theme.textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _StandingsTable extends ConsumerWidget {
  const _StandingsTable({required this.competition});
  final Competition competition;

  static const _tableFormats = {
    CompetitionFormat.roundRobin,
    CompetitionFormat.leagueTable,
    CompetitionFormat.swiss,
    CompetitionFormat.groupThenKnockout,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_tableFormats.contains(competition.format)) {
      return const SizedBox.shrink();
    }

    // A groups draw has several tables and no meaningful combined one: Group
    // A's players have never met Group B's, so their points do not compare.
    // Showing one merged table was not just untidy, it was wrong.
    if (competition.format == CompetitionFormat.groupThenKnockout) {
      final groupsAsync = ref.watch(
        groupStandingsProvider(CompRef(competition.orgId, competition.id)),
      );
      final tables = groupsAsync.valueOrNull ?? const <String, List<Standing>>{};
      if (tables.isEmpty) return const SizedBox.shrink();

      final ids = tables.keys.toList()..sort();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GroupTable(
                orgId: competition.orgId,
                compId: competition.id,
                groupId: id,
                rows: tables[id]!,
                qualifiers: competition.drawConfig.qualifiersPerGroup,
              ),
            ),
        ],
      );
    }

    final tableAsync = ref.watch(
      standingsProvider(CompRef(competition.orgId, competition.id)),
    );

    // A table that failed to load must say so. Collapsing to `shrink()` on
    // error is what made a rejected fixtures read look like a competition
    // nobody had played yet.
    if (tableAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Table unavailable'),
            subtitle: Text(errorMessage(tableAsync.error!)),
          ),
        ),
      );
    }

    final table = tableAsync.valueOrNull ?? const <Standing>[];
    if (table.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final anyPlayed = table.any((r) => r.played > 0);

    // The order shown has to be the order actually applied. This used to be a
    // fixed sentence naming score difference, which misdescribed every cricket
    // league (net run rate) and every Swiss event (Buchholz).
    final chain = Tiebreak.parse(
      competition.tiebreakChain,
      competition.sportId,
    );
    final shownChain =
        chain.where((t) => t != Tiebreak.name).map((t) => t.label).toList();

    // Whichever separator the chain actually uses gets its own column, so an
    // organizer can show a disputing captain the number that decided the order.
    final showNrr = chain.contains(Tiebreak.netRunRate);
    final showBuchholz = chain.contains(Tiebreak.buchholz);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Table', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            anyPlayed
                ? 'Points, then ${shownChain.join(', then ').toLowerCase()}.'
                : 'Updates automatically as results come in.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              // A table is genuinely wide content, so it scrolls inside its own
              // box rather than making the whole page scroll sideways on a
              // phone.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 42,
                  dataRowMaxHeight: 48,
                  columnSpacing: 18,
                  columns: [
                    const DataColumn(label: Text('#')),
                    const DataColumn(label: Text('Entrant')),
                    const DataColumn(label: Text('P'), numeric: true),
                    const DataColumn(label: Text('W'), numeric: true),
                    const DataColumn(label: Text('D'), numeric: true),
                    const DataColumn(label: Text('L'), numeric: true),
                    const DataColumn(label: Text('+/−'), numeric: true),
                    if (showNrr)
                      const DataColumn(
                        label: Tooltip(
                          message: 'Net run rate',
                          child: Text('NRR'),
                        ),
                        numeric: true,
                      ),
                    if (showBuchholz)
                      const DataColumn(
                        label: Tooltip(
                          message: 'Buchholz — sum of opponents’ scores',
                          child: Text('BH'),
                        ),
                        numeric: true,
                      ),
                    const DataColumn(label: Text('Pts'), numeric: true),
                  ],
                  rows: [
                    for (final row in table)
                      DataRow(
                        cells: [
                          DataCell(Text('${row.rank}')),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                row.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onTap: () => context.push(
                              Routes.entrant(
                                competition.orgId,
                                competition.id,
                                row.entrantId,
                              ),
                            ),
                          ),
                          DataCell(Text('${row.played}')),
                          DataCell(Text('${row.won}')),
                          DataCell(Text('${row.drawn}')),
                          DataCell(Text('${row.lost}')),
                          DataCell(Text(
                            row.scoreDifference > 0
                                ? '+${row.scoreDifference}'
                                : '${row.scoreDifference}',
                          )),
                          if (showNrr)
                            DataCell(Text(
                              // Three decimals, because that is the precision
                              // qualification is argued at (CLAUDE.md §12.6).
                              row.netRunRate == null
                                  ? '—'
                                  : row.netRunRate!.toStringAsFixed(3),
                            )),
                          if (showBuchholz)
                            DataCell(Text('${row.buchholz}')),
                          DataCell(Text(
                            '${row.points}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks who may score a match.
///
/// Without this the only person who could ever score was whoever pressed
/// "Generate the draw" — `assignScorers` existed in the repository with no
/// caller, so the judge/scorer role could be granted but never used, and the
/// "an event manager can add you as a scorer" empty state pointed at a screen
/// that did not exist.
class _AssignScorersDialog extends ConsumerStatefulWidget {
  const _AssignScorersDialog({required this.fixture});
  final Fixture fixture;

  @override
  ConsumerState<_AssignScorersDialog> createState() =>
      _AssignScorersDialogState();
}

class _AssignScorersDialogState extends ConsumerState<_AssignScorersDialog> {
  late final Set<String> _selected = {...widget.fixture.scorerUids};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(orgMembersProvider(widget.fixture.orgId));
    final members = membersAsync.valueOrNull ?? const [];
    // Only roles that carry the scoring capability. Offering a plain member
    // would let an organizer assign someone the rules will then reject.
    final eligible = members
        .where((m) =>
            m.isActive &&
            PermissionMatrix.can(m.role, Capability.scoreMatches))
        .toList();

    return AlertDialog(
      title: const Text('Who can score this match?'),
      content: SizedBox(
        width: 400,
        // The "nobody holds the scoring role" sentence sends the organizer to
        // the Members screen to fix a problem that may not exist, so it is
        // only claimed when the member list genuinely loaded.
        child: membersAsync.hasError
            ? AsyncErrorStrip(value: membersAsync, what: 'the member list')
            : eligible.isEmpty
            // Was three sentences ending in "…on the Members screen first",
            // which left the organizer to dismiss this, find the drawer and
            // hunt for that screen. The fix it describes is one tap, so it is
            // a button.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nobody here holds the scorer role yet.'),
                  const SizedBox(height: 12),
                  PsSecondaryButton(
                    label: 'Open members',
                    icon: Icons.people_alt_outlined,
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(Routes.members(widget.fixture.orgId));
                    },
                  ),
                ],
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final m in eligible)
                    CheckboxListTile(
                      value: _selected.contains(m.uid),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _selected.add(m.uid);
                        } else {
                          _selected.remove(m.uid);
                        }
                      }),
                      title: Text(m.displayName),
                      subtitle: Text(m.role.label),
                      dense: true,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || eligible.isEmpty
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ref
                        .read(competitionRepositoryProvider)
                        .assignScorers(
                          orgId: widget.fixture.orgId,
                          compId: widget.fixture.compId,
                          fixtureId: widget.fixture.id,
                          scorerUids: _selected.toList(),
                        );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _busy = false);
                      showError(context, e);
                    }
                  }
                },
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _Fixtures extends ConsumerWidget {
  const _Fixtures({required this.competition, required this.canManage});
  final Competition competition;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final key = CompRef(c.orgId, c.id);
    final fixturesAsync = ref.watch(fixturesProvider(key));
    final fixtures = fixturesAsync.valueOrNull ?? const [];
    final myUid = ref.watch(currentUidProvider);

    // "No matches yet" is a claim about the draw. Only make it when the read
    // actually succeeded — otherwise an organizer is told to generate a draw
    // that already exists.
    if (fixturesAsync.hasError) {
      return AsyncErrorStrip(value: fixturesAsync, what: 'the match list');
    }

    final visibleFixtures =
        canManage ? fixtures : fixtures.where((f) => !f.isDraft).toList();

    if (visibleFixtures.isEmpty) {
      return Text(
        fixtures.any((f) => f.isDraft)
            ? 'Schedule is being prepared by the organizers and will be published once entries close.'
            : 'No matches yet — generate the draw once entries are closed.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    Widget matchRow(Fixture f) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: LiveScoreCard(
                  fixture: f,
                  dense: true,
                  // A draft fixture is placeholder teams — there is nothing
                  // to score or watch yet, so the tap goes straight to
                  // editing it instead of a scoring pad or scoreboard with
                  // nobody real on it.
                  onTap: f.isDraft
                      ? () => MoveMatchSheet.show(
                            context,
                            fixture: f,
                            siblings: fixtures,
                          )
                      : () {
                          // A match that has not started opens the Match
                          // Center — `docs/Heart_of_the_playsphere.md` §3/§4:
                          // tapping a match opens the hub where it is
                          // prepared and started, not a scoring pad for a
                          // game with no umpire or an empty scoreboard.
                          //
                          // A live or finished match still goes straight to
                          // the score. Somebody opening a game in progress
                          // wants the ball-by-ball, not a step in front of
                          // it.
                          final started = f.isLiveAt(DateTime.now()) ||
                              f.status.isResulted;
                          if (!started) {
                            context.push(
                              Routes.matchCenter(c.orgId, c.id, f.id),
                            );
                            return;
                          }
                          final canScore = myUid != null &&
                              f.canBeScoredBy(myUid, isOrgManager: canManage);
                          context.push(
                            canScore
                                ? Routes.scoring(c.orgId, c.id, f.id)
                                : Routes.watch(c.orgId, c.id, f.id),
                          );
                        },
                ),
              ),
              // Only while there is something to watch. A link to a match
              // that has not started shows an empty scoreboard, which is a
              // worse thing to send someone than nothing.
              // Bug #1 / #15: use activity-aware isLiveAt rather than the
              // raw status field, so a match abandoned by its scorer days
              // ago is not treated as in-progress.
              if (!f.isDraft && (f.isLiveAt(DateTime.now()) || f.hasResult))
                ShareMatchButton(fixture: f, compact: true),
              if (f.isDraft) ...[
                // Editing is the entire point of a draft match, so the icon
                // stays even though the tap above already opens the same
                // sheet — a visible affordance, not just a hidden gesture.
                IconButton(
                  tooltip: 'Edit venue, time and court',
                  icon: const Icon(Icons.edit_calendar_outlined),
                  onPressed: () => MoveMatchSheet.show(
                    context,
                    fixture: f,
                    siblings: fixtures,
                  ),
                ),
              ] else ...[
                // A match already played is history; one in progress has a
                // scorer standing over it. Neither is the organizer's to move.
                if (canManage &&
                    !f.hasResult &&
                    !f.isLiveAt(DateTime.now())) ...[
                  IconButton(
                    tooltip: 'Start this match early',
                    icon: const Icon(Icons.play_circle_outline,
                        color: Colors.green),
                    onPressed: () => StartEarlySheet.show(
                      context,
                      fixture: f,
                      sportId: c.sportId,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move this match',
                    icon: const Icon(Icons.edit_calendar_outlined),
                    onPressed: () => MoveMatchSheet.show(
                      context,
                      fixture: f,
                      siblings: fixtures,
                    ),
                  ),
                ],
                if (canManage)
                  IconButton(
                    tooltip: f.scorerUids.isEmpty
                        ? 'No scorer assigned'
                        : '${f.scorerUids.length} scorer(s) assigned',
                    icon: Icon(
                      f.scorerUids.isEmpty
                          ? Icons.person_off_outlined
                          : Icons.how_to_reg_outlined,
                      color: f.scorerUids.isEmpty
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _AssignScorersDialog(fixture: f),
                    ),
                  ),
              ],
            ],
          ),
        );

    // Grouped so the schedule reads the same way the standings already do —
    // `_StandingsTable` has shown one table per group since groups existed;
    // this list showing all of "Group A" and "Group B" interleaved, with no
    // way to tell which match belongs to which table, was the one place the
    // schedule and the standings disagreed about whether groups exist.
    final byGroup = <String?, List<Fixture>>{};
    for (final f in fixtures) {
      byGroup.putIfAbsent(f.groupId, () => []).add(f);
    }
    final groupIds = byGroup.keys.whereType<String>().toList()..sort();
    final ungrouped = byGroup[null] ?? const <Fixture>[];
    int byRound(Fixture a, Fixture b) => a.round != b.round
        ? a.round.compareTo(b.round)
        : a.matchIndex.compareTo(b.matchIndex);

    // A draft schedule and a real one are never mixed — generating either
    // wipes whatever the competition had before — so one banner is enough
    // rather than marking every row.
    final isDraftSchedule = fixtures.any((f) => f.isDraft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Matches', style: Theme.of(context).textTheme.titleMedium),
        if (isDraftSchedule) ...[
          const SizedBox(height: 4),
          Text(
            'Draft schedule — "Team A", "Team B" and the rest are '
            'placeholders. Real entrants replace them once you generate the '
            'draw after entries close.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ],
        const SizedBox(height: 10),
        if (groupIds.isEmpty)
          for (final f in [...fixtures]..sort(byRound)) matchRow(f)
        else ...[
          for (final id in groupIds) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text('Group $id', style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final f in [...byGroup[id]!]..sort(byRound)) matchRow(f),
          ],
          // The knockout stage of a groups+knockout draw — everything left
          // once every group bucket above has taken its matches.
          if (ungrouped.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text('Knockout', style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final f in [...ungrouped]..sort(byRound)) matchRow(f),
          ],
        ],
      ],
    );
  }
}

/// The squad call for a challenge match.
///
/// A challenge has exactly one fixture, so this finds it rather than making
/// the reader pick one from a list of one.
class _InterClubSquads extends ConsumerWidget {
  const _InterClubSquads({required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = ref
            .watch(fixturesProvider(CompRef(competition.orgId, competition.id)))
            .valueOrNull ??
        const <Fixture>[];
    if (fixtures.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SquadCallCard(
        competition: competition,
        fixture: fixtures.first,
      ),
    );
  }
}
