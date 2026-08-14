import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// A single ground, previously a route that existed only as `Routes.ground`
/// with nothing registered behind it — booking has always happened through
/// `showGroundBookingSheet` from an event or from `GroundsScreen`, so no
/// screen ever needed a place to send a bare ground id. Food ordering does:
/// "order a bottle of water at the ground you are already at" has no event
/// to hang off, so this is that screen, and it stays deliberately thin.
class GroundDetailScreen extends ConsumerWidget {
  const GroundDetailScreen({super.key, required this.groundId});

  final String groundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ground = ref.watch(groundProvider(groundId)).valueOrNull;
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isOwner = me != null && ground != null && me.uid == ground.ownerUid;

    return AppScaffold(
      title: ground?.name ?? 'Ground',
      subtitle: ground?.city,
      actions: isOwner
          ? [
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: 'Food orders',
                onPressed: () => context.push('/grounds/$groundId/food/orders'),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Manage food menu',
                onPressed: () => context.push('/grounds/$groundId/food/manage'),
              ),
            ]
          : null,
      body: ground == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ContentBounds(
                  maxWidth: 700,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Chip(label: Text(ground.rateLabel)),
                            if (ground.isVerified)
                              const Chip(
                                avatar: Icon(Icons.verified, size: 16),
                                label: Text('Verified'),
                              ),
                            for (final f in ground.facilities) Chip(label: Text(f)),
                          ],
                        ),
                        if (ground.latitude != null &&
                            ground.longitude != null) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.map_outlined),
                              title: const Text('Open in Maps'),
                              subtitle: const Text('Get directions'),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () => launchUrl(
                                Uri.parse(
                                  'https://www.google.com/maps/search/'
                                  '?api=1&query=${ground.latitude},'
                                  '${ground.longitude}',
                                ),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.fastfood_outlined),
                            title: const Text('Order food & drinks'),
                            subtitle: const Text(
                              'Water, snacks and meals from this ground\'s canteen',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/grounds/$groundId/food'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
