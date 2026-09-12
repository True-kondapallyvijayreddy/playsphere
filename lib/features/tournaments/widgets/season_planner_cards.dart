import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/draw/schedule_guarantees.dart';
import '../../../domain/draw/season_capacity.dart';
import '../../../shared/ui_kit.dart';

/// "Will this fit?", answered before the organizer presses Generate.
///
/// ## Why this is a card and not an error message
///
/// The failure it prevents — a season that cannot be played in the days and
/// grounds it has — used to surface as a list of unplaced matches *after* the
/// draw was made and published. By then every option is expensive. Asked
/// first, the same arithmetic is a plan: 45 matches needed, 50 slots
/// available, green. Or 45 against 30, and five things that would fix it.
class SeasonCapacityCard extends ConsumerWidget {
  const SeasonCapacityCard({
    super.key,
    required this.orgId,
    required this.tournamentId,
    this.canManage = false,
  });

  final String orgId;
  final String tournamentId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final async = ref.watch(seasonCapacityProvider(key));
    final theme = Theme.of(context);

    return async.when(
      loading: () => const PsCard(
        child: Row(
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Working out whether the season fits…'),
          ],
        ),
      ),
      // A capacity check that cannot run is not a red verdict. It usually
      // means the season has no dates or no events yet, and announcing
      // "impossible" for a season nobody has finished setting up is worse
      // than saying nothing.
      error: (e, _) => PsCard(
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Capacity cannot be checked yet. $e',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      data: (report) => _CapacityBody(
        orgId: orgId,
        tournamentId: tournamentId,
        report: report,
        canManage: canManage,
      ),
    );
  }
}

class _CapacityBody extends StatelessWidget {
  const _CapacityBody({
    required this.orgId,
    required this.tournamentId,
    required this.report,
    required this.canManage,
  });

  final String orgId;
  final String tournamentId;
  final CapacityReport report;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = report.isFeasible;
    final accent = ok ? Colors.green.shade700 : theme.colorScheme.error;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline,
                  size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok ? 'Schedule feasible' : 'Will not fit as planned',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
              if (canManage)
                TextButton.icon(
                  onPressed: () => context.push(
                    Routes.venuePlanner(orgId, tournamentId),
                  ),
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Venues'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Matches required',
                  value: '${report.totalRequired}',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Slots available',
                  value: '${report.totalCapacity}',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Playing areas',
                  value: '${report.courts}',
                ),
              ),
            ],
          ),
          if (!ok) ...[
            const SizedBox(height: 12),
            for (final problem in report.problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $problem', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Text(
              report.shortfall > 0
                  ? 'You need ${report.shortfall} more match '
                      '${report.shortfall == 1 ? 'slot' : 'slots'}. Any of '
                      'these would give them:'
                  : 'Any of these would help:',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            for (final s in report.suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('→ $s', style: theme.textTheme.bodySmall),
              ),
          ] else if (report.perEvent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${report.perEvent.length} '
              '${report.perEvent.length == 1 ? 'event' : 'events'} all fit '
              'inside the grounds and days they were given.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Every promise the timetable makes, checked — and shown even when they all
/// hold.
///
/// A panel that only appears when something is wrong is a panel nobody
/// believes when it stays quiet. Zeroes across the board is the state an
/// organizer wants to see before they press Publish.
class ScheduleHealthCard extends ConsumerWidget {
  const ScheduleHealthCard({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  static const _checks = <(ScheduleViolationKind, String)>[
    (ScheduleViolationKind.playerDoubleBooked, 'Player conflicts'),
    (ScheduleViolationKind.teamDoubleBooked, 'Team conflicts'),
    (ScheduleViolationKind.courtDoubleBooked, 'Venue conflicts'),
    (ScheduleViolationKind.outsideVenueAvailability, 'Unavailable slots'),
    (ScheduleViolationKind.outsideEventAvailability, 'Wrong ground or day'),
    (ScheduleViolationKind.restGapTooShort, 'Rest violations'),
    (ScheduleViolationKind.dailyLimitExceeded, 'Daily maximum exceeded'),
    (ScheduleViolationKind.roundOutOfOrder, 'Rounds out of order'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (orgId: orgId, tournamentId: tournamentId);
    final async = ref.watch(scheduleHealthProvider(key));
    final theme = Theme.of(context);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (report) {
        if (report.scheduled == 0) return const SizedBox.shrink();
        final ok = report.isHealthy;

        return PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
                    size: 20,
                    color: ok ? Colors.green.shade700 : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Schedule health',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${report.scheduled} placed',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final check in _checks)
                _HealthRow(
                  label: check.$2,
                  count: report.countOf(check.$1),
                  details: report.detailsOf(check.$1),
                ),
              if (report.unscheduled > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${report.unscheduled} '
                  '${report.unscheduled == 1 ? 'match has' : 'matches have'} '
                  'no time yet — usually a knockout waiting on a result.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (report.unverifiable > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${report.unverifiable} on a court this season does not '
                  'recognise, so venue hours could not be checked for '
                  '${report.unverifiable == 1 ? 'it' : 'them'}.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.label,
    required this.count,
    required this.details,
  });

  final String label;
  final int count;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = count == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ok ? null : theme.colorScheme.error,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                ok ? Icons.check : Icons.close,
                size: 16,
                color: ok ? Colors.green.shade700 : theme.colorScheme.error,
              ),
            ],
          ),
          for (final d in details)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                '• $d',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

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
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
