import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/enums.dart';
import '../../core/models/food_order.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// The ground owner's canteen menu management — add, edit, pause. Gated by
/// `firestore.rules`' ground-owner check on `groundMenuItems`.
class GroundFoodManageScreen extends ConsumerWidget {
  const GroundFoodManageScreen({super.key, required this.groundId});

  final String groundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(groundFullMenuProvider(groundId));
    final ground = ref.watch(groundProvider(groundId)).valueOrNull;

    return AppScaffold(
      title: 'Manage food menu',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ground?.name ?? ''),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: AsyncView(
        value: menu,
        onRetry: () => ref.invalidate(groundFullMenuProvider(groundId)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.fastfood_outlined,
                      title: 'Nothing listed yet',
                    )
                  else
                    for (final item in list)
                      _ItemTile(
                        item: item,
                        onEdit: () => _openEditor(context, ground?.name ?? '', item),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    String groundName, [
    GroundMenuItem? existing,
  ]) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _ItemEditorSheet(groundId: groundId, groundName: groundName, existing: existing),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item, required this.onEdit});

  final GroundMenuItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: Text(item.category.emoji, style: const TextStyle(fontSize: 24)),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${Pricing.formatPaise(item.priceInPaise)} · ${item.isActive ? 'Active' : 'Paused'}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
            Switch(
              value: item.isActive,
              onChanged: (v) =>
                  ref.read(foodRepositoryProvider).setMenuItemActive(item.id, v),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEditorSheet extends ConsumerStatefulWidget {
  const _ItemEditorSheet({
    required this.groundId,
    required this.groundName,
    this.existing,
  });

  final String groundId;
  final String groundName;
  final GroundMenuItem? existing;

  @override
  ConsumerState<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends ConsumerState<_ItemEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _price = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.priceInPaise / 100).toStringAsFixed(0),
  );
  late FoodItemCategory _category = widget.existing?.category ?? FoodItemCategory.water;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final me = ref.read(authUserProvider).valueOrNull;
    if (me == null) return;
    if (_name.text.trim().isEmpty) {
      showError(context, 'Give it a name.');
      return;
    }
    final rupees = double.tryParse(_price.text.trim()) ?? 0;
    setState(() => _busy = true);
    try {
      final repo = ref.read(foodRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.addMenuItem(
          GroundMenuItem(
            id: '',
            groundId: widget.groundId,
            groundName: widget.groundName,
            name: _name.text.trim(),
            category: _category,
            priceInPaise: (rupees * 100).round(),
          ),
          createdByUid: me.uid,
        );
      } else {
        await repo.updateMenuItem(GroundMenuItem(
          id: existing.id,
          groundId: existing.groundId,
          groundName: existing.groundName,
          name: _name.text.trim(),
          category: _category,
          priceInPaise: (rupees * 100).round(),
          isActive: existing.isActive,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'Add item' : 'Edit item',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in FoodItemCategory.values)
                ChoiceChip(
                  avatar: Text(c.emoji),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder()),
          ),
          if (Pricing.introOfferActive) ...[
            const SizedBox(height: 8),
            Text(
              'Free for buyers during launch — this is the list price.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
