import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/auction.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/identity.dart';
import '../../../shared/ui_kit.dart';

/// One player in the pool list.
///
/// ## The one number this may show and the one it may not
///
/// It shows how many sides have a live bid — the heat — and never what any of
/// them is worth. That distinction is the whole sealed auction: a count comes
/// from `AuctionLot.bidCount`, which is on the lot document everybody can
/// read, while the amounts live one document deeper where only their own
/// bidder can reach them. So a pool can honestly say "3 sides want him",
/// which is most of what makes a sealed auction feel alive, without handing
/// anybody a figure to bid just over.
///
/// The caller's OWN bid is shown, because it is theirs and forgetting what
/// you committed is how you end up unable to bid on anybody else.
class AuctionLotTile extends ConsumerWidget {
  const AuctionLotTile({
    super.key,
    required this.auction,
    required this.lot,
    required this.canBid,
    this.myBid,
  });

  final Auction auction;
  final AuctionLot lot;
  final AuctionBid? myBid;

  /// Whether the person looking owns a side. Not whether they may bid right
  /// now — that also depends on the clock, and the tile defers that to the
  /// bid sheet so the reason for a refusal is given in words rather than by a
  /// greyed-out row with no explanation.
  final bool canBid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sold = lot.isSold;
    final withdrawn = lot.status == AuctionLotStatus.withdrawn;

    return Opacity(
      opacity: withdrawn ? 0.55 : 1,
      child: PsCard(
        onTap: () => context.push(Routes.auctionLot(auction.id, lot.id)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PsCrest(
              name: lot.displayName,
              logoUrl: lot.photoUrl,
              seed: lot.playerUid,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          lot.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                      if (lot.roleLabel != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            lot.roleLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Ps.muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lot.summaryLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                  const SizedBox(height: 6),
                  _StateLine(auction: auction, lot: lot, myBid: myBid),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sold)
                  Text(
                    AuctionMoney.compact(lot.soldPricePaise ?? 0),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Ps.primary,
                    ),
                  )
                else
                  Text(
                    'Base ${AuctionMoney.compact(lot.basePricePaise)}',
                    style: const TextStyle(fontSize: 12, color: Ps.faint),
                  ),
                const SizedBox(height: 4),
                if (lot.isBiddable && canBid)
                  Text(
                    myBid == null ? 'Bid' : 'Change',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Ps.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The line that says where this player stands, written differently for the
/// person who bid on them.
class _StateLine extends StatelessWidget {
  const _StateLine({
    required this.auction,
    required this.lot,
    required this.myBid,
  });

  final Auction auction;
  final AuctionLot lot;
  final AuctionBid? myBid;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (lot.isSold) {
      final mine = myBid != null && lot.soldToTeamId == myBid!.teamId;
      chips.add(_Chip(
        label: mine
            ? 'You won them'
            : 'Sold — ${lot.soldToTeamName ?? 'a side'}',
        tint: mine ? Ps.primary : Ps.ink,
      ));
      if (lot.acquiredBy == 'trade') {
        chips.add(const _Chip(label: 'Traded', tint: Color(0xFF7C3AED)));
      }
      if (lot.soldInRound != null && lot.soldInRound! > 1) {
        chips.add(_Chip(label: 'Round ${lot.soldInRound}', tint: Ps.muted));
      }
    } else if (lot.status == AuctionLotStatus.unsold) {
      chips.add(const _Chip(label: 'Nobody bid', tint: Ps.muted));
    } else if (lot.status == AuctionLotStatus.withdrawn) {
      chips.add(const _Chip(label: 'Withdrawn', tint: Ps.faint));
    } else if (lot.bidCount > 0) {
      // A COUNT, never an amount. See the class doc on AuctionLotTile.
      chips.add(_Chip(
        label: '${lot.bidCount} side${lot.bidCount == 1 ? '' : 's'} bidding',
        tint: const Color(0xFFB45309),
      ));
    } else if (auction.status.acceptsBids) {
      chips.add(const _Chip(label: 'No bids yet', tint: Ps.faint));
    }

    if (myBid != null && !lot.isSold) {
      chips.add(_Chip(
        label: 'You bid ${AuctionMoney.compact(myBid!.amountPaise)}',
        tint: const Color(0xFF2563EB),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: tint.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tint,
        ),
      ),
    );
  }
}
