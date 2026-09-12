import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/identity.dart';
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
        //
        // The event's own crest displaces it where there is one: an organizer
        // who put a badge on their tournament expects to see it on the row,
        // and the sport is already named on the line below. Nothing is
        // invented when there is no logo — the sport mark stays.
        leading: (c.logoUrl ?? '').trim().isEmpty
            ? SportBadge(sportId: c.sportId, size: 40)
            : PsCrest(name: c.name, logoUrl: c.logoUrl, seed: c.id, size: 40),
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
        trailing: EventStatusChip(status: c.displayStatus()),
        onTap: () => context.push(Routes.competition(c.orgId, c.id)),
      ),
    );
  }
}

/// Where an event is up to, as a chip on its card.
///
/// Public, and shared. Three screens had a private copy of this — the club
/// dashboard, this card, and the club's events list — and they had already
/// drifted: one of them coloured a cancelled event exactly like a completed
/// one, so a club could not tell a tournament it called off from one it
/// finished without opening both.
///
/// Always pass `Competition.displayStatus()`, never the raw `status` field.
/// A registration whose deadline has passed is closed whether or not anybody
/// has written that down, and a chip that says "Registration Open" over a
/// closed form is the one thing this chip must not do.
class EventStatusChip extends StatelessWidget {
  const EventStatusChip({super.key, required this.status});

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
      CompetitionStatus.cancelled => (
          scheme.errorContainer,
          scheme.onErrorContainer
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
