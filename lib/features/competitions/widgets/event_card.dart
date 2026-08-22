import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/section_header.dart';
import '../../../shared/ui_kit.dart';

/// One event in a list — the club, the sport, the field size and where it is
/// up to.
///
/// Lived inside `home_screen.dart` until the dashboard stopped carrying lists.
/// It was always a competitions widget: the home screen was simply the first
/// place that needed one, and three other screens imported it from there,
/// which meant a change to the dashboard could break the events list.
class EventCard extends ConsumerWidget {
  const EventCard({super.key, required this.competition});

  final Competition competition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final org = ref.watch(organizationProvider(c.orgId)).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        // An emoji on a grey disc, which rendered flat-and-grey on one
        // Android build and glossy 3D on another. `SportBadge` is the app's
        // own sport mark and looks the same on every device — the reasoning
        // is written out in `ui_kit.dart`, and this row was ignoring it.
        leading: SportBadge(sportId: c.sportId, size: 40),
        title: Text(c.name),
        subtitle: Text(
          [
            if (org != null) org.name,
            c.sportName,
            c.category.label,
            '${c.entrantCount} entered',
            if (c.startDate != null) friendlyDate(c.startDate!),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: _StatusChip(status: c.displayStatus()),
        onTap: () => context.push(Routes.competition(c.orgId, c.id)),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CompetitionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      CompetitionStatus.registrationOpen => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      CompetitionStatus.inProgress => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
