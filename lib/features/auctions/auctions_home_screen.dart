import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';

/// The door to the auction space — More → Auctions.
///
/// ## Why "mine" comes first and the public board second
///
/// Almost every auction in this product will be unlisted. It is somebody's
/// village tournament, the code went out on WhatsApp, and the five people who
/// matter are already in it. A public board is genuinely useful for finding
/// one you have not heard of, but it is the rarer errand — so the list of
/// auctions you are already in leads, and the board sits under it.
///
/// The code box is at the top of both for the same reason: being handed a
/// code and having nowhere obvious to type it is the single most likely way a
/// first-time user of this feature gets stuck.
class AuctionsHomeScreen extends ConsumerWidget {
  const AuctionsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myAuctionsProvider).valueOrNull ?? const [];
    final public = ref.watch(publicAuctionsProvider(null)).valueOrNull;

    // Auctions the person is in are hidden from the public board below.
    // Seeing your own auction twice on one screen, once under "Yours" and
    // once under "Open to join", reads as a bug.
    final mineIds = {for (final p in mine) p.auctionId};

    return AppScaffold(
      title: 'Auctions',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.auctionCreate),
        backgroundColor: Ps.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.gavel),
        label: const Text('Hold an auction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _WhatThisIs(),
                const SizedBox(height: 14),
                const _JoinByCodeCard(),
                const SizedBox(height: 20),
                if (mine.isNotEmpty) ...[
                  const PsSectionHeader(title: 'Yours', actionLabel: ''),
                  const SizedBox(height: 8),
                  for (final p in mine) ...[
                    _MyAuctionRow(place: p),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                ],
                const PsSectionHeader(title: 'Open to join', actionLabel: ''),
                const SizedBox(height: 8),
                if (public == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  for (final a in public.where((a) => !mineIds.contains(a.id)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PublicAuctionRow(auction: a),
                    ),
                  if (public.where((a) => !mineIds.contains(a.id)).isEmpty)
                    const _Empty(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four lines, once, at the top. An auction is the one feature in this
/// product whose rules are not guessable from its screens — somebody who has
/// never seen a sealed-bid draft will otherwise look for the live bidding
/// room that is deliberately not there.
class _WhatThisIs extends StatelessWidget {
  const _WhatThisIs();

  @override
  Widget build(BuildContext context) {
    return const PsCard(
      color: Color(0xFFF0FDF4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel, size: 18, color: Ps.primary),
              SizedBox(width: 8),
              Text(
                'Build sides by bidding',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Players put their hands up. Team owners get a purse and bid '
            'privately on whoever they want, over days — nobody has to be '
            'online at the same time. On the closing date every bid opens at '
            'once and the highest offer takes the player.',
            style: TextStyle(fontSize: 13, height: 1.45, color: Ps.muted),
          ),
        ],
      ),
    );
  }
}

/// The code box. Resolves through `auctionCodes/{code}` and pushes straight
/// into the auction — joining is a decision made on the auction's own screen,
/// not here, because you should be able to read what you are joining first.
class _JoinByCodeCard extends ConsumerStatefulWidget {
  const _JoinByCodeCard();

  @override
  ConsumerState<_JoinByCodeCard> createState() => _JoinByCodeCardState();
}

class _JoinByCodeCardState extends ConsumerState<_JoinByCodeCard> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final typed = _controller.text.trim();
    if (typed.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id =
          await ref.read(auctionRepositoryProvider).resolveJoinCode(typed);
      if (!mounted) return;
      if (id == null) {
        setState(() => _error = 'No auction with that code.');
        return;
      }
      _controller.clear();
      context.push(Routes.auction(id));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not check that code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Have a code?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(
                    hintText: 'PSA-4K7M2',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Ps.radiusSm),
                    ),
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _busy ? null : _go,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Ps.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Ps.radiusSm),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Go'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One auction the person is already in.
///
/// Renders entirely from the participant row — no read of the auction
/// document itself. That is what lets this list work for unlisted auctions
/// without N extra listeners, and it is why `AuctionParticipant` carries a
/// denormalized `auctionName`.
class _MyAuctionRow extends ConsumerWidget {
  const _MyAuctionRow({required this.place});

  final AuctionParticipant place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = place.status == AuctionJoinStatus.pending;
    final declined = place.status == AuctionJoinStatus.declined;

    return PsCard(
      onTap: () => context.push(Routes.auction(place.auctionId)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: declined
                  ? Ps.border
                  : (pending
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFDCFCE7)),
              borderRadius: BorderRadius.circular(Ps.radiusSm),
            ),
            child: Icon(
              Icons.gavel,
              size: 20,
              color: declined
                  ? Ps.faint
                  : (pending ? const Color(0xFFB45309) : Ps.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.auctionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  place.rolesLabel,
                  if (pending) 'Waiting for approval',
                  if (declined) 'Not accepted',
                ]),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Ps.faint),
        ],
      ),
    );
  }
}

class _PublicAuctionRow extends StatelessWidget {
  const _PublicAuctionRow({required this.auction});

  final Auction auction;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      onTap: () => context.push(Routes.auction(auction.id)),
      child: Row(
        children: [
          SportBadge(sportId: auction.sportId, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  auction.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  auction.sportName,
                  auction.locationLabel,
                  auction.status.label,
                ]),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  '${auction.playerCount} players',
                  '${auction.teamCount} sides',
                  '${AuctionMoney.compact(auction.defaultPursePaise)} purse',
                ]),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Ps.faint),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.gavel_outlined, size: 36, color: Ps.faint),
          SizedBox(height: 10),
          Text(
            'No public auctions right now.',
            style: TextStyle(color: Ps.muted, fontSize: 13.5),
          ),
          SizedBox(height: 4),
          Text(
            'Most are private — ask the organizer for the code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Ps.faint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
