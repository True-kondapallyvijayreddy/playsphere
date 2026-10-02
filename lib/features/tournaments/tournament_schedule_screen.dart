import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/competition.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/tournament_repository.dart';
import '../../domain/schedule/schedule_view_model.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import '../competitions/widgets/schedule_board.dart';
import '../competitions/widgets/schedule_export.dart';
import '../scoring/open_match.dart';
import 'widgets/graphical_schedule_view.dart';
import 'widgets/season_planner_cards.dart';

/// The timetable on a page of its own.
///
/// A season with fifteen events and four courts does not fit in a panel on a
/// detail screen — the grid needs the width, and an organizer working the
/// schedule is doing that and nothing else. The detail screen keeps a copy so
/// the timetable is still one glance from the tournament, and links here.
class TournamentScheduleScreen extends ConsumerWidget {
  const TournamentScheduleScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
    this.sportId,
  });

  final String orgId;
  final String tournamentId;

  /// One sport's timetable instead of the season's — what "Full schedule" on
  /// a sport's panel of the season page opens. The capacity and health cards
  /// stay season-wide, because the grounds are shared whatever the filter.
  ///
  /// It is also the only place a timetable is built: draw, schedule and
  /// publish act on this sport alone. Without a sport the page is the
  /// season's read-only programme, with a way into each sport.
  final String? sportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final tournamentAsync = ref.watch(tournamentProvider(key));
    final canManage = ref.watch(seasonAccessProvider(key)).canManage;

    final tournament = tournamentAsync.valueOrNull;
    final seasonEvents =
        ref.watch(tournamentEventsProvider(key)).valueOrNull ?? const [];
    final events = _inSport(seasonEvents);
    final eventIds = {for (final e in events) e.id};
    final allFixtures = <Fixture>[
      for (final f
          in ref.watch(tournamentFixturesProvider(key)).valueOrNull ?? const [])
        if ((sportId == null || eventIds.contains(f.compId)) &&
            // Placeholder "Team A v Team B" previews are the organizer's.
            (canManage || !f.isDraft))
          f,
    ];
    final eventNames = {for (final e in events) e.id: e.name};
    final sportName =
        sportId == null || events.isEmpty ? null : events.first.sportName;

    return AppScaffold(
      orgId: orgId,
      title: sportName == null ? 'Schedule' : '$sportName schedule',
      // At the top of the page, not only beside the Programme heading below
      // the court grid. An organiser printing a timetable for a noticeboard
      // should not have to scroll past the grid to find the printer.
      actions: [
        if (tournament != null && allFixtures.isNotEmpty)
          ScheduleDownloadButton(
            fixtures: allFixtures,
            title: sportName == null
                ? tournament.name
                : '${tournament.name} — $sportName',
            subtitle: '${events.length} events · ${allFixtures.length} matches',
            note: allFixtures.any((f) => f.isDraft)
                ? 'DRAFT — team names are placeholders until each draw is '
                    'generated.'
                : null,
            mineEntrantIds: _seasonEntrantIds(ref, key),
            byDay: true,
            sectionOf: (f) => eventNames[f.compId] ?? 'Matches',
            compact: true,
          ),
      ],
      body: AsyncView(
        value: tournamentAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }
          final fixturesAsync = ref.watch(tournamentFixturesProvider(key));

          final sport = sportId;
          final grid = GraphicalScheduleView(
            tournament: tournament,
            events: events,
            fixtures: allFixtures,
            canManage: canManage,
            embedded: false,
            sportId: sport,
            sportName: sportName,
            onDrawAndSchedule: sport == null
                ? null
                : (timings) => drawAndScheduleSport(
                      context: context,
                      ref: ref,
                      orgId: orgId,
                      tournamentId: tournamentId,
                      sportId: sport,
                      sportName: sportName ?? 'this sport',
                      timings: timings,
                    ),
            onRegenerateDraft: sport == null
                ? null
                : (timings) => regenerateTournamentSchedule(
                      context: context,
                      ref: ref,
                      orgId: orgId,
                      tournamentId: tournamentId,
                      sportId: sport,
                      timings: timings,
                    ),
            onLockSchedule: sport == null
                ? null
                : () => lockTournamentSchedule(
                      context: context,
                      ref: ref,
                      orgId: orgId,
                      tournamentId: tournamentId,
                      sportId: sport,
                      sportName: sportName ?? 'this sport',
                    ),
            onOpenSport: (id) => context.pushReplacement(
              Routes.tournamentSchedule(orgId, tournamentId, sportId: id),
            ),
            onMoveMatch: (fixture) => moveMatchByHand(
              context: context,
              ref: ref,
              orgId: orgId,
              tournamentId: tournamentId,
              fixture: fixture,
            ),
            // A live or finished cell cannot be moved; before this it did
            // nothing at all, so the grid was a dead end on match day.
            onOpenMatch: (fixture) => openMatch(
              context,
              fixture: fixture,
              myUid: ref.read(currentUidProvider),
              canManage: canManage,
            ),
          );
          // The grid answers "is Court 2 free at 11" and is the right shape
          // for building a schedule; a coach wants their club's matches in
          // order and a school office wants a sheet for the wall. Both come
          // from the same fixtures, so neither can drift from the other.
          final programme = _SeasonProgramme(
            orgId: orgId,
            tournamentId: tournamentId,
            tournamentName: sportName == null
                ? tournament.name
                : '${tournament.name} — $sportName',
            events: events,
            fixtures: allFixtures,
            canManage: canManage,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              AsyncErrorStrip(value: fixturesAsync, what: 'the matches'),
              if (sportName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InputChip(
                        avatar: Icon(SportVisual.of(sportId!).icon, size: 16),
                        label: Text('$sportName only'),
                        onDeleted: () => context.pushReplacement(
                          Routes.tournamentSchedule(orgId, tournamentId),
                        ),
                        deleteButtonTooltipMessage: 'Show every sport',
                      ),
                    ],
                  ),
                ),
              if (canManage) ...[
                // Feasibility first, timetable second. An organizer opening this
                // page before anything is drawn should be told whether the
                // season fits at all — the answer is available from the entrant
                // counts, and it is worth far more before Generate than after.
                SeasonCapacityCard(
                  orgId: orgId,
                  tournamentId: tournamentId,
                  canManage: canManage,
                ),
                const SizedBox(height: 12),
                ScheduleHealthCard(orgId: orgId, tournamentId: tournamentId),
                const SizedBox(height: 12),
              ],
              // The organizer builds the timetable on the grid, so it comes
              // first for them; everyone else came to read the programme —
              // the same fixtures as a list, and the button that prints it.
              if (canManage) ...[
                grid,
                const SizedBox(height: 24),
                programme,
              ] else ...[
                programme,
                const SizedBox(height: 24),
                grid,
              ],
            ],
          );
        },
      ),
    );
  }
}

extension on TournamentScheduleScreen {
  List<Competition> _inSport(List<Competition> events) => sportId == null
      ? events
      : [
          for (final e in events)
            if (e.sportId == sportId) e,
        ];
}

/// The reader's own entrants across every event in one season.
///
/// The season-level twin of the per-event helper in
/// `competition_detail_screen.dart`; both defer to [MyEntrants] so "ours"
/// means one thing everywhere.
Set<String> _seasonEntrantIds(
  WidgetRef ref,
  ({String orgId, String tournamentId}) key,
) =>
    MyEntrants.resolve(
      entrants: ref.watch(tournamentEntrantsProvider(key)),
      uid: ref.watch(currentUidProvider),
      myOrgIds: {
        for (final m
            in ref.watch(myMembershipsProvider).valueOrNull ?? const [])
          m.orgId,
      },
      myTeamIds: {
        for (final t in ref.watch(myTeamsProvider).valueOrNull ?? const [])
          t.id,
      },
    );

/// The season's matches as a printable, filterable list.
///
/// Bucketed by day rather than by event: the reader of a list is planning a
/// Saturday. The grid above is bucketed by event, because the writer of a
/// schedule is placing one draw at a time.
class _SeasonProgramme extends ConsumerWidget {
  const _SeasonProgramme({
    required this.orgId,
    required this.tournamentId,
    required this.tournamentName,
    required this.events,
    required this.fixtures,
    required this.canManage,
  });

  final String orgId;
  final String tournamentId;
  final String tournamentName;
  final List<Competition> events;
  final List<Fixture> fixtures;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fixtures.isEmpty) return const SizedBox.shrink();
    final key = (orgId: orgId, tournamentId: tournamentId);
    final eventNames = {for (final e in events) e.id: e.name};

    // A draft fixture is "Team A v Team B". The event's own board hides those
    // from everybody but the organizer, and this one must too, or a season
    // page becomes the one place a player reads placeholder opponents.
    final visible =
        canManage ? fixtures : fixtures.where((f) => !f.isDraft).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return ScheduleBoard(
      fixtures: visible,
      mineEntrantIds: _seasonEntrantIds(ref, key),
      title: 'Programme',
      byDay: true,
      sectionOf: (f) => eventNames[f.compId] ?? 'Matches',
      pdfTitle: tournamentName,
      pdfSubtitle: '${events.length} events · ${visible.length} matches',
      pdfNote: visible.any((f) => f.isDraft)
          ? 'DRAFT — team names are placeholders until each draw is generated.'
          : null,
      // The season's copy of the timetable is the one an organizer is looking
      // at on match day, and it was the only fixture list in the app with no
      // tap on it: every row was a dead end, so the scoring pad could not be
      // reached from the season at all. Same destination as the event's own
      // board — `openMatch` owns that decision for both.
      onTapFixture: (f) => openMatch(
        context,
        fixture: f,
        myUid: ref.read(currentUidProvider),
        canManage: canManage,
        onDraft: () => moveMatchByHand(
          context: context,
          ref: ref,
          orgId: orgId,
          tournamentId: tournamentId,
          fixture: f,
        ),
      ),
    );
  }
}

/// Draws every event of one sport and lays its matches out, from one press.
///
/// The stress this product exists to remove: an organizer with fifteen events
/// otherwise opens each one, generates its draw, returns, and only then asks
/// for a timetable. The sport is fitted around the season's other sports, so
/// it still can't double-book a player who entered three of them.
Future<void> drawAndScheduleSport({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
  required String sportId,
  required String sportName,
  required ScheduleTimings timings,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 16),
          Expanded(child: Text('Drawing and scheduling…')),
        ],
      ),
    ),
  );

  SeasonSetupReport? report;
  Object? failure;
  try {
    report = await ref.read(tournamentRepositoryProvider).setUpSport(
          orgId: orgId,
          tournamentId: tournamentId,
          sportId: sportId,
          matchMinutes: timings.matchMinutes,
          changeoverMinutes: timings.changeoverMinutes,
          restGapMinutes: timings.restGapMinutes,
        );
  } catch (e) {
    failure = e;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // the progress dialog

  if (failure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not set up $sportName: $failure')),
    );
    return;
  }

  final r = report!;
  if (r.isClean) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${r.eventsDrawn} events drawn · ${r.schedule.scheduled} matches '
          'placed across ${r.schedule.courts} courts, no clashes.',
        ),
      ),
    );
    return;
  }

  // Anything less than a clean run gets a dialog rather than a snackbar: the
  // organizer has to act on it, and a snackbar disappears while they read.
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$sportName laid out, with gaps'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.eventsDrawn} events drawn · ${r.schedule.scheduled} matches '
              'placed across ${r.schedule.courts} courts.',
            ),
            if (r.eventsSkipped.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Not drawn',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              for (final s in r.eventsSkipped) Text('• $s'),
            ],
            if (r.schedule.problems.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${r.schedule.unscheduled} matches have no court or time',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              for (final p in r.schedule.problems) Text('• $p'),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// Persists the organizer's timings and re-solves the timetable.
///
/// Shared with the detail screen's embedded copy rather than duplicated: two
/// buttons that regenerate the same schedule must not drift into two
/// behaviours, and the first version of this had the timings on one path only.
Future<void> regenerateTournamentSchedule({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
  required String sportId,
  required ScheduleTimings timings,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final report =
        await ref.read(tournamentRepositoryProvider).regenerateDraftSchedule(
              orgId: orgId,
              tournamentId: tournamentId,
              sportId: sportId,
              matchMinutes: timings.matchMinutes,
              changeoverMinutes: timings.changeoverMinutes,
              restGapMinutes: timings.restGapMinutes,
            );
    if (!context.mounted) return;
    final unplaced = report.unscheduled > 0
        ? ' ${report.unscheduled} could not be placed.'
        : '';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${report.scheduled} matches placed across ${report.courts} '
          'courts.$unplaced',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('Could not schedule: $e')));
  }
}

/// Moves one match by hand, and re-checks the whole timetable before it does.
///
/// ## Why the organizer keeps control and still cannot break the schedule
///
/// Manual intervention is not a failure of the solver — a team asks for a
/// later start, a ground frees up, a parent has to leave by four. What must
/// not happen is a move that quietly breaks something a page away: the same
/// player is in the table-tennis doubles at that hour, or the ground is shut.
/// So the move is validated against the entire season first, refused with the
/// specific clash named, and only then offered again as an explicit override.
Future<void> moveMatchByHand({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
  required Fixture fixture,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final calendarsAsync = ref.read(venueCapacityLinesProvider((
    orgId: orgId,
    tournamentId: tournamentId,
  )));

  final choice = await showModalBottomSheet<_MoveChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveMatchSheet(
      orgId: orgId,
      tournamentId: tournamentId,
      fixture: fixture,
      venueNames: [
        for (final l in calendarsAsync.valueOrNull ?? const [])
          (id: l.venueId, name: l.venueName),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  Future<void> attempt({required bool force}) async {
    await ref.read(tournamentRepositoryProvider).moveFixture(
          orgId: orgId,
          tournamentId: tournamentId,
          compId: fixture.compId,
          fixtureId: fixture.id,
          newStart: choice.start,
          venueId: choice.venueId,
          courtRefId: choice.courtRefId,
          force: force,
        );
  }

  try {
    await attempt(force: false);
    messenger.showSnackBar(
      const SnackBar(content: Text('Match moved. Schedule still clean.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    final override = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('That move causes a conflict'),
        content: SingleChildScrollView(child: Text('$e')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Leave it where it was'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move anyway'),
          ),
        ],
      ),
    );
    if (override != true) return;
    try {
      await attempt(force: true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Moved. The conflict is listed under Schedule health.'),
        ),
      );
    } catch (e2) {
      if (!context.mounted) return;
      showError(context, e2);
    }
  }
}

typedef _MoveChoice = ({DateTime? start, String? venueId, String? courtRefId});

/// Where and when, asked in the two questions an organizer actually has.
class _MoveMatchSheet extends ConsumerStatefulWidget {
  const _MoveMatchSheet({
    required this.orgId,
    required this.tournamentId,
    required this.fixture,
    required this.venueNames,
  });

  final String orgId;
  final String tournamentId;
  final Fixture fixture;
  final List<({String id, String name})> venueNames;

  @override
  ConsumerState<_MoveMatchSheet> createState() => _MoveMatchSheetState();
}

class _MoveMatchSheetState extends ConsumerState<_MoveMatchSheet> {
  late DateTime _when = widget.fixture.scheduledAt ??
      DateTime.now().add(const Duration(hours: 1));
  String? _venueId;
  String? _courtRefId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final venues =
        ref.watch(venuesProvider(widget.orgId)).valueOrNull ?? const [];
    final allowed = {for (final v in widget.venueNames) v.id};
    final options = [
      for (final v in venues)
        if (allowed.isEmpty || allowed.contains(v.id)) v,
    ];
    final selected = _venueId == null
        ? null
        : options.where((v) => v.id == _venueId).firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Move this match', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${widget.fixture.displayNameA()} v '
            '${widget.fixture.displayNameB()}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Date and time'),
            subtitle: Text(
              '${_when.day}/${_when.month}/${_when.year} · '
              '${_when.hour.toString().padLeft(2, '0')}:'
              '${_when.minute.toString().padLeft(2, '0')}',
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _when,
                firstDate: DateTime(_when.year - 1),
                lastDate: DateTime(_when.year + 2),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_when),
              );
              if (time == null) return;
              setState(() => _when = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ));
            },
          ),
          DropdownButtonFormField<String>(
            value: _venueId,
            decoration: const InputDecoration(
              labelText: 'Ground',
              helperText: 'Leave unchanged to keep the current court',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final v in options)
                DropdownMenuItem(value: v.id, child: Text(v.name)),
            ],
            onChanged: (v) => setState(() {
              _venueId = v;
              _courtRefId = null;
            }),
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _courtRefId,
              decoration: const InputDecoration(
                labelText: 'Playing area',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in selected.usableCourts)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _courtRefId = v),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  // Choosing a ground without a court would move the match to
                  // a venue and leave it on a court belonging to another one.
                  onPressed: _venueId != null && _courtRefId == null
                      ? null
                      : () => Navigator.of(context).pop((
                            start: _when,
                            venueId: _venueId,
                            courtRefId: _courtRefId,
                          )),
                  child: const Text('Move'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Publishes one sport's draft: its timetable becomes official and everyone
/// entered in it is told. The season's other sports are untouched.
Future<void> lockTournamentSchedule({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
  required String sportId,
  required String sportName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Publish the $sportName schedule?'),
      content: Text(
        'This publishes the $sportName timetable, closes new entries to its '
        'events, and notifies every team and player entered in them. Other '
        'sports in the season are not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Lock & Notify'),
        ),
      ],
    ),
  );
  if (confirm != true) return;

  try {
    await ref.read(tournamentRepositoryProvider).lockSchedule(
          orgId: orgId,
          tournamentId: tournamentId,
          sportId: sportId,
        );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('$sportName schedule published.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('Could not publish: $e')));
  }
}

/// Brings a paused season back, and says what came back with it.
///
/// No reason box and no confirmation dialog on this side: pausing is the half
/// that owes an explanation to everyone who entered, resuming is the half
/// they were waiting for. Every event the season paused resumes with it — see
/// `TournamentRepository.resumeTournament` for the one that does not.
Future<void> resumeSeason({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;

  try {
    await ref.read(tournamentRepositoryProvider).resumeTournament(
          orgId: orgId,
          tournamentId: tournamentId,
          byUid: uid,
        );
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Season resumed. Entries are open again.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    showError(context, e);
  }
}
