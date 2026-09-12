/// Listing a sports shop, and editing the listing.
///
/// One screen for both, same as `CoachProfileEditScreen` and
/// `SportsMedicRegistrationScreen`: the document id is the uid, so there is no
/// "which listing" to choose and a separate edit screen would be the same form
/// twice.
///
/// The required set is deliberately small — a name, a city, one thing you
/// sell, one way to be reached. Everything else is optional, because a shop
/// owner filling this in on a phone between customers will abandon a long
/// form, and a short listing that exists beats a complete one that does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sports_shop.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

class SportsShopRegistrationScreen extends ConsumerStatefulWidget {
  const SportsShopRegistrationScreen({super.key});

  @override
  ConsumerState<SportsShopRegistrationScreen> createState() =>
      _SportsShopRegistrationScreenState();
}

class _SportsShopRegistrationScreenState
    extends ConsumerState<SportsShopRegistrationScreen> {
  final _name = TextEditingController();
  final _headline = TextEditingController();
  final _about = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _hours = TextEditingController();
  final _established = TextEditingController();

  final _stocks = <ShopStock>{ShopStock.equipment};
  final _services = <ShopService>{};
  final _sports = <String>{};
  bool _isActive = true;

  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name, _headline, _about, _city, _district,
      _address, _pincode, _phone, _whatsapp, _hours, _established,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the form from the existing listing exactly once.
  ///
  /// Guarded by [_seeded] rather than done in `initState`, because the
  /// listing arrives on a stream and is usually still loading when the screen
  /// first builds — seeding on every build would overwrite what the owner is
  /// typing the moment the stream re-emits.
  void _seed(SportsShop shop, String? accountName) {
    if (_seeded) return;
    _seeded = true;
    _name.text = shop.shopName;
    _headline.text = shop.headline ?? '';
    _about.text = shop.about ?? '';
    _city.text = shop.city;
    _district.text = shop.district ?? '';
    _address.text = shop.address ?? '';
    _pincode.text = shop.pincode ?? '';
    _phone.text = shop.contactPhone ?? '';
    _whatsapp.text = shop.whatsappPhone ?? '';
    _hours.text = shop.hours ?? '';
    _established.text = shop.establishedYear?.toString() ?? '';
    _stocks
      ..clear()
      ..addAll(shop.stocks);
    _services
      ..clear()
      ..addAll(shop.services);
    _sports
      ..clear()
      ..addAll(shop.sportIds);
    _isActive = shop.isActive;
  }

  String? _validate() {
    if (_name.text.trim().length < 2) return 'Give the shop a name.';
    if (_city.text.trim().isEmpty) {
      return 'A city is what people search on — without one nobody finds you.';
    }
    if (_stocks.isEmpty) return 'Pick at least one thing you stock.';
    if (_phone.text.trim().length < 6 && _whatsapp.text.trim().length < 6) {
      return 'Add a phone or WhatsApp number, or nobody can reach you.';
    }
    return null;
  }

  Future<void> _save({required bool isNew}) async {
    final problem = _validate();
    final messenger = ScaffoldMessenger.of(context);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    final uid = ref.read(authUidProvider);
    if (uid == null) return;
    final me = ref.read(currentUserProvider).valueOrNull;

    setState(() => _saving = true);
    try {
      String? trimmed(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();

      await ref.read(sportsShopRepositoryProvider).saveMyShop(
            SportsShop(
              uid: uid,
              shopName: _name.text.trim(),
              ownerName: me?.displayName,
              headline: trimmed(_headline),
              about: trimmed(_about),
              stocks: _stocks.toList(),
              services: _services.toList(),
              sportIds: _sports.toList(),
              city: _city.text.trim(),
              district: trimmed(_district),
              address: trimmed(_address),
              pincode: trimmed(_pincode),
              contactPhone: trimmed(_phone),
              whatsappPhone: trimmed(_whatsapp),
              hours: trimmed(_hours),
              establishedYear: int.tryParse(_established.text.trim()),
              isActive: _isActive,
            ),
            isNew: isNew,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isNew ? 'Your shop is listed' : 'Listing updated'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = ref.watch(mySportsShopProvider);
    final existing = mine.valueOrNull;
    final isNew = existing == null;
    if (existing != null) {
      _seed(existing, ref.watch(currentUserProvider).valueOrNull?.displayName);
    }

    return AppScaffold(
      title: isNew ? 'List your shop' : 'Your shop listing',
      subtitle: 'Be found by clubs and players near you',
      body: mine.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                ContentBounds(
                  maxWidth: 640,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Field(
                        controller: _name,
                        label: 'Shop name',
                        hint: 'The name on the board outside',
                        capitalize: true,
                      ),
                      _Field(
                        controller: _headline,
                        label: 'One line about the shop (optional)',
                        hint: 'Cricket specialists since 1998',
                      ),

                      const _Heading(
                        title: 'What you stock',
                        note: 'The filter most people search on.',
                      ),
                      _Chips(
                        children: [
                          for (final s in ShopStock.values)
                            FilterChip(
                              label: Text('${s.emoji} ${s.label}'),
                              selected: _stocks.contains(s),
                              onSelected: (on) => setState(
                                () => on ? _stocks.add(s) : _stocks.remove(s),
                              ),
                            ),
                        ],
                      ),

                      const _Heading(
                        title: 'What you do',
                        note: 'Bulk club orders is the one clubs search for '
                            'most — tick it only if you actually take them.',
                      ),
                      _Chips(
                        children: [
                          for (final s in ShopService.values)
                            FilterChip(
                              label: Text(s.label),
                              selected: _services.contains(s),
                              onSelected: (on) => setState(
                                () =>
                                    on ? _services.add(s) : _services.remove(s),
                              ),
                            ),
                        ],
                      ),

                      const _Heading(
                        title: 'Sports you stock for',
                        note: 'Leave every one unticked if you sell across '
                            'all sports — that is a real answer, not a blank.',
                      ),
                      _Chips(
                        children: [
                          for (final s in SportCatalog.all)
                            FilterChip(
                              label: Text(s.name),
                              selected: _sports.contains(s.id),
                              onSelected: (on) => setState(
                                () => on
                                    ? _sports.add(s.id)
                                    : _sports.remove(s.id),
                              ),
                            ),
                        ],
                      ),

                      const _Heading(title: 'Where you are'),
                      _Field(
                        controller: _city,
                        label: 'City',
                        capitalize: true,
                      ),
                      _Field(
                        controller: _district,
                        label: 'District (optional)',
                        capitalize: true,
                      ),
                      _Field(
                        controller: _address,
                        label: 'Address (optional)',
                        maxLines: 2,
                        capitalize: true,
                      ),
                      _Field(
                        controller: _pincode,
                        label: 'PIN code (optional)',
                        keyboardType: TextInputType.number,
                      ),
                      _Field(
                        controller: _hours,
                        label: 'Opening hours (optional)',
                        hint: 'Mon-Sat 10am-9pm, Sunday closed',
                      ),
                      _Field(
                        controller: _established,
                        label: 'Year established (optional)',
                        keyboardType: TextInputType.number,
                      ),

                      const _Heading(
                        title: 'How to reach you',
                        note: 'At least one. A bulk order usually starts on '
                            'WhatsApp — a club sends a list and a photo.',
                      ),
                      _Field(
                        controller: _phone,
                        label: 'Shop phone',
                        keyboardType: TextInputType.phone,
                      ),
                      _Field(
                        controller: _whatsapp,
                        label: 'WhatsApp number',
                        keyboardType: TextInputType.phone,
                      ),

                      _Field(
                        controller: _about,
                        label: 'More about the shop (optional)',
                        maxLines: 4,
                      ),

                      if (!isNew)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: SwitchListTile(
                            title: const Text('Listed in the directory'),
                            subtitle: const Text(
                              'Turn this off while you are closed. Nothing is '
                              'deleted and you can switch it back on.',
                            ),
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Your listing is public, including the numbers '
                          'above. PlaySphere does not check prices or service '
                          '— nothing here is a recommendation.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: FilledButton(
                          onPressed: _saving ? null : () => _save(isNew: isNew),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(isNew ? 'List my shop' : 'Save changes'),
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

class _Heading extends StatelessWidget {
  const _Heading({required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Wrap(spacing: 6, runSpacing: 6, children: children),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.capitalize = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool capitalize;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textCapitalization: capitalize
              ? TextCapitalization.words
              : TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
