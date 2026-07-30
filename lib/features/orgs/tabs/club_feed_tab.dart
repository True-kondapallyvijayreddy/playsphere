import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/announcement.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/organization.dart';
import '../../../core/providers.dart';

class ClubFeedTab extends ConsumerWidget {
  const ClubFeedTab({
    super.key,
    required this.org,
    required this.currentUser,
  });

  final Organization org;
  final AppUser currentUser;

  void _showNewAnnouncementDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    var isPinned = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Post Club Announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notice Content',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Pin Announcement'),
                  value: isPinned,
                  onChanged: (v) {
                    if (v != null) setDialogState(() => isPinned = v);
                  },
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
                if (titleCtrl.text.trim().isEmpty) return;

                final announcement = Announcement(
                  id: '',
                  orgId: org.id,
                  authorUid: currentUser.uid,
                  authorName: currentUser.displayName,
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  isPinned: isPinned,
                );

                await ref
                    .read(communityRepositoryProvider)
                    .createAnnouncement(announcement);

                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Post Notice'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(communityRepositoryProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewAnnouncementDialog(context, ref),
        icon: const Icon(Icons.campaign),
        label: const Text('Post Notice'),
      ),
      body: StreamBuilder<List<Announcement>>(
        stream: repo.watchAnnouncements(org.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final announcements = snapshot.data ?? [];
          if (announcements.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.campaign_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No notices posted yet in ${org.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Post an announcement to notify club members.'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final a = announcements[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (a.isPinned) ...[
                            const Icon(Icons.push_pin, size: 18, color: Colors.amber),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              a.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(a.content),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Posted by ${a.authorName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (a.createdAt != null)
                            Text(
                              '${a.createdAt!.day}/${a.createdAt!.month}/${a.createdAt!.year}',
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
