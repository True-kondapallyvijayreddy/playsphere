import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/auction.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/ui_kit.dart';

/// A team owner's money, at the top of the auction screen.
///
/// ## Why three numbers and not one
///
/// "Balance" is the obvious single figure and it is the wrong one, because
/// during bidding there are genuinely two different balances and confusing
/// them is how somebody loses a player they thought they could afford:
///
///   * **Free** — what a new bid may still commit. Purse minus everything
///     locked behind live bids. This is the number that decides whether the
///     next bid goes through, so it leads.
///   * **Locked** — committed to bids that have not been resolved. It is not
///     gone; a losing bid gives it straight back at the reveal. Showing it as
///     "spent" would be a lie, and showing it not at all would leave the
///     purse looking mysteriously short.
///   * **Spent** — actually paid for players actually held.
///
/// After the reveal the first two collapse into each other — every live bid
/// has resolved — so the card drops to the two that still mean something.
class AuctionPurseCard extends ConsumerWidget {
  const AuctionPurseCard({
    super.key,
    required this.auction,
    required this.team,
  });

  final Auction auction;
  final AuctionTeam team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revealed = auction.status.isRevealed;
    final cap = auction.maxSquadSize;

    return PsCard(
      onTap: () => context.push(Routes.auctionTeam(auction.id, team.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your side · purse ${AuctionMoney.format(team.pursePaise)}',
                      style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Ps.faint),
            ],
          ),
          const SizedBox(height: 14),

          // The bar reads left to right as spent, then locked, then free —
          // the same order as the three figures below it, so the eye maps one
          // onto the other without a legend.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  Expanded(
                    flex: _flex(team.spentPaise, team.pursePaise),
                    child: Container(color: Ps.primary),
                  ),
                  if (!revealed)
                    Expanded(
                      flex: _flex(
                        team.committedPaise - team.spentPaise,
                        team.pursePaise,
                      ),
                      child: Container(color: const Color(0xFFF59E0B)),
                    ),
                  Expanded(
                    flex: _flex(
                      team.pursePaise -
                          (revealed ? team.spentPaise : team.committedPaise),
                      team.pursePaise,
                    ),
                    child: Container(color: Ps.border),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: revealed ? 'Left' : 'Free to bid',
                  value: AuctionMoney.format(
                    revealed ? team.remainingPaise : team.availablePaise,
                  ),
                  tint: Ps.ink,
                ),
              ),
              if (!revealed)
                Expanded(
                  child: _Figure(
                    label: 'Locked in ${team.liveBidCount} bid'
                        '${team.liveBidCount == 1 ? '' : 's'}',
                    value: AuctionMoney.format(team.committedPaise),
                    tint: const Color(0xFFB45309),
                  ),
                ),
              Expanded(
                child: _Figure(
                  label: 'Spent',
                  value: AuctionMoney.format(team.spentPaise),
                  tint: Ps.primary,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: cap == null ? 'Players' : 'Players (max $cap)',
                  value: '${team.wonCount}',
                  tint: Ps.ink,
                ),
              ),
            ],
          ),

          // The one thing a bidder cannot work out for themselves, and the one
          // that costs them a squad if they get it wrong.
          if (!revealed && team.liveBidCount > 0) ...[
            const SizedBox(height: 10),
            const Text(
              'Locked money comes back the moment a bid loses. Nothing is '
              'paid until the reveal.',
              style: TextStyle(fontSize: 11.5, color: Ps.faint, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  /// Flex weights for the bar. Scaled up so a small slice still renders as a
  /// sliver rather than rounding to zero flex and vanishing — a purse with
  /// ₹500 spent out of ₹1,00,000 should still show that something happened.
  int _flex(int part, int whole) {
    if (whole <= 0) return part > 0 ? 1000 : 0;
    final scaled = (part * 1000 / whole).round();
    if (part > 0 && scaled == 0) return 4;
    return scaled.clamp(0, 1000);
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: tint,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          maxLines: 2,
          style: const TextStyle(fontSize: 11, color: Ps.muted, height: 1.2),
        ),
      ],
    );
  }
}
