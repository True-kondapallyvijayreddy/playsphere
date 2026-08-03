import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/app_scaffold.dart';

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
    // Poll options as free text, one per line. A club admin adding "Ground A
    // / Ground B / Can't make it" should not have to tap Add Option three
    // times on a phone.
    final optionsCtrl = TextEditingController();
    var isPinned = false;
    var isPoll = false;

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
                CheckboxListTile(
                  title: const Text('Ask the club to choose'),
                  subtitle: const Text('Turns this into a poll'),
                  value: isPoll,
                  onChanged: (v) {
                    if (v != null) setDialogState(() => isPoll = v);
                  },
                ),
                if (isPoll) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: optionsCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Options, one per line',
                      hintText: 'Sunday 6am\nSunday 4pm\nCan\'t make it',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
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

                final options = optionsCtrl.text
                    .split('\n')
                    .map((o) => o.trim())
                    .where((o) => o.isNotEmpty)
                    .toList();
                // A poll with one answer is not a question. Falling back to a
                // plain announcement is kinder than refusing the post.
                final poll =
                    isPoll && options.length >= 2 ? Poll(options: options) : null;

                final announcement = Announcement(
                  id: '',
                  orgId: org.id,
                  authorUid: currentUser.uid,
                  authorName: currentUser.displayName,
                  title: titleCtrl.text.trim(),
                  content: contentCtrl.text.trim(),
                  isPinned: isPinned,
                  poll: poll,
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
                      if (a.content.isNotEmpty) Text(a.content),
                      if (a.isPoll) ...[
                        const SizedBox(height: 12),
                        _PollBody(orgId: org.id, announcement: a),
                      ],
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

/// A club poll, and the act of answering it.
///
/// Shows the tallies to everyone, always — not only after you have voted.
/// In a club, "who else is coming on Sunday" is usually the thing that decides
/// whether *you* come, and hiding it until you commit gets the order of that
/// decision backwards.
class _PollBody extends ConsumerWidget {
  const _PollBody({required this.orgId, required this.announcement});

  final String orgId;
  final Announcement announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poll = announcement.poll!;
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final myVote = uid == null ? null : poll.voteOf(uid);
    final canVote = uid != null && !poll.closed;

    Future<void> vote(int index) async {
      if (uid == null) return;
      try {
        await ref.read(communityRepositoryProvider).voteInPoll(
              orgId: orgId,
              announcementId: announcement.id,
              uid: uid,
              // Tapping your own answer again takes it back.
              optionIndex: myVote == index ? null : index,
            );
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < poll.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: canVote ? () => vote(i) : null,
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  // The bar is behind the label rather than beside it, so a
                  // long option ("Ground behind the school") is not squeezed
                  // into whatever space a chart left over.
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: poll.shareFor(i).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: myVote == i
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          myVote == i
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 18,
                          color: myVote == i
                              ? theme.colorScheme.primary
                              : theme.hintColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(poll.options[i])),
                        Text(
                          '${poll.countFor(i)}',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        Text(
          poll.closed
              ? '${poll.totalVotes} votes · closed'
              : poll.totalVotes == 0
                  ? 'No votes yet'
                  : '${poll.totalVotes} votes · tap to change yours',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}
