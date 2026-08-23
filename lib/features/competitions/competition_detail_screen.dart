import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/models/draw_slot.dart';
import '../../domain/draw/group_bounds.dart';
import '../../domain/draw/seeding.dart';
import '../../domain/draw/swiss_pairing.dart';
import '../../domain/tournament/house_roster.dart';
import '../../domain/standings/standings_calculator.dart';
import '../../domain/standings/tiebreak.dart';
import '../../data/image_composer.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/image_upload.dart';
import '../../shared/ps_banner.dart';
import '../../shared/ui_kit.dart';
import 'widgets/cancel_event_sheet.dart';
import 'widgets/competition_rule_editor.dart';
import 'widgets/houses_editor_sheet.dart';
import 'widgets/draw_setup_sheet.dart';
import 'widgets/group_entry_sheet.dart';
import 'widgets/group_stage_fields.dart';
import 'widgets/move_match_sheet.dart';
import 'widgets/register_team_sheet.dart';
import 'widgets/team_builder_sheet.dart';
import '../tournaments/widgets/running_late_card.dart';
import 'widgets/squad_call_card.dart';
import 'widgets/start_early_sheet.dart';
import 'widgets/suspend_sheet.dart';
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
                    _Header(competition: comp, canManage: canManage),
                    const SizedBox(height: 16),
                    // Above the organizer's own controls: a paused event is
                    // the first thing anyone opening this needs to know, and
                    // the reason is what stops them phoning to ask.
                    if (comp.isSuspended)
                      OnHoldBanner(
                        what: 'event',
                        reason: comp.suspendReason,
                        resumeLabel: 'Resume',
                        onResume: !canManage || comp.suspendedBySeason
                            ? null
                            : () => _resumeEvent(context, ref, comp),
                      ),
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
                    if (canManage) _SwissRoundCard(competition: comp),
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
class _Header extends ConsumerWidget {
  const _Header({required this.competition, this.canManage = false});
  final Competition competition;
  final bool canManage;

  Future<void> _changeBanner(BuildContext context, WidgetRef ref) {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return Future.value();
    final repo = ref.read(competitionRepositoryProvider);
    return pickAndUploadImage(
      context: context,
      title: 'Event banner',
      shape: ImageShape.banner,
      successMessage: 'Banner updated.',
      removedMessage: 'Banner removed.',
      onUpload: (image) => repo.uploadEventBanner(
        orgId: competition.orgId,
        compId: competition.id,
        uid: uid,
        bytes: image.bytes,
        contentType: image.contentType,
      ),
      onRemove: competition.bannerUrl == null
          ? null
          : () => repo.removeEventBanner(
                orgId: competition.orgId,
                compId: competition.id,
              ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsBanner(
        imageUrl: c.bannerUrl,
        sportId: c.sportId,
        seed: c.id,
        height: 156,
        trailing: canManage
            ? _BannerEditButton(onTap: () => _changeBanner(context, ref))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                c.sportName,
                c.category.label,
                c.format.label,
                // Derived, not stored: nothing writes the status field when a
                // registration deadline passes, so a closed event went on
                // advertising "Registration Open" (Bug #6).
                c.displayStatus().label,
                if (c.venue != null && c.venue!.trim().isNotEmpty) c.venue!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Color(0xE6FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one control that sits on top of a banner.
///
/// A filled circle rather than a plain [IconButton]: it has to stay legible
/// over an uploaded photograph of unknown brightness, and a bare white glyph
/// disappears against a pale sky.
class _BannerEditButton extends StatelessWidget {
  const _BannerEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8A000000),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Change the banner',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
        onPressed: onTap,
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

                // No default scorer. The organizer making the draw cannot be
                // at every court, and naming them on every match produced a
                // roster nobody believed — see `generateDraw`'s parameter.
                final made = await repo.generateDraw(
                  competition: configured,
                  entrants: entrants,
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
          // Only for events people enter as part of a group. An individual
          // event has nothing to split into houses, and offering the editor
          // there would be a menu item that changes nothing.
          if (c.entrantType == EntrantType.team)
            PsAction(
              label: 'Houses & groups',
              icon: Icons.holiday_village_outlined,
              onSelected: () =>
                  HousesEditorSheet.show(context, competition: c),
            ),
          PsAction(
            label: 'Send a note',
            icon: Icons.campaign_outlined,
            onSelected: () => EventNoteSheet.show(context, competition: c),
          ),
          // Above cancelling in the menu, and not destructive: it is the
          // one an organizer actually wants on a wet morning, and the
          // permanent one below it is what they used to reach for instead.
          // Nothing offered when the SEASON paused this event: the resume
          // belongs on the season, and an event-level button that always
          // fails is worse than no button.
          if (canStillCancel && !c.suspendedBySeason)
            if (c.isSuspended)
              PsAction(
                label: 'Resume event',
                icon: Icons.play_circle_outline,
                onSelected: () => _resumeEvent(context, ref, c),
              )
            else
              PsAction(
                label: 'Put on hold',
                icon: Icons.pause_circle_outline,
                onSelected: () =>
                    SuspendSheet.showForEvent(context, competition: c),
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
            const SizedBox(height: 10),
            // Said out loud because an organizer will not risk a half-built
            // bracket on a guess. It is true at every layer, not just this
            // one: the fixture list pins `isDraft == false` for anyone
            // without `manageCompetitions`, `firestore.rules` refuses a
            // draft to them on both the nested and collection-group paths,
            // and a draft carries no scorer for anyone to reach it through.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, size: 15, color: Ps.faint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Only club admins can see a draft. Nothing here reaches '
                    'members, entrants or other clubs until you publish it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
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
                numGroups: plan.numGroups,
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

  static Future<({int teamCount, int? numGroups})?> show(
    BuildContext context, {
    required Competition competition,
    int registeredCount = 0,
  }) =>
      showModalBottomSheet<({int teamCount, int? numGroups})>(
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

  /// How many GROUPS, which is the question the organizer is answering.
  ///
  /// Null until they touch the stepper, so the number shown tracks the field
  /// size as they change it rather than freezing at whatever was legal for
  /// the first value they saw. Once set it is theirs, re-clamped only when
  /// the field size makes it illegal.
  int? _numGroups;

  bool get _isGroups => widget.competition.hasGroupStage;

  /// Qualifiers matter to the bounds only when the groups feed a knockout —
  /// a pool promotes nobody, so the only floor on it is what makes a group a
  /// group. Same rule [GroupStageFields] applies, deliberately.
  int get _qualifierFloor => widget.competition.groupsFeedKnockout
      ? widget.competition.drawConfig.qualifiersPerGroup
      : 1;

  int get _minGroups => GroupBounds.minGroups(_teamCount);

  int get _maxGroups =>
      GroupBounds.maxGroups(_teamCount, qualifiersPerGroup: _qualifierFloor);

  /// The group count the draw will actually use, so nothing on this sheet can
  /// promise a shape the generator will not produce.
  int get _resolvedGroups => GroupBounds.resolve(
        entrants: _teamCount,
        requested: _numGroups,
        qualifiersPerGroup: _qualifierFloor,
      );

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
            CountStepper(
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
              // The number of GROUPS, not the number of teams in one.
              //
              // This asked for "Teams per group", capped at 4, and the two
              // mistakes compounded: an organizer with 32 teams who wanted
              // four groups typed 4 and got eight groups of four, and four
              // groups of eight was not reachable from this sheet at all
              // because a group of eight was over the cap. Groups is also
              // the number they are choosing between — two or four or eight —
              // while the size is what falls out of it, which is why the
              // size now lives in the read-only summary below.
              CountStepper(
                label: 'Number of groups',
                value: _resolvedGroups,
                min: _minGroups,
                max: _maxGroups,
                onChanged: (v) => setState(() => _numGroups = v),
              ),
              // Why the stepper stops where it does. An organizer who cannot
              // reach the number they wanted deserves the reason rather than
              // a greyed-out button: a group of one advances unplayed, and a
              // group of nine is a longer phase than the knockout it feeds.
              Text(
                'Between $_minGroups and $_maxGroups groups for $_teamCount '
                'teams — no group smaller than ${GroupBounds.minPerGroup} or '
                'bigger than ${GroupBounds.maxPerGroup}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              _GroupSplit(
                groups: _resolvedGroups,
                teams: _teamCount,
                qualifiersPerGroup: widget.competition.groupsFeedKnockout
                    ? widget.competition.drawConfig.qualifiersPerGroup
                    : null,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((
                teamCount: _teamCount,
                numGroups: _isGroups ? _resolvedGroups : null,
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

/// What "4 groups" actually produces, spelled out before the button is
/// pressed.
///
/// The organizer's input and the tournament they get are two different
/// numbers — pick four groups from a field of 32 and eight-team groups are
/// the consequence — and a stepper alone shows only the input. Every argument
/// about a group stage is really an argument about the arithmetic nobody was
/// shown, so it is shown.
class _GroupSplit extends StatelessWidget {
  const _GroupSplit({
    required this.groups,
    required this.teams,
    required this.qualifiersPerGroup,
  });

  final int groups;
  final int teams;

  /// Null for pools, which promote nobody and so have no knockout line.
  final int? qualifiersPerGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final smallest = GroupBounds.smallestGroupSize(teams, groups);
    final largest = GroupBounds.largestGroupSize(teams, groups);
    // An uneven split is said out loud rather than averaged away. Somebody
    // has to explain to the group of five why they play an extra match, and
    // they can only do that if the app told them it was happening.
    final even = smallest == largest;
    final perGroup = even ? '$smallest' : '$smallest\u2013$largest';
    final qualifiers = qualifiersPerGroup;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          _SplitRow(label: 'Groups', value: '$groups'),
          _SplitRow(
            label: 'Teams per group',
            value: even ? perGroup : '$perGroup (uneven)',
          ),
          _SplitRow(label: 'Teams total', value: '$teams'),
          if (qualifiers != null)
            _SplitRow(
              label: 'Into the knockout',
              value: '${groups * qualifiers} '
                  '(top $qualifiers of each)',
            ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
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

      // House / group selection.
      //
      // Which house someone represents is an affiliation, not an entrant
      // shape: a sprinter in the 100m enters as herself and still scores for
      // Red House. Gating this on `houseBatch` meant every individual event
      // in a school season — athletics, singles, chess, the bulk of a sports
      // day — registered people with no house at all, and the organizer was
      // left with a flat list no house table could be built from. So the ask
      // follows the house list the organizer authored, not the entry mode.
      // `houseBatch` still differs downstream, where `EntrantPromoter` folds
      // a house's registrations into one entrant; here the two are the same
      // question.
      if (c.presetHouses.isNotEmpty ||
          c.teamEntryMode == TeamEntryMode.houseBatch) {
        // The fallback is for events created before houses were editable,
        // whose `presetHouses` is empty. A new event always carries the
        // organizer's own list — see `HousesEditorSheet`.
        final houses = c.presetHouses.isNotEmpty
            ? c.presetHouses
            : HouseTemplates.schoolColours;
        // The club already knows this student is ECE 3rd Year; making her say
        // so again is how a roster and a registration drift apart. Falls back
        // to the first house only when the membership cannot answer — see
        // `HouseAssigner`, which is the same matcher the bulk placement uses.
        String selectedHouse =
            HouseAssigner.assign(membership?.grouping ?? MemberGrouping.empty,
                    houses) ??
                houses.first;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.school_outlined),
                  SizedBox(width: 8),
                  Text('Select Your Group'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Which house, department, year or section are you '
                    'representing?',
                  ),
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

    // Whether the thing that enters this event is a TEAM DOCUMENT.
    //
    // Not simply `entrantType == team`: houses, a doubles draw and a player
    // pool all produce team-shaped entrants and all three are assembled from
    // registrations that individual people make, which is correct and stays.
    // What is left — a pre-formed side, and the default an organizer never
    // changed — is the case where a person registering themselves produces
    // nothing that can play. `individual` is included deliberately: it is the
    // value a cricket event created from the ordinary "New event" form used
    // to carry, and reading it as "one player, one entry" is precisely how a
    // 32-team tournament ended up with a bracket of individuals.
    final teamIsTheEntrant = c.entrantType == EntrantType.team &&
        (c.teamEntryMode == TeamEntryMode.preformedTeam ||
            c.teamEntryMode == TeamEntryMode.individual);

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
                      if (teamIsTheEntrant) ...[
                        // The entry unit is a side, so this is the only
                        // primary action. A personal "Register" here was the
                        // bug: on a 32-team cricket tournament it invited
                        // three hundred and fifty people to enter singly, and
                        // the field that produced could not be drawn.
                        FilledButton.tonal(
                          onPressed: () => RegisterTeamSheet.show(
                            context,
                            competition: c,
                          ),
                          child: const Text('Enter a team'),
                        ),
                        OutlinedButton.icon(
                          onPressed: eligibility?.isEligible == true
                              ? () => GroupEntrySheet.show(
                                    context,
                                    competition: c,
                                  )
                              : null,
                          icon: const Icon(Icons.groups_outlined, size: 16),
                          // Distinct from the button beside it, because they
                          // are different things: this assembles a squad for
                          // this event alone, with an accept from each person
                          // named, and it disappears when the event does.
                          label: const Text('One-off squad'),
                        ),
                      ] else ...[
                        FilledButton.tonal(
                          onPressed:
                              eligibility?.isEligible == true ? enter : null,
                          child: Text(actionLabel),
                        ),
                        if (c.entrantType == EntrantType.team)
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
                  // A side gets a crest and a person gets a face. They are
                  // in one list and a round photo frame on a club reads as a
                  // person, which on a team event is every row.
                  leading: r.isTeamEntry
                      ? PsCrest(
                          name: r.displayName,
                          logoUrl: r.photoUrl,
                          seed: r.uid,
                          size: 32,
                        )
                      : PsAvatar(
                          name: r.displayName,
                          photoUrl: r.photoUrl,
                          seed: r.uid,
                          size: 32,
                        ),
                  title: Text(r.displayName),
                  subtitle: Text(
                    [
                      if (r.status == RegistrationStatus.waitlisted &&
                          r.waitlistPosition != null)
                        'Waitlist #${r.waitlistPosition}'
                      else
                        r.status.label,
                      // How many are in the squad that entered. The one
                      // number an organizer checks a team entry against, and
                      // the one a captain needs to see is wrong before the
                      // draw rather than at the toss.
                      if (r.isTeamEntry)
                        '${r.memberUids.length} '
                            '${r.memberUids.length == 1 ? 'player' : 'players'}',
                      // The house is the whole point of a school event —
                      // an entries list that does not show it cannot be
                      // checked against the roster, and the organizer has no
                      // way to spot the student who picked the wrong one
                      // until the house table comes out wrong.
                      if (r.houseName != null) r.houseName!,
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
    // Qualifier promotion is a groups-into-a-bracket thing, and asking the
    // format alone missed a knockout that had a group stage added to it.
    if (!c.groupsFeedKnockout) return const SizedBox.shrink();

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

/// Pairs the next Swiss round, and says why it cannot yet when it cannot.
///
/// ## Why Swiss needs a card and a knockout does not
///
/// Every other format's whole shape is written at draw time: a knockout's
/// quarter-final exists, empty, from the moment the bracket does, and
/// finishing a match just fills a name into a document already there. Swiss
/// has nothing to fill. Round three does not exist in any form until round
/// two has been played, because its pairings ARE the standings — so somebody
/// has to ask for it, and until this card there was nowhere to ask.
///
/// The card is deliberately loud about the two reasons pairing is refused —
/// a round still being played, and the event having run its distance —
/// because both look identical from the organizer's side otherwise: a button
/// that does nothing.
class _SwissRoundCard extends ConsumerStatefulWidget {
  const _SwissRoundCard({required this.competition});
  final Competition competition;

  @override
  ConsumerState<_SwissRoundCard> createState() => _SwissRoundCardState();
}

class _SwissRoundCardState extends ConsumerState<_SwissRoundCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.competition;
    if (c.format != CompetitionFormat.swiss) {
      return const SizedBox.shrink();
    }

    final fixtures =
        ref.watch(fixturesProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const <Fixture>[];
    // Before the draw exists there is no round to pair from, and "Make the
    // draw" is already the screen's primary action — two buttons asking for
    // the same thing is worse than one.
    if (fixtures.isEmpty) return const SizedBox.shrink();

    final entrants =
        ref.watch(entrantsProvider(CompRef(c.orgId, c.id))).valueOrNull ??
            const <Entrant>[];
    final activeCount = entrants.where((e) => !e.withdrawn).length;
    if (activeCount < 2) return const SizedBox.shrink();

    final currentRound =
        fixtures.fold<int>(1, (hi, f) => f.round > hi ? f.round : hi);
    final totalRounds = const SwissPairing().recommendedRoundCount(
      activeCount,
      override: c.drawConfig.swissRounds,
    );
    final pending = fixtures
        .where((f) => f.round == currentRound && !f.hasResult)
        .length;

    final isComplete = currentRound >= totalRounds;
    final canPair = !isComplete && pending == 0;

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
                'Round $currentRound of $totalRounds',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                isComplete
                    ? 'Every round has been played. The standings below are '
                        'the final order.'
                    : pending > 0
                        ? '$pending ${pending == 1 ? 'match' : 'matches'} '
                            'still ${pending == 1 ? 'needs' : 'need'} a '
                            'result. Swiss pairs the next round by standing, '
                            'so the table has to be final before it can be '
                            'drawn.'
                        : 'Round $currentRound is finished. Pairing round '
                            '${currentRound + 1} puts each entrant against '
                            'the closest opponent on the table they have not '
                            'already played.',
                style: theme.textTheme.bodyMedium,
              ),
              if (!isComplete) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy || !canPair ? null : _pair,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_outlined),
                  label: Text('Pair round ${currentRound + 1}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pair() async {
    setState(() => _busy = true);
    final c = widget.competition;
    try {
      final entrants =
          ref.read(entrantsProvider(CompRef(c.orgId, c.id))).valueOrNull ??
              const <Entrant>[];
      final outcome = await ref
          .read(competitionRepositoryProvider)
          .generateNextSwissRound(competition: c, entrants: entrants);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Round ${outcome.round} paired — ${outcome.written} '
            '${outcome.written == 1 ? 'match' : 'matches'}.'
            // The bye is the absence of a fixture, so it is the one thing
            // about the new round that the fixture list cannot show. An
            // organizer who is not told here gets asked at the venue.
            '${outcome.byeEntrantName != null ? ' ${outcome.byeEntrantName} has the bye.' : ''}'
            '${outcome.isFinalRound ? ' This is the final round.' : ''}',
          ),
        ),
      );
      if (outcome.hasScheduleProblems) {
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _ScheduleProblemsDialog(problems: outcome.scheduleProblems),
        );
      }
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
    // A knockout with a group stage in front of it has tables too — its
    // groups are round robins. Gating on the format alone hid them.
    if (!_tableFormats.contains(competition.format) &&
        !competition.hasGroupStage) {
      return const SizedBox.shrink();
    }

    // A groups draw has several tables and no meaningful combined one: Group
    // A's players have never met Group B's, so their points do not compare.
    // Showing one merged table was not just untidy, it was wrong.
    if (competition.hasGroupStage) {
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
    final canPromote = ref
        .watch(myCapabilitiesProvider(widget.fixture.orgId))
        .contains(Capability.manageMembers);

    // EVERY active member, not only the ones who already hold a scoring role.
    //
    // This list used to be filtered to role-holders, on the reasoning that
    // offering a plain member would let an organizer assign somebody the
    // rules then reject. True as far as it went, and it made the common case
    // a dead end: on a Sunday morning the person willing to score is whoever
    // turned up, a club that has never appointed a scorer saw "Nobody here
    // holds the scorer role yet", and the fix was three screens away in the
    // middle of a match that was about to start.
    //
    // Both halves of the grant are made here instead. Anyone without the role
    // is shown with that fact against their name, and choosing them promotes
    // them to Judge / Scorer — the club's narrowest role — as part of saving.
    // An event manager, who may assign but not change roles, is told so
    // rather than being handed a grant that dies at the database.
    final eligible = [
      for (final m in members)
        if (m.isActive)
          if (canPromote || PermissionMatrix.can(m.role, Capability.scoreMatches))
            m,
    ];

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
                  Text(
                    canPromote
                        ? 'This club has no active members yet.'
                        : 'Nobody here holds the scorer role yet, and only a '
                            'club admin can give it to someone.',
                  ),
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
                      subtitle: Text(
                        PermissionMatrix.can(m.role, Capability.scoreMatches)
                            ? m.role.label
                            : '${m.role.label} — will be made a '
                                'Judge / Scorer',
                      ),
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
                    // The role grants first, and awaited: assigning somebody
                    // who cannot score is the failure this whole dialog was
                    // rewritten to stop, so the pen is only handed over once
                    // the authority behind it exists.
                    final org = ref.read(orgRepositoryProvider);
                    for (final m in eligible) {
                      if (!_selected.contains(m.uid)) continue;
                      if (PermissionMatrix.can(
                        m.role,
                        Capability.scoreMatches,
                      )) {
                        continue;
                      }
                      await org.changeRole(
                        orgId: widget.fixture.orgId,
                        uid: m.uid,
                        role: MembershipRole.judgeScorer,
                      );
                    }
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

/// Brings one paused event back.
///
/// Refuses out of the repository when the season above it is on hold, so this
/// does not have to know whether there is a season — the message that comes
/// back names the season and tells the organizer to resume that instead.
Future<void> _resumeEvent(
  BuildContext context,
  WidgetRef ref,
  Competition competition,
) async {
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(competitionRepositoryProvider).resumeCompetition(
          orgId: competition.orgId,
          compId: competition.id,
          byUid: uid,
        );
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Event resumed. Entries are open again.')),
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
