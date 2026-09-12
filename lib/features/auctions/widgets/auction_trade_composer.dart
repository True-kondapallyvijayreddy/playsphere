import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/auction.dart';
import '../../../shared/ui_kit.dart';
import '../auction_providers.dart';

/// Building a swap offer.
///
/// ## Why both squads are on one sheet
///
/// A trade is a comparison, and a composer that asks "pick your players" on
/// one screen and "pick theirs" on the next makes the person hold one half in
/// their head while choosing the other. Both lists are here, stacked, with
/// the running shape of the deal between them.
///
/// ## Why cash is one field and not two
///
/// The data model carries `fromCashPaise` and `toCashPaise` separately, but
/// "I pay you ₹5,000 and you pay me ₹3,000" is a ₹2,000 offer written
/// confusingly, and a composer that allows it will be used to write it. So
/// there is one signed amount here — positive means you add money, negative
/// means you want money — and it is split onto the correct side at the last
/// moment.
void showAuctionTradeComposer(
  BuildContext context, {
  required Auction auction,
  required AuctionTeam myTeam,
  required AuctionTeam theirTeam,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, controller) => _TradeComposer(
        auction: auction,
        myTeam: myTeam,
        theirTeam: theirTeam,
        scrollController: controller,
      ),
    ),
  );
}

class _TradeComposer extends ConsumerStatefulWidget {
  const _TradeComposer({
    required this.auction,
    required this.myTeam,
    required this.theirTeam,
    required this.scrollController,
  });

  final Auction auction;
  final AuctionTeam myTeam;
  final AuctionTeam theirTeam;
  final ScrollController scrollController;

  @override
  ConsumerState<_TradeComposer> createState() => _TradeComposerState();
}

class _TradeComposerState extends ConsumerState<_TradeComposer> {
  final _mine = <String>{};
  final _theirs = <String>{};
  final _cash = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _iPay = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cash.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(List<AuctionLot> mySquad, List<AuctionLot> theirSquad) async {
    if (_mine.isEmpty && _theirs.isEmpty) {
      setState(() => _error = 'Pick at least one player.');
      return;
    }
    final cash = AuctionMoney.parseRupees(_cash.text) ?? 0;

    // Bounded against what the payer actually has left. The server checks the
    // same thing in the execution transaction — this one only saves the other
    // side from being sent an offer that could never have completed.
    if (_iPay && cash > widget.myTeam.remainingPaise) {
      setState(() => _error =
          'You only have ${AuctionMoney.format(widget.myTeam.remainingPaise)} '
          'left to offer.');
      return;
    }
    if (!_iPay && cash > widget.theirTeam.remainingPaise) {
      setState(() => _error =
          '${widget.theirTeam.name} only has '
          '${AuctionMoney.format(widget.theirTeam.remainingPaise)} left.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final byId = {
        for (final l in [...mySquad, ...theirSquad]) l.id: l.displayName,
      };
      await ref.read(auctionRepositoryProvider).proposeTrade(
            AuctionTrade(
              id: '',
              auctionId: widget.auction.id,
              fromTeamId: widget.myTeam.id,
              fromTeamName: widget.myTeam.name,
              toTeamId: widget.theirTeam.id,
              toTeamName: widget.theirTeam.name,
              fromLotIds: _mine.toList(),
              toLotIds: _theirs.toList(),
              fromLotNames: [for (final id in _mine) byId[id] ?? 'Player'],
              toLotNames: [for (final id in _theirs) byId[id] ?? 'Player'],
              fromCashPaise: _iPay ? cash : 0,
              toCashPaise: _iPay ? 0 : cash,
              status: AuctionTradeStatus.proposed,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            ),
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
    final mySquad = ref
            .watch(auctionSquadProvider(
                (auctionId: widget.auction.id, teamId: widget.myTeam.id)))
            .valueOrNull ??
        const <AuctionLot>[];
    final theirSquad = ref
            .watch(auctionSquadProvider(
                (auctionId: widget.auction.id, teamId: widget.theirTeam.id)))
            .valueOrNull ??
        const <AuctionLot>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        controller: widget.scrollController,
        children: [
          const Text(
            'Offer a swap',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing moves until ${widget.theirTeam.name} accepts.',
            style: const TextStyle(fontSize: 12.5, color: Ps.muted),
          ),
          const SizedBox(height: 16),

          _SquadPicker(
            title: 'You give',
            squad: mySquad,
            selected: _mine,
            onToggle: (id) => setState(() {
              _mine.contains(id) ? _mine.remove(id) : _mine.add(id);
              _error = null;
            }),
            emptyNote: 'You have no players to give.',
          ),
          const SizedBox(height: 14),
          _SquadPicker(
            title: 'You get',
            squad: theirSquad,
            selected: _theirs,
            onToggle: (id) => setState(() {
              _theirs.contains(id) ? _theirs.remove(id) : _theirs.add(id);
              _error = null;
            }),
            emptyNote: '${widget.theirTeam.name} has no players yet.',
          ),
          const SizedBox(height: 16),

          const Text(
            'CASH',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Ps.faint,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('I add')),
                    ButtonSegment(value: false, label: Text('They add')),
                  ],
                  selected: {_iPay},
                  onSelectionChanged: (s) =>
                      setState(() => _iPay = s.first),
                  showSelectedIcon: false,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _cash,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Ps.radiusSm),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _iPay
                ? 'You have ${AuctionMoney.format(widget.myTeam.remainingPaise)} unspent.'
                : '${widget.theirTeam.name} has '
                    '${AuctionMoney.format(widget.theirTeam.remainingPaise)} unspent.',
            style: const TextStyle(fontSize: 11.5, color: Ps.faint),
          ),

          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'A word about it (optional)',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Ps.radiusSm),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, color: Ps.live),
            ),
          ],
          const SizedBox(height: 16),
          PsPrimaryButton(
            label: _busy ? 'Sending…' : 'Send the offer',
            onPressed: _busy ? null : () => _send(mySquad, theirSquad),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SquadPicker extends StatelessWidget {
  const _SquadPicker({
    required this.title,
    required this.squad,
    required this.selected,
    required this.onToggle,
    required this.emptyNote,
  });

  final String title;
  final List<AuctionLot> squad;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String emptyNote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Ps.faint,
          ),
        ),
        const SizedBox(height: 8),
        if (squad.isEmpty)
          Text(
            emptyNote,
            style: const TextStyle(fontSize: 12.5, color: Ps.muted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lot in squad)
                FilterChip(
                  selected: selected.contains(lot.id),
                  onSelected: (_) => onToggle(lot.id),
                  label: Text(
                    '${lot.displayName} · '
                    '${AuctionMoney.compact(lot.soldPricePaise ?? 0)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
