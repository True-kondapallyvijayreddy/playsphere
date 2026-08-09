import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/club_product.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// The club's fulfilment queue — every order placed against its store, with
/// confirm/fulfil/cancel. Gated by `canManageOrg` in `firestore.rules`.
class ClubStoreOrdersScreen extends ConsumerWidget {
  const ClubStoreOrdersScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(clubOrdersProvider(orgId));

    return AppScaffold(
      title: 'Store orders',
      body: AsyncView(
        value: orders,
        onRetry: () => ref.invalidate(clubOrdersProvider(orgId)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No orders yet',
                    )
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

  final ClubOrder order;

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
                    '${order.productName}${order.size != null ? ' (${order.size})' : ''} × ${order.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(order.status.label),
                  visualDensity: VisualDensity.compact,
                ),
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
                  if (order.status == ClubOrderStatus.placed)
                    FilledButton.tonal(
                      onPressed: () => ref
                          .read(clubCommerceRepositoryProvider)
                          .updateOrderStatus(order.id, status: 'confirmed'),
                      child: const Text('Confirm'),
                    ),
                  if (order.status == ClubOrderStatus.confirmed)
                    FilledButton(
                      onPressed: () => ref
                          .read(clubCommerceRepositoryProvider)
                          .updateOrderStatus(order.id, status: 'fulfilled'),
                      child: const Text('Mark delivered'),
                    ),
                  OutlinedButton(
                    onPressed: () => ref
                        .read(clubCommerceRepositoryProvider)
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
