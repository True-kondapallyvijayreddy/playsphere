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
      floatingActionButton: !canCreate
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go(Routes.createCompetition(orgId)),
              icon: const Icon(Icons.add),
              label: const Text('New event'),
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
                          onTap: () => context.go(Routes.members(orgId)),
                        ),
                      ),

                    if (live.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const _LiveDot(),
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
                            onTap: () => context.go(
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
                                      .go(Routes.createCompetition(orgId)),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create an event'),
                                ),
                        ),
                      )
                    else
                      for (final c in comps)
                        _CompetitionTile(orgId: orgId, competition: c),
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
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
        trailing: _StatusChip(status: c.status),
        onTap: () => context.go(Routes.competition(orgId, c.id)),
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

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.35, end: 1.0)),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFDC2626),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
