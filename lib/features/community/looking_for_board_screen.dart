import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_user.dart';
import '../../core/models/looking_for_post.dart';
import '../../core/providers.dart';

class LookingForBoardScreen extends ConsumerStatefulWidget {
  const LookingForBoardScreen({
    super.key,
    required this.user,
  });

  final AppUser user;

  @override
  ConsumerState<LookingForBoardScreen> createState() =>
      _LookingForBoardScreenState();
}

class _LookingForBoardScreenState
    extends ConsumerState<LookingForBoardScreen> {
  // Final for now because nothing writes it: the sport filter chips are not
  // built yet, so the board always shows every sport. Becomes mutable again
  // when the filter row lands.
  final String _selectedSport = 'all';

  void _showNewPostDialog(BuildContext context) {
    final descCtrl = TextEditingController();
    final districtCtrl = TextEditingController();
    final mandalCtrl = TextEditingController();
    var postType = 'player';
    var sportId = 'cricket';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Post on Looking-For Board'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: postType,
                  decoration: const InputDecoration(
                    labelText: 'What are you looking for?',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'player', child: Text('Looking for Player')),
                    DropdownMenuItem(value: 'team', child: Text('Looking for Team')),
                    DropdownMenuItem(value: 'umpire', child: Text('Looking for Umpire/Ref')),
                    DropdownMenuItem(value: 'scorer', child: Text('Looking for Scorer')),
                    DropdownMenuItem(value: 'ground', child: Text('Looking for Ground/Venue')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => postType = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: sportId,
                  decoration: const InputDecoration(
                    labelText: 'Sport',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cricket', child: Text('Cricket')),
                    DropdownMenuItem(value: 'football', child: Text('Football')),
                    DropdownMenuItem(value: 'kabaddi', child: Text('Kabaddi')),
                    DropdownMenuItem(value: 'volleyball', child: Text('Volleyball')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => sportId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: districtCtrl,
                  decoration: const InputDecoration(
                    labelText: 'District (e.g. Hyderabad / Warangal)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mandalCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mandal / Village',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (e.g. Need fast bowler for Sunday match)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (descCtrl.text.trim().isEmpty) return;

                final post = LookingForPost(
                  id: '',
                  authorUid: widget.user.uid,
                  authorName: widget.user.displayName,
                  type: postType,
                  sportId: sportId,
                  description: descCtrl.text.trim(),
                  district: districtCtrl.text.trim().isEmpty
                      ? null
                      : districtCtrl.text.trim(),
                  mandal: mandalCtrl.text.trim().isEmpty
                      ? null
                      : mandalCtrl.text.trim(),
                  contactPhone: widget.user.phone,
                );

                await ref
                    .read(communityRepositoryProvider)
                    .createLookingForPost(post);

                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Publish Post'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(communityRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community "Looking For" Board'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewPostDialog(context),
        icon: const Icon(Icons.post_add),
        label: const Text('Post Requirement'),
      ),
      body: StreamBuilder<List<LookingForPost>>(
        stream: repo.watchLookingForPosts(
          sportId: _selectedSport == 'all' ? null : _selectedSport,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final posts = snapshot.data ?? [];
          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No open requirements found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Post a requirement for players, umpires, or grounds.'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(
                            avatar: Icon(
                              switch (post.type) {
                                'umpire' => Icons.sports_score,
                                'scorer' => Icons.edit_note,
                                'ground' => Icons.stadium,
                                'team' => Icons.groups,
                                _ => Icons.person_search,
                              },
                              size: 16,
                            ),
                            label: Text(
                              'LOOKING FOR ${post.type.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(post.sportId.toUpperCase()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.description,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Posted by ${post.authorName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (post.district != null)
                            Text(
                              '📍 ${post.district}'
                              '${post.mandal != null ? ', ${post.mandal}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
