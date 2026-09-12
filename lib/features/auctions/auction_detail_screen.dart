import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';
import 'widgets/auction_join_sheet.dart';
import 'widgets/auction_lot_tile.dart';
import 'widgets/auction_organizer_bar.dart';
import 'widgets/auction_purse_card.dart';

/// One auction, for whoever is looking at it.
///
/// ## Why this is one screen and not four
///
/// An organizer, a team owner, a player in the pool and a passer-by want
/// substantially different things from an auction, and the obvious design is
/// four screens behind a role check. That was rejected for the reason the
/// More menu's doc comment gives about four menus: the same auction under
/// four different shapes means a person who saw something once cannot
/// reliably find it again — and here it is worse, because the common case is
/// ONE PERSON HOLDING TWO ROLES. The man who organizes the village auction
/// almost always owns a side in it too.
///
/// So: one screen, one layout, and the parts that only apply to a role appear
/// or do not. The organizer's controls are a bar at the top; the bidder's
/// purse is a card under it; the pool is the same list for everybody, with a
/// bid box on it only for somebody who has a purse to bid from.
class AuctionDetailScreen extends ConsumerStatefulWidget {
  const AuctionDetailScreen({super.key, required this.auctionId});

  final String auctionId;

  @override
  ConsumerState<AuctionDetailScreen> createState() =>
      _AuctionDetailScreenState();
}

enum _Tab { pool, sides, mine }

class _AuctionDetailScreenState extends ConsumerState<AuctionDetailScreen> {
  _Tab _tab = _Tab.pool;

  @override
  Widget build(BuildContext context) {
    final auctionAsync = ref.watch(auctionProvider(widget.auctionId));
    final auction = auctionAsync.valueOrNull;

    if (auctionAsync.isLoading && auction == null) {
      return const AppScaffold(
        title: 'Auction',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (auction == null) {
      // Covers two cases that look the same from here and should: the
      // auction was deleted, and it is unlisted and this person is not in it.
      // Telling an outsider which of the two it is would leak the existence
      // of every private auction to anybody who guesses an id.
      return const AppScaffold(
        title: 'Auction',
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This auction is not available. If it is a private one, ask the '
              'organizer for the code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Ps.muted),
            ),
          ),
        ),
      );
    }

    final me = ref.watch(myAuctionPlaceProvider(widget.auctionId)).valueOrNull;
    final myTeam = ref.watch(myAuctionTeamProvider(widget.auctionId)).valueOrNull;
    final isOrganizer = me?.isOrganizer == true && me?.isApproved == true;
    final now = DateTime.now();

    return AppScaffold(
      title: auction.name,
      subtitle: auction.headline(now),
      actions: [
        IconButton(
          tooltip: 'Share the code',
          icon: const Icon(Icons.ios_share),
          onPressed: () => _showCode(context, auction),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusBanner(auction: auction, now: now),
                const SizedBox(height: 12),

                if (isOrganizer) ...[
                  AuctionOrganizerBar(auction: auction),
                  const SizedBox(height: 12),
                ],

                // The purse. The single most-looked-at thing on the screen for
                // somebody who has one, so it sits above the pool rather than
                // on a tab they would have to leave the pool to check.
                if (myTeam != null) ...[
                  AuctionPurseCard(auction: auction, team: myTeam),
                  const SizedBox(height: 12),
                ],

                _JoinBlock(auction: auction, me: me),

                _QuickLinks(
                  auction: auction,
                  isOrganizer: isOrganizer,
                  hasTeam: myTeam != null,
                ),
                const SizedBox(height: 16),

                PsUnderlineTabs(
                  labels: const ['Players', 'Sides', 'My bids'],
                  selected: _tab.index,
                  onSelected: (i) => setState(() => _tab = _Tab.values[i]),
                ),
                const SizedBox(height: 12),

                switch (_tab) {
                  _Tab.pool => _PoolList(auction: auction, canBid: myTeam != null),
                  _Tab.sides => _SidesList(auction: auction),
                  _Tab.mine => _MyBidsList(auction: auction, hasTeam: myTeam != null),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCode(BuildContext context, Auction auction) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Anyone with this code can find the auction',
              style: TextStyle(fontSize: 13.5, color: Ps.muted),
            ),
            const SizedBox(height: 14),
            SelectableText(
              auction.joinCode,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 16),
            PsSecondaryButton(
              label: 'Copy',
              icon: Icons.copy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: auction.joinCode));
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The one-line state of play, with the countdown that matters right now.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.auction, required this.now});

  final Auction auction;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (Color tint, IconData icon) = switch (auction.status) {
      AuctionStatus.draft => (Ps.faint, Icons.edit_note),
      AuctionStatus.registration => (const Color(0xFF2563EB), Icons.how_to_reg),
      AuctionStatus.bidding => (const Color(0xFFB45309), Icons.gavel),
      AuctionStatus.revealed => (Ps.primary, Icons.check_circle_outline),
      AuctionStatus.locked => (Ps.ink, Icons.lock_outline),
      AuctionStatus.cancelled => (Ps.live, Icons.cancel_outlined),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(Ps.radius),
        // ignore: deprecated_member_use
        border: Border.all(color: tint.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  auction.headline(now),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  auction.sportName,
                  auction.locationLabel,
                  if (auction.round > 1) 'Round ${auction.round}',
                  '${auction.playerCount} players',
                  '${auction.teamCount} sides',
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The way in, for somebody who is not in yet or is still waiting.
///
/// Absent entirely for an approved participant — a person who is already in
/// should not carry a card telling them how to get in for the rest of the
/// auction's life.
class _JoinBlock extends ConsumerWidget {
  const _JoinBlock({required this.auction, required this.me});

  final Auction auction;
  final AuctionParticipant? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = me;

    if (place != null && place.isApproved) return const SizedBox.shrink();

    if (place != null && place.status == AuctionJoinStatus.pending) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PsCard(
          color: const Color(0xFFFFFBEB),
          child: Row(
            children: [
              const Icon(Icons.hourglass_empty,
                  size: 18, color: Color(0xFFB45309)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You asked to join as ${place.rolesLabel.toLowerCase()}. '
                  'Waiting for the organizer.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(auctionRepositoryProvider)
                    .withdrawJoinRequest(auction.id, place.uid),
                child: const Text('Withdraw'),
              ),
            ],
          ),
        ),
      );
    }

    if (place != null && place.status == AuctionJoinStatus.declined) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: PsCard(
          child: Text(
            'You were not taken on for this auction.',
            style: TextStyle(fontSize: 13, color: Ps.muted),
          ),
        ),
      );
    }

    if (!auction.isOpenForJoining) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PsCard(
          child: Text(
            auction.status == AuctionStatus.draft
                ? 'This auction has not opened for joining yet.'
                : 'Joining has closed for this auction.',
            style: const TextStyle(fontSize: 13, color: Ps.muted),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Take part',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            const SizedBox(height: 4),
            const Text(
              'Put your hand up to play, to own a side, or both. The '
              'organizer approves who gets in.',
              style: TextStyle(fontSize: 12.5, color: Ps.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            PsPrimaryButton(
              label: "I'm in",
              onPressed: () => showAuctionJoinSheet(context, auction),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four destinations that do not fit on this screen.
class _QuickLinks extends ConsumerWidget {
  const _QuickLinks({
    required this.auction,
    required this.isOrganizer,
    required this.hasTeam,
  });

  final Auction auction;
  final bool isOrganizer;
  final bool hasTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waitingJoins =
        ref.watch(pendingAuctionJoinCountProvider(auction.id));
    final waitingTrades =
        ref.watch(pendingAuctionTradeCountProvider(auction.id));

    return Row(
      children: [
        Expanded(
          child: _LinkTile(
            icon: Icons.group_outlined,
            label: 'People',
            badge: waitingJoins,
            onTap: () => context.push(Routes.auctionPeople(auction.id)),
          ),
        ),
        const SizedBox(width: 8),
        if (hasTeam || auction.status.isRevealed)
          Expanded(
            child: _LinkTile(
              icon: Icons.swap_horiz,
              label: 'Trades',
              badge: waitingTrades,
              // Greyed rather than hidden once the window shuts: a person who
              // used it yesterday should find the record, not an absence.
              enabled: auction.status.isRevealed,
              onTap: () => context.push(Routes.auctionTrades(auction.id)),
            ),
          ),
        if (isOrganizer) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _LinkTile(
              icon: Icons.tune,
              label: 'Settings',
              onTap: () => context.push(Routes.auctionSettings(auction.id)),
            ),
          ),
        ],
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: enabled ? onTap : null,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 22, color: enabled ? Ps.ink : Ps.faint),
              if (badge > 0)
                Positioned(
                  right: -8,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Ps.live,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: enabled ? Ps.ink : Ps.faint,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pool, sold players last.
///
/// Sorted rather than filtered: a sold player is the most interesting row on
/// the screen the day after a reveal, and hiding them would make the list
/// shrink every round with nothing to show for it.
class _PoolList extends ConsumerWidget {
  const _PoolList({required this.auction, required this.canBid});

  final Auction auction;
  final bool canBid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lots = ref.watch(auctionLotsProvider(auction.id)).valueOrNull;
    final myBids =
        ref.watch(myAuctionBidsProvider(auction.id)).valueOrNull ?? const {};

    if (lots == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (lots.isEmpty) {
      return const _EmptyNote(
        'No players in the pool yet. They appear here as the organizer '
        'approves them.',
      );
    }

    final sorted = [...lots]..sort((a, b) {
        int rank(AuctionLot l) => switch (l.status) {
              AuctionLotStatus.pool => 0,
              AuctionLotStatus.sold => 1,
              AuctionLotStatus.unsold => 2,
              AuctionLotStatus.withdrawn => 3,
            };
        final byStatus = rank(a).compareTo(rank(b));
        if (byStatus != 0) return byStatus;
        // Inside the pool, the most contested first — it is the closest thing
        // a sealed auction has to a live one's excitement, and it is the only
        // signal available without leaking an amount.
        final byHeat = b.bidCount.compareTo(a.bidCount);
        if (byHeat != 0) return byHeat;
        return a.displayName.compareTo(b.displayName);
      });

    return Column(
      children: [
        for (final lot in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AuctionLotTile(
              auction: auction,
              lot: lot,
              myBid: myBids[lot.id],
              canBid: canBid,
            ),
          ),
      ],
    );
  }
}

class _SidesList extends ConsumerWidget {
  const _SidesList({required this.auction});

  final Auction auction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(auctionTeamsProvider(auction.id)).valueOrNull;
    if (teams == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (teams.isEmpty) {
      return const _EmptyNote(
        'No sides yet. A side appears when the organizer approves a team '
        'owner.',
      );
    }

    final sorted = [...teams]
      ..sort((a, b) => b.wonCount.compareTo(a.wonCount));

    return Column(
      children: [
        for (final t in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PsCard(
              onTap: () => context.push(Routes.auctionTeam(auction.id, t.id)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        PsMetaRow(items: [
                          t.ownerName,
                          '${t.wonCount} player${t.wonCount == 1 ? '' : 's'}',
                          // Before the reveal this is what is LOCKED, which is
                          // not the same number as what has been paid — and
                          // saying "spent" before anything is bought would be
                          // a lie the whole screen depends on not telling.
                          auction.status.isRevealed
                              ? '${AuctionMoney.compact(t.spentPaise)} spent'
                              : '${AuctionMoney.compact(t.availablePaise)} free',
                        ]),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Ps.faint),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything this person has money riding on.
class _MyBidsList extends ConsumerWidget {
  const _MyBidsList({required this.auction, required this.hasTeam});

  final Auction auction;
  final bool hasTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasTeam) {
      return const _EmptyNote(
        'Only a team owner places bids. If you are in the pool as a player, '
        'the Players tab is where you will see what happens to you.',
      );
    }

    final bids = ref.watch(myAuctionBidsProvider(auction.id)).valueOrNull;
    final lots = ref.watch(auctionLotsProvider(auction.id)).valueOrNull;
    if (bids == null || lots == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (bids.isEmpty) {
      return const _EmptyNote(
        'You have not bid on anybody yet. Open a player from the Players tab '
        'to make an offer.',
      );
    }

    final byId = {for (final l in lots) l.id: l};
    final rows = bids.values.toList()
      ..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));

    return Column(
      children: [
        for (final bid in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PsCard(
              onTap: () =>
                  context.push(Routes.auctionLot(auction.id, bid.lotId)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bid.playerName ?? byId[bid.lotId]?.displayName ??
                              'Player',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        PsMetaRow(items: [
                          _outcome(byId[bid.lotId], bid),
                          if (bid.round < auction.round) 'Round ${bid.round}',
                        ]),
                      ],
                    ),
                  ),
                  Text(
                    AuctionMoney.format(bid.amountPaise),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _outcome(AuctionLot? lot, AuctionBid bid) {
    if (lot == null) return 'Bid placed';
    if (lot.status == AuctionLotStatus.pool) return 'Locked until the reveal';
    if (lot.isSold) {
      return lot.soldToTeamId == bid.teamId
          ? 'You won them'
          : 'Went to ${lot.soldToTeamName ?? 'another side'}';
    }
    return lot.status.label;
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Ps.muted, fontSize: 13, height: 1.45),
      ),
    );
  }
}
