import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/auction.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'auction_providers.dart';

/// The organizer's settings.
///
/// ## What cannot be changed here, and why
///
/// The sport, the join code and the creator are frozen by `firestore.rules`,
/// not merely absent from this form. A changed code orphans the document in
/// `auctionCodes` that people are typing in; a changed sport invalidates every
/// career snapshot already copied onto the lots.
///
/// The status, the round, the bidding deadline and all three outcome
/// timestamps are also frozen. They move through the callables in
/// `functions/auctions.js`, each of which carries a transaction the settings
/// form has no way to perform.
///
/// The base price is editable here but the rules refuse it once bidding has
/// opened — a floor raised under a sealed bid already placed would invalidate
/// it without telling the bidder. The form greys it out to match, but the
/// rule is what holds.
class AuctionSettingsScreen extends ConsumerStatefulWidget {
  const AuctionSettingsScreen({super.key, required this.auctionId});

  final String auctionId;

  @override
  ConsumerState<AuctionSettingsScreen> createState() =>
      _AuctionSettingsScreenState();
}

class _AuctionSettingsScreenState
    extends ConsumerState<AuctionSettingsScreen> {
  final _name = TextEditingController();
  final _place = TextEditingController();
  final _description = TextEditingController();
  final _purse = TextEditingController();
  final _basePrice = TextEditingController();
  final _minSquad = TextEditingController();
  final _maxSquad = TextEditingController();

  AuctionVisibility? _visibility;
  DateTime? _eventStartsAt;
  DateTime? _exchangeClosesAt;
  bool _seeded = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name, _place, _description, _purse, _basePrice, _minSquad, _maxSquad,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the form from the document once, and never again.
  ///
  /// A stream rebuild must not overwrite half-typed text — which is exactly
  /// what happens on any screen that seeds its controllers from the latest
  /// snapshot on every build, and it is invisible until two organizers are
  /// editing at once.
  void _seed(Auction a) {
    if (_seeded) return;
    _seeded = true;
    _name.text = a.name;
    _place.text = a.locationLabel ?? '';
    _description.text = a.description ?? '';
    _purse.text = '${a.defaultPursePaise ~/ 100}';
    _basePrice.text = '${a.defaultBasePricePaise ~/ 100}';
    _minSquad.text = a.minSquadSize?.toString() ?? '';
    _maxSquad.text = a.maxSquadSize?.toString() ?? '';
    _visibility = a.visibility;
    _eventStartsAt = a.eventStartsAt;
    _exchangeClosesAt = a.exchangeClosesAt;
  }

  Future<void> _save(Auction a) async {
    setState(() => _busy = true);
    try {
      await ref.read(auctionRepositoryProvider).updateSettings(
            a.copyWith(
              name: _name.text.trim(),
              visibility: _visibility,
              defaultPursePaise: AuctionMoney.parseRupees(_purse.text),
              defaultBasePricePaise:
                  AuctionMoney.parseRupees(_basePrice.text),
              minSquadSize: int.tryParse(_minSquad.text.trim()),
              maxSquadSize: int.tryParse(_maxSquad.text.trim()),
              description: _description.text.trim(),
              locationLabel: _place.text.trim(),
              eventStartsAt: _eventStartsAt,
              exchangeClosesAt: _exchangeClosesAt,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(
    DateTime? current,
    ValueChanged<DateTime> onPicked,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? date),
    );
    if (!mounted) return;
    onPicked(DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 9,
      time?.minute ?? 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auction = ref.watch(auctionProvider(widget.auctionId)).valueOrNull;
    if (auction == null) {
      return const AppScaffold(
        title: 'Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    _seed(auction);

    // Once sealed bids exist, the money settings stop being editable. The
    // rules enforce the base price; the purse default only affects sides
    // approved later, of which there are none after registration closes.
    final moneyEditable = auction.status == AuctionStatus.draft ||
        auction.status == AuctionStatus.registration;

    return AppScaffold(
      title: 'Settings',
      subtitle: auction.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Frozen(auction: auction),
                const SizedBox(height: 16),

                TextField(
                  controller: _name,
                  decoration: _dec('Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _place,
                  decoration: _dec('Where'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  decoration: _dec('Anything else'),
                ),
                const SizedBox(height: 18),

                if (!moneyEditable)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'The money settings are fixed once bidding has opened. '
                      'Changing a base price under a sealed bid would '
                      'invalidate it without telling the bidder.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFB45309),
                        height: 1.4,
                      ),
                    ),
                  ),
                TextField(
                  controller: _purse,
                  enabled: moneyEditable,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Default purse', prefix: '₹ '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _basePrice,
                  enabled: moneyEditable,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Default base price', prefix: '₹ '),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minSquad,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Smallest squad'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxSquad,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Largest squad'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                _DateTile(
                  label: 'Event starts',
                  value: _eventStartsAt,
                  onTap: () => _pick(
                    _eventStartsAt,
                    (d) => setState(() => _eventStartsAt = d),
                  ),
                ),
                const SizedBox(height: 8),
                _DateTile(
                  label: 'Player swaps close',
                  value: _exchangeClosesAt,
                  onTap: () => _pick(
                    _exchangeClosesAt,
                    (d) => setState(() => _exchangeClosesAt = d),
                  ),
                ),
                const SizedBox(height: 18),

                for (final v in AuctionVisibility.values)
                  RadioListTile<AuctionVisibility>(
                    value: v,
                    // ignore: deprecated_member_use
                    groupValue: _visibility,
                    // ignore: deprecated_member_use
                    onChanged: (x) => setState(() => _visibility = x),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(v.label, style: const TextStyle(fontSize: 14)),
                  ),

                const SizedBox(height: 12),
                PsPrimaryButton(
                  label: _busy ? 'Saving…' : 'Save',
                  onPressed: _busy ? null : () => _save(auction),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String label, {String? prefix}) => InputDecoration(
        labelText: label,
        prefixText: prefix,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ps.radiusSm),
        ),
      );
}

/// The facts that cannot change, shown rather than hidden — an organizer
/// hunting for a setting that is not there needs to be told it is fixed, not
/// left to conclude the screen is incomplete.
class _Frozen extends StatelessWidget {
  const _Frozen({required this.auction});

  final Auction auction;

  @override
  Widget build(BuildContext context) {
    return PsCard(
      color: Ps.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FIXED FOR THE LIFE OF THIS AUCTION',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Ps.faint,
            ),
          ),
          const SizedBox(height: 8),
          PsMetaRow(items: [
            auction.sportName,
            'Code ${auction.joinCode}',
            'Round ${auction.round}',
            auction.status.label,
          ]),
          const SizedBox(height: 6),
          const Text(
            'The code is on somebody\'s noticeboard by now, and the sport is '
            'what every player\'s record was measured against.',
            style: TextStyle(fontSize: 11.5, color: Ps.faint, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
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
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
            Text(
              v == null
                  ? 'Not set'
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
    );
  }
}
