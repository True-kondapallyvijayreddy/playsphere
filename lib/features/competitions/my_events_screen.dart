import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/section_header.dart';
import '../home/event_feed.dart';
import '../home/home_providers.dart';
import '../home/home_screen.dart' show EventCard;

/// Every event and tournament across every club this person belongs to.
///
/// The home screen shows a short preview of this same list — open-for-entry
/// events only, capped at five — and stops there so one club's busy season
/// does not push clubs, live matches and everything else off the first
/// screen. This is where its "More" button sends you: the full list,
/// running or scheduled or still open, same as the club pages they came
/// from but gathered in one place across every club at once.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(myUpcomingEventsProvider);
    final events = eventsAsync.valueOrNull ?? const <Competition>[];
    // A season's sports gather behind one card here instead of one each — see
    // [groupEventFeed] — so this list reads as "your clubs' events" rather
    // than "your clubs' sports, five rows per season".
    final feed = groupEventFeed(events);
    final organizingOrgId = ref
        .watch(myActiveMembershipsProvider)
        .valueOrNull
        ?.map((m) => m.orgId)
        .where(
          (id) => ref
              .watch(myCapabilitiesProvider(id))
              .contains(Capability.manageCompetitions),
        )
        .firstOrNull;

    return AppScaffold(
      title: 'Events & tournaments',
      subtitle: events.isEmpty
          ? 'Nothing on right now'
          : '${feed.length} across your clubs',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ContentBounds(
            maxWidth: 980,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                AsyncErrorStrip(value: eventsAsync, what: 'events'),
                if (events.isEmpty)
                  QuietCard(
                    icon: Icons.calendar_month_outlined,
                    title: 'No events on right now',
                    // No message: the title already says the list is empty,
                    // and the organizer gets the button rather than a sentence
                    // describing the form behind it.
                    action: organizingOrgId == null
                        ? null
                        : FilledButton.icon(
                            onPressed: () => context.push(
                              Routes.createCompetition(organizingOrgId),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Create an event'),
                          ),
                  )
                else ...[
                  const SectionHeader(
                    icon: Icons.emoji_events_outlined,
                    title: 'Your clubs',
                  ),
                  for (final item in feed)
                    switch (item) {
                      EventFeedSingle(:final competition) =>
                        EventCard(competition: competition),
                      EventFeedSeason(
                        :final orgId,
                        :final tournamentId,
                        :final competitions
                      ) =>
                        SeasonCard(
                          orgId: orgId,
                          tournamentId: tournamentId,
                          competitions: competitions,
                        ),
                    },
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
