/// One shop's page — what they stock, what they do, and how to reach them.
///
/// The whole point of this screen is the two contact buttons. Nothing is
/// bought through PlaySphere (see `SportsShop`'s class doc), so the measure of
/// whether this page worked is whether a club secretary got through to
/// somebody who can quote them for twenty jerseys.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sports_shop.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

class SportsShopDetailScreen extends ConsumerWidget {
  const SportsShopDetailScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(sportsShopProvider(uid));

    return AppScaffold(
      title: shop.valueOrNull?.shopName ?? 'Sports shop',
      subtitle: shop.valueOrNull?.city,
      body: AsyncView(
        value: shop,
        onRetry: () => ref.invalidate(sportsShopProvider(uid)),
        builder: (s) => s == null
            ? const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'This shop is no longer listed',
                message: 'The owner may have taken it down.',
              )
            : _Body(shop: s),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.shop});

  final SportsShop shop;

  Future<void> _launch(BuildContext context, Uri uri, String what) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open $what')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = shop.contactPhone;
    final whatsapp = shop.whatsappPhone;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ContentBounds(
          maxWidth: 700,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    PsCrest(
                      name: shop.shopName,
                      logoUrl: shop.logoUrl,
                      seed: shop.uid,
                      size: 56,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  shop.shopName,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (shop.isVerified) ...[
                                const SizedBox(width: 5),
                                const Icon(Icons.verified,
                                    size: 17, color: Color(0xFF16A34A)),
                              ],
                            ],
                          ),
                          if (shop.headline != null &&
                              shop.headline!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                shop.headline!,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: theme.hintColor),
                              ),
                            ),
                          if (shop.establishedYear != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Since ${shop.establishedYear}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // The two buttons this page exists for.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  children: [
                    if (phone != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _launch(
                            context,
                            Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                            'the dialler',
                          ),
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: const Text('Call'),
                        ),
                      ),
                    if (phone != null && whatsapp != null)
                      const SizedBox(width: 10),
                    if (whatsapp != null)
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _launch(
                            context,
                            // wa.me wants digits only, no plus, no spaces.
                            Uri.parse(
                              'https://wa.me/'
                              '${whatsapp.replaceAll(RegExp(r'[^0-9]'), '')}',
                            ),
                            'WhatsApp',
                          ),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                  ],
                ),
              ),

              if (shop.about != null && shop.about!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Text(shop.about!, style: theme.textTheme.bodyMedium),
                ),

              _Block(
                title: 'Stocks',
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in shop.stocks)
                      Chip(
                        label: Text(s.label),
                        avatar: Text(s.emoji),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),

              if (shop.services.isNotEmpty)
                _Block(
                  title: 'Services',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in shop.services)
                        Chip(
                          label: Text(s.label),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: s == ShopService.clubOrders
                              ? theme.colorScheme.primaryContainer
                              : null,
                        ),
                    ],
                  ),
                ),

              _Block(
                title: 'Sports',
                child: shop.sportIds.isEmpty
                    ? Text(
                        'All sports',
                        style: theme.textTheme.bodyMedium,
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final id in shop.sportIds)
                            Chip(
                              label: Text(SportCatalog.byId(id).name),
                              avatar: Text(SportCatalog.byId(id).icon),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
              ),

              _Block(
                title: 'Where',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shop.address != null && shop.address!.isNotEmpty)
                      Text(shop.address!, style: theme.textTheme.bodyMedium),
                    Text(
                      [
                        shop.city,
                        if (shop.district != null) shop.district!,
                        if (shop.pincode != null) shop.pincode!,
                      ].where((s) => s.isNotEmpty).join(', '),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (shop.hours != null && shop.hours!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.schedule, size: 15),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(shop.hours!,
                                style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  shop.isVerified
                      ? 'PlaySphere has confirmed this shop exists at the '
                          'address given. That is not a statement about its '
                          'prices or its service.'
                      : 'PlaySphere has not checked this listing. Everything '
                          'on this page was entered by the shop.',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                theme.textTheme.labelLarge?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
