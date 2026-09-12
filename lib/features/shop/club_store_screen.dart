import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/billing.dart';
import '../../core/models/club_product.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

/// One club's own storefront — its active products, buyable directly,
/// distinct from the curated vendor catalog at [Routes.shop]. See
/// `ClubProduct`'s class doc.
class ClubStoreScreen extends ConsumerWidget {
  const ClubStoreScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(clubActiveProductsProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;
    final canManage =
        ref.watch(myCapabilitiesProvider(orgId)).contains(Capability.manageOrganization);

    return AppScaffold(
      title: org?.name ?? 'Club store',
      subtitle: 'Official merchandise',
      actions: canManage
          ? [
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: 'Orders',
                onPressed: () => context.push('/org/$orgId/store/orders'),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Manage catalog',
                onPressed: () => context.push('/org/$orgId/store/manage'),
              ),
            ]
          : null,
      body: AsyncView(
        value: products,
        onRetry: () => ref.invalidate(clubActiveProductsProvider(orgId)),
        builder: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No products yet',
                message: canManage
                    ? 'Add your club\'s first jersey or kit from "Manage catalog".'
                    : 'Check back once the club lists something.',
              )
            : GridView(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                children: [
                  for (final product in list)
                    _ProductCard(orgId: orgId, product: product),
                ],
              ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.orgId, required this.product});

  final String orgId;
  final ClubProduct product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = Pricing.productPricePaise(product.listPricePaise);
    final onOffer = price != product.listPricePaise;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openBuySheet(context, product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: PsNetworkImage(
                url: product.imageUrl,
                fallback: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Text(product.category.emoji,
                        style: const TextStyle(fontSize: 40)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (onOffer)
                        Text(
                          Pricing.formatPaise(product.listPricePaise),
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: theme.hintColor,
                          ),
                        ),
                      if (onOffer) const SizedBox(width: 6),
                      Text(
                        Pricing.formatPaise(price),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBuySheet(BuildContext context, ClubProduct product) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BuySheet(orgId: orgId, product: product),
    );
  }
}

class _BuySheet extends ConsumerStatefulWidget {
  const _BuySheet({required this.orgId, required this.product});

  final String orgId;
  final ClubProduct product;

  @override
  ConsumerState<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends ConsumerState<_BuySheet> {
  String? _size;
  int _quantity = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _size = widget.product.sizes.isNotEmpty ? widget.product.sizes.first : null;
  }

  Future<void> _placeOrder() async {
    final me = ref.read(authUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    try {
      final price = Pricing.productPricePaise(widget.product.listPricePaise);
      await ref.read(clubCommerceRepositoryProvider).placeOrder(ClubOrder(
            id: '',
            orgId: widget.orgId,
            orgName: widget.product.orgName,
            productId: widget.product.id,
            productName: widget.product.name,
            size: _size,
            quantity: _quantity,
            buyerUid: me.uid,
            buyerName: me.displayName,
            unitListPricePaise: widget.product.listPricePaise,
            amountPaidPaise: price * _quantity,
          ));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          price == 0
              ? 'Order placed — free during launch. The club will confirm it.'
              : 'Order placed. The club will confirm it.',
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
    final theme = Theme.of(context);
    final price = Pricing.productPricePaise(widget.product.listPricePaise);
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
          Text(widget.product.name,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (widget.product.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.product.description),
          ],
          const SizedBox(height: 12),
          if (widget.product.sizes.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final s in widget.product.sizes)
                  ChoiceChip(
                    label: Text(s),
                    selected: _size == s,
                    onSelected: (_) => setState(() => _size = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const Text('Quantity'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              Text('$_quantity'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _quantity++),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _placeOrder,
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
                : Text('Order — ${Pricing.formatPaise(price * _quantity)}'),
          ),
        ],
      ),
    );
  }
}
