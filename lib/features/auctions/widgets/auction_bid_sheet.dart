import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/auction.dart';
import '../../../shared/ui_kit.dart';
import '../auction_providers.dart';

/// The box a bid is actually typed into.
///
/// ## Why the maximum is shown as a number and not only enforced
///
/// The server refuses a bid that would over-commit the purse, and it refuses
/// it with a sentence naming the exact figure that was free. That is the
/// backstop, not the interface. Somebody who has to discover their ceiling by
/// being rejected will bid under it out of caution for the rest of the
/// auction, which is the failure mode the committed-budget model is most
/// vulnerable to — a bidder who under-uses their purse and ends up with four
/// players and ₹60,000 they never spent.
///
/// So the ceiling is stated up front, the slider cannot exceed it, and the
/// quick amounts are computed from it rather than being round numbers that
/// might already be out of reach.
///
/// ## Why raising a bid warns about seniority
///
/// Changing the amount restarts the tie-break clock — see `AuctionBid`. It is
/// a small thing that almost never bites, and when it does it decides a
/// player, so it is said out loud rather than buried in a rule nobody reads.
void showAuctionBidSheet(
  BuildContext context, {
  required Auction auction,
  required AuctionLot lot,
  required AuctionTeam team,
  AuctionBid? existing,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _BidSheet(
        auction: auction,
        lot: lot,
        team: team,
        existing: existing,
      ),
    ),
  );
}

class _BidSheet extends ConsumerStatefulWidget {
  const _BidSheet({
    required this.auction,
    required this.lot,
    required this.team,
    this.existing,
  });

  final Auction auction;
  final AuctionLot lot;
  final AuctionTeam team;
  final AuctionBid? existing;

  @override
  ConsumerState<_BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends ConsumerState<_BidSheet> {
  late final TextEditingController _amount;
  bool _busy = false;
  String? _error;

  /// The most this side may commit to THIS player: everything not already
  /// locked behind other bids, plus whatever is currently locked behind this
  /// one — because raising an existing bid only has to fund the difference.
  int get _ceiling =>
      widget.team.availablePaise + (widget.existing?.amountPaise ?? 0);

  @override
  void initState() {
    super.initState();
    final start = widget.existing?.amountPaise ?? widget.lot.basePricePaise;
    _amount = TextEditingController(text: '${start ~/ 100}');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _typed => AuctionMoney.parseRupees(_amount.text);

  Future<void> _submit() async {
    final value = _typed;
    if (value == null) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    if (value < widget.lot.basePricePaise) {
      setState(() => _error =
          'The base price is ${AuctionMoney.format(widget.lot.basePricePaise)}.');
      return;
    }
    if (value > _ceiling) {
      setState(() => _error =
          'You only have ${AuctionMoney.format(_ceiling)} free for this player.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(auctionRepositoryProvider).placeBid(
            auctionId: widget.auction.id,
            lotId: widget.lot.id,
            amountPaise: value,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // The server's refusals are already written as sentences a bidder can
      // act on ("You have ₹40,000 free for this player"), so they go straight
      // on screen rather than being replaced with a generic failure.
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('ValidationException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      await ref.read(auctionRepositoryProvider).withdrawBid(
            auctionId: widget.auction.id,
            lotId: widget.lot.id,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('ValidationException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raising = widget.existing != null;
    final ceiling = _ceiling;

    // Quarter, half, three-quarters and everything, derived from the real
    // ceiling rather than from round numbers. A "₹50,000" button on a side
    // with ₹31,000 free is a button that can only fail.
    final quick = <int>{
      widget.lot.basePricePaise,
      if (ceiling > 0) (ceiling * 0.25).round(),
      if (ceiling > 0) (ceiling * 0.5).round(),
      if (ceiling > 0) (ceiling * 0.75).round(),
      if (ceiling > 0) ceiling,
    }.where((v) => v >= widget.lot.basePricePaise && v <= ceiling).toList()
      ..sort();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              raising ? 'Change your bid' : 'Bid for ${widget.lot.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Base ${AuctionMoney.format(widget.lot.basePricePaise)} · '
              'you can commit up to ${AuctionMoney.format(ceiling)}',
              style: const TextStyle(fontSize: 12.5, color: Ps.muted),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              autofocus: true,
              onChanged: (_) => setState(() => _error = null),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Ps.ink,
                ),
                errorText: _error,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in quick)
                  ActionChip(
                    label: Text(AuctionMoney.compact(v)),
                    onPressed: () => setState(() {
                      _amount.text = '${v ~/ 100}';
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            _AfterThisCard(
              team: widget.team,
              previous: widget.existing?.amountPaise ?? 0,
              proposed: _typed ?? 0,
            ),
            const SizedBox(height: 14),

            PsPrimaryButton(
              label: _busy
                  ? 'Sending…'
                  : (raising ? 'Update bid' : 'Place bid'),
              onPressed: _busy ? null : _submit,
            ),
            if (raising) ...[
              const SizedBox(height: 8),
              PsSecondaryButton(
                label: 'Withdraw this bid',
                icon: Icons.undo,
                onPressed: _busy ? null : _withdraw,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              raising
                  ? 'Changing the amount restarts your place in a tie. If two '
                      'sides end up level, the one who committed that figure '
                      'first takes the player.'
                  : 'This locks the money until the reveal. Nobody — not even '
                      'the organizer — can see what you bid until then.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                color: Ps.faint,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the purse looks like the second after this bid lands.
///
/// The single most useful thing on the sheet. A bidder's real question is
/// never "can I afford this player" — it is "can I still afford the other
/// three I want", and that is a subtraction they should not have to do in
/// their head while a deadline runs.
class _AfterThisCard extends StatelessWidget {
  const _AfterThisCard({
    required this.team,
    required this.previous,
    required this.proposed,
  });

  final AuctionTeam team;
  final int previous;
  final int proposed;

  @override
  Widget build(BuildContext context) {
    final nextCommitted = team.committedPaise - previous + proposed;
    final left = team.pursePaise - nextCommitted;
    final over = left < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: over ? const Color(0xFFFEF2F2) : Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: over ? Ps.live : Ps.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              over
                  ? 'That is more than you have.'
                  : 'Free for other players after this',
              style: TextStyle(
                fontSize: 12.5,
                color: over ? Ps.live : Ps.muted,
                fontWeight: over ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            AuctionMoney.format(left),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: over ? Ps.live : Ps.ink,
            ),
          ),
        ],
      ),
    );
  }
}
