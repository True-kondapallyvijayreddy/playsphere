import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/sponsorship.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../shared/app_scaffold.dart';

/// Browsing open sponsorship listings, filtered by target type, sport and
/// district. See `SponsorRepository.watchListings` — every result here has
/// already cleared `firestore.rules`' publish gate, so nothing shown is an
/// unpublished draft.
class SponsorBrowseScreen extends ConsumerStatefulWidget {
  const SponsorBrowseScreen({super.key});

  @override
  ConsumerState<SponsorBrowseScreen> createState() =>
      _SponsorBrowseScreenState();
}

class _SponsorBrowseScreenState extends ConsumerState<SponsorBrowseScreen> {
  final _sportController = TextEditingController();
  final _districtController = TextEditingController();

  @override
  void dispose() {
    _sportController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(sponsorBrowseFilterProvider);
    final listings = ref.watch(sponsorshipListingsProvider);

    return AppScaffold(
      title: 'Find someone to sponsor',
      subtitle: 'Athletes and teams open to backing',
      body: AsyncView(
        value: listings,
        onRetry: () => ref.invalidate(sponsorshipListingsProvider),
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
                    child: SegmentedButton<SponsorshipTargetType?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('All')),
                        ButtonSegment(
                          value: SponsorshipTargetType.athlete,
                          label: Text('Athletes'),
                          icon: Icon(Icons.person_outline),
                        ),
                        ButtonSegment(
                          value: SponsorshipTargetType.team,
                          label: Text('Teams'),
                          icon: Icon(Icons.groups_outlined),
                        ),
                      ],
                      selected: {filter.targetType},
                      onSelectionChanged: (s) => ref
                          .read(sponsorBrowseFilterProvider.notifier)
                          .update((f) => f.copyWith(targetType: () => s.first)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sportController,
                            decoration: const InputDecoration(
                              labelText: 'Sport',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => ref
                                .read(sponsorBrowseFilterProvider.notifier)
                                .update((f) => f.copyWith(
                                      sport: () =>
                                          v.trim().isEmpty ? null : v.trim(),
                                    )),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _districtController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'District',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => ref
                                .read(sponsorBrowseFilterProvider.notifier)
                                .update((f) => f.copyWith(
                                      district: () =>
                                          v.trim().isEmpty ? null : v.trim(),
                                    )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.travel_explore_outlined,
                      title: 'No open listings match yet',
                      message: 'Try clearing a filter, or check back soon — '
                          'new listings are published all the time.',
                    )
                  else
                    for (final listing in list) _ListingCard(listing: listing),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing});

  final SponsorshipListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = listing.isAthlete
        ? (listing.subjectDisplayName ?? 'An athlete')
        : (listing.orgName ?? 'A team');

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        onTap: () => context.push(Routes.sponsorListing(listing.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    listing.isAthlete ? Icons.person_outline : Icons.groups_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      listing.headline,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  who,
                  listing.sport,
                  if (listing.geo.district != null) listing.geo.district!,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              if (listing.story.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  listing.story,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final ask in listing.asks.take(4))
                    Chip(
                      label: Text(ask.category.label),
                      avatar: Text(ask.category.emoji),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (listing.sponsorsCount > 0)
                    Chip(
                      label: Text(
                        '${listing.sponsorsCount} sponsor${listing.sponsorsCount == 1 ? '' : 's'}',
                      ),
                      avatar: const Icon(Icons.favorite, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
