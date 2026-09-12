import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/providers.dart';
import '../../data/career_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';
import 'widgets/auction_bid_sheet.dart';

/// One player on the block: their record, and the box you bid from.
///
/// ## Why the real career record is read here and nowhere else
///
/// `AuctionLot` carries a small snapshot of the player's record — matches,
/// wins, a stat line — copied at approval, and the pool list renders from
/// that. It has to: sixty players in a list cannot each open a listener on
/// somebody's career.
///
/// This screen is the one place somebody has actually chosen a player, so it
/// pays for the live read. `careerProvider` gives the same per-sport lines the
/// player's own profile shows, which is the difference between "3 sides are
/// bidding on him" and knowing whether that is justified. It is also why the
/// full profile is one tap further on rather than reproduced here — the
/// question being answered is "what is he worth", not "who is he".
class AuctionLotScreen extends ConsumerWidget {
  const AuctionLotScreen({
    super.key,
    required this.auctionId,
    required this.lotId,
  });

  final String auctionId;
  final String lotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auction = ref.watch(auctionProvider(auctionId)).valueOrNull;
    final lot = ref
        .watch(auctionLotProvider((auctionId: auctionId, lotId: lotId)))
        .valueOrNull;
    final myTeam = ref.watch(myAuctionTeamProvider(auctionId)).valueOrNull;
    final bids = ref
        .watch(auctionLotBidsProvider((auctionId: auctionId, lotId: lotId)))
        .valueOrNull ??
        const <AuctionBid>[];

    if (auction == null || lot == null) {
      return const AppScaffold(
        title: 'Player',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final myUid = ref.watch(currentUidProvider);
    final myBid = myTeam == null
        ? null
        : bids.where((b) => b.teamId == myTeam.id).firstOrNull;
    final now = DateTime.now();
    final canBidNow = myTeam != null && lot.isBiddable && auction.bidsOpenAt(now);

    return AppScaffold(
      title: lot.displayName,
      subtitle: lot.roleLabel ?? auction.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(lot: lot, auction: auction),
                const SizedBox(height: 12),

                if (lot.isSold) ...[
                  _SoldCard(lot: lot, mineUid: myUid),
                  const SizedBox(height: 12),
                ],

                // The bid box sits above the stats, not below them. Somebody
                // who already knows this player — which, in a village
                // auction, is almost everybody — should not scroll a career
                // history to reach the only control on the screen.
                if (myTeam != null) ...[
                  _BidBox(
                    auction: auction,
                    lot: lot,
                    team: myTeam,
                    myBid: myBid,
                    enabled: canBidNow,
                  ),
                  const SizedBox(height: 12),
                ],

                _CareerCard(lot: lot),
                const SizedBox(height: 12),

                _BidsCard(auction: auction, lot: lot, bids: bids, myUid: myUid),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lot, required this.auction});

  final AuctionLot lot;
  final Auction auction;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      child: Row(
        children: [
          PsCrest(
            name: lot.displayName,
            logoUrl: lot.photoUrl,
            seed: lot.playerUid,
            size: 56,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lot.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  lot.roleLabel,
                  lot.playerCode,
                  lot.status.label,
                ]),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'Base ${AuctionMoney.format(lot.basePricePaise)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Ps.muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          context.push(Routes.profile(lot.playerUid)),
                      child: const Text(
                        'Full profile',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoldCard extends StatelessWidget {
  const _SoldCard({required this.lot, required this.mineUid});

  final AuctionLot lot;
  final String? mineUid;

  @override
  Widget build(BuildContext context) {
    final mine = lot.soldToTeamId == mineUid;
    return PsCard(
      color: mine ? const Color(0xFFF0FDF4) : null,
      child: Row(
        children: [
          Icon(
            lot.acquiredBy == 'trade' ? Icons.swap_horiz : Icons.gavel,
            size: 20,
            color: Ps.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mine
                      ? 'In your squad'
                      : 'Playing for ${lot.soldToTeamName ?? 'another side'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  'Bought for ${AuctionMoney.format(lot.soldPricePaise ?? 0)}',
                  if (lot.soldInRound != null) 'Round ${lot.soldInRound}',
                  if (lot.acquiredBy == 'trade') 'Moved in a trade since',
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The live career record, per sport.
///
/// Falls back to the snapshot copied onto the lot when a player has no career
/// lines yet — a first-timer in a village auction genuinely has no record,
/// and an empty card would read as a loading failure rather than as the true
/// and rather important fact that nobody has seen this person play.
class _CareerCard extends ConsumerWidget {
  const _CareerCard({required this.lot});

  final AuctionLot lot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final career = ref.watch(careerProvider(lot.playerUid)).valueOrNull;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Record',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          if (career == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (career.isEmpty)
            Text(
              lot.matchesPlayed > 0
                  ? lot.summaryLine
                  : 'No matches on record. Nothing has been scored for this '
                      'player in PlaySphere yet — which is not the same as '
                      'never having played.',
              style: const TextStyle(
                fontSize: 13,
                color: Ps.muted,
                height: 1.4,
              ),
            )
          else
            // Most-played first, and only the top four. A bidder deciding on
            // a cricketer does not need his eighth sport, and four lines is
            // what fits above the fold beside the bid box.
            for (final line in ([...career]
                  ..sort((a, b) => b.prominence.compareTo(a.prominence)))
                .take(4))
              _CareerLineRow(line: line, playerUid: lot.playerUid),
        ],
      ),
    );
  }
}

/// What a bidder may do about this player right now, in words.
///
/// Every refusal states its reason. A greyed button with no sentence beside
/// it is the single most common way somebody concludes an app is broken, and
/// there are five genuinely different reasons a bid may be impossible here.
class _BidBox extends StatelessWidget {
  const _BidBox({
    required this.auction,
    required this.lot,
    required this.team,
    required this.myBid,
    required this.enabled,
  });

  final Auction auction;
  final AuctionLot lot;
  final AuctionTeam team;
  final AuctionBid? myBid;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reason = _blockedReason();

    return PsCard(
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
                      myBid == null
                          ? 'Your bid'
                          : 'You have bid '
                              '${AuctionMoney.format(myBid!.amountPaise)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AuctionMoney.format(team.availablePaise)} free of '
                      '${AuctionMoney.format(team.pursePaise)}',
                      style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (reason != null)
            Text(
              reason,
              style: const TextStyle(
                fontSize: 12.5,
                color: Ps.muted,
                height: 1.4,
              ),
            )
          else ...[
            PsPrimaryButton(
              label: myBid == null ? 'Place a bid' : 'Change your bid',
              onPressed: () => showAuctionBidSheet(
                context,
                auction: auction,
                lot: lot,
                team: team,
                existing: myBid,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nobody can see your bid until the reveal. You can change or '
              'withdraw it any time before then.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Ps.faint, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  String? _blockedReason() {
    if (enabled) return null;
    if (lot.status == AuctionLotStatus.withdrawn) {
      return 'This player has pulled out of the auction.';
    }
    if (lot.isSold) return 'This player has already been bought.';
    if (lot.status == AuctionLotStatus.unsold) {
      return 'Nobody bid on this player. They come back up if the organizer '
          'opens another round.';
    }
    return switch (auction.status) {
      AuctionStatus.draft ||
      AuctionStatus.registration =>
        'Bidding has not opened yet.',
      AuctionStatus.bidding =>
        'Bidding has closed. The lots open shortly.',
      AuctionStatus.revealed ||
      AuctionStatus.locked =>
        'The auction is over. Squads can only change by trade now.',
      AuctionStatus.cancelled => 'This auction was called off.',
    };
  }
}

/// The bids on this player.
///
/// Before the reveal this holds exactly one row — the reader's own — because
/// that is all the security rules will hand over. Afterwards it holds every
/// one of them, losing bids included. That transparency is deliberate and is
/// argued for in `AuctionBid`: a result nobody can check by hand is a result
/// the first person who feels cheated can destroy the league over.
class _BidsCard extends StatelessWidget {
  const _BidsCard({
    required this.auction,
    required this.lot,
    required this.bids,
    required this.myUid,
  });

  final Auction auction;
  final AuctionLot lot;
  final List<AuctionBid> bids;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final revealed = auction.status.isRevealed;
    final sorted = [...bids]
      ..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            revealed ? 'Every bid' : 'Bids',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            revealed
                ? 'Open for everybody to check, winners and losers alike.'
                : '${lot.bidCount} side${lot.bidCount == 1 ? '' : 's'} '
                    '${lot.bidCount == 1 ? 'has' : 'have'} bid. Amounts stay '
                    'sealed until the reveal — including yours, to everyone '
                    'else.',
            style: const TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
          ),
          if (sorted.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final bid in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (bid.isWinning)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.check_circle,
                            size: 16, color: Ps.primary),
                      ),
                    Expanded(
                      child: Text(
                        bid.teamId == myUid
                            ? '${bid.teamName} (you)'
                            : bid.teamName,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: bid.isWinning
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      AuctionMoney.format(bid.amountPaise),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One sport's line.
///
/// A rating id is not always a sport id — chess is rated per time control
/// (`chess:blitz`) — so the qualifier is split off to find the catalogue
/// entry and kept in the label, exactly as `MySportsScreen` does. Getting
/// this wrong renders "chess:blitz" as an unknown sport with a blank badge.
class _CareerLineRow extends StatelessWidget {
  const _CareerLineRow({required this.line, required this.playerUid});

  final CareerLine line;
  final String playerUid;

  @override
  Widget build(BuildContext context) {
    final baseId = line.sportId.split(':').first;
    final qualifier =
        line.sportId.contains(':') ? line.sportId.split(':').last : null;
    final sport = SportCatalog.byId(baseId);
    final rating = line.rating;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SportBadge(sportId: baseId, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  qualifier == null ? sport.name : '${sport.name} · $qualifier',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                PsMetaRow(items: [
                  '${line.matchesPlayed} '
                      '${line.matchesPlayed == 1 ? 'match' : 'matches'}',
                  if (rating != null)
                    '${rating.tier} · ${rating.rating.round()}',
                  if (line.stats?.lastPlayedAt != null)
                    'Last played ${_ago(line.stats!.lastPlayedAt!)}',
                ]),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () =>
                context.push(Routes.playerSport(playerUid, line.sportId)),
            child: const Text('Detail', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  /// Recency in the roughest terms that are still useful. A bidder wants to
  /// know whether this record is current or five years stale; the exact date
  /// is on the profile one tap away.
  static String _ago(DateTime t) {
    final days = DateTime.now().difference(t).inDays;
    if (days <= 0) return 'today';
    if (days < 30) return '${days}d ago';
    if (days < 365) return '${(days / 30).round()}mo ago';
    return '${(days / 365).round()}y ago';
  }
}
