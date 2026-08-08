import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/sponsorship.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Every offer this person has made as a sponsor, newest first, with a
/// withdraw action while an offer is still pending.
class SponsorMyPledgesScreen extends ConsumerWidget {
  const SponsorMyPledgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pledges = ref.watch(myPledgesProvider);

    return AppScaffold(
      title: 'My sponsorships',
      body: AsyncView(
        value: pledges,
        onRetry: () => ref.invalidate(myPledgesProvider),
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
                      icon: Icons.volunteer_activism_outlined,
                      title: 'No offers made yet',
                      message: 'Browse listings and back someone directly.',
                    )
                  else
                    for (final pledge in list) _PledgeCard(pledge: pledge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PledgeCard extends ConsumerWidget {
  const _PledgeCard({required this.pledge});

  final SponsorPledge pledge;

  Color _statusColor(BuildContext context) => switch (pledge.status) {
        SponsorPledgeStatus.accepted => Colors.green,
        SponsorPledgeStatus.declined => Colors.red,
        SponsorPledgeStatus.withdrawn => Theme.of(context).hintColor,
        SponsorPledgeStatus.completed => Colors.blueGrey,
        SponsorPledgeStatus.pending => Colors.orange,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing =
        ref.watch(sponsorshipListingProvider(pledge.listingId)).valueOrNull;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        onTap: () => context.push(Routes.sponsorListing(pledge.listingId)),
        title: Text(listing?.headline ?? 'Listing'),
        subtitle: Text(
          pledge.message.isEmpty ? pledge.status.label : pledge.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: pledge.status == SponsorPledgeStatus.pending
            ? TextButton(
                onPressed: () => ref
                    .read(sponsorRepositoryProvider)
                    .withdrawPledge(pledge.id),
                child: const Text('Withdraw'),
              )
            : Chip(
                label: Text(pledge.status.label),
                backgroundColor: _statusColor(context).withValues(alpha: 0.15),
                labelStyle: TextStyle(color: _statusColor(context)),
                visualDensity: VisualDensity.compact,
              ),
      ),
    );
  }
}
