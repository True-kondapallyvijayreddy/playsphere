import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../data/tournament_repository.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/graphical_schedule_view.dart';

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
      title: 'Schedule',
      body: AsyncView(
        value: tournamentAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }
          final eventsAsync = ref.watch(tournamentEventsProvider(key));
          final fixturesAsync = ref.watch(tournamentFixturesProvider(key));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              AsyncErrorStrip(value: fixturesAsync, what: 'the matches'),
              GraphicalScheduleView(
                tournament: tournament,
                events: eventsAsync.valueOrNull ?? const [],
                fixtures: fixturesAsync.valueOrNull ?? const [],
                canManage: canManage,
                embedded: false,
                onSetUpWholeSeason: (timings) => setUpWholeSeason(
                  context: context,
                  ref: ref,
                  orgId: orgId,
                  tournamentId: tournamentId,
                  timings: timings,
                ),
                onRegenerateDraft: (timings) => regenerateTournamentSchedule(
                  context: context,
                  ref: ref,
                  orgId: orgId,
                  tournamentId: tournamentId,
                  timings: timings,
                ),
                onLockSchedule: () => lockTournamentSchedule(
                  context: context,
                  ref: ref,
                  orgId: orgId,
                  tournamentId: tournamentId,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Draws every event and lays the whole season out, from one press.
///
/// The stress this product exists to remove: an organizer with fifteen events
/// otherwise opens each one, generates its draw, returns, and only then asks
/// for a timetable — and a schedule solved per event still double-books the
/// player who entered three of them.
Future<void> setUpWholeSeason({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
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
          Expanded(child: Text('Drawing every event and scheduling…')),
        ],
      ),
    ),
  );

  SeasonSetupReport? report;
  Object? failure;
  try {
    report = await ref.read(tournamentRepositoryProvider).setUpWholeSeason(
          orgId: orgId,
          tournamentId: tournamentId,
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
      SnackBar(content: Text('Could not set up the season: $failure')),
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
      title: const Text('Season laid out, with gaps'),
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
  required ScheduleTimings timings,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final report =
        await ref.read(tournamentRepositoryProvider).regenerateDraftSchedule(
              orgId: orgId,
              tournamentId: tournamentId,
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

/// Publishes the draft: the timetable becomes official and everyone entered
/// is told.
Future<void> lockTournamentSchedule({
  required BuildContext context,
  required WidgetRef ref,
  required String orgId,
  required String tournamentId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Lock & publish schedule?'),
      content: const Text(
        'This publishes the timetable, closes new entries, and notifies every '
        'registered team and player.',
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
        );
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Schedule published.')),
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
