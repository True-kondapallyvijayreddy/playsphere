/// Who on the team hears about what.
///
/// See `StaffMember`'s class doc for why this roster exists next to the
/// `admin` custom claim rather than instead of it. The short version, and the
/// reason this screen is not optional: a custom claim lives on an auth token,
/// Cloud Functions cannot enumerate accounts by claim, and so every "a
/// campaign was submitted" / "a donation arrived" notification in the product
/// had no recipient list at all. An empty roster is a product where inbound
/// work is only ever found by somebody deciding to go looking.
///
/// Adding is by PSOS player code rather than by email, and that is the same
/// decision `AddChildScreen` and the squad sheets already made: `playerCodes`
/// is the one lookup in this product designed to be resolvable by somebody
/// who cannot read the target's profile, so it works without opening up user
/// search or handing this screen the ability to read every account by address.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/platform_staff.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

class OpsTeamScreen extends ConsumerWidget {
  const OpsTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isPlatformAdminProvider);

    return AppScaffold(
      title: 'Ops team',
      subtitle: 'Who gets told when something arrives',
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AsyncErrorStrip(value: isAdmin, what: 'your access'),
        data: (admin) => admin
            ? const _Roster()
            : const EmptyState(
                icon: Icons.lock_outline,
                title: 'PlaySphere staff only',
                message: 'The operations roster is not public.',
              ),
      ),
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster();

  Future<void> _addSelf(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authUidProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(staffRepositoryProvider).upsert(
            StaffMember(
              uid: uid,
              displayName: me?.displayName ?? 'You',
              photoUrl: me?.photoUrl,
              // A person adding themselves is the owner setting the product
              // up, and they are on call for everything until they say
              // otherwise. Starting them on no desks would reproduce the
              // exact silence this roster exists to end.
              desks: StaffDesk.values,
            ),
            addedByUid: uid,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('You are on the roster')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(staffRosterProvider);
    final myUid = ref.watch(authUidProvider);

    return AsyncView(
      value: roster,
      onRetry: () => ref.invalidate(staffRosterProvider),
      builder: (members) {
        final onRoster = members.any((m) => m.uid == myUid);
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(
                      'A place on this list decides who is notified when an '
                      'advertiser submits a campaign, a donor hands over kit, '
                      'or a club raises a need. It grants no access on its '
                      'own — that is the staff role, and removing somebody '
                      'here does not remove theirs.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ),
                  if (!onRoster)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Card(
                        color: theme.colorScheme.tertiaryContainer,
                        child: ListTile(
                          leading: const Icon(Icons.person_add_alt),
                          title: const Text('Add yourself'),
                          subtitle: const Text(
                            'Start receiving everything that lands on these '
                            'queues.',
                          ),
                          trailing: FilledButton(
                            onPressed: () => _addSelf(context, ref),
                            child: const Text('Add me'),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: OutlinedButton.icon(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const _AddTeammateSheet(),
                      ),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Add a teammate by player code'),
                    ),
                  ),
                  if (members.isEmpty)
                    const EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: 'Nobody is on the roster',
                      message:
                          'Until somebody is here, every donation, need and '
                          'campaign lands silently and is only found by '
                          'opening the queue.',
                    )
                  else
                    for (final m in members)
                      _MemberCard(member: m, isMe: m.uid == myUid),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MemberCard extends ConsumerWidget {
  const _MemberCard({required this.member, required this.isMe});

  final StaffMember member;
  final bool isMe;

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    StaffDesk desk,
    bool on,
  ) async {
    final desks = member.desks.toList();
    if (on) {
      if (!desks.contains(desk)) desks.add(desk);
    } else {
      desks.remove(desk);
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(staffRepositoryProvider).setDesks(member.uid, desks);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: const Text(
          'They stop being notified about anything landing on these queues. '
          'Their staff access is a separate role and is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(staffRepositoryProvider).remove(member.uid);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PsAvatar(
                  name: member.displayName,
                  photoUrl: member.photoUrl,
                  seed: member.uid,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMe
                            ? '${member.displayName} (you)'
                            : member.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (member.playerCode != null)
                        Text(
                          member.playerCode!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove from roster',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () => _remove(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                for (final desk in StaffDesk.values)
                  FilterChip(
                    label: Text(desk.label),
                    selected: member.isOn(desk),
                    visualDensity: VisualDensity.compact,
                    onSelected: (on) => _toggle(context, ref, desk, on),
                  ),
              ],
            ),
            if (member.desks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'On no desks — they will not be notified about anything.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Resolving a PSOS code to the person it belongs to, then adding them.
///
/// Reuses `OrgRepository.findByPlayerCode` — the same lookup the squad sheets
/// and the guardian handoff use — rather than adding a second way to name a
/// person to this product.
class _AddTeammateSheet extends ConsumerStatefulWidget {
  const _AddTeammateSheet();

  @override
  ConsumerState<_AddTeammateSheet> createState() => _AddTeammateSheetState();
}

class _AddTeammateSheetState extends ConsumerState<_AddTeammateSheet> {
  final _code = TextEditingController();
  final _desks = <StaffDesk>{...StaffDesk.values};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final addedBy = ref.read(authUidProvider);
    if (addedBy == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found =
          await ref.read(userRepositoryProvider).findByPlayerCode(_code.text);
      if (found == null) {
        setState(() {
          _busy = false;
          _error = 'No player has that code. Codes look like PSOS-XXXXX.';
        });
        return;
      }
      await ref.read(staffRepositoryProvider).upsert(
            StaffMember(
              uid: found.uid,
              displayName: found.displayName,
              photoUrl: found.photoUrl,
              playerCode: found.code,
              desks: _desks.toList(),
            ),
            addedByUid: addedBy,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${found.displayName} added. They still need the staff role to '
            'open these queues.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a teammate',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Their PlaySphere player code — on their profile, under their '
            'name.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Player code',
              hintText: 'PSOS-4K7Q2',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _busy ? null : _add(),
          ),
          const SizedBox(height: 14),
          Text('Notify them about',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final desk in StaffDesk.values)
                FilterChip(
                  label: Text(desk.label),
                  selected: _desks.contains(desk),
                  onSelected: (on) => setState(
                    () => on ? _desks.add(desk) : _desks.remove(desk),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Adding somebody here does not give them access. That is the '
            'staff role, granted separately.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _add,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add to roster'),
          ),
        ],
      ),
    );
  }
}
