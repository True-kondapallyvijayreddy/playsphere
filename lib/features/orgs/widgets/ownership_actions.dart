import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/organization.dart';
import '../../../core/models/owner_proposal.dart';
import '../../../core/providers.dart';
import '../../../domain/governance/owner_vote.dart';
import '../../../shared/app_scaffold.dart';

/// The controls on an owner's row in the member list.
///
/// Owners are not edited through the role dropdown that serves everybody else,
/// because the two directions are not symmetric. Appointing a co-owner is one
/// owner's decision and sits in the ordinary menu. Removing one is a motion
/// that needs two thirds of the other owners, and stepping down is nobody
/// else's business at all.
class OwnershipActions extends ConsumerWidget {
  const OwnershipActions({
    super.key,
    required this.orgId,
    required this.member,
    required this.isSelf,
  });

  final String orgId;
  final Membership member;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isSelf) {
      return TextButton(
        onPressed: () => _stepDown(context, ref),
        child: const Text('Step down'),
      );
    }

    final proposals =
        ref.watch(ownerProposalsProvider(orgId)).valueOrNull ?? const [];
    final owners = ref.watch(orgOwnersProvider(orgId)).valueOrNull ?? const [];
    final myUid = ref.watch(currentUidProvider);

    final motion = proposals
        .where((p) => p.targetUid == member.uid && p.isOpen)
        .firstOrNull;

    if (motion == null) {
      return TextButton(
        onPressed: () => _propose(context, ref),
        child: const Text('Propose removal'),
      );
    }

    final needed = OwnerVote.votesNeeded(owners.length);
    final have = motion.votes.length;
    final iHaveVoted = myUid != null && motion.hasVoted(myUid);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$have of $needed votes',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        if (motion.openedBy == myUid)
          TextButton(
            onPressed: () => ref
                .read(orgRepositoryProvider)
                .withdrawOwnerProposal(orgId: orgId, targetUid: member.uid),
            child: const Text('Withdraw'),
          )
        else if (!iHaveVoted)
          TextButton(
            onPressed: () => _vote(context, ref, motion),
            child: const Text('Agree'),
          )
        else
          const Text('You agreed'),
      ],
    );
  }

  Future<void> _stepDown(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Step down as owner?'),
        content: const Text(
          'You stay in the club as an admin — you can still run events and '
          'manage members. Only another owner can make you an owner again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay owner'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Step down'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref
          .read(orgRepositoryProvider)
          .resignOwnership(orgId: orgId, uid: uid);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _propose(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final owners = ref.read(orgOwnersProvider(orgId)).valueOrNull ?? const [];
    final needed = OwnerVote.votesNeeded(owners.length);

    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Propose removing ${member.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              needed <= 1
                  ? 'This club has two owners, so your vote alone carries it. '
                      'They can do the same to you.'
                  : 'Needs $needed of the ${owners.length - 1} other owners to '
                      'agree. Your vote counts as the first.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Why?',
                helperText: 'The other owners will read this.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Open motion'),
          ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;

    try {
      await ref.read(orgRepositoryProvider).proposeOwnerRemoval(
            orgId: orgId,
            targetUid: member.uid,
            targetName: member.displayName,
            reason: reason,
            byUid: uid,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _vote(
    BuildContext context,
    WidgetRef ref,
    OwnerProposal motion,
  ) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${motion.targetName} as owner?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reason given:'),
            const SizedBox(height: 4),
            Text(motion.reason),
            const SizedBox(height: 12),
            const Text(
              'They stay in the club as an admin. A vote cannot be taken back.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(orgRepositoryProvider).voteToRemoveOwner(
            orgId: orgId,
            targetUid: motion.targetUid,
            byUid: uid,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
