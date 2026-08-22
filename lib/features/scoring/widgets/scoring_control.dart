import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/models/organization.dart';
import '../../../core/permissions/capability.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Handing over exclusive scoring control — "the pen".
///
/// ## What this is for
///
/// `fixture.scorerUids` says who *may* score a match. That is a list, and it
/// is right that it is one: a club assigns two umpires to a final and both
/// need the right for the whole match. What a list cannot say is which of
/// them is scoring right now — and until something did, both of them had a
/// live pad. Both wrote authoritative events, both raced for the same
/// sequence numbers, and every race the second pad lost was a tap that
/// vanished. The scorer's experience of that is the score jumping backwards
/// under their thumb, and retrying cannot fix it, because neither write was
/// wrong.
///
/// So one person, on one device, holds the pen (`fixture.activeScorerUid`).
/// An owner or admin hands it over here. While it is held, nobody else can
/// score — the owner included, deliberately: an organizer who wants it back
/// takes it in a way that is recorded, rather than by quietly opening a
/// screen and overwriting the official standing at the ground. Every scoring
/// dispute is ultimately about that distinction.

/// Asks who should hold the pen, then hands it to them.
///
/// Returns the display name of the new holder, or null if nothing changed.
/// Candidates are drawn from `scorerUids` first — the people already assigned
/// to this match — then the rest of the club's active members, because the
/// commonest handover at a ground is to the umpire who was already named.
Future<String?> showHandOverPenSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Fixture fixture,
}) async {
  final myUid = ref.read(currentUidProvider);
  final members =
      ref.read(orgMembersProvider(fixture.orgId)).valueOrNull ?? const [];
  final candidates = <Membership>[
    for (final m in members)
      if (m.isActive && fixture.scorerUids.contains(m.uid)) m,
    for (final m in members)
      if (m.isActive && !fixture.scorerUids.contains(m.uid)) m,
  ]..removeWhere((m) => m.uid == fixture.activeScorerUid);

  if (candidates.isEmpty) {
    showError(context, 'This club has no other active members to score.');
    return null;
  }

  final picked = await showModalBottomSheet<Membership>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _HandOverSheet(
      candidates: candidates,
      assigned: fixture.scorerUids.toSet(),
    ),
  );
  if (picked == null || !context.mounted) return null;

  // The role check that used to be discovered on the scorer's first tap.
  //
  // `firestore.rules` wants a scoring role as well as a place on
  // `scorerUids`, so handing the pen to an ordinary member produced a
  // confirmation on the organizer's phone, the match in the member's list,
  // and a permission error on their first press with nothing on either
  // screen explaining it. Ask here, where the decision is being made.
  if (!PermissionMatrix.can(picked.role, Capability.scoreMatches)) {
    final canPromote = ref
        .read(myCapabilitiesProvider(fixture.orgId))
        .contains(Capability.manageMembers);
    if (!canPromote) {
      showError(
        context,
        '${picked.displayName} is a ${picked.role.label.toLowerCase()} of '
        'this club, so they cannot enter scores yet. A club admin can make '
        'them a Judge / Scorer.',
      );
      return null;
    }

    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Make ${picked.displayName} a scorer?'),
        content: Text(
          '${picked.displayName} is a ${picked.role.label.toLowerCase()} and '
          'cannot enter scores yet. Giving them the Judge / Scorer role lets '
          'them score the matches they are assigned to, and nothing else. '
          'You can take it back on the Members screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Give them the role'),
          ),
        ],
      ),
    );
    if (agreed != true || !context.mounted) return null;

    try {
      await ref.read(orgRepositoryProvider).changeRole(
            orgId: fixture.orgId,
            uid: picked.uid,
            role: MembershipRole.judgeScorer,
          );
    } catch (e) {
      if (context.mounted) showError(context, e);
      return null;
    }
  }

  try {
    await ref.read(umpireRepositoryProvider).grantPen(
          orgId: fixture.orgId,
          compId: fixture.compId,
          fixtureId: fixture.id,
          scorerUid: picked.uid,
          byUid: myUid ?? '',
        );
    return picked.displayName;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

/// Hands the pen to the person asking for it — the organizer taking it back.
///
/// Separate from [showHandOverPenSheet] because taking control of a match
/// somebody else is scoring is worth one sentence of confirmation. The
/// sentence names what actually happens, which is that the other person's pad
/// stops accepting taps: an organizer who does this while an umpire is mid-
/// match needs to know that before they tap, not after.
Future<bool> confirmTakeControl({
  required BuildContext context,
  required WidgetRef ref,
  required Fixture fixture,
  required String myUid,
  required String holderName,
}) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Take scoring control?'),
      content: Text(
        '$holderName is scoring this match. Taking control stops their pad '
        'from recording anything, and the score continues from where it '
        'stands — nothing already scored is lost. You can hand it back at '
        'any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Leave it with them'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Take control'),
        ),
      ],
    ),
  );
  if (agreed != true || !context.mounted) return false;

  try {
    await ref.read(umpireRepositoryProvider).grantPen(
          orgId: fixture.orgId,
          compId: fixture.compId,
          fixtureId: fixture.id,
          scorerUid: myUid,
          byUid: myUid,
        );
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

/// The holder's display name, resolved from their profile.
///
/// Not denormalized onto the fixture: a name copied beside a uid goes stale
/// the first time somebody changes how they are listed, and this is read on
/// screens that are already watching the profile anyway.
class PenHolderName extends ConsumerWidget {
  const PenHolderName({
    super.key,
    required this.uid,
    this.style,
    this.fallback = 'the assigned scorer',
  });

  final String uid;
  final TextStyle? style;
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(uid)).valueOrNull;
    return Text(profile?.displayName ?? fallback, style: style);
  }
}

class _HandOverSheet extends StatefulWidget {
  const _HandOverSheet({required this.candidates, required this.assigned});

  final List<Membership> candidates;
  final Set<String> assigned;

  @override
  State<_HandOverSheet> createState() => _HandOverSheetState();
}

class _HandOverSheetState extends State<_HandOverSheet> {
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
            const ListTile(
              leading: Icon(Icons.edit_note),
              title: Text('Who is scoring this match?'),
              subtitle: Text(
                'Only they can enter scores until you change it.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search members',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final m = shown[i];
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(m.displayName),
                    subtitle: Text(
                      widget.assigned.contains(m.uid)
                          ? 'Already assigned to this match'
                          : m.role.label,
                    ),
                    onTap: () => Navigator.pop(context, m),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
