import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// Every food order this person has placed, across every ground.
class MyFoodOrdersScreen extends ConsumerWidget {
  const MyFoodOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myFoodOrdersProvider);

    return AppScaffold(
      title: 'My food orders',
      body: AsyncView(
        value: orders,
        onRetry: () => ref.invalidate(myFoodOrdersProvider),
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
                      icon: Icons.fastfood_outlined,
                      title: 'No orders yet',
                      message: 'Order water or a snack next time you\'re at a ground.',
                    )
                  else
                    for (final order in list)
                      Card(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: ListTile(
                          title: Text(order.lines.map((l) => '${l.quantity}× ${l.name}').join(', ')),
                          subtitle: Text(
                            '${order.groundName} · ${Pricing.formatPaise(order.amountPaidPaise)}',
                          ),
                          trailing: Chip(
                            label: Text(order.status.label),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
