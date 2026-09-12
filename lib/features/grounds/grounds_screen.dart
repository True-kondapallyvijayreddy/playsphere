import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ads/promo.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/models/ground.dart';
import '../../data/ground_repository.dart';
import '../../data/site_fix_service.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ground_trust.dart';
import '../../shared/promo_banner.dart';
import 'ground_booking_flow.dart';
import 'report_ground_sheet.dart';

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
                  for (final b in upcoming) _BookingCard(booking: b),
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

/// One booking this person holds, with the two things they can do about it:
/// cancel it, or say they have arrived.
///
/// ## Why arriving is a button and not an assumption
///
/// A booking says somebody intended to be at a ground. Nothing in the system
/// said whether they got there, and the gap between those two facts is where
/// the whole ground-listing fraud lives: a fake listing takes bookings that
/// look exactly like real ones, right up until nobody can find the place.
///
/// One tap on the day, with the phone's own position behind it, closes the
/// gap. Three different people doing it is stronger evidence a ground exists
/// than anything its owner could ever upload — see `GroundCheckIn`. And a
/// listing that collects bookings and never collects an arrival becomes
/// visible, which it was not before.
class _BookingCard extends ConsumerStatefulWidget {
  const _BookingCard({required this.booking});

  final GroundBooking booking;

  @override
  ConsumerState<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends ConsumerState<_BookingCard> {
  bool _busy = false;

  Future<void> _checkIn() async {
    final b = widget.booking;
    final uid = ref.read(authUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      // The listing is read fresh rather than taken from the booking row.
      // The row carries a denormalized name and nothing else, and the check
      // needs the ground's pin — which is also the field most likely to have
      // been corrected since the slot was taken.
      final ground = await ref
          .read(groundRepositoryProvider)
          .watchGround(b.groundId)
          .first;
      if (ground == null) throw 'That ground is no longer listed.';

      final fix = await const SiteFixService().currentChecked();
      final checkIn = await ref.read(groundRepositoryProvider).checkInToBooking(
            ground: ground,
            booking: b,
            fix: fix,
            uid: uid,
          );
      if (!mounted) return;

      if (checkIn.isWithinRange) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checked in. Thanks — this helps other clubs '
                'trust this ground.'),
          ),
        );
        return;
      }

      // Out of range. Not an error and not silently swallowed: the person is
      // standing somewhere that is not the ground they booked, which is
      // either a wrong pin or a listing with nothing behind it. Both are
      // worth reporting and neither is their fault.
      final distance = checkIn.distanceMetres >= 1000
          ? '${(checkIn.distanceMetres / 1000).toStringAsFixed(1)} km'
          : '${checkIn.distanceMetres.round()} m';
      final report = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('You are not at this ground'),
          content: Text(
            'Your phone says you are $distance from where ${b.groundName} is '
            'listed. If you are at the right place and there is no ground '
            'here, tell us — it is the fastest way to get a fake listing '
            'taken down.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Report this listing'),
            ),
          ],
        ),
      );
      if (report == true && mounted) {
        await showReportGroundSheet(context, ground: ground, bookingId: b.id);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = widget.booking;
    final canCheckIn = b.canCheckInOn(DateTime.now());

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              b.isCheckedIn
                  ? Icons.where_to_vote_outlined
                  : Icons.event_available_outlined,
              color: b.isCheckedIn ? theme.colorScheme.primary : null,
            ),
            title: Text(b.groundName),
            subtitle: Text(
              '${DateFormat('EEE d MMM').format(b.startsAt)} · '
              '${groundHourLabel(b.startHour)}–'
              '${groundHourLabel(b.endHour)}'
              '${b.amountPaise == 0 ? '' : ' · '
                  '${Pricing.formatPaise(b.amountPaise)}'}',
            ),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => GroundsScreen._cancel(
                        context,
                        ref,
                        b.groundId,
                        b.id,
                        b.groundName,
                      ),
              child: const Text('Cancel'),
            ),
          ),
          // Shown only on the day. Offering "I'm here" for next Tuesday would
          // collect a fix from somebody's sofa and walk a listing towards
          // "Location confirmed" on the strength of nothing.
          if (canCheckIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'At the ground? Confirm it so other clubs know this '
                      'place is real.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _checkIn,
                    child: Text(_busy ? 'Checking…' : 'I\'m here'),
                  ),
                ],
              ),
            )
          else if (b.isCheckedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'You checked in here',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          if (b.amountPaise > 0 && !b.isCheckedIn)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: AdvancePaymentWarning(dense: true),
            ),
        ],
      ),
    );
  }
}
