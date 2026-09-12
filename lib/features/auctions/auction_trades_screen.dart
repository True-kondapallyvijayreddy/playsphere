import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';

/// The exchange window: offers waiting on you, and offers you have sent.
///
/// ## Why an accepted offer still has a button on it
///
/// Accepting and executing are two steps — see `executeAuctionTrade`. The
/// accept is an ordinary Firestore write; the roster moves in a transaction
/// afterwards. Almost always the second follows the first within a second and
/// nobody sees this state. When a phone dies in between, the offer sits here
/// marked agreed with a "Complete the swap" button, and either side can press
/// it. The function is idempotent, so both pressing it is fine.
///
/// That is the whole reason the split exists: the alternative is an accept
/// that half-applies and a player who belongs to two squads.
class AuctionTradesScreen extends ConsumerWidget {
  const AuctionTradesScreen({super.key, required this.auctionId});

  final String auctionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auction = ref.watch(auctionProvider(auctionId)).valueOrNull;
    final trades = ref.watch(auctionTradesProvider(auctionId)).valueOrNull;
    final myUid = ref.watch(currentUidProvider);

    if (auction == null || trades == null || myUid == null) {
      return const AppScaffold(
        title: 'Trades',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();
    final open = auction.tradingOpenAt(now);

    final waitingOnMe =
        trades.where((t) => t.isPending && t.toTeamId == myUid).toList();
    final waitingOnThem =
        trades.where((t) => t.isPending && t.fromTeamId == myUid).toList();
    final agreed = trades
        .where((t) => t.status == AuctionTradeStatus.accepted && !t.isDone)
        .toList();
    final history = trades
        .where((t) =>
            t.isDone ||
            t.status == AuctionTradeStatus.declined ||
            t.status == AuctionTradeStatus.cancelled)
        .toList();

    return AppScaffold(
      title: 'Trades',
      subtitle: auction.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WindowBanner(auction: auction, open: open, now: now),
                const SizedBox(height: 14),

                if (agreed.isNotEmpty) ...[
                  const _Heading('Agreed — finish these'),
                  for (final t in agreed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TradeCard(
                        auction: auction,
                        trade: t,
                        myUid: myUid,
                        open: open,
                      ),
                    ),
                  const SizedBox(height: 14),
                ],

                if (waitingOnMe.isNotEmpty) ...[
                  _Heading('Waiting on you (${waitingOnMe.length})'),
                  for (final t in waitingOnMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TradeCard(
                        auction: auction,
                        trade: t,
                        myUid: myUid,
                        open: open,
                      ),
                    ),
                  const SizedBox(height: 14),
                ],

                if (waitingOnThem.isNotEmpty) ...[
                  const _Heading('Sent'),
                  for (final t in waitingOnThem)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TradeCard(
                        auction: auction,
                        trade: t,
                        myUid: myUid,
                        open: open,
                      ),
                    ),
                  const SizedBox(height: 14),
                ],

                if (history.isNotEmpty) ...[
                  const _Heading('Done'),
                  for (final t in history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TradeCard(
                        auction: auction,
                        trade: t,
                        myUid: myUid,
                        open: open,
                      ),
                    ),
                ],

                if (trades.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No offers yet. Open another side from the auction '
                      'screen and offer them a swap.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Ps.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowBanner extends StatelessWidget {
  const _WindowBanner({
    required this.auction,
    required this.open,
    required this.now,
  });

  final Auction auction;
  final bool open;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final closes = auction.exchangeClosesAt;
    final tint = open ? Ps.primary : Ps.muted;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(Ps.radius),
      ),
      child: Row(
        children: [
          Icon(open ? Icons.swap_horiz : Icons.lock_outline,
              size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              open
                  ? (closes == null
                      ? 'Swaps are open until the organizer locks the squads.'
                      : 'Swaps are open until ${closes.day}/${closes.month}, '
                          '${closes.hour.toString().padLeft(2, '0')}:'
                          '${closes.minute.toString().padLeft(2, '0')}.')
                  : (auction.status == AuctionStatus.locked
                      ? 'Squads are locked. Nothing can move now.'
                      : auction.status.isRevealed
                          ? 'The swap window has closed.'
                          : 'Swaps open once the squads are revealed.'),
              style: TextStyle(
                fontSize: 12.5,
                color: tint,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeCard extends ConsumerStatefulWidget {
  const _TradeCard({
    required this.auction,
    required this.trade,
    required this.myUid,
    required this.open,
  });

  final Auction auction;
  final AuctionTrade trade;
  final String myUid;
  final bool open;

  @override
  ConsumerState<_TradeCard> createState() => _TradeCardState();
}

class _TradeCardState extends ConsumerState<_TradeCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('ValidationException: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trade;
    final repo = ref.read(auctionRepositoryProvider);
    final theirs = t.fromTeamId == widget.myUid;

    // Written from the reader's side. "You give / you get" beats "from / to",
    // which forces every reader to work out which end they are on.
    final iGive = theirs ? t.fromLotNames : t.toLotNames;
    final iGet = theirs ? t.toLotNames : t.fromLotNames;
    final iPay = theirs ? t.fromCashPaise : t.toCashPaise;
    final iReceive = theirs ? t.toCashPaise : t.fromCashPaise;

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  theirs
                      ? 'Your offer to ${t.toTeamName}'
                      : 'From ${t.fromTeamName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              _StatusPill(trade: t),
            ],
          ),
          const SizedBox(height: 10),
          _Leg(
            label: 'You give',
            players: iGive,
            cash: iPay,
            tint: Ps.live,
          ),
          const SizedBox(height: 6),
          _Leg(
            label: 'You get',
            players: iGet,
            cash: iReceive,
            tint: Ps.primary,
          ),
          if (t.note != null) ...[
            const SizedBox(height: 8),
            Text(
              '"${t.note}"',
              style: const TextStyle(fontSize: 12.5, color: Ps.muted),
            ),
          ],

          if (widget.open && t.isPending && !theirs) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PsSecondaryButton(
                    label: 'Decline',
                    onPressed: _busy
                        ? null
                        : () => _run(() => repo.declineTrade(
                              auctionId: widget.auction.id,
                              tradeId: t.id,
                            )),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PsPrimaryButton(
                    label: _busy ? '…' : 'Accept',
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              await repo.acceptTrade(
                                auctionId: widget.auction.id,
                                tradeId: t.id,
                              );
                              // Straight on to the roster move, so the normal
                              // case never shows the intermediate state.
                              await repo.executeTrade(
                                auctionId: widget.auction.id,
                                tradeId: t.id,
                              );
                            }),
                  ),
                ),
              ],
            ),
          ] else if (widget.open && t.isPending && theirs) ...[
            const SizedBox(height: 12),
            PsSecondaryButton(
              label: 'Withdraw the offer',
              onPressed: _busy
                  ? null
                  : () => _run(() => repo.cancelTrade(
                        auctionId: widget.auction.id,
                        tradeId: t.id,
                      )),
            ),
          ] else if (t.status == AuctionTradeStatus.accepted && !t.isDone) ...[
            const SizedBox(height: 12),
            PsPrimaryButton(
              label: _busy ? '…' : 'Complete the swap',
              onPressed: _busy
                  ? null
                  : () => _run(() => repo.executeTrade(
                        auctionId: widget.auction.id,
                        tradeId: t.id,
                      )),
            ),
          ],
        ],
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({
    required this.label,
    required this.players,
    required this.cash,
    required this.tint,
  });

  final String label;
  final List<String> players;
  final int cash;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final parts = [
      ...players,
      if (cash > 0) AuctionMoney.format(cash),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ),
        Expanded(
          child: Text(
            parts.isEmpty ? 'nothing' : parts.join(', '),
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.trade});

  final AuctionTrade trade;

  @override
  Widget build(BuildContext context) {
    final (String label, Color tint) = trade.isDone
        ? ('Done', Ps.primary)
        : switch (trade.status) {
            AuctionTradeStatus.proposed => ('Open', const Color(0xFFB45309)),
            AuctionTradeStatus.accepted => ('Agreed', Ps.primary),
            AuctionTradeStatus.declined => ('Declined', Ps.muted),
            AuctionTradeStatus.cancelled => ('Withdrawn', Ps.muted),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: tint,
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: Ps.faint,
        ),
      ),
    );
  }
}
