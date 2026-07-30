import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import 'widgets/live_score_card.dart';

/// Everything happening right now in this organization, plus the matches the
/// signed-in user is personally assigned to score.
///
/// This is the screen a remote spectator lands on, and the one a volunteer
/// scorer opens when they arrive at the ground.
class LiveMatchesScreen extends ConsumerWidget {
  const LiveMatchesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveFixturesProvider(orgId));
    final mineAsync = ref.watch(myScoringAssignmentsProvider);
    final mine = mineAsync.valueOrNull ?? const [];
    final canScore =
        ref.watch(myCapabilitiesProvider(orgId)).contains(Capability.scoreMatches);

    final myHere = mine.where((f) => f.orgId == orgId).toList();

    return AppScaffold(
      orgId: orgId,
      title: 'Live now',
      body: AsyncView(
        value: live,
        builder: (fixtures) {
          // Guarded by `!hasError`: if the assignments query was rejected,
          // `myHere` is empty for the wrong reason, and telling a scorer that
          // nothing is being played would send them home from a live ground.
          if (fixtures.isEmpty && myHere.isEmpty && !mineAsync.hasError) {
            return const EmptyState(
              icon: Icons.sensors_off_outlined,
              title: 'Nothing is being played right now',
              message: 'When a scorer starts a match it will appear here '
                  'instantly, for everyone.',
            );
          }

          return ListView(
            children: [
              ContentBounds(
                maxWidth: 980,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AsyncErrorStrip(
                      value: mineAsync,
                      what: 'the matches you are scoring',
                    ),
                    if (canScore && myHere.isNotEmpty) ...[
                      Text(
                        'You are scoring',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to open the scoring pad.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      for (final f in myHere)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiveScoreCard(
                            fixture: f,
                            onTap: () => context.go(
                              Routes.scoring(orgId, f.compId, f.id),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                    if (fixtures.isNotEmpty) ...[
                      Text(
                        'Live matches',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      for (final f in fixtures)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiveScoreCard(
                            fixture: f,
                            onTap: () => context.go(
                              Routes.watch(orgId, f.compId, f.id),
                            ),
                          ),
                        ),
                    ],
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
