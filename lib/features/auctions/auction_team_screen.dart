import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';
import 'widgets/auction_purse_card.dart';
import 'widgets/auction_trade_composer.dart';

/// One side: its squad, its money, and the way to propose a swap.
///
/// The "Offer a swap" button lives HERE, on the other side's page, rather
/// than on a trades screen with a team picker. A trade starts as "I want
/// somebody off that team", and the moment you are looking at their squad is
/// the moment you know which player — a composer opened from a neutral screen
/// makes you name the team from memory first.
class AuctionTeamScreen extends ConsumerWidget {
  const AuctionTeamScreen({
    super.key,
    required this.auctionId,
    required this.teamId,
  });

  final String auctionId;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auction = ref.watch(auctionProvider(auctionId)).valueOrNull;
    final team = ref
        .watch(auctionTeamProvider((auctionId: auctionId, teamId: teamId)))
        .valueOrNull;
    final squad = ref
        .watch(auctionSquadProvider((auctionId: auctionId, teamId: teamId)))
        .valueOrNull;
    final myTeam = ref.watch(myAuctionTeamProvider(auctionId)).valueOrNull;
    final myUid = ref.watch(currentUidProvider);

    if (auction == null || team == null) {
      return const AppScaffold(
        title: 'Side',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isMine = team.id == myUid;
    final now = DateTime.now();
    final canOffer = myTeam != null &&
        !isMine &&
        auction.tradingOpenAt(now);

    return AppScaffold(
      title: team.name,
      subtitle: '${team.ownerName} · ${auction.name}',
      actions: [
        if (isMine)
          IconButton(
            tooltip: 'Rename your side',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(context, ref, auction.id, team),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isMine)
                  AuctionPurseCard(auction: auction, team: team)
                else
                  _OtherSideMoney(auction: auction, team: team),
                const SizedBox(height: 14),

                if (canOffer) ...[
                  PsSecondaryButton(
                    label: 'Offer a swap',
                    icon: Icons.swap_horiz,
                    onPressed: () => showAuctionTradeComposer(
                      context,
                      auction: auction,
                      myTeam: myTeam,
                      theirTeam: team,
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else if (myTeam != null &&
                    !isMine &&
                    auction.status.isRevealed) ...[
                  // Says why, rather than simply not showing the button. The
                  // exchange window is the one deadline in this feature people
                  // will miss, and an absent button teaches nothing.
                  Text(
                    auction.status == AuctionStatus.locked
                        ? 'Squads are locked. No more swaps.'
                        : 'The swap window has closed.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: Ps.muted),
                  ),
                  const SizedBox(height: 14),
                ],

                Text(
                  'SQUAD (${squad?.length ?? 0})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Ps.faint,
                  ),
                ),
                const SizedBox(height: 8),

                if (squad == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (squad.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      auction.status.isRevealed
                          ? 'This side did not win anybody.'
                          : 'Nothing yet — squads fill up at the reveal.',
                      style: const TextStyle(fontSize: 13, color: Ps.muted),
                    ),
                  )
                else
                  for (final lot in [...squad]
                    ..sort((a, b) =>
                        (b.soldPricePaise ?? 0).compareTo(a.soldPricePaise ?? 0)))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PsCard(
                        onTap: () =>
                            context.push(Routes.auctionLot(auction.id, lot.id)),
                        child: Row(
                          children: [
                            PsCrest(
                              name: lot.displayName,
                              logoUrl: lot.photoUrl,
                              seed: lot.playerUid,
                              size: 38,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    lot.displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  PsMetaRow(items: [
                                    lot.roleLabel,
                                    lot.summaryLine,
                                    if (lot.acquiredBy == 'trade') 'Traded in',
                                  ]),
                                ],
                              ),
                            ),
                            Text(
                              AuctionMoney.compact(lot.soldPricePaise ?? 0),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                if (auction.minSquadSize != null &&
                    squad != null &&
                    squad.length < auction.minSquadSize! &&
                    auction.status.isRevealed) ...[
                  const SizedBox(height: 12),
                  // Advisory only — the minimum is never enforced, because
                  // enforcing it would mean forcing somebody to spend. Said
                  // out loud so an owner can fix it in the swap window.
                  Text(
                    'Short of the ${auction.minSquadSize} this auction asks '
                    'for. Trade for the difference before the window closes.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String auctionId,
    AuctionTeam team,
  ) async {
    final controller = TextEditingController(text: team.name);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Name your side'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(auctionRepositoryProvider)
        .renameTeam(auctionId: auctionId, teamId: team.id, name: name);
  }
}

/// Another side's money, from the outside.
///
/// Shows the purse, what they have spent and what is left — never what they
/// have LOCKED behind live bids. The locked figure is the sum of their sealed
/// bids, and publishing it would hand every rival a running total of how much
/// somebody is committing, which is most of the information a sealed auction
/// exists to withhold.
class _OtherSideMoney extends StatelessWidget {
  const _OtherSideMoney({required this.auction, required this.team});

  final Auction auction;
  final AuctionTeam team;

  @override
  Widget build(BuildContext context) {
    final revealed = auction.status.isRevealed;
    return PsCard(
      child: Row(
        children: [
          Expanded(
            child: _Fig(
              label: 'Purse',
              value: AuctionMoney.format(team.pursePaise),
            ),
          ),
          if (revealed) ...[
            Expanded(
              child: _Fig(
                label: 'Spent',
                value: AuctionMoney.format(team.spentPaise),
              ),
            ),
            Expanded(
              child: _Fig(
                label: 'Left',
                value: AuctionMoney.format(team.remainingPaise),
              ),
            ),
          ],
          Expanded(
            child: _Fig(label: 'Players', value: '${team.wonCount}'),
          ),
        ],
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value});

  final String label;
  final String value;

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
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Ps.muted),
        ),
      ],
    );
  }
}
