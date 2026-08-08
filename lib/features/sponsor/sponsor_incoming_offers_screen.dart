import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/sponsorship.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// A listing owner's inbox: every offer made against one listing, with
/// accept/decline for the ones still pending. `firestore.rules` on
/// `sponsorPledges` restricts accept/decline to exactly the listing's own
/// `createdByUid`, so this screen never needs to re-check ownership itself —
/// a stranger who somehow opens it would simply have every write refused.
class SponsorIncomingOffersScreen extends ConsumerWidget {
  const SponsorIncomingOffersScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pledges = ref.watch(pledgesForListingProvider(listingId));

    return AppScaffold(
      title: 'Offers',
      body: AsyncView(
        value: pledges,
        onRetry: () => ref.invalidate(pledgesForListingProvider(listingId)),
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ContentBounds(
              maxWidth: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No offers yet',
                      message:
                          'When a sponsor offers to back this listing, it '
                          'shows up here.',
                    )
                  else
                    for (final pledge in list) _OfferCard(pledge: pledge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.pledge});

  final SponsorPledge pledge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pending = pledge.status == SponsorPledgeStatus.pending;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pledge.anonymous ? 'An anonymous sponsor' : pledge.sponsorDisplayName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!pending)
                  Chip(
                    label: Text(pledge.status.label),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (pledge.offeredCategories.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in pledge.offeredCategories)
                    Chip(
                      avatar: Text(c.emoji),
                      label: Text(c.label),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (pledge.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(pledge.message, style: theme.textTheme.bodyMedium),
            ],
            if (pending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(sponsorRepositoryProvider)
                          .respondToPledge(pledge.id, accept: false),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => ref
                          .read(sponsorRepositoryProvider)
                          .respondToPledge(pledge.id, accept: true),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
