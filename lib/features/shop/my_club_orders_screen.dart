import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// Every club-store order this person has placed, across every club.
class MyClubOrdersScreen extends ConsumerWidget {
  const MyClubOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myClubOrdersProvider);

    return AppScaffold(
      title: 'My orders',
      body: AsyncView(
        value: orders,
        onRetry: () => ref.invalidate(myClubOrdersProvider),
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
                      icon: Icons.shopping_bag_outlined,
                      title: 'No orders yet',
                      message: 'Visit a club\'s store from its dashboard to buy something.',
                    )
                  else
                    for (final order in list)
                      Card(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: ListTile(
                          title: Text(
                            '${order.productName}${order.size != null ? ' (${order.size})' : ''} × ${order.quantity}',
                          ),
                          subtitle: Text(
                            '${order.orgName} · ${Pricing.formatPaise(order.amountPaidPaise)}',
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
