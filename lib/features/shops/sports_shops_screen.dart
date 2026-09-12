/// Find a local sports shop.
///
/// The fourth public directory in the product, after grounds, coaches and
/// practitioners, and built to the same shape on purpose — a filter row, a
/// search box, a list — because a club secretary pricing twenty jerseys and a
/// parent looking for a physiotherapist are doing the same thing, and a
/// directory that answered it with a different control would read as a
/// different product.
///
/// See `SportsShop`'s class doc for why this is not the `products` catalogue
/// and not a club store. Nothing is bought here: the useful thing PlaySphere
/// can provide is the introduction, and the transaction that matters in this
/// market is a bulk order negotiated at the counter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sports_shop.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

class SportsShopsScreen extends ConsumerStatefulWidget {
  const SportsShopsScreen({super.key, this.initialSportId});

  /// Set when a sport hub sends somebody here, so the list arrives already
  /// scoped — same courtesy `CoachesScreen` extends.
  final String? initialSportId;

  @override
  ConsumerState<SportsShopsScreen> createState() => _SportsShopsScreenState();
}

class _SportsShopsScreenState extends ConsumerState<SportsShopsScreen> {
  final _words = TextEditingController();
  final _city = TextEditingController();

  @override
  void initState() {
    super.initState();
    final sportId = widget.initialSportId;
    if (sportId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _set(sportId: () => sportId);
    });
  }

  @override
  void dispose() {
    _words.dispose();
    _city.dispose();
    super.dispose();
  }

  void _set({
    String? keywords,
    String? city,
    ShopStock? Function()? stock,
    ShopService? Function()? service,
    String? Function()? sportId,
  }) {
    final q = ref.read(shopQueryProvider);
    ref.read(shopQueryProvider.notifier).state = (
      keywords: keywords ?? q.keywords,
      city: city ?? q.city,
      stock: stock != null ? stock() : q.stock,
      service: service != null ? service() : q.service,
      sportId: sportId != null ? sportId() : q.sportId,
    );
  }

  bool get _asked {
    final q = ref.read(shopQueryProvider);
    return q.keywords.trim().isNotEmpty ||
        q.city.trim().isNotEmpty ||
        q.stock != null ||
        q.service != null ||
        q.sportId != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = ref.watch(shopQueryProvider);
    final results = ref.watch(sportsShopSearchProvider);
    final mine = ref.watch(mySportsShopProvider).valueOrNull;
    final signedIn = ref.watch(currentUidProvider) != null;

    return AppScaffold(
      title: 'Sports shops',
      subtitle: 'Kit, gear and team orders near you',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _words,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Shop name, area, or a sport',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) => _set(keywords: v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) => _set(city: v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: query.sportId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Sport',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Any sport'),
                            ),
                            for (final s in SportCatalog.all)
                              DropdownMenuItem(
                                  value: s.id, child: Text(s.name)),
                          ],
                          onChanged: (v) => _set(sportId: () => v),
                        ),
                      ),
                    ],
                  ),
                ),

                // What they sell.
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: [
                        for (final s in ShopStock.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text('${s.emoji} ${s.label}'),
                              selected: query.stock == s,
                              onSelected: (on) =>
                                  _set(stock: () => on ? s : null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // What they do. Kept as a second row rather than merged with
                // the one above: "sells footwear" and "does club orders" are
                // different questions, and a club buying a season's kit is
                // asking the second one.
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final s in ShopService.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(s.label),
                            selected: query.service == s,
                            onSelected: (on) =>
                                _set(service: () => on ? s : null),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                results.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: PsListSkeleton(),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: EmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load shops',
                      message: errorMessage(e),
                    ),
                  ),
                  data: (shops) {
                    if (!_asked) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'Search for a shop',
                          message:
                              'Type a city, or pick what you need — bulk club '
                              'orders, racket stringing, names and numbers on '
                              'jerseys.',
                        ),
                      );
                    }
                    if (shops.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'No shops match yet',
                          message:
                              'Try a nearby city, or clear a filter. This '
                              'directory is only as good as the shops on it.',
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text(
                            '${shops.length} shop${shops.length == 1 ? '' : 's'}',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ),
                        for (final shop in shops) _ShopCard(shop: shop),
                      ],
                    );
                  },
                ),

                // The registration door, below the list — same placement as
                // the officials directory, and for the same reason: far more
                // people arrive needing a shop than owning one.
                if (signedIn) _ListYourShopCard(alreadyListed: mine != null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});

  final SportsShop shop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        onTap: () => context.push(Routes.sportsShop(shop.uid)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PsCrest(
                    name: shop.shopName,
                    logoUrl: shop.logoUrl,
                    seed: shop.uid,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                shop.shopName,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (shop.isVerified) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified,
                                  size: 15, color: Color(0xFF16A34A)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          shop.subtitleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (shop.headline != null && shop.headline!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  shop.headline!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (shop.services.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in shop.services.take(4))
                      Chip(
                        label: Text(s.label),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: s == ShopService.clubOrders
                            ? theme.colorScheme.primaryContainer
                            : null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ListYourShopCard extends StatelessWidget {
  const _ListYourShopCard({required this.alreadyListed});

  final bool alreadyListed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alreadyListed ? 'Your shop is listed' : 'Do you run a shop?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              alreadyListed
                  ? 'Update what you stock, the services you offer, or take '
                      'the listing down while you are closed.'
                  : 'List it once and every club in your district can find '
                      'you when they need a season of kit.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.push(Routes.mySportsShop),
              icon: Icon(alreadyListed ? Icons.edit_outlined : Icons.add),
              label: Text(
                alreadyListed ? 'Edit my listing' : 'List your shop',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
