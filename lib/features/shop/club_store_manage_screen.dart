import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/club_product.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../data/image_composer.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/image_upload.dart';
import '../../shared/ui_kit.dart';

/// The club's own catalog management view — add, edit, pause. Gated by
/// `firestore.rules`' `canManageOrg` (owner-only) on `clubProducts`, since
/// this is the one screen that sets a price.
class ClubStoreManageScreen extends ConsumerWidget {
  const ClubStoreManageScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(clubCatalogProvider(orgId));
    final org = ref.watch(organizationProvider(orgId)).valueOrNull;

    return AppScaffold(
      title: 'Manage catalog',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, org?.name ?? ''),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
      body: AsyncView(
        value: catalog,
        onRetry: () => ref.invalidate(clubCatalogProvider(orgId)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No products listed yet',
                    )
                  else
                    for (final product in list)
                      _CatalogTile(
                        product: product,
                        onEdit: () =>
                            _openEditor(context, ref, org?.name ?? '', product),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    String orgName, [
    ClubProduct? existing,
  ]) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _ProductEditorSheet(orgId: orgId, orgName: orgName, existing: existing),
    );
  }
}

class _CatalogTile extends ConsumerWidget {
  const _CatalogTile({required this.product, required this.onEdit});

  final ClubProduct product;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        leading: Text(product.category.emoji, style: const TextStyle(fontSize: 24)),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${Pricing.formatPaise(product.listPricePaise)} · ${product.isActive ? 'Active' : 'Paused'}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            Switch(
              value: product.isActive,
              onChanged: (v) => ref
                  .read(clubCommerceRepositoryProvider)
                  .setActive(product.id, v),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductEditorSheet extends ConsumerStatefulWidget {
  const _ProductEditorSheet({
    required this.orgId,
    required this.orgName,
    this.existing,
  });

  final String orgId;
  final String orgName;
  final ClubProduct? existing;

  @override
  ConsumerState<_ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends ConsumerState<_ProductEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _price = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.listPricePaise / 100).toStringAsFixed(0),
  );
  late final _sizes =
      TextEditingController(text: widget.existing?.sizes.join(', ') ?? '');
  late ClubProductCategory _category =
      widget.existing?.category ?? ClubProductCategory.jersey;
  bool _busy = false;

  /// Seeded from the product being edited and held here until save, so
  /// backing out of the sheet changes nothing.
  late String? _imageUrl = widget.existing?.imageUrl;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _sizes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    await pickAndUploadImage(
      context: context,
      title: 'Product photo',
      shape: ImageShape.banner,
      successMessage: 'Photo added.',
      onUpload: (image) async {
        final url =
            await ref.read(clubCommerceRepositoryProvider).uploadProductImage(
                  orgId: widget.orgId,
                  uid: me.uid,
                  bytes: image.bytes,
                  contentType: image.contentType,
                );
        if (mounted) setState(() => _imageUrl = url);
      },
    );
  }

  Future<void> _save() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    if (_name.text.trim().isEmpty) {
      showError(context, 'Give it a name.');
      return;
    }
    final rupees = double.tryParse(_price.text.trim()) ?? 0;
    setState(() => _busy = true);
    try {
      final sizes = _sizes.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      final repo = ref.read(clubCommerceRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.createProduct(
          ClubProduct(
            id: '',
            orgId: widget.orgId,
            orgName: widget.orgName,
            name: _name.text.trim(),
            description: _description.text.trim(),
            category: _category,
            listPricePaise: (rupees * 100).round(),
            sizes: sizes,
            imageUrl: _imageUrl,
          ),
          createdByUid: me.uid,
        );
      } else {
        await repo.updateProduct(ClubProduct(
          id: existing.id,
          orgId: existing.orgId,
          orgName: existing.orgName,
          name: _name.text.trim(),
          description: _description.text.trim(),
          category: _category,
          listPricePaise: (rupees * 100).round(),
          sizes: sizes,
          imageUrl: _imageUrl,
          isActive: existing.isActive,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            widget.existing == null ? 'Add product' : 'Edit product',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _PhotoRow(
            imageUrl: _imageUrl,
            emoji: _category.emoji,
            onPick: _pickPhoto,
            onClear:
                _imageUrl == null ? null : () => setState(() => _imageUrl = null),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in ClubProductCategory.values)
                ChoiceChip(
                  avatar: Text(c.emoji),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price (₹)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _sizes,
                  decoration: const InputDecoration(
                    labelText: 'Sizes (S, M, L)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (Pricing.introOfferActive) ...[
            const SizedBox(height: 8),
            Text(
              'Free for buyers during launch — this is the list price shown '
              'struck through, and what buyers will actually pay once the '
              'launch offer ends.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
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
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// The photo slot on the product form.
///
/// Optional, and says so. A club listing three jerseys from a phone at a
/// ground should be able to finish the form in a minute; the category emoji is
/// a perfectly good stand-in until somebody has time to take a picture.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.imageUrl,
    required this.emoji,
    required this.onPick,
    required this.onClear,
  });

  final String? imageUrl;
  final String emoji;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 64,
            height: 64,
            color: Ps.canvas,
            child: PsNetworkImage(
              url: imageUrl,
              fallback: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Photo (optional)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              const Text(
                'Skip it and the category icon is used.',
                style: TextStyle(fontSize: 12, color: Ps.muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(imageUrl == null ? 'Add photo' : 'Replace'),
                  ),
                  if (onClear != null)
                    TextButton(onPressed: onClear, child: const Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
