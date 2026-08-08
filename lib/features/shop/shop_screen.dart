import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/shop_product.dart';
import '../../core/providers.dart';
import '../../data/shop_repository.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/promo_banner.dart';

/// The PlaySphere shop.
///
/// A curated shelf of the kit the sports in this app actually need, pointing
/// at a retailer who holds the stock. See `ShopRepository` for why the
/// checkout is deliberately the vendor's rather than PlaySphere's.
///
/// The filter defaults to the sports the viewer plays. A cricketer opening
/// the shop should land on bats and balls, not on a general sports catalog —
/// that is the entire advantage PlaySphere has over a retailer's own app,
/// and burying it behind a dropdown would throw it away.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initialSportId});

  /// Arrives from a promo banner deep link (`/shop?sport=badminton`).
  final String? initialSportId;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  /// Null means "everything". Otherwise a sport id.
  String? _sportFilter;
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mySports = ref.watch(myPromoSportIdsProvider);
    final products = ref.watch(shopProductsProvider).valueOrNull;

    // Applied once, not on every build: a rebuild must not yank the filter
    // back to the default after the person has changed it.
    if (!_initialised) {
      _initialised = true;
      _sportFilter = widget.initialSportId ??
          (mySports.length == 1 ? mySports.first : null);
    }

    final all = products ?? DecathlonCatalog.all;
    final visible = _sportFilter == null
        ? _orderedForViewer(all, mySports)
        : all.where((p) => p.matchesSport(_sportFilter!)).toList(growable: false);

    final sportChips = <String>{...mySports, ..._sportsIn(all)}.toList();

    return AppScaffold(
      title: 'Shop',
      subtitle: 'Kit for every sport you play',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PromoBanner(
                  slot: PromoSlot.shop,
                  margin: EdgeInsets.fromLTRB(12, 12, 12, 4),
                ),

                // Says plainly who sells this and who does not. A player
                // handing over a card should never be unclear about whose
                // checkout they are standing in, and finding out at the
                // payment page is finding out too late.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sold and delivered by Decathlon. PlaySphere lists '
                          'the kit; the order, payment and returns are theirs.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _SportChip(
                        label: 'All sports',
                        selected: _sportFilter == null,
                        onTap: () => setState(() => _sportFilter = null),
                      ),
                      for (final s in sportChips)
                        _SportChip(
                          label: _sportLabel(s),
                          selected: _sportFilter == s,
                          onTap: () => setState(() => _sportFilter = s),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (visible.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Nothing listed for this sport yet',
                    message: 'Try another sport, or browse everything.',
                  )
                else
                  for (final p in visible) _ProductCard(product: p),

                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Prices are indicative and set by the vendor — check the '
                    'final price on their page before ordering. PlaySphere may '
                    'earn a commission on purchases made through these links.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Puts the viewer's own sports at the top of an unfiltered list.
  ///
  /// Same intent as the default filter, applied where a filter cannot be:
  /// somebody browsing "All sports" still plays two of them, and those two
  /// should not be forty items down.
  static List<ShopProduct> _orderedForViewer(
    List<ShopProduct> all,
    List<String> mySports,
  ) {
    if (mySports.isEmpty) return all;
    final mine = <ShopProduct>[];
    final rest = <ShopProduct>[];
    for (final p in all) {
      if (p.sportIds.any(mySports.contains)) {
        mine.add(p);
      } else {
        rest.add(p);
      }
    }
    return [...mine, ...rest];
  }

  static List<String> _sportsIn(List<ShopProduct> products) {
    final seen = <String>[];
    for (final p in products) {
      for (final s in p.sportIds) {
        if (!seen.contains(s)) seen.add(s);
      }
    }
    return seen;
  }

  /// `table_tennis` → `Table tennis`. The shop is the one screen that can
  /// meet a sport id it has no `SportSpec` for — a listing seeded into
  /// Firestore for a sport the app does not yet score — so it formats the id
  /// rather than looking it up and crashing.
  static String _sportLabel(String sportId) {
    final words = sportId.split('_');
    if (words.isEmpty) return sportId;
    final first = words.first;
    return [
      first.isEmpty ? first : first[0].toUpperCase() + first.substring(1),
      ...words.skip(1),
    ].join(' ');
  }
}

class _SportChip extends StatelessWidget {
  const _SportChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final ShopProduct product;

  /// Opens the vendor's page, after saying that is what is about to happen.
  ///
  /// The confirmation is not ceremony. Leaving the app is a real transition —
  /// a different company, a different cart, a different privacy policy — and
  /// a tap on a product card should not silently hand somebody to a third
  /// party's checkout without naming them first.
  Future<void> _openVendor(BuildContext context) async {
    final uri = Uri.tryParse(product.url);
    if (uri == null) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Open ${product.vendor}?'),
        content: Text(
          '${product.name} is sold by ${product.vendor}. You will leave '
          'PlaySphere and finish the order on their site — they take the '
          'payment and handle delivery and returns.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay here'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Open ${product.vendor}'),
          ),
        ],
      ),
    );
    if (go != true) return;

    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showError(
        context,
        'Could not open ${product.vendor}. Check your connection and try '
        'again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openVendor(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Text(product.emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (product.blurb != null) ...[
                      const SizedBox(height: 2),
                      Text(product.blurb!, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'from ${Pricing.formatPaise(product.pricePaise)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${product.vendor}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, size: 18, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}
