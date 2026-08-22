import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/providers.dart';
import '../../data/image_composer.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/image_upload.dart';
import '../../shared/ps_banner.dart';

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
                        // Somebody choosing between two grounds an hour apart
                        // is choosing on the strength of a picture. `photoUrl`
                        // had been on the model since grounds shipped and was
                        // read by nothing.
                        PsBanner(
                          imageUrl: ground.photoUrl,
                          sportId: ground.sportIds.length == 1
                              ? ground.sportIds.first
                              : null,
                          seed: ground.id,
                          fallbackIcon: Icons.stadium_outlined,
                          fallbackColor: const Color(0xFF15803D),
                          height: 168,
                          trailing: isOwner
                              ? _PhotoButton(
                                  onTap: () => _changePhoto(
                                    context,
                                    ref,
                                    groundId: ground.id,
                                    ownerUid: ground.ownerUid,
                                    hasPhoto: ground.photoUrl != null,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 14),
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

Future<void> _changePhoto(
  BuildContext context,
  WidgetRef ref, {
  required String groundId,
  required String ownerUid,
  required bool hasPhoto,
}) {
  final repo = ref.read(groundRepositoryProvider);
  return pickAndUploadImage(
    context: context,
    title: 'Ground photo',
    shape: ImageShape.banner,
    successMessage: 'Photo updated.',
    removedMessage: 'Photo removed.',
    onUpload: (image) => repo.uploadGroundPhoto(
      groundId: groundId,
      // The owner's own uid, which is both the Storage path segment and the
      // Firestore gate on `grounds/{groundId}`.
      uid: ownerUid,
      bytes: image.bytes,
      contentType: image.contentType,
    ),
    onRemove: hasPhoto ? () => repo.removeGroundPhoto(groundId) : null,
  );
}

/// Filled circle so the control stays legible over a photograph of unknown
/// brightness.
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8A000000),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: 'Change the photo',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}
