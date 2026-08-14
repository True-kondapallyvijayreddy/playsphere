import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/enums.dart';
import '../../core/models/food_order.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// The ground's fulfilment queue for food orders. Gated by the ground-owner
/// check in `firestore.rules`.
class GroundFoodOrdersScreen extends ConsumerWidget {
  const GroundFoodOrdersScreen({super.key, required this.groundId});

  final String groundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(groundFoodOrdersProvider(groundId));

    return AppScaffold(
      title: 'Food orders',
      body: AsyncView(
        value: orders,
        onRetry: () => ref.invalidate(groundFoodOrdersProvider(groundId)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.isEmpty)
                    const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet')
                  else
                    for (final order in list) _OrderTile(order: order),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});

  final FoodOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.lines.map((l) => '${l.quantity}× ${l.name}').join(', '),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(label: Text(order.status.label), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${order.buyerName} · ${Pricing.formatPaise(order.amountPaidPaise)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (!order.status.isTerminal) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  if (order.status == FoodOrderStatus.placed)
                    FilledButton.tonal(
                      onPressed: () => ref
                          .read(foodRepositoryProvider)
                          .updateOrderStatus(order.id, status: 'preparing'),
                      child: const Text('Start preparing'),
                    ),
                  if (order.status == FoodOrderStatus.preparing)
                    FilledButton.tonal(
                      onPressed: () => ref
                          .read(foodRepositoryProvider)
                          .updateOrderStatus(order.id, status: 'out_for_delivery'),
                      child: const Text('Send it out'),
                    ),
                  if (order.status == FoodOrderStatus.outForDelivery)
                    FilledButton(
                      onPressed: () => ref
                          .read(foodRepositoryProvider)
                          .updateOrderStatus(order.id, status: 'delivered'),
                      child: const Text('Mark delivered'),
                    ),
                  OutlinedButton(
                    onPressed: () => ref
                        .read(foodRepositoryProvider)
                        .updateOrderStatus(order.id, status: 'cancelled'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
