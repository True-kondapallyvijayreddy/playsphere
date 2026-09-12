import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/auction.dart';
import '../../../core/providers.dart';
import '../../../shared/ui_kit.dart';
import '../auction_providers.dart';

/// "I'm in" — the RSVP, asked as two independent questions.
///
/// ## Why both boxes can be ticked
///
/// The obvious design is a two-way choice: are you a player, or do you own a
/// side? It is wrong for the actual users of this feature. In a village or
/// apartment-block auction the man putting up the money for a team very often
/// walks out and opens the batting for it, and forcing him to pick one would
/// mean either a captain who cannot be picked or a player who cannot bid.
///
/// So they are two checkboxes, not two radio buttons, and the whole system
/// carries that through — `AuctionParticipant.roles` is a set, a team's id is
/// its owner's uid, and a lot's id is the player's uid, so one person can hold
/// one of each without either colliding.
void showAuctionJoinSheet(BuildContext context, Auction auction) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _JoinSheet(auction: auction),
    ),
  );
}

class _JoinSheet extends ConsumerStatefulWidget {
  const _JoinSheet({required this.auction});

  final Auction auction;

  @override
  ConsumerState<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<_JoinSheet> {
  bool _asPlayer = true;
  bool _asOwner = false;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    final roles = <AuctionRole>{
      if (_asPlayer) AuctionRole.player,
      if (_asOwner) AuctionRole.bidder,
    };
    if (roles.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(auctionRepositoryProvider).join(
            auction: widget.auction,
            user: me,
            roles: roles,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.auction.name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tick whichever applies. You can be both.',
              style: TextStyle(fontSize: 12.5, color: Ps.muted),
            ),
            const SizedBox(height: 14),

            _RoleTile(
              icon: Icons.sports_cricket,
              title: 'I want to play',
              subtitle: 'You go into the pool. Sides bid to pick you up, and '
                  'they can see your match record while they decide.',
              value: _asPlayer,
              onChanged: (v) => setState(() => _asPlayer = v),
            ),
            const SizedBox(height: 8),
            _RoleTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'I want to own a side',
              subtitle: 'You get a purse of '
                  '${AuctionMoney.format(widget.auction.defaultPursePaise)} '
                  'to bid with. The organizer can change it.',
              value: _asOwner,
              onChanged: (v) => setState(() => _asOwner = v),
            ),

            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 2,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: 'Anything the organizer should know (optional)',
                hintText: 'I keep wicket · I can bring a full side',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                ),
              ),
            ),
            const SizedBox(height: 4),
            PsPrimaryButton(
              label: _busy ? 'Sending…' : 'Ask to join',
              onPressed:
                  (_busy || (!_asPlayer && !_asOwner)) ? null : _submit,
            ),
            const SizedBox(height: 8),
            const Text(
              'The organizer decides who gets in. You will be told either way.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Ps.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: value ? Ps.primary : Ps.border),
          // ignore: deprecated_member_use
          color: value ? Ps.primary.withOpacity(0.05) : null,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: value ? Ps.primary : Ps.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Ps.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
