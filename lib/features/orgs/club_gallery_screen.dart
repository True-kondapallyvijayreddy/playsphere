import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../profile/widgets/memory_grid.dart';

/// Everything the club has photographed, across every match it has played.
///
/// The flow puts a gallery inside a club alongside chat, announcements, polls
/// and files, and the pieces for it already existed — memories are uploaded
/// per match and a player's own timeline reads across them. What was missing
/// was the club's own view of them: a village club's ten years of Sunday
/// mornings, in one place, rather than scattered one match at a time behind
/// scorecards nobody navigates back to.
class ClubGalleryScreen extends ConsumerWidget {
  const ClubGalleryScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoriesAsync = ref.watch(clubMemoriesProvider(orgId));
    final memories = memoriesAsync.valueOrNull ?? const [];

    return AppScaffold(
      orgId: orgId,
      title: 'Gallery',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsyncErrorStrip(value: memoriesAsync, what: 'the gallery'),
                if (memories.isNotEmpty) ...[
                  Text(
                    '${memories.length} '
                    '${memories.length == 1 ? 'memory' : 'memories'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                MemoryGrid(
                  memories: memories,
                  loading: memoriesAsync.isLoading,
                  emptyMessage:
                      'Nothing here yet. Photos added to a match show up in '
                      'the club gallery automatically.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
