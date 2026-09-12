import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';

/// Who has put their hand up, and the organizer's decision on each.
///
/// ## Why approving a player is not just a status flip
///
/// An approval is what CREATES the thing the person came for: a bidder gets a
/// side with a purse, a player gets a lot in the pool. Both are written here,
/// from the client, under `firestore.rules` — see
/// `AuctionRepository.decide` for why the three writes are sequential rather
/// than batched.
///
/// The player's career snapshot is captured at this moment too. It is the
/// only point at which the organizer's device is already reading that
/// person's record, and copying it onto the lot is what lets a pool of sixty
/// players render without sixty listeners.
///
/// Everybody is shown, decided or not, because an organizer's most common
/// question after the first day is "did I already deal with him".
class AuctionPeopleScreen extends ConsumerWidget {
  const AuctionPeopleScreen({super.key, required this.auctionId});

  final String auctionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auction = ref.watch(auctionProvider(auctionId)).valueOrNull;
    final people =
        ref.watch(auctionParticipantsProvider(auctionId)).valueOrNull;
    final me = ref.watch(myAuctionPlaceProvider(auctionId)).valueOrNull;
    final teams = ref.watch(auctionTeamsProvider(auctionId)).valueOrNull ??
        const <AuctionTeam>[];

    if (auction == null || people == null) {
      return const AppScaffold(
        title: 'People',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isOrganizer = me?.isOrganizer == true && me?.isApproved == true;
    final purseByUid = {for (final t in teams) t.ownerUid: t};

    final waiting = people
        .where((p) => p.status == AuctionJoinStatus.pending)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final inIt = people.where((p) => p.isApproved).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final out = people
        .where((p) => p.status == AuctionJoinStatus.declined)
        .toList();

    return AppScaffold(
      title: 'People',
      subtitle: auction.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isOrganizer && waiting.isNotEmpty) ...[
                  _Heading('Waiting on you (${waiting.length})'),
                  for (final p in waiting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PendingCard(
                        auction: auction,
                        participant: p,
                        deciderUid: me!.uid,
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                _Heading('In the auction (${inIt.length})'),
                if (inIt.isEmpty)
                  const _Note('Nobody approved yet.')
                else
                  for (final p in inIt)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ApprovedCard(
                        auction: auction,
                        participant: p,
                        team: purseByUid[p.uid],
                        canEdit: isOrganizer,
                      ),
                    ),

                if (!isOrganizer && waiting.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Heading('Still to be decided (${waiting.length})'),
                  for (final p in waiting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlainRow(participant: p),
                    ),
                ],

                if (isOrganizer && out.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Heading('Not taken on (${out.length})'),
                  for (final p in out)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlainRow(participant: p),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One application, with everything the organizer needs to answer it.
class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({
    required this.auction,
    required this.participant,
    required this.deciderUid,
  });

  final Auction auction;
  final AuctionParticipant participant;
  final String deciderUid;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    try {
      // The career read happens once, here, and the result is frozen onto the
      // lot. See the screen's class doc.
      final career = approve && widget.participant.isPlayer
          ? ref.read(careerProvider(widget.participant.uid)).valueOrNull
          : null;
      final best = (career == null || career.isEmpty)
          ? null
          : ([...career]..sort((a, b) => b.prominence.compareTo(a.prominence)))
              .first;

      await ref.read(auctionRepositoryProvider).decide(
            auction: widget.auction,
            participant: widget.participant,
            approve: approve,
            deciderUid: widget.deciderUid,
            statLine: best == null
                ? null
                : '${best.matchesPlayed} '
                    '${best.matchesPlayed == 1 ? 'match' : 'matches'}'
                    '${best.rating != null ? ' · ${best.rating!.tier}' : ''}',
            matchesPlayed: best?.matchesPlayed ?? 0,
            ratingLabel: best?.rating == null
                ? null
                : '${best!.rating!.tier} ${best.rating!.rating.round()}',
          );
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
    final p = widget.participant;
    final career = ref.watch(careerProvider(p.uid)).valueOrNull;

    return PsCard(
      color: const Color(0xFFFFFBEB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PsCrest(
                name: p.displayName,
                logoUrl: p.photoUrl,
                seed: p.uid,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    PsMetaRow(items: [
                      p.rolesLabel,
                      p.playerCode,
                      if (career != null && career.isNotEmpty)
                        '${career.fold<int>(0, (s, l) => s + l.matchesPlayed)} '
                            'matches on record',
                      if (career != null && career.isEmpty)
                        'No record yet',
                    ]),
                  ],
                ),
              ),
            ],
          ),
          if (p.note != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Ps.surface,
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(color: Ps.border),
              ),
              child: Text(
                '"${p.note}"',
                style: const TextStyle(fontSize: 12.5, color: Ps.muted),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (p.isBidder)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Approving gives them a side with a purse of '
                '${AuctionMoney.format(widget.auction.defaultPursePaise)}. '
                'You can change it afterwards.',
                style: const TextStyle(fontSize: 12, color: Ps.muted),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: PsSecondaryButton(
                  label: 'Not this time',
                  onPressed: _busy ? null : () => _decide(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PsPrimaryButton(
                  label: _busy ? '…' : 'Approve',
                  onPressed: _busy ? null : () => _decide(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Somebody who is in, with their purse if they own a side.
class _ApprovedCard extends ConsumerWidget {
  const _ApprovedCard({
    required this.auction,
    required this.participant,
    required this.team,
    required this.canEdit,
  });

  final Auction auction;
  final AuctionParticipant participant;
  final AuctionTeam? team;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = team;
    return PsCard(
      child: Row(
        children: [
          PsCrest(
            name: participant.displayName,
            logoUrl: participant.photoUrl,
            seed: participant.uid,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  participant.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                PsMetaRow(items: [
                  participant.rolesLabel,
                  if (t != null) '${t.name} · ${AuctionMoney.format(t.pursePaise)}',
                ]),
              ],
            ),
          ),
          // Purses are only editable before bidding opens. Afterwards the
          // rules still permit a raise, but changing one side's money once
          // sealed bids are in is the sort of thing that ends a league — so
          // the door is shut here rather than left ajar.
          if (canEdit && t != null && auction.status == AuctionStatus.registration)
            TextButton(
              onPressed: () => _editPurse(context, ref, t),
              child: const Text('Purse'),
            ),
        ],
      ),
    );
  }

  Future<void> _editPurse(
    BuildContext context,
    WidgetRef ref,
    AuctionTeam t,
  ) async {
    final controller =
        TextEditingController(text: '${t.pursePaise ~/ 100}');
    final value = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Purse for ${t.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(prefixText: '₹ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d)
                .pop(AuctionMoney.parseRupees(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await ref.read(auctionRepositoryProvider).setPurse(
          auctionId: auction.id,
          teamId: t.id,
          pursePaise: value,
        );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.participant});

  final AuctionParticipant participant;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      child: Row(
        children: [
          PsCrest(
            name: participant.displayName,
            logoUrl: participant.photoUrl,
            seed: participant.uid,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              participant.displayName,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          Text(
            participant.rolesLabel,
            style: const TextStyle(fontSize: 12, color: Ps.muted),
          ),
        ],
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

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Ps.muted),
      ),
    );
  }
}
