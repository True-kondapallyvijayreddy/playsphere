import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/memory.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../profile/widgets/memory_grid.dart';

/// Every photo and clip from every match of one season, in one place.
///
/// The capstone the rest of the season lifecycle builds toward: a season
/// owner or a player opens this once the tournament is done and finds the
/// whole thing in one book, next to the champions board and the
/// certificates — not scattered across however many matches it took to get
/// there.
///
/// Assembled from [Memory.tournamentId], stamped at upload time on whatever
/// match a photo was attached to (see `MemoryRepository.upload`). A memory
/// uploaded before that field existed simply is not in the book — the book
/// is a going-forward thing, not a backfill.
class SeasonMemoryBookScreen extends ConsumerWidget {
  const SeasonMemoryBookScreen({
    super.key,
    required this.orgId,
    required this.tournamentId,
  });

  final String orgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tKey = (orgId: orgId, tournamentId: tournamentId);
    final tAsync = ref.watch(tournamentProvider(tKey));
    final myUid = ref.watch(currentUidProvider);

    return AppScaffold(
      orgId: orgId,
      title: 'Season memories',
      body: AsyncView(
        value: tAsync,
        builder: (tournament) {
          if (tournament == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This tournament no longer exists',
            );
          }

          final memoriesAsync = ref.watch(tournamentMemoriesProvider(tKey));
          final memories = memoriesAsync.valueOrNull ?? const <Memory>[];

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 960,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      tournament.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      memories.isEmpty
                          ? 'Photos and clips from this season will collect '
                              'here as they are added to each match.'
                          : '${memories.length} moment'
                              '${memories.length == 1 ? '' : 's'} from this '
                              'season',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.push(
                          Routes.certificates(orgId, tournamentId),
                        ),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('View certificates'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AsyncErrorStrip(
                      value: memoriesAsync,
                      what: "this season's memories",
                    ),
                    MemoryGrid(
                      memories: memories,
                      loading: memoriesAsync.isLoading,
                      emptyMessage: 'Nothing yet — memories added to any '
                          "match in this season's events will show up here.",
                      onDelete: myUid == null
                          ? null
                          : (memory) async {
                              try {
                                await ref
                                    .read(memoryRepositoryProvider)
                                    .delete(memory);
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                    ),
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
