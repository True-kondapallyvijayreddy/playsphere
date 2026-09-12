import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';

/// Calling an auction into being.
///
/// ## What is on this form and what is not
///
/// Everything here is a decision the organizer has to have made before
/// anybody can be invited — the name, the sport, the money, the shape of the
/// squads, and when the exchange window shuts.
///
/// What is deliberately NOT here is `bidsCloseAt`. The bidding deadline is
/// set on the day bidding opens, from the auction's own screen, because an
/// organizer creating the auction three weeks early has no idea yet when the
/// registrations will have come in. Asking for it now would guarantee a wrong
/// answer, and a wrong bidding deadline is the one setting that cannot be
/// fixed after the fact without invalidating sealed bids.
class AuctionCreateScreen extends ConsumerStatefulWidget {
  const AuctionCreateScreen({super.key});

  @override
  ConsumerState<AuctionCreateScreen> createState() =>
      _AuctionCreateScreenState();
}

class _AuctionCreateScreenState extends ConsumerState<AuctionCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _place = TextEditingController();
  final _description = TextEditingController();

  // Defaults chosen to match what the feature was asked for: ₹1,00,000 a side
  // and a nominal floor. An organizer running a no-money "draw for teams"
  // auction sets the purse to zero, which every screen handles.
  final _purse = TextEditingController(text: '100000');
  final _basePrice = TextEditingController(text: '1000');
  final _maxSquad = TextEditingController(text: '11');
  final _minSquad = TextEditingController(text: '7');
  final _maxTeams = TextEditingController();

  String _sportId = 'cricket';
  AuctionVisibility _visibility = AuctionVisibility.unlisted;
  DateTime? _eventStartsAt;
  DateTime? _exchangeClosesAt;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name, _place, _description, _purse, _basePrice,
      _maxSquad, _minSquad, _maxTeams,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? picked),
    );
    if (!mounted) return;
    onPicked(DateTime(
      picked.year,
      picked.month,
      picked.day,
      time?.hour ?? 9,
      time?.minute ?? 0,
    ));
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;

    final purse = AuctionMoney.parseRupees(_purse.text) ?? 0;
    final base = AuctionMoney.parseRupees(_basePrice.text) ?? 0;
    if (base > purse && purse > 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('A base price above the purse means nobody can bid.'),
      ));
      return;
    }

    final sport = SportCatalog.all.firstWhere(
      (s) => s.id == _sportId,
      orElse: () => SportCatalog.all.first,
    );

    setState(() => _busy = true);
    try {
      final id = await ref.read(auctionRepositoryProvider).createAuction(
            draft: Auction(
              id: '',
              name: _name.text.trim(),
              sportId: sport.id,
              sportName: sport.name,
              status: AuctionStatus.draft,
              visibility: _visibility,
              createdByUid: me.uid,
              createdByName: me.displayName,
              joinCode: '',
              defaultPursePaise: purse,
              defaultBasePricePaise: base,
              round: 1,
              minSquadSize: int.tryParse(_minSquad.text.trim()),
              maxSquadSize: int.tryParse(_maxSquad.text.trim()),
              maxTeams: int.tryParse(_maxTeams.text.trim()),
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              locationLabel:
                  _place.text.trim().isEmpty ? null : _place.text.trim(),
              eventStartsAt: _eventStartsAt,
              // Defaults to the morning the event starts. An organizer who
              // wants a tighter window — "trades shut a week before" — moves
              // it; one who never thinks about it still gets the behaviour
              // that was asked for, which is that trading stops when play
              // starts.
              exchangeClosesAt: _exchangeClosesAt ?? _eventStartsAt,
            ),
            creator: me,
          );
      if (!mounted) return;
      // Replaces rather than pushes: going Back from a freshly made auction
      // should land on the list, not on the form that made it.
      context.pushReplacement(Routes.auction(id));
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
    return AppScaffold(
      title: 'Hold an auction',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            ContentBounds(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Group(
                    title: 'What is it',
                    children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: _dec(
                          'Name',
                          hint: 'Maram 2026 Dec Sports — Cricket',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Give it a name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _sportId,
                        decoration: _dec('Sport'),
                        items: [
                          for (final s in SportCatalog.all)
                            DropdownMenuItem(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (v) =>
                            setState(() => _sportId = v ?? _sportId),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _place,
                        textCapitalization: TextCapitalization.words,
                        decoration: _dec(
                          'Where',
                          hint: 'Maram village',
                          optional: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        maxLines: 3,
                        decoration: _dec(
                          'Anything else',
                          hint: 'Two grounds, matches every Sunday…',
                          optional: true,
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'The money',
                    note: 'Each side gets this to spend. A bid locks the '
                        'money until the reveal, so nobody can promise the '
                        'same rupee twice. You can give any side a different '
                        'purse after you approve them.',
                    children: [
                      TextFormField(
                        controller: _purse,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Purse per side', prefix: '₹'),
                        validator: (v) =>
                            AuctionMoney.parseRupees(v ?? '') == null
                                ? 'Enter an amount'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _basePrice,
                        keyboardType: TextInputType.number,
                        decoration: _dec(
                          'Base price per player',
                          prefix: '₹',
                          hint: 'The lowest a bid may be',
                        ),
                        validator: (v) =>
                            AuctionMoney.parseRupees(v ?? '') == null
                                ? 'Enter an amount'
                                : null,
                      ),
                    ],
                  ),
                  _Group(
                    title: 'The squads',
                    note: 'The cap counts players already won plus bids still '
                        'live, because every live bid is somebody you might '
                        'be about to own.',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minSquad,
                              keyboardType: TextInputType.number,
                              decoration: _dec('Smallest squad'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _maxSquad,
                              keyboardType: TextInputType.number,
                              decoration: _dec('Largest squad'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _maxTeams,
                        keyboardType: TextInputType.number,
                        decoration: _dec(
                          'How many sides',
                          hint: 'Leave blank for no limit',
                          optional: true,
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'Dates',
                    note: 'You set the bidding deadline later, on the day you '
                        'open bidding — by then you will know who actually '
                        'turned up.',
                    children: [
                      _DateRow(
                        label: 'Event starts',
                        value: _eventStartsAt,
                        onTap: () => _pickDate(
                          current: _eventStartsAt,
                          onPicked: (d) => setState(() => _eventStartsAt = d),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DateRow(
                        label: 'Player swaps close',
                        value: _exchangeClosesAt ?? _eventStartsAt,
                        hint: 'Defaults to when the event starts',
                        onTap: () => _pickDate(
                          current: _exchangeClosesAt ?? _eventStartsAt,
                          onPicked: (d) =>
                              setState(() => _exchangeClosesAt = d),
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'Who can find it',
                    children: [
                      for (final v in AuctionVisibility.values)
                        RadioListTile<AuctionVisibility>(
                          value: v,
                          // ignore: deprecated_member_use
                          groupValue: _visibility,
                          // ignore: deprecated_member_use
                          onChanged: (x) =>
                              setState(() => _visibility = x ?? _visibility),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            v.label,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            v == AuctionVisibility.public
                                ? 'Shows on the auctions board'
                                : 'Only people you give the code to',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Ps.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PsPrimaryButton(
                    label: _busy ? 'Creating…' : 'Create',
                    onPressed: _busy ? null : _create,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'It starts as a draft. Nobody sees it until you publish '
                    'it on the next screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Ps.faint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(
    String label, {
    String? hint,
    String? prefix,
    bool optional = false,
  }) =>
      InputDecoration(
        labelText: optional ? '$label (optional)' : label,
        hintText: hint,
        prefixText: prefix,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ps.radiusSm),
        ),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note!,
              style: const TextStyle(
                fontSize: 12.5,
                color: Ps.muted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
  });

  final String label;
  final DateTime? value;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Ps.border),
          borderRadius: BorderRadius.circular(Ps.radiusSm),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, size: 18, color: Ps.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13.5)),
                  Text(
                    v == null
                        ? (hint ?? 'Not set')
                        : '${v.day}/${v.month}/${v.year}, '
                            '${v.hour.toString().padLeft(2, '0')}:'
                            '${v.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: v == null ? Ps.faint : Ps.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Ps.faint),
          ],
        ),
      ),
    );
  }
}
