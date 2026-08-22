import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/ad_campaign.dart';
import '../../core/models/billing.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../data/image_composer.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import '../../shared/image_upload.dart';

/// The advertiser's own console: submit a campaign, see it through review.
///
/// There is no in-app approval screen on the other end of this — see
/// `AdRepository`'s class doc for why that mirrors Give's own precedent.
/// What ships here is the actual gap `lib/core/ads/promo.dart`'s file doc
/// named: a real submission path that fills the same [Promo] shape a house
/// promo already does.
class AdConsoleScreen extends ConsumerWidget {
  const AdConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(myAdCampaignsProvider);

    return AppScaffold(
      title: 'Advertise on PlaySphere',
      subtitle: 'Reach players by sport, club and ground',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New campaign'),
      ),
      body: AsyncView(
        value: campaigns,
        onRetry: () => ref.invalidate(myAdCampaignsProvider),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'PlaySphere knows the sport, the club and the ground —'
                      ' so a badminton player sees a badminton advert, never'
                      ' a generic one. Every campaign is reviewed before it'
                      ' goes live, and never shown to a minor or a Premium'
                      ' member.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No campaigns yet',
                    )
                  else
                    for (final campaign in list) _CampaignTile(campaign: campaign),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CampaignEditorSheet(),
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({required this.campaign});

  final AdCampaign campaign;

  Color _statusColor(BuildContext context) => switch (campaign.status) {
        AdCampaignStatus.approved => Colors.green,
        AdCampaignStatus.rejected => Colors.red,
        AdCampaignStatus.paused => Theme.of(context).hintColor,
        AdCampaignStatus.pending => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: PsNetworkImage(
                      url: campaign.imageUrl,
                      fallback: Center(
                        child: Text(campaign.emoji,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(campaign.headline,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Chip(
                  label: Text(campaign.status.label),
                  backgroundColor: _statusColor(context).withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: _statusColor(context)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(campaign.body, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final slot in campaign.slots)
                  Chip(label: Text(slot.name), visualDensity: VisualDensity.compact),
              ],
            ),
            if (campaign.isLive) ...[
              const SizedBox(height: 8),
              Text(
                '${campaign.impressions} views · ${campaign.clicks} clicks',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CampaignEditorSheet extends ConsumerStatefulWidget {
  const _CampaignEditorSheet();

  @override
  ConsumerState<_CampaignEditorSheet> createState() => _CampaignEditorSheetState();
}

class _CampaignEditorSheetState extends ConsumerState<_CampaignEditorSheet> {
  final _advertiserName = TextEditingController();
  final _headline = TextEditingController();
  final _body = TextEditingController();
  final _emoji = TextEditingController(text: '📣');
  final _ctaLabel = TextEditingController(text: 'Learn more');
  final _sport = TextEditingController();
  final _budget = TextEditingController();
  final Set<PromoSlot> _slots = {PromoSlot.home};
  bool _busy = false;

  /// Held here rather than written anywhere until submit, so an advertiser who
  /// picks artwork and then closes the sheet has changed nothing.
  String? _imageUrl;

  @override
  void dispose() {
    _advertiserName.dispose();
    _headline.dispose();
    _body.dispose();
    _emoji.dispose();
    _ctaLabel.dispose();
    _sport.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _pickCreative() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    await pickAndUploadImage(
      context: context,
      title: 'Campaign artwork',
      shape: ImageShape.square,
      successMessage: 'Artwork added.',
      onUpload: (image) async {
        final url = await ref.read(adRepositoryProvider).uploadCreative(
              advertiserUid: me.uid,
              bytes: image.bytes,
              contentType: image.contentType,
            );
        if (mounted) setState(() => _imageUrl = url);
      },
    );
  }

  Future<void> _submit() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    if (_headline.text.trim().isEmpty || _advertiserName.text.trim().isEmpty) {
      showError(context, 'Give it a business name and a headline.');
      return;
    }
    if (_slots.isEmpty) {
      showError(context, 'Pick at least one slot.');
      return;
    }
    setState(() => _busy = true);
    try {
      final rupees = double.tryParse(_budget.text.trim()) ?? 0;
      await ref.read(adRepositoryProvider).submit(
            AdCampaign(
              id: '',
              advertiserUid: me.uid,
              advertiserName: _advertiserName.text.trim(),
              headline: _headline.text.trim(),
              body: _body.text.trim(),
              emoji: _emoji.text.trim().isEmpty ? '📣' : _emoji.text.trim(),
              // Optional. A campaign with no artwork runs on its emoji, which
              // is what every house promotion does.
              imageUrl: _imageUrl,
              ctaLabel: _ctaLabel.text.trim().isEmpty ? 'Learn more' : _ctaLabel.text.trim(),
              sportIds: _sport.text.trim().isEmpty ? const [] : [_sport.text.trim()],
              slots: _slots.toList(growable: false),
              budgetPaise: (rupees * 100).round(),
            ),
            advertiserUid: me.uid,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Submitted for review. You\'ll see it here once approved.'),
      ));
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New campaign',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _advertiserName,
              decoration: const InputDecoration(
                labelText: 'Business / brand name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _CreativeRow(
              imageUrl: _imageUrl,
              emoji: _emoji.text,
              onPick: _pickCreative,
              onClear: _imageUrl == null
                  ? null
                  : () => setState(() => _imageUrl = null),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _emoji,
                    decoration: const InputDecoration(
                      labelText: 'Emoji',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _headline,
                    decoration: const InputDecoration(
                      labelText: 'Headline',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Body',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctaLabel,
                    decoration: const InputDecoration(
                      labelText: 'Button label',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sport,
                    decoration: const InputDecoration(
                      labelText: 'Sport (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Where should this show?',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final slot in PromoSlot.values)
                  FilterChip(
                    label: Text(slot.name),
                    selected: _slots.contains(slot),
                    onSelected: (sel) => setState(
                      () => sel ? _slots.add(slot) : _slots.remove(slot),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _budget,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Budget quoted (₹, informational)',
                border: OutlineInputBorder(),
              ),
            ),
            if (Pricing.introOfferActive) ...[
              const SizedBox(height: 8),
              Text(
                'Campaigns are free while PlaySphere is in launch — nothing '
                'is charged for this today.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
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
                  : const Text('Submit for review'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The artwork slot on the campaign form.
///
/// Explicitly labelled optional. An advertiser is the one person in the
/// product with a commercial reason to be nagged into uploading something, and
/// nagging them is still the wrong call: a campaign that runs on its emoji is
/// a complete campaign, and a required upload is how a small shop in a
/// district town abandons the form.
class _CreativeRow extends StatelessWidget {
  const _CreativeRow({
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
            width: 56,
            height: 56,
            color: Ps.canvas,
            child: PsNetworkImage(
              url: imageUrl,
              fallback: Center(
                child: Text(
                  emoji.trim().isEmpty ? '📣' : emoji.trim(),
                  style: const TextStyle(fontSize: 26),
                ),
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
                'Artwork (optional)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              const Text(
                'Skip it and your emoji is used instead.',
                style: TextStyle(fontSize: 12, color: Ps.muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(imageUrl == null ? 'Add artwork' : 'Replace'),
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
