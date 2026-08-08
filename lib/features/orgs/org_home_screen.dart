import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/live_dot.dart';
import '../home/event_feed.dart';
import '../scoring/widgets/live_score_card.dart';

class OrgHomeScreen extends ConsumerWidget {
  const OrgHomeScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(myCapabilitiesProvider(orgId));
    final canCreate = caps.contains(Capability.manageCompetitions);
    final competitions = ref.watch(competitionsProvider(orgId));
    final liveAsync = ref.watch(liveFixturesProvider(orgId));
    final pendingAsync = ref.watch(pendingMembersProvider(orgId));
    final live = liveAsync.valueOrNull ?? const [];
    final pending = pendingAsync.valueOrNull ?? const [];

    return AppScaffold(
      orgId: orgId,
      title: 'Home',
      // Two buttons, and the smaller one is the more used. Starting a match
      // between people who are already standing on the ground is the single
      // most common thing a club does; running a tournament is the rarer,
      // heavier act, so it keeps the labelled button and quick match takes the
      // one beside it.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'quick-match',
            tooltip: 'Quick match — play now',
            onPressed: () => context.push(Routes.quickMatch(orgId)),
            child: const Icon(Icons.sports_score),
          ),
          const SizedBox(height: 12),
          if (canCreate)
            FloatingActionButton.extended(
              heroTag: 'new-event',
              onPressed: () => context.push(Routes.createCompetition(orgId)),
              icon: const Icon(Icons.add),
              label: const Text('New event'),
            ),
        ],
      ),
      body: AsyncView(
        value: competitions,
        builder: (comps) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ContentBounds(
                maxWidth: 980,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AsyncErrorStrip(
                      value: liveAsync,
                      what: 'live matches',
                    ),
                    if (caps.contains(Capability.manageMembers))
                      AsyncErrorStrip(
                        value: pendingAsync,
                        what: 'join requests',
                      ),
                    if (pending.isNotEmpty &&
                        caps.contains(Capability.manageMembers))
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.person_add_alt),
                          title: Text(
                            '${pending.length} '
                            '${pending.length == 1 ? 'person is' : 'people are'} '
                            'waiting to join',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(Routes.members(orgId)),
                        ),
                      ),
                    if (live.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const LiveDot(),
                          const SizedBox(width: 8),
                          Text(
                            'Live now',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final f in live)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiveScoreCard(
                            fixture: f,
                            onTap: () => context.push(
                              Routes.watch(orgId, f.compId, f.id),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      'Events',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (comps.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'No events yet',
                          message: canCreate
                              ? 'Create your first competition — pick a sport, '
                                  'set the age category, and open entries.'
                              : 'Nothing has been scheduled here yet.',
                          action: !canCreate
                              ? null
                              : FilledButton.icon(
                                  onPressed: () => context
                                      .push(Routes.createCompetition(orgId)),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create an event'),
                                ),
                        ),
                      )
                    else
                      // A season's sports gather behind one card here instead
                      // of one each — see [groupEventFeed] — so a club that
                      // just ran through `CreateSeasonScreen` sees the season
                      // it created, not a wall of same-named sport rows.
                      for (final item in groupEventFeed(comps))
                        switch (item) {
                          EventFeedSingle(:final competition) =>
                            _CompetitionTile(
                              orgId: orgId,
                              competition: competition,
                            ),
                          EventFeedSeason(
                            :final tournamentId,
                            :final competitions
                          ) =>
                            SeasonCard(
                              orgId: orgId,
                              tournamentId: tournamentId,
                              competitions: competitions,
                              showOrg: false,
                            ),
                        },
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

class _CompetitionTile extends StatelessWidget {
  const _CompetitionTile({required this.orgId, required this.competition});

  final String orgId;
  final Competition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(
            _sportEmoji(c.sportId),
            style: const TextStyle(fontSize: 18),
          ),
        ),
        title: Text(c.name),
        subtitle: Text(
          [
            c.sportName,
            c.category.label,
            '${c.entrantCount} entered',
          ].join(' · '),
        ),
        trailing: _StatusChip(status: c.displayStatus()),
        onTap: () => context.push(Routes.competition(orgId, c.id)),
      ),
    );
  }

  static String _sportEmoji(String sportId) => switch (sportId) {
        'cricket' => '🏏',
        'badminton' => '🏸',
        'table_tennis' => '🏓',
        'volleyball' => '🏐',
        'football' => '⚽',
        'basketball' => '🏀',
        'kabaddi' => '🤼',
        'hockey' => '🏑',
        'chess' => '♟️',
        'tennis' => '🎾',
        _ => '🏅',
      };
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
      CompetitionStatus.completed => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
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
