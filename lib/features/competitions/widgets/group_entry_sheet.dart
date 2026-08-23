import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/group_entry.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Proposing a group entry: name it, pick the people, send it to them.
///
/// Only active members of the club are offered. That is not merely a filter —
/// a named person has to ACCEPT before the group goes anywhere, and only a
/// member can make that write, so offering a non-member would produce a group
/// that could never complete. Showing only who can actually accept is the
/// honest version of the same rule.
class GroupEntrySheet extends ConsumerStatefulWidget {
  const GroupEntrySheet({super.key, required this.competition});

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => GroupEntrySheet(competition: competition),
      );

  @override
  ConsumerState<GroupEntrySheet> createState() => _GroupEntrySheetState();
}

class _GroupEntrySheetState extends ConsumerState<GroupEntrySheet> {
  final _name = TextEditingController();
  final _search = TextEditingController();

  /// uid → display name of everyone invited, not counting the leader.
  final Map<String, String> _picked = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    final c = widget.competition;

    try {
      await ref.read(competitionRepositoryProvider).createGroupEntry(
            orgId: c.orgId,
            compId: c.id,
            name: _name.text,
            leaderUid: me.uid,
            leaderName: me.displayName,
            members: _picked,
            competitionName: c.name,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent to ${_picked.length} '
            '${_picked.length == 1 ? 'person' : 'people'}. Once they all '
            'accept, the organizer decides.',
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
    final c = widget.competition;
    final myUid = ref.watch(currentUidProvider);
    final members =
        ref.watch(orgMembersProvider(c.orgId)).valueOrNull ?? const [];
    final query = _search.text.trim().toLowerCase();

    final candidates = members
        .where((m) => m.isActive && m.uid != myUid)
        .where((m) =>
            query.isEmpty || m.displayName.toLowerCase().contains(query))
        .take(50)
        .toList();

    final canSend =
        !_busy && _name.text.trim().isNotEmpty && _picked.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter as a group', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Everyone you pick has to accept, then the organizer approves '
                'the group as a whole. You are counted as part of it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                enabled: !_busy,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'Ravi\'s XI',
                  helperText: 'This is what appears on the scoreboard.',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _search,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search club members',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_picked.length + 1} in the group (including you)',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: candidates.isEmpty
                    ? const EmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'Nobody else to add',
                        message: 'A group can only contain members of this '
                            'club.',
                      )
                    : ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, i) {
                          final m = candidates[i];
                          final on = _picked.containsKey(m.uid);
                          return CheckboxListTile(
                            value: on,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      if (v == true) {
                                        _picked[m.uid] = m.displayName;
                                      } else {
                                        _picked.remove(m.uid);
                                      }
                                    }),
                            title: Text(m.displayName),
                            subtitle: Text(m.role.label),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: canSend ? _send : null,
                      child: Text(_busy ? 'Sending…' : 'Ask them'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The groups attached to one event, and whatever this person can do about
/// them.
///
/// Three audiences on one list, deliberately. A member sees the invitation
/// they owe an answer to; the leader sees who they are still waiting on; the
/// organizer sees the completed groups waiting on them. Splitting these into
/// separate screens is how an approval queue goes unvisited.
class GroupEntriesSection extends ConsumerWidget {
  const GroupEntriesSection({
    super.key,
    required this.competition,
    required this.canManage,
  });

  final Competition competition;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = competition;
    final myUid = ref.watch(currentUidProvider);
    final groups = ref
            .watch(groupEntriesProvider(CompRef(c.orgId, c.id)))
            .valueOrNull ??
        const <GroupEntry>[];

    // A settled group that nobody in it belongs to is noise on an event page.
    // Approved ones already appear in the entry list as their members.
    final worthShowing = groups.where((g) {
      if (!g.isSettled) return true;
      return myUid != null && g.memberUids.contains(myUid);
    }).toList();

    if (worthShowing.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Groups (${worthShowing.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final g in worthShowing)
              _GroupTile(
                competition: c,
                group: g,
                canManage: canManage,
                myUid: myUid,
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.competition,
    required this.group,
    required this.canManage,
    required this.myUid,
  });

  final Competition competition;
  final GroupEntry group;
  final bool canManage;
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final g = group;
    final repo = ref.read(competitionRepositoryProvider);
    final iOweAnAnswer = myUid != null && g.awaits(myUid!);
    final organizerMustDecide =
        canManage && g.status == GroupEntryStatus.pendingApproval;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(g.name, style: theme.textTheme.titleSmall),
              ),
              Chip(
                label: Text(g.status.label),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text(
            '${g.size} ${g.size == 1 ? 'player' : 'players'} · '
            '${g.acceptedUids.length} accepted'
            '${g.pendingUids.isEmpty ? '' : ' · waiting on ${g.pendingUids.length}'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final uid in g.memberUids)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    g.acceptedUids.contains(uid)
                        ? Icons.check_circle_outline
                        : g.declinedUids.contains(uid)
                            ? Icons.cancel_outlined
                            : Icons.schedule,
                    size: 16,
                  ),
                  label: Text(g.nameFor(uid)),
                ),
            ],
          ),
          if (iOweAnAnswer) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => run(() => repo.answerGroupInvite(
                        orgId: competition.orgId,
                        compId: competition.id,
                        groupId: g.id,
                        uid: myUid!,
                        accept: true,
                      )),
                  child: const Text('Count me in'),
                ),
                OutlinedButton(
                  onPressed: () => run(() => repo.answerGroupInvite(
                        orgId: competition.orgId,
                        compId: competition.id,
                        groupId: g.id,
                        uid: myUid!,
                        accept: false,
                      )),
                  child: const Text('No thanks'),
                ),
              ],
            ),
          ] else if (organizerMustDecide) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => run(() => repo.decideGroupEntry(
                        orgId: competition.orgId,
                        compId: competition.id,
                        groupId: g.id,
                        approve: true,
                        byUid: myUid ?? '',
                      )),
                  child: Text('Approve all ${g.size}'),
                ),
                OutlinedButton(
                  onPressed: () => run(() => repo.decideGroupEntry(
                        orgId: competition.orgId,
                        compId: competition.id,
                        groupId: g.id,
                        approve: false,
                        byUid: myUid ?? '',
                      )),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
