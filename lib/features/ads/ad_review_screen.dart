/// Where an advertiser's submission actually lands.
///
/// ## The gap this closes
///
/// `AdConsoleScreen` let anybody submit a campaign, `firestore.rules` let only
/// the `admin` claim approve one, and in between there was nothing: a campaign
/// was created `pending` and no screen in the product could read the pending
/// queue, so the only way to approve an ad was the Firebase console — and
/// nobody was told an ad had arrived at all. An advertiser's submission was,
/// from the product's point of view, sent nowhere.
///
/// This is the destination. `onAdCampaignSubmitted` in `functions/index.js` is
/// what puts it on somebody's phone; `platformStaff` (see `StaffMember`) is
/// what gives that function a recipient to send to.
///
/// ## Why rejection asks for a reason
///
/// An advertiser whose campaign is rejected with no note has one recourse,
/// which is to ask a human — and there is one human. A required note is
/// cheaper for the reviewer than the support conversation it prevents, and
/// `AdRepository.review` clears it on approval so it cannot outlive the
/// decision it explains.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/ad_campaign.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/identity.dart';

class AdReviewScreen extends ConsumerStatefulWidget {
  const AdReviewScreen({super.key});

  @override
  ConsumerState<AdReviewScreen> createState() => _AdReviewScreenState();
}

class _AdReviewScreenState extends ConsumerState<AdReviewScreen> {
  /// The queue order is the reviewer's day: everything waiting, then what is
  /// running, then the decisions already made. Rejected sits last because it
  /// is the one nobody needs to revisit on a normal morning.
  static const _tabs = [
    AdCampaignStatus.pending,
    AdCampaignStatus.approved,
    AdCampaignStatus.paused,
    AdCampaignStatus.rejected,
  ];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isPlatformAdminProvider);

    return AppScaffold(
      title: 'Advertising requests',
      subtitle: 'Campaigns waiting on a decision',
      body: isAdmin.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AsyncErrorStrip(value: isAdmin, what: 'your access'),
        data: (admin) {
          // Checked here only so the screen does not present a queue it
          // cannot load — `firestore.rules` is the actual gate, same posture
          // as `GroundReviewScreen`.
          if (!admin) {
            return const EmptyState(
              icon: Icons.lock_outline,
              title: 'PlaySphere staff only',
              message:
                  'This is where advertiser campaigns are approved, paused '
                  'or turned down.',
            );
          }
          return _buildQueue(context);
        },
      ),
    );
  }

  Widget _buildQueue(BuildContext context) {
    final status = _tabs[_tab];
    final queue = ref.watch(adReviewQueueProvider(status));
    final pending =
        ref.watch(adReviewQueueProvider(AdCampaignStatus.pending)).valueOrNull;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        _tabs[i] == AdCampaignStatus.pending &&
                                (pending?.isNotEmpty ?? false)
                            ? 'Awaiting review (${pending!.length})'
                            : _tabs[i].label,
                      ),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: AsyncView(
            value: queue,
            onRetry: () => ref.invalidate(adReviewQueueProvider(status)),
            skeleton: const PsListSkeleton(),
            builder: (campaigns) {
              if (campaigns.isEmpty) {
                return EmptyState(
                  icon: status == AdCampaignStatus.pending
                      ? Icons.inbox_outlined
                      : Icons.campaign_outlined,
                  title: status == AdCampaignStatus.pending
                      ? 'Nothing waiting'
                      : 'No ${status.label.toLowerCase()} campaigns',
                  message: status == AdCampaignStatus.pending
                      ? 'Every campaign submitted so far has been decided.'
                      : null,
                );
              }
              return ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 32),
                children: [
                  ContentBounds(
                    maxWidth: 760,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final c in campaigns) _ReviewCard(campaign: c),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.campaign});

  final AdCampaign campaign;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    AdCampaignStatus to,
  ) async {
    String? note;

    // Approval is the one decision that needs no explanation — the advertiser
    // sees the result on the shelf. Everything else takes something away and
    // owes a reason.
    if (to != AdCampaignStatus.approved) {
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => _NoteDialog(
          title: to == AdCampaignStatus.rejected
              ? 'Turn down this campaign'
              : 'Pause this campaign',
          action: to == AdCampaignStatus.rejected ? 'Turn down' : 'Pause',
        ),
      );
      if (note == null || !context.mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adRepositoryProvider).review(
            campaign.id,
            status: to,
            reviewNote: note,
          );
      messenger.showSnackBar(
        SnackBar(content: Text('Campaign ${to.label.toLowerCase()}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final created = campaign.createdAt;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The banner as it will actually appear. A reviewer approving
            // from a summary of fields is approving something they have not
            // seen — this is the artefact, not a description of it.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (campaign.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PsNetworkImage(
                        url: campaign.imageUrl,
                        width: 64,
                        height: 64,
                        fallback: Text(campaign.emoji,
                            style: const TextStyle(fontSize: 30)),
                      ),
                    )
                  else
                    Text(campaign.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          campaign.headline,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(campaign.body,
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Text(
                          campaign.ctaLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Text(
              campaign.advertiserName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              [
                if (created != null)
                  'Submitted ${DateFormat('d MMM, h:mm a').format(created)}',
                if (campaign.budgetPaise > 0)
                  'Quoted \u{20B9}${(campaign.budgetPaise / 100).round()}',
              ].join(' · '),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),

            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final slot in campaign.slots)
                  Chip(
                    label: Text(_slotLabel(slot)),
                    avatar: const Icon(Icons.view_carousel_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                for (final sport in campaign.sportIds.take(4))
                  Chip(
                    label: Text(sport),
                    visualDensity: VisualDensity.compact,
                  ),
                if (campaign.isLive)
                  Chip(
                    label: Text(
                      '${campaign.impressions} seen · ${campaign.clicks} tapped',
                    ),
                    avatar: const Icon(Icons.insights_outlined, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),

            // The single field most worth a second look before approving:
            // it is the only part of a campaign that moves the viewer
            // somewhere, and rules constrain it to an in-app path but not to
            // a path that exists.
            if (campaign.destination != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.link, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      campaign.destination!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],

            if (campaign.reviewNote != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  campaign.reviewNote!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],

            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (campaign.status != AdCampaignStatus.approved)
                  FilledButton.icon(
                    onPressed: () =>
                        _decide(context, ref, AdCampaignStatus.approved),
                    icon: const Icon(Icons.check),
                    label: Text(
                      campaign.status == AdCampaignStatus.pending
                          ? 'Approve'
                          : 'Put back live',
                    ),
                  ),
                if (campaign.status == AdCampaignStatus.approved)
                  OutlinedButton.icon(
                    onPressed: () =>
                        _decide(context, ref, AdCampaignStatus.paused),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (campaign.status != AdCampaignStatus.rejected)
                  TextButton.icon(
                    onPressed: () =>
                        _decide(context, ref, AdCampaignStatus.rejected),
                    icon: const Icon(Icons.block),
                    label: const Text('Turn down'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _slotLabel(PromoSlot slot) => switch (slot) {
      PromoSlot.home => 'Home',
      PromoSlot.events => 'Events',
      PromoSlot.shop => 'Shop',
      PromoSlot.grounds => 'Grounds',
    };

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.action});

  final String title;
  final String action;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The advertiser is shown this, so say what would need to change.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. the destination link goes nowhere',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _note.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
