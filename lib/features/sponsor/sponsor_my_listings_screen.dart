import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/sponsorship.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Listings this person owns — as an athlete, or as a team's admin. Each
/// card links to the public listing and to its incoming-offers inbox.
class SponsorMyListingsScreen extends ConsumerWidget {
  const SponsorMyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(mySponsorshipListingsProvider);

    return AppScaffold(
      title: 'My listings',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.sponsorCreate),
        icon: const Icon(Icons.add),
        label: const Text('New listing'),
      ),
      body: AsyncView(
        value: listings,
        onRetry: () => ref.invalidate(mySponsorshipListingsProvider),
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
                      icon: Icons.campaign_outlined,
                      title: 'No listings yet',
                      message: 'Publish one and sponsors can find and back you.',
                    )
                  else
                    for (final listing in list) _MyListingCard(listing: listing),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyListingCard extends StatelessWidget {
  const _MyListingCard({required this.listing});

  final SponsorshipListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ListTile(
        title: Text(listing.headline, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${listing.status.label} · ${listing.sponsorsCount} sponsor${listing.sponsorsCount == 1 ? '' : 's'}',
        ),
        trailing: FilledButton.tonal(
          onPressed: () => context.push(Routes.sponsorOffers(listing.id)),
          child: const Text('Offers'),
        ),
        onTap: () => context.push(Routes.sponsorListing(listing.id)),
        tileColor: theme.colorScheme.surface,
      ),
    );
  }
}
