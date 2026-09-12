import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/club_thread.dart';
import '../../../core/models/tournament.dart';
import '../../../core/router/app_router.dart';
import '../club_network_providers.dart';

/// Picks something of the acting club's to pin to a message.
///
/// ## Why an attachment and not a pasted link
///
/// The thing a club owner is actually writing to another club about is almost
/// always a season: "we're running this, bring a team". Pasted as a URL that
/// is a line of grey text the recipient has to trust, open in a browser, and
/// sign in to. Pinned as an attachment it is a card with the season's name,
/// its sport and its dates, that opens the season inside the app in one tap —
/// and, because [ThreadShare] stores a copy, still says what was offered
/// months later when the season has been renamed or closed.
///
/// Returns null if the sheet is dismissed.
Future<ThreadShare?> showShareToClubSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<ThreadShare>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _ShareToClubSheet(),
  );
}

class _ShareToClubSheet extends ConsumerWidget {
  const _ShareToClubSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final club = ref.watch(actingClubProvider);
    final seasons = ref.watch(shareableSeasonsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text('Share with this club', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'They will see a card they can open in one tap.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),
          if (club != null)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(club.name),
                subtitle: const Text('Our club page'),
                onTap: () => Navigator.of(context).pop(
                  ThreadShare(
                    kind: ThreadShareKind.club,
                    orgId: club.id,
                    refId: club.id,
                    title: club.name,
                    subtitle: club.orgType.label,
                    route: Routes.org(club.id),
                  ),
                ),
              ),
            ),
          Text('Our seasons', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (seasons.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing published yet. A season has to be out of draft '
                'before it can be sent to another club — a club invited into '
                'a draft opens a page it cannot enter.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final season in seasons)
              _SeasonRow(
                season: season,
                onPick: () => Navigator.of(context).pop(_shareOf(season)),
              ),
        ],
      ),
    );
  }
}

ThreadShare _shareOf(Tournament season) => ThreadShare(
      kind: ThreadShareKind.season,
      orgId: season.orgId,
      refId: season.id,
      title: season.name,
      subtitle: [
        season.status.label,
        if (season.eventCount > 0)
          season.eventCount == 1 ? '1 event' : '${season.eventCount} events',
      ].join(' · '),
      startsAt: season.startDate,
      // The public, signed-out season page rather than the organizer's view:
      // the recipient is another club's owner, not a member of this one, and
      // the organizer route would refuse them.
      route: Routes.publicTournament(season.orgId, season.id),
    );

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({required this.season, required this.onPick});

  final Tournament season;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final start = season.startDate;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.emoji_events_outlined),
        title: Text(season.name),
        subtitle: Text(
          [
            season.status.label,
            if (start != null) DateFormat('d MMM yyyy').format(start),
            if (season.eventCount > 0) '${season.eventCount} events',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onPick,
      ),
    );
  }
}
