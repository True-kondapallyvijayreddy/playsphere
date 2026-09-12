import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/give_donation.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// The equipment donation form.
///
/// Money donations are deliberately not offered here — see
/// `GiveDonation.amountPaise` for why the pledge path waits on PlaySphere's
/// payment gateway, which is deferred product-wide. This screen only ever
/// writes `GiveDonationType.equipment` rows.
class GiveDonateScreen extends ConsumerStatefulWidget {
  const GiveDonateScreen({super.key});

  @override
  ConsumerState<GiveDonateScreen> createState() => _GiveDonateScreenState();
}

class _GiveDonateScreenState extends ConsumerState<GiveDonateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _city = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  /// category -> quantity. A map rather than a list of line editors: nobody
  /// donating a bat and two pairs of shoes needs a repeating-row form when a
  /// tappable grid of the fourteen categories with a stepper does the same
  /// job in fewer taps.
  final Map<EquipmentCategory, int> _quantities = {};

  bool _prefilled = false;
  bool _busy = false;

  @override
  void dispose() {
    _city.dispose();
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _prefillFromProfile() {
    if (_prefilled) return;
    final me = ref.read(authUserProvider).valueOrNull;
    if (me != null) {
      _name.text = me.displayName;
      _phone.text = me.phone ?? '';
    }
    _prefilled = true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_quantities.isEmpty) {
      showError(context, 'Add at least one item.');
      return;
    }
    final uid = ref.read(authUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final donation = GiveDonation(
        id: '',
        donorUid: uid,
        donorName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        donorPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        type: GiveDonationType.equipment,
        items: [
          for (final e in _quantities.entries)
            GiveItemLine(category: e.key, quantity: e.value),
        ],
        city: _city.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      final id =
          await ref.read(giveRepositoryProvider).submitDonation(donation);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Thank you — donation ${id.substring(0, 6).toUpperCase()} '
            'submitted. We\'ll confirm collection soon.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _prefillFromProfile();
    final theme = Theme.of(context);
    final totalItems = _quantities.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Donate equipment')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 640,
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What are you giving?',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to add an item, tap again to add more of it.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in EquipmentCategory.values)
                        _CategoryChip(
                          category: c,
                          quantity: _quantities[c] ?? 0,
                          onAdd: () => setState(
                            () => _quantities[c] = (_quantities[c] ?? 0) + 1,
                          ),
                          onRemove: () => setState(() {
                            final next = (_quantities[c] ?? 0) - 1;
                            if (next <= 0) {
                              _quantities.remove(c);
                            } else {
                              _quantities[c] = next;
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      helperText: 'So we can point you at a nearby centre',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (for pickup/drop-off coordination)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (condition, size, anything useful)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(totalItems == 0
                            ? 'Submit donation'
                            : 'Submit $totalItems item${totalItems == 1 ? '' : 's'}'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Staff will inspect, clean and safety-check every item '
                    'before it reaches anyone. You\'ll be able to see its '
                    'progress from "My donations".',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final EquipmentCategory category;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = quantity > 0;
    return InputChip(
      avatar: Text(category.emoji, style: const TextStyle(fontSize: 16)),
      label: Text(selected ? '${category.label} × $quantity' : category.label),
      selected: selected,
      showCheckmark: false,
      selectedColor: theme.colorScheme.primaryContainer,
      onPressed: onAdd,
      onDeleted: selected ? onRemove : null,
      deleteIcon: selected ? const Icon(Icons.remove_circle_outline, size: 18) : null,
    );
  }
}
