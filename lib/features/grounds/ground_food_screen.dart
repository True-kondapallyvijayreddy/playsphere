import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/food_order.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// One ground's canteen: browse, add to a running order, place it. See
/// `DeliveryPartner` for who actually hands it over.
class GroundFoodScreen extends ConsumerStatefulWidget {
  const GroundFoodScreen({super.key, required this.groundId});

  final String groundId;

  @override
  ConsumerState<GroundFoodScreen> createState() => _GroundFoodScreenState();
}

class _GroundFoodScreenState extends ConsumerState<GroundFoodScreen> {
  final Map<String, int> _cart = {}; // menuItemId -> quantity
  bool _busy = false;

  Future<void> _placeOrder(List<GroundMenuItem> menu) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null || _cart.isEmpty) return;
    final ground = ref.read(groundProvider(widget.groundId)).valueOrNull;
    setState(() => _busy = true);
    try {
      final lines = [
        for (final entry in _cart.entries)
          if (entry.value > 0)
            FoodOrderLine(
              menuItemId: entry.key,
              name: menu.firstWhere((m) => m.id == entry.key).name,
              quantity: entry.value,
              unitPricePaise: menu.firstWhere((m) => m.id == entry.key).priceInPaise,
            ),
      ];
      final total = lines.fold<int>(
        0,
        (sum, l) => sum + Pricing.productPricePaise(l.unitPricePaise) * l.quantity,
      );
      await ref.read(foodRepositoryProvider).placeOrder(FoodOrder(
            id: '',
            groundId: widget.groundId,
            groundName: ground?.name ?? '',
            lines: lines,
            buyerUid: me.uid,
            buyerName: me.displayName,
            amountPaidPaise: total,
          ));
      if (!mounted) return;
      setState(() => _cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          total == 0
              ? 'Order placed — free during launch. The ground will prepare it.'
              : 'Order placed.',
        ),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(groundActiveMenuProvider(widget.groundId));

    return AppScaffold(
      title: 'Food & drinks',
      body: AsyncView(
        value: menu,
        onRetry: () => ref.invalidate(groundActiveMenuProvider(widget.groundId)),
        builder: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.fastfood_outlined,
              title: 'No canteen menu here yet',
              message: 'This ground hasn\'t listed anything to order.',
            );
          }
          final total = items.fold<int>(
            0,
            (sum, item) =>
                sum +
                Pricing.productPricePaise(item.priceInPaise) * (_cart[item.id] ?? 0),
          );
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    ContentBounds(
                      maxWidth: 700,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in items) _MenuItemTile(
                              item: item,
                              quantity: _cart[item.id] ?? 0,
                              onChanged: (q) => setState(() => _cart[item.id] = q)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_cart.values.any((q) => q > 0))
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: FilledButton(
                      onPressed: _busy ? null : () => _placeOrder(items),
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
                          : Text('Place order — ${Pricing.formatPaise(total)}'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({
    required this.item,
    required this.quantity,
    required this.onChanged,
  });

  final GroundMenuItem item;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final price = Pricing.productPricePaise(item.priceInPaise);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: Text(item.category.emoji, style: const TextStyle(fontSize: 22)),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(Pricing.formatPaise(price)),
        trailing: quantity == 0
            ? OutlinedButton(
                onPressed: () => onChanged(1),
                child: const Text('Add'),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => onChanged(quantity - 1),
                  ),
                  Text('$quantity'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => onChanged(quantity + 1),
                  ),
                ],
              ),
      ),
    );
  }
}
