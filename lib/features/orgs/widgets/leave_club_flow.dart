import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/organization.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/governance/club_exit.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/identity.dart';

/// The one way out of a club, from wherever it is offered.
///
/// A member confirms and is gone. An owner who shares the club steps down on
/// the way out. The sole owner picks who takes the club over first — see
/// [ClubExit] for why they cannot just walk away.
Future<void> startLeaveClub(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
}) async {
  final repo = ref.read(orgRepositoryProvider);
  final Membership? me;
  final List<Membership> roster;
  try {
    me = await ref.read(myMembershipProvider(orgId).future);
    roster = await ref.read(orgMembersProvider(orgId).future);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (me == null || !context.mounted) return;
  final myUid = me.uid;

  final clubName =
      ref.read(organizationProvider(orgId)).valueOrNull?.name ?? 'this club';

  switch (ClubExit.pathFor(me: me, roster: roster)) {
    case ClubExitPath.leave:
      final ok = await _confirm(
        context,
        title: 'Leave $clubName?',
        message: 'You stop seeing its events, notices and files. Your matches '
            'stay on your record, and you can ask to join again later.',
        action: 'Leave',
      );
      if (!ok || !context.mounted) return;
      await _run(
          context, clubName, () => repo.leaveClub(orgId: orgId, uid: myUid));

    case ClubExitPath.stepDownAndLeave:
      final others = roster
          .where((m) =>
              m.isActive && m.role == MembershipRole.owner && m.uid != myUid)
          .map((m) => m.displayName)
          .toList();
      final ok = await _confirm(
        context,
        title: 'Leave $clubName?',
        message: 'You stop being an owner and leave the club. '
            '${_names(others)} ${others.length == 1 ? 'keeps' : 'keep'} '
            'running it. Your matches stay on your record.',
        action: 'Leave',
      );
      if (!ok || !context.mounted) return;
      await _run(
          context, clubName, () => repo.leaveClub(orgId: orgId, uid: myUid));

    case ClubExitPath.nobodyToHandTo:
      await _nobodyToHandTo(context, clubName);

    case ClubExitPath.handOverAndLeave:
      await _handOver(context, ref,
          orgId: orgId,
          clubName: clubName,
          me: me,
          roster: roster,
          soleOwner: true);
  }
}

/// An owner choosing who the club goes to, with the choice of staying on as
/// an admin or leaving. Offered on its own from the owner's menu — handing over
/// is not always leaving — and reached from [startLeaveClub] by a sole owner.
Future<void> startHandOverClub(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
}) async {
  final Membership? me;
  final List<Membership> roster;
  try {
    me = await ref.read(myMembershipProvider(orgId).future);
    roster = await ref.read(orgMembersProvider(orgId).future);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (me == null || me.role != MembershipRole.owner || !context.mounted) {
    return;
  }
  final clubName =
      ref.read(organizationProvider(orgId)).valueOrNull?.name ?? 'this club';

  final path = ClubExit.pathFor(me: me, roster: roster);
  if (path == ClubExitPath.nobodyToHandTo) {
    await _nobodyToHandTo(context, clubName);
    return;
  }
  if (ClubExit.successorsFor(me: me, roster: roster).isEmpty) {
    // Co-owners and nobody else. There is no one to promote, and the other
    // owners already hold the club.
    await _notice(
      context,
      title: 'Everyone else is already an owner',
      message: 'The other owners of $clubName already run it. Use Step down '
          'to become an admin, or Leave club to exit.',
    );
    return;
  }
  final soleOwner = path == ClubExitPath.handOverAndLeave;
  await _handOver(context, ref,
      orgId: orgId,
      clubName: clubName,
      me: me,
      roster: roster,
      soleOwner: soleOwner);
}

Future<void> _handOver(
  BuildContext context,
  WidgetRef ref, {
  required String orgId,
  required String clubName,
  required Membership me,
  required List<Membership> roster,
  required bool soleOwner,
}) async {
  final repo = ref.read(orgRepositoryProvider);
  final choice = await showModalBottomSheet<_HandOver>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _SuccessorSheet(
      clubName: clubName,
      soleOwner: soleOwner,
      candidates: ClubExit.successorsFor(me: me, roster: roster),
    ),
  );
  if (choice == null || !context.mounted) return;
  await _run(
    context,
    clubName,
    () => repo.handOverClub(
      orgId: orgId,
      fromUid: me.uid,
      toUid: choice.to.uid,
      stayAsAdmin: choice.stay,
    ),
    stayed: choice.stay,
    newOwner: choice.to.displayName,
  );
}

Future<void> _nobodyToHandTo(BuildContext context, String clubName) => _notice(
      context,
      title: 'Nobody to hand the club to',
      message: "You are $clubName's only member. A club needs an owner, so "
          'someone has to join before you can give it to them.',
    );

Future<void> _notice(
  BuildContext context, {
  required String title,
  required String message,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );

String _names(List<String> names) => switch (names.length) {
      0 => 'The other owners',
      1 => names.first,
      2 => '${names[0]} and ${names[1]}',
      _ => '${names[0]}, ${names[1]} and ${names.length - 2} more',
    };

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ==
    true;

Future<void> _run(
  BuildContext context,
  String clubName,
  Future<void> Function() write, {
  bool stayed = false,
  String? newOwner,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    await write();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  messenger.showSnackBar(SnackBar(
    content: Text(switch ((newOwner, stayed)) {
      (final String n, true) => '$n now owns $clubName. You are an admin.',
      (final String n, false) => '$n now owns $clubName. You have left.',
      _ => 'You have left $clubName.',
    }),
  ));
  // Staying as an admin keeps every club screen readable; leaving does not,
  // and the club selection moves on by itself once the membership is gone.
  if (!stayed) router.go(Routes.home);
}

class _HandOver {
  const _HandOver(this.to, this.stay);
  final Membership to;
  final bool stay;
}

/// Picking who takes the club over.
///
/// Searchable because a school club's roster runs to hundreds, and a list the
/// owner has to scroll to find the games teacher is a list they give up on.
class _SuccessorSheet extends StatefulWidget {
  const _SuccessorSheet({
    required this.clubName,
    required this.soleOwner,
    required this.candidates,
  });

  final String clubName;
  final bool soleOwner;
  final List<Membership> candidates;

  @override
  State<_SuccessorSheet> createState() => _SuccessorSheetState();
}

class _SuccessorSheetState extends State<_SuccessorSheet> {
  String _query = '';
  Membership? _picked;
  bool _stay = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((m) => m.displayName.toLowerCase().contains(q))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hand over ${widget.clubName}',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  widget.soleOwner
                      ? 'You are the only owner, so choose who takes the club '
                          'over. They get full control, including making other '
                          'owners.'
                      : 'Choose who becomes an owner in your place. They get '
                          'full control, including making other owners.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search members',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No member by that name.'))
                : ListView.builder(
                    controller: scroll,
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final m = shown[i];
                      final selected = _picked?.uid == m.uid;
                      return ListTile(
                        leading: PsAvatar(
                          name: m.displayName,
                          photoUrl: m.photoUrl,
                          seed: m.uid,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(m.role.label),
                        trailing: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected ? theme.colorScheme.primary : null,
                        ),
                        selected: selected,
                        onTap: () => setState(() => _picked = m),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          CheckboxListTile(
            value: _stay,
            onChanged: (v) => setState(() => _stay = v ?? false),
            title: const Text('Stay in the club as an admin'),
            subtitle: const Text('Leave this off to exit the club'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(
              onPressed: _picked == null ? null : _submit,
              child: Text(_picked == null
                  ? 'Choose the new owner'
                  : _stay
                      ? 'Make ${_picked!.displayName} owner'
                      : 'Make ${_picked!.displayName} owner and leave'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final to = _picked;
    if (to == null) return;
    final ok = await _confirm(
      context,
      title: 'Give ${widget.clubName} to ${to.displayName}?',
      message: _stay
          ? '${to.displayName} becomes the owner and you become an admin. '
              'Only an owner can make you an owner again.'
          : '${to.displayName} becomes the owner and you leave the club. '
              'You cannot undo this — only an owner can let you back in as one.',
      action: _stay ? 'Hand over' : 'Hand over and leave',
    );
    if (ok && mounted) Navigator.pop(context, _HandOver(to, _stay));
  }
}
