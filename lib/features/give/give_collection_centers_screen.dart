import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/give_collection_center.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// Drop-off points, searchable by city — the physical half of Give. See
/// `GiveCollectionCenter` for why these are curated rather than self-listed.
class GiveCollectionCentersScreen extends ConsumerStatefulWidget {
  const GiveCollectionCentersScreen({super.key});

  @override
  ConsumerState<GiveCollectionCentersScreen> createState() =>
      _GiveCollectionCentersScreenState();
}

class _GiveCollectionCentersScreenState
    extends ConsumerState<GiveCollectionCentersScreen> {
  final _cityController = TextEditingController();
  String? _city;

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centers = ref.watch(giveCollectionCentersProvider(_city));

    return AppScaffold(
      title: 'Collection centres',
      subtitle: 'Drop off equipment near you',
      body: AsyncView(
        value: centers,
        onRetry: () => ref.invalidate(giveCollectionCentersProvider(_city)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      controller: _cityController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'City',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _cityController.text.isEmpty
                            ? null
                            : IconButton(
                              tooltip: 'Clear',
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _cityController.clear();
                                  _city = null;
                                }),
                              ),
                      ),
                      onSubmitted: (v) => setState(
                        () => _city = v.trim().isEmpty ? null : v.trim(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    EmptyState(
                      icon: Icons.storefront_outlined,
                      title: _city == null
                          ? 'No collection centres listed yet'
                          : 'No centre in "$_city" yet',
                      message: 'PlaySphere Give is expanding city by city — '
                          'check back soon, or try a nearby city.',
                    )
                  else
                    for (final c in list) _CenterCard(center: c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({required this.center});

  final GiveCollectionCenter center;

  Future<void> _call(BuildContext context) async {
    final phone = center.contactPhone;
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      showError(context, 'Could not open the dialler.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    center.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${center.address ?? ''}${center.address == null ? '' : ', '}${center.city}'),
            if (center.acceptedCategories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in center.acceptedCategories)
                    Chip(
                      label: Text(c.label, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (center.contactPhone != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _call(context),
                icon: const Icon(Icons.call_outlined, size: 16),
                label: Text(center.contactPhone!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
