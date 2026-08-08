import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/give_donation.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// A donor's own traceability view — "Donation PS-DON-2026-001245: collected,
/// cleaned, on its way." Every donation this account has ever submitted,
/// newest first, each with the pipeline it's currently sitting in.
class GiveMyDonationsScreen extends ConsumerWidget {
  const GiveMyDonationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donations = ref.watch(myDonationsProvider);

    return AppScaffold(
      title: 'My donations',
      subtitle: 'Track where your gear ended up',
      body: AsyncView(
        value: donations,
        onRetry: () => ref.invalidate(myDonationsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.volunteer_activism_outlined,
              title: 'No donations yet',
              message: 'Donations you submit will show up here, with their '
                  'progress through collection and delivery.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ContentBounds(
                maxWidth: 700,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final d in list) _DonationCard(donation: d),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DonationCard extends StatelessWidget {
  const _DonationCard({required this.donation});

  final GiveDonation donation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount =
        donation.items.fold<int>(0, (a, l) => a + l.quantity);
    final rejected = donation.status.isTerminalRejection;

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
                    donation.type == GiveDonationType.equipment
                        ? '$itemCount item${itemCount == 1 ? '' : 's'} · '
                            '${donation.items.map((l) => l.category.label).join(', ')}'
                        : 'Money pledge',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  label: Text(donation.status.label),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: rejected
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.primaryContainer,
                ),
              ],
            ),
            if (donation.createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Submitted ${DateFormat.yMMMd().format(donation.createdAt!)}'
                '${donation.city.isEmpty ? '' : ' · ${donation.city}'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ],
            if (!rejected) ...[
              const SizedBox(height: 12),
              _StatusTrack(current: donation.status),
            ],
            if (donation.status == DonationStatus.distributed) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.favorite, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Delivered — this kit is in a player\'s hands now.',
                      style: theme.textTheme.bodySmall,
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

class _StatusTrack extends StatelessWidget {
  const _StatusTrack({required this.current});

  final DonationStatus current;

  // The happy-path steps only — `rejected` branches off and is rendered as
  // a chip instead, not as a stop on this track.
  static const _steps = [
    DonationStatus.submitted,
    DonationStatus.collected,
    DonationStatus.inspected,
    DonationStatus.cleaned,
    DonationStatus.repaired,
    DonationStatus.safetyChecked,
    DonationStatus.graded,
    DonationStatus.packed,
    DonationStatus.assigned,
    DonationStatus.distributed,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reached = current.step;
    return SizedBox(
      height: 6,
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: _steps[i].step <= reached
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
