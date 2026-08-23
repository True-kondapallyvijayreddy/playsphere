import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/group_entry.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// "Rahul has put you in Hyderabad CC A" — answered from here.
///
/// ## Why this needed a card of its own
///
/// A group entry has always required every named member to accept before it
/// reaches an organizer, and nothing ever asked them. The invitation lived on
/// the event's own page — a page somebody who has not entered has no reason to
/// open — so the honest description of the flow was that a leader named five
/// people and then messaged them on WhatsApp to go and find it.
///
/// The answer is a yes or a no about a Saturday, taken by someone who is
/// usually not sitting down with the app open. So it is answered in place: two
/// buttons on the row, no screen in between.
///
/// ## Why declining is heavier than accepting
///
/// One decline ends the group for everybody — that is the rule the repository
/// enforces, and it is the right rule, because the alternative is four people
/// waiting indefinitely on a fifth who has already decided. It does mean "No"
/// is not a personal answer but a decision about other people's weekend, which
/// is worth one confirmation.
class SquadInviteCard extends ConsumerStatefulWidget {
  const SquadInviteCard({super.key, required this.group});

  final GroupEntry group;

  @override
  ConsumerState<SquadInviteCard> createState() => _SquadInviteCardState();
}

class _SquadInviteCardState extends ConsumerState<SquadInviteCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final g = widget.group;

    if (!accept) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Say no to ${g.name}?'),
          content: Text(
            'One "no" ends the whole entry — ${g.size - 1} other '
            '${g.size - 1 == 1 ? 'person' : 'people'} would have to be asked '
            'again as a new group.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Say no'),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(competitionRepositoryProvider).answerGroupInvite(
            orgId: g.orgId,
            compId: g.compId,
            groupId: g.id,
            uid: uid,
            accept: accept,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'You are in ${g.name}.'
                : 'You are out. ${g.leaderName} has been told.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.group;
    final waiting = g.pendingUids.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.groups_2_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    g.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              // Who asked, and what for. Both are needed: a name with no event
              // is an invitation to nothing in particular, and an event with
              // no name behind it reads as an automated message.
              '${g.leaderName} put you in this squad'
              '${g.competitionName.isEmpty ? '' : ' for ${g.competitionName}'}'
              ' · ${g.size} in the squad',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final uid in g.memberUids)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: g.acceptedUids.contains(uid)
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    avatar: Icon(
                      g.acceptedUids.contains(uid)
                          ? Icons.check
                          : Icons.schedule,
                      size: 14,
                    ),
                    label: Text(g.nameFor(uid)),
                    labelStyle: theme.textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              waiting == 1
                  ? 'Waiting on you alone.'
                  : 'Waiting on $waiting of them, including you.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _answer(false),
                  child: const Text('No'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _busy ? null : () => _answer(true),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("I'm in"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
