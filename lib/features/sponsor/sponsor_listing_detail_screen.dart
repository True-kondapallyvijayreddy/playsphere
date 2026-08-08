import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/sponsorship.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// One listing, in full — story, achievements, what it's asking for, and the
/// "Offer to sponsor" affordance. `firestore.rules` on `sponsorPledges` is
/// what actually keeps an offer's message private between the sponsor and
/// the listing owner; this screen only ever writes a pending pledge, never
/// reads anyone else's.
class SponsorListingDetailScreen extends ConsumerWidget {
  const SponsorListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingAsync = ref.watch(sponsorshipListingProvider(listingId));
    final me = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: AsyncView(
        value: listingAsync,
        onRetry: () => ref.invalidate(sponsorshipListingProvider(listingId)),
        builder: (listing) {
          if (listing == null) {
            return const EmptyState(
              icon: Icons.search_off_outlined,
              title: 'This listing is no longer available',
            );
          }
          final isOwner = me != null && me.uid == listing.createdByUid;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ContentBounds(
                maxWidth: 700,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            listing.isAthlete
                                ? Icons.person_outline
                                : Icons.groups_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              listing.headline,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          listing.isAthlete
                              ? (listing.subjectDisplayName ?? 'An athlete')
                              : (listing.orgName ?? 'A team'),
                          listing.sport,
                          if (listing.geo.district != null)
                            listing.geo.district!,
                        ].join(' · '),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                      if (listing.sponsorsCount > 0) ...[
                        const SizedBox(height: 8),
                        Chip(
                          label: Text(
                            'Backed by ${listing.sponsorsCount} sponsor${listing.sponsorsCount == 1 ? '' : 's'}',
                          ),
                          avatar: const Icon(Icons.favorite, size: 16),
                        ),
                      ],
                      if (listing.story.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(listing.story,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ],
                      if (listing.achievementSummary.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Achievements',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        for (final a in listing.achievementSummary)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  '),
                                Expanded(child: Text(a)),
                              ],
                            ),
                          ),
                      ],
                      if (listing.asks.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('What would help',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final ask in listing.asks)
                              Chip(
                                avatar: Text(ask.category.emoji),
                                label: Text(
                                  ask.description.isEmpty
                                      ? ask.category.label
                                      : ask.description,
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (isOwner)
                        Card(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'This is your own listing. Manage offers '
                                    'from "My listings".',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: me == null
                              ? null
                              : () => _openPledgeSheet(context, ref, listing),
                          icon: const Icon(Icons.volunteer_activism_outlined),
                          label: const Text('Offer to sponsor'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openPledgeSheet(
    BuildContext context,
    WidgetRef ref,
    SponsorshipListing listing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PledgeSheet(listing: listing),
    );
  }
}

class _PledgeSheet extends ConsumerStatefulWidget {
  const _PledgeSheet({required this.listing});

  final SponsorshipListing listing;

  @override
  ConsumerState<_PledgeSheet> createState() => _PledgeSheetState();
}

class _PledgeSheetState extends ConsumerState<_PledgeSheet> {
  final _message = TextEditingController();
  final _categories = <SponsorshipSupportCategory>{};
  bool _anonymous = false;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(sponsorRepositoryProvider).offerSponsorship(SponsorPledge(
            id: '',
            listingId: widget.listing.id,
            sponsorUid: me.uid,
            sponsorDisplayName: me.displayName,
            message: _message.text.trim(),
            offeredCategories: _categories.toList(growable: false),
            anonymous: _anonymous,
          ));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Offer sent. The listing owner will see it and can respond — '
          'nothing about you is shared until they accept.',
        ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Offer to sponsor',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in SponsorshipSupportCategory.values)
                FilterChip(
                  avatar: Text(c.emoji),
                  label: Text(c.label),
                  selected: _categories.contains(c),
                  onSelected: (sel) => setState(
                    () => sel ? _categories.add(c) : _categories.remove(c),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message (optional)',
              hintText: 'What you\'d like to offer, and any questions',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stay anonymous'),
            subtitle: const Text('Your name won\'t appear if accepted'),
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
          ),
          const SizedBox(height: 8),
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
                : const Text('Send offer'),
          ),
        ],
      ),
    );
  }
}
