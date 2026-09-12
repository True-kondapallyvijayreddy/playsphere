import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/season_interest.dart';
import '../../../core/providers.dart';
import '../../../shared/identity.dart';
import '../../../shared/ui_kit.dart';

/// The block a member of an INVITED club sees on another club's season.
///
/// ## The rule it makes visible
///
/// An invitation is addressed to a club, so the entry is the club's to make
/// and its owner is the one who makes it. Every other member of that club
/// gets one button here — "I'm interested" — and no Register button anywhere
/// on the season. See [SeasonInterest] for why availability and entry are
/// two different things, and why letting four hundred members each enter a
/// host's draw individually produces a field nobody can draw.
///
/// ## Why the block exists at all rather than just hiding the button
///
/// A member who arrives from their home screen, finds the season their club
/// was invited to, and sees no way in has been told nothing — they cannot
/// tell "not for me" from "broken". So the block says all three things at
/// once: your club was invited, this is who decides, and this is the one
/// thing you can do about it.
///
/// Shown to nobody else. A member of the host club, a follower, a passer-by
/// on a public season: none of them are in an invited club and the ordinary
/// entry rules already answer them.
class InvitedClubBlock extends ConsumerWidget {
  const InvitedClubBlock({
    super.key,
    required this.hostOrgId,
    required this.tournamentId,
  });

  final String hostOrgId;
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(
      invitedSeasonContextProvider(
        (hostOrgId: hostOrgId, tournamentId: tournamentId),
      ),
    );
    if (ctx == null) return const SizedBox.shrink();

    final me = ref.watch(currentUserProvider).valueOrNull;
    final interest = ref
            .watch(seasonInterestProvider((
              orgId: ctx.orgId,
              hostOrgId: hostOrgId,
              tournamentId: tournamentId,
            )))
            .valueOrNull ??
        const <SeasonInterest>[];
    final mine = me == null
        ? null
        : interest.where((i) => i.uid == me.uid).firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PsCrest(
                  name: ctx.invite.toOrgName,
                  seed: ctx.orgId,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ctx.invite.isAccepted
                            ? '${ctx.invite.toOrgName} is playing this season'
                            : '${ctx.invite.toOrgName} has been invited',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The one sentence that stops a member hunting for a
                        // Register button that is deliberately not there.
                        ctx.canEnterForClub
                            ? 'You enter the club into these draws. Members '
                                'below have said they are available.'
                            : 'Your club enters as one side, so entries are '
                                "the club's to make. Put your hand up and "
                                'your organizers will see it.',
                        style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ctx.invite.message != null &&
                ctx.invite.message!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Ps.surface,
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                  border: Border.all(color: Ps.border),
                ),
                child: Text(
                  '"${ctx.invite.message!.trim()}"',
                  style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (!ctx.canEnterForClub)
              _InterestButton(
                orgId: ctx.orgId,
                hostOrgId: hostOrgId,
                tournamentId: tournamentId,
                tournamentName: ctx.invite.tournamentName,
                alreadyIn: mine != null,
              ),
            if (interest.isNotEmpty) ...[
              if (!ctx.canEnterForClub) const SizedBox(height: 14),
              Text(
                '${interest.length} available',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Ps.faint,
                ),
              ),
              const SizedBox(height: 8),
              // Everyone in the club sees the list, not only the organizers.
              // Knowing five teammates have already said yes is most of what
              // makes the sixth say it.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final i in interest)
                    Chip(
                      avatar: PsCrest(
                        name: i.displayName,
                        logoUrl: i.photoUrl,
                        seed: i.uid,
                        size: 20,
                      ),
                      label: Text(
                        i.displayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "I'm interested", and the way back out of it.
///
/// A toggle rather than a one-way button: availability is a statement about a
/// weekend that a person is allowed to change their mind about, and one that
/// cannot be withdrawn is one people stop making.
class _InterestButton extends ConsumerStatefulWidget {
  const _InterestButton({
    required this.orgId,
    required this.hostOrgId,
    required this.tournamentId,
    required this.tournamentName,
    required this.alreadyIn,
  });

  final String orgId;
  final String hostOrgId;
  final String tournamentId;
  final String tournamentName;
  final bool alreadyIn;

  @override
  ConsumerState<_InterestButton> createState() => _InterestButtonState();
}

class _InterestButtonState extends ConsumerState<_InterestButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    final repo = ref.read(tournamentRepositoryProvider);
    try {
      if (widget.alreadyIn) {
        await repo.clearSeasonInterest(
          orgId: widget.orgId,
          hostOrgId: widget.hostOrgId,
          tournamentId: widget.tournamentId,
          uid: me.uid,
        );
      } else {
        await repo.setSeasonInterest(
          SeasonInterest(
            id: SeasonInterest.idFor(
              hostOrgId: widget.hostOrgId,
              tournamentId: widget.tournamentId,
              uid: me.uid,
            ),
            orgId: widget.orgId,
            hostOrgId: widget.hostOrgId,
            tournamentId: widget.tournamentId,
            tournamentName: widget.tournamentName,
            uid: me.uid,
            displayName: me.displayName,
            photoUrl: me.photoUrl,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alreadyIn) {
      return OutlinedButton.icon(
        onPressed: _busy ? null : _toggle,
        icon: const Icon(Icons.check_circle, size: 18, color: Ps.primary),
        label: const Text("You're on the list — tap to withdraw"),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : _toggle,
      icon: const Icon(Icons.pan_tool_alt_outlined, size: 18),
      label: const Text("I'm interested"),
    );
  }
}
