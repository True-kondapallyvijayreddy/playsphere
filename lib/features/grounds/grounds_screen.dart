import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/ground_repository.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/promo_banner.dart';
import 'ground_booking_flow.dart';

/// Grounds to hire, and the bookings this person already holds.
///
/// The same booking flow the event form uses, reached directly — because
/// wanting a pitch for Sunday is a complete errand on its own. Most bookings
/// will be made while creating an event, but a captain arranging a friendly
/// has no event to create and would otherwise have to invent one.
class GroundsScreen extends ConsumerWidget {
  const GroundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myBookings =
        ref.watch(myGroundBookingsProvider).valueOrNull ?? const [];
    final upcoming = myBookings
        .where((b) => b.holdsSlot && b.startsAt.isAfter(
              DateTime.now().subtract(const Duration(hours: 3)),
            ))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return AppScaffold(
      title: 'Grounds',
      subtitle: 'Find a ground and book it by the hour',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PromoBanner(
                  slot: PromoSlot.grounds,
                  margin: EdgeInsets.fromLTRB(12, 12, 12, 4),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: FilledButton.icon(
                    onPressed: () => showGroundBookingSheet(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(Icons.search),
                    label: const Text('Find a ground'),
                  ),
                ),
                const SizedBox(height: 20),

                if (upcoming.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Your bookings',
                        style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: 8),
                  for (final b in upcoming)
                    Card(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: ListTile(
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(b.groundName),
                        subtitle: Text(
                          '${DateFormat('EEE d MMM').format(b.startsAt)} · '
                          '${groundHourLabel(b.startHour)}–'
                          '${groundHourLabel(b.endHour)}'
                          '${b.amountPaise == 0 ? '' : ' · '
                              '${Pricing.formatPaise(b.amountPaise)}'}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _cancel(context, ref, b.groundId,
                              b.id, b.groundName),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],

                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: Icon(Icons.business_center_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('Own a ground?'),
                    subtitle: const Text(
                      'List it and take bookings from clubs nearby',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.myGrounds),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cancelling asks first. A slot released by a misplaced tap is a slot the
  /// club turns up to find gone, and the fix costs somebody a phone call.
  static Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    String groundId,
    String bookingId,
    String groundName,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(
          'The slot at $groundName will be released and anyone else can take '
          'it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ref
          .read(groundRepositoryProvider)
          .cancelBooking(groundId: groundId, bookingId: bookingId);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
