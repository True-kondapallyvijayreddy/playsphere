import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/organization.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_context_banner.dart';
import '../../shared/identity.dart';

/// Who runs this club, and what each of them is responsible for.
///
/// ## Why this is its own screen and not the member list
///
/// The roster is a list of everybody, and in a school that is four hundred
/// rows. The people who actually run the club are five of them. An owner
/// asking "who can see our money?" should not have to scroll a roster to
/// find out, and the answer to that question is the single thing this screen
/// exists to show on its first paint.
///
/// It is also where the two halves of authority meet. A rank
/// ([MembershipRole]) says how much say somebody has; a portfolio
/// ([ClubPortfolio]) says which department they look after. Both are edited
/// in the same sheet because they are the same decision — "what is this
/// person's job here" — and splitting them across two screens is how a club
/// ends up with an admin nobody meant to give the bank details to.
class ClubStaffScreen extends ConsumerWidget {
  const ClubStaffScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(orgMembersProvider(orgId));
    final me = ref.watch(myMembershipProvider(orgId)).valueOrNull;
    final canManage =
        me != null && me.isActive && me.can(Capability.manageMembers);

    return AppScaffold(
      orgId: orgId,
      title: 'Staff & roles',
      body: AsyncView(
        value: members,
        builder: (all) {
          final active = all.where((m) => m.isActive).toList();
          // Anybody with a rank above plain member, or any department brief.
          final staff = active
              .where((m) =>
                  m.role != MembershipRole.member || m.portfolios.isNotEmpty)
              .toList()
            ..sort((a, b) {
              final byRank = b.role.rank.compareTo(a.role.rank);
              return byRank != 0 ? byRank : a.displayName.compareTo(b.displayName);
            });
          final rest = active
              .where((m) =>
                  m.role == MembershipRole.member && m.portfolios.isEmpty)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 820,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClubContextBanner(orgId: orgId, label: 'Managing'),
                    const _ExplainerCard(),
                    const SizedBox(height: 8),
                    _SectionTitle('Running the club (${staff.length})'),
                    if (staff.isEmpty)
                      const _EmptyHint(
                        'Only you, so far. Put somebody in charge of a '
                        'department below and they can get on with it '
                        'without asking you every time.',
                      ),
                    for (final m in staff)
                      _StaffTile(
                        orgId: orgId,
                        member: m,
                        actor: me,
                        canManage: canManage,
                      ),
                    if (canManage) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: FilledButton.tonalIcon(
                          onPressed: rest.isEmpty
                              ? null
                              : () => _addStaff(context, ref, rest),
                          icon: const Icon(Icons.person_add_alt),
                          label: Text(
                            rest.isEmpty
                                ? 'Everyone already has a job'
                                : 'Give someone a job',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _DepartmentLegend(members: staff),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addStaff(
    BuildContext context,
    WidgetRef ref,
    List<Membership> candidates,
  ) async {
    final picked = await showModalBottomSheet<Membership>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MemberPickerSheet(candidates: candidates),
    );
    if (picked == null || !context.mounted) return;
    await StaffRoleSheet.show(context, orgId: orgId, member: picked);
  }
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Two separate things', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'A role says how much say someone has — an admin runs the club, '
              'an event manager runs competitions but has no authority over '
              'people.\n\n'
              'A department says what they look after. Give the grounds to '
              'the person who opens the gate and the books to your treasurer, '
              'whatever their role. Owners look after every department '
              'automatically.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

/// One person who runs some part of the club.
class _StaffTile extends ConsumerWidget {
  const _StaffTile({
    required this.orgId,
    required this.member,
    required this.actor,
    required this.canManage,
  });

  final String orgId;
  final Membership member;
  final Membership? actor;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isSelf = member.uid == actor?.uid;
    final isOwner = member.role == MembershipRole.owner;

    // An owner's row is never edited here. Appointing and removing owners is
    // governance — it lives on the member list, where removal goes through the
    // two-thirds motion in `OwnershipActions` rather than a settings tap.
    final editable = canManage && !isSelf && !isOwner;

    final held = member.effectivePortfolios.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: editable
            ? () => StaffRoleSheet.show(context, orgId: orgId, member: member)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PsAvatar(
                name: member.displayName,
                photoUrl: member.photoUrl,
                seed: member.uid,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName + (isSelf ? ' (you)' : ''),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOwner
                          ? 'Owner · every department'
                          : member.role.label,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (!isOwner && held.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in held)
                            Chip(
                              label: Text(p.label),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (editable)
                const Icon(Icons.chevron_right)
              else if (isOwner)
                const Icon(Icons.shield_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every department and who currently has it — the answer to "so who is
/// looking after the ground?", without reading down a list of people and
/// assembling it in your head.
class _DepartmentLegend extends StatelessWidget {
  const _DepartmentLegend({required this.members});
  final List<Membership> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Departments'),
        for (final p in ClubPortfolio.values)
          Builder(
            builder: (context) {
              final holders = members
                  .where((m) => m.effectivePortfolios.contains(p))
                  .map((m) => m.displayName)
                  .toList();
              return ListTile(
                dense: true,
                title: Text(p.label, style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  holders.isEmpty
                      ? 'Nobody yet — ${p.blurb[0].toLowerCase()}'
                          '${p.blurb.substring(1)}'
                      : holders.join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: holders.isEmpty
                        ? theme.colorScheme.error
                        : theme.textTheme.bodySmall?.color,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Picks a member off the roster to give a job to.
class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.candidates});
  final List<Membership> candidates;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((m) => m.displayName.toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Who?', style: Theme.of(context).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search the roster',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final m = shown[i];
                  return ListTile(
                    leading: PsAvatar(
                      name: m.displayName,
                      photoUrl: m.photoUrl,
                      seed: m.uid,
                    ),
                    title: Text(m.displayName),
                    onTap: () => Navigator.pop(context, m),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one sheet where a person's job is decided: their rank, and the
/// departments they look after.
///
/// Both are shown against what the person *editing* may actually grant. A
/// choice that would be rejected by the security rules is disabled with the
/// reason next to it, rather than offered and then failing on save — the
/// rules are the authority either way, and being told "no" after tapping
/// teaches nothing about why.
class StaffRoleSheet extends ConsumerStatefulWidget {
  const StaffRoleSheet({
    super.key,
    required this.orgId,
    required this.member,
  });

  final String orgId;
  final Membership member;

  static Future<void> show(
    BuildContext context, {
    required String orgId,
    required Membership member,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => StaffRoleSheet(orgId: orgId, member: member),
      );

  @override
  ConsumerState<StaffRoleSheet> createState() => _StaffRoleSheetState();
}

class _StaffRoleSheetState extends ConsumerState<StaffRoleSheet> {
  late MembershipRole _role = widget.member.role;
  final Set<ClubPortfolio> _portfolios = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _portfolios.addAll(widget.member.portfolios);
  }

  bool get _dirty =>
      _role != widget.member.role ||
      !_setEquals(_portfolios, widget.member.portfolios);

  static bool _setEquals(Set<ClubPortfolio> a, Set<ClubPortfolio> b) =>
      a.length == b.length && a.every(b.contains);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = ref.watch(myMembershipProvider(widget.orgId)).valueOrNull;
    if (actor == null) return const SizedBox.shrink();

    final assignableRoles =
        PermissionMatrix.assignableBy(actor.role).toSet();
    final grantable = PermissionMatrix.portfoliosAssignableBy(
      actorRole: actor.role,
      actorPortfolios: actor.portfolios,
    );

    // Owners are handled on the member list, under the removal motion.
    final ownerLocked = widget.member.role == MembershipRole.owner;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              PsAvatar(
                name: widget.member.displayName,
                photoUrl: widget.member.photoUrl,
                seed: widget.member.uid,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.member.displayName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Role', style: theme.textTheme.titleSmall),
          Text(
            'How much say they have in the club itself.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final r in MembershipRole.values.reversed)
            if (r != MembershipRole.owner || ownerLocked)
              RadioListTile<MembershipRole>(
                value: r,
                groupValue: _role,
                dense: true,
                title: Text(r.label),
                subtitle: Text(_roleBlurb(r), style: theme.textTheme.bodySmall),
                onChanged: ownerLocked || !assignableRoles.contains(r)
                    ? null
                    : (v) => setState(() => _role = v!),
              ),
          if (ownerLocked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "An owner's role is not changed here. Owners are appointed and "
                'removed on the member list, where taking one out needs a vote '
                'of the other owners.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const Divider(height: 32),
          Text('Departments', style: theme.textTheme.titleSmall),
          Text(
            ownerLocked
                ? 'Owners look after every department. Nothing to choose.'
                : 'What they look after day to day. Independent of the role '
                    'above — a treasurer does not have to be an admin.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final p in ClubPortfolio.values)
            SwitchListTile(
              value: ownerLocked || _portfolios.contains(p),
              dense: true,
              title: Text(p.label),
              subtitle: Text(
                grantable.contains(p) || ownerLocked
                    ? p.blurb
                    : "You don't look after this yourself, so you can't hand "
                        'it on.',
                style: theme.textTheme.bodySmall,
              ),
              onChanged: ownerLocked || !grantable.contains(p)
                  ? null
                  : (on) => setState(() {
                        on ? _portfolios.add(p) : _portfolios.remove(p);
                      }),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || !_dirty || ownerLocked ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
          if (!ownerLocked &&
              (widget.member.role != MembershipRole.member ||
                  widget.member.portfolios.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: _saving ? null : _standDown,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Remove from all duties'),
              ),
            ),
        ],
      ),
    );
  }

  static String _roleBlurb(MembershipRole role) => switch (role) {
        MembershipRole.owner =>
          'Everything, including deleting the club or handing it on.',
        MembershipRole.admin =>
          'Runs the club: approves members, sets roles, runs events.',
        MembershipRole.eventManager =>
          'Runs competitions and entries. No authority over people.',
        MembershipRole.judgeScorer => 'Scores the matches they are assigned.',
        MembershipRole.member => 'Plays. No administrative access.',
      };

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(orgRepositoryProvider);
    try {
      if (_role != widget.member.role) {
        await repo.changeRole(
          orgId: widget.orgId,
          uid: widget.member.uid,
          role: _role,
        );
      }
      if (!_setEquals(_portfolios, widget.member.portfolios)) {
        await repo.setPortfolios(
          orgId: widget.orgId,
          uid: widget.member.uid,
          portfolios: _portfolios,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  Future<void> _standDown() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${widget.member.displayName} from all duties?'),
        content: const Text(
          'They stay in the club as an ordinary member and keep their playing '
          'history. Every role and department comes off in one go.',
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
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(orgRepositoryProvider).standDown(
            orgId: widget.orgId,
            uid: widget.member.uid,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }
}
