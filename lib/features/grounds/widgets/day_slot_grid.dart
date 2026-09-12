/// A ground's whole day, hour by hour, with the taken hours visible.
///
/// ## Why the taken hours are shown rather than hidden
///
/// The picker this replaces asked `startsFitting(hours)` and rendered the
/// answer as a row of chips. That is a list of what you *can* have, and it
/// makes what you cannot have invisible: book 9–12 on a ground and the next
/// person does not see a blocked 9–12, they see a shorter list of chips with
/// no explanation of what happened to the morning.
///
/// Two things go wrong with that. A person who wanted 10am cannot tell
/// whether the ground is busy then or shut then, so they do not know whether
/// to try next week or try somewhere else. And a ground with three bookings
/// looks identical to a ground with none, so the one piece of information
/// that says "other people use this place" is thrown away — which matters
/// more than usual here, because a listing nobody has ever booked is exactly
/// what a fake one looks like.
///
/// A grid where every open hour is drawn, free or not, answers both. It is
/// also simply the shape people already know from booking a cinema seat.
///
/// ## Why it is live
///
/// The sheet used to take a one-shot read. Two clubs hunting for a pitch on
/// Sunday evening at the same moment is the expected traffic on a popular
/// ground, not a rare race: both saw 18:00 free, both tapped, and the second
/// one got an error where a booking should have been. Watching the day means
/// the grid closes the slot under them before they reach for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/ground.dart';
import '../../../core/providers.dart';
import '../../../data/ground_repository.dart' show groundHourLabel;

/// What one hour on the grid is.
enum _CellState { free, taken, past, inSelection, startOfSelection }

class DaySlotGrid extends ConsumerWidget {
  const DaySlotGrid({
    super.key,
    required this.ground,
    required this.day,
    required this.hours,
    required this.onBook,
    this.selectedStart,
    this.onSelect,
    this.busy = false,
  });

  final Ground ground;
  final DateTime day;

  /// How long a slot the person is after. Decides which starts are offered:
  /// an hour that is free but has a booked hour right after it cannot start a
  /// two-hour slot, and the grid says so by refusing the tap rather than by
  /// hiding the hour.
  final int hours;

  final void Function(int startHour) onBook;

  /// The start currently pencilled in, so the whole span highlights rather
  /// than just the hour tapped. A two-hour booking at 18:00 occupies 18 and
  /// 19, and showing only 18 selected is how somebody ends up surprised by
  /// what they paid for.
  final int? selectedStart;
  final void Function(int startHour)? onSelect;

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bookings = ref.watch(
      groundDayBookingsProvider((groundId: ground.id, day: day)),
    );

    return bookings.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Could not load this ground\'s calendar. $e',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.error),
        ),
      ),
      data: (list) {
        final availability = DayAvailability(ground, list, day: day);
        final open = [
          for (var h = ground.openHour; h < ground.closeHour; h++) h,
        ];

        if (open.isEmpty) {
          return Text(
            'This ground has no opening hours set.',
            style: theme.textTheme.bodySmall,
          );
        }

        final anyFree = open.any((h) => availability.isFree(h, h + hours));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in open)
                  _HourCell(
                    hour: h,
                    state: _stateFor(h, availability),
                    // Tappable only where a slot of the wanted length
                    // actually fits. The hour is still drawn either way.
                    onTap: busy || !availability.isFree(h, h + hours)
                        ? null
                        : () => (onSelect ?? onBook)(h),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const _Legend(),
            if (!anyFree) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_busy_outlined,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        hours == 1
                            ? 'Nothing free on this day.'
                            : 'No $hours-hour gap left on this day. Try a '
                                'shorter slot or another day.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  _CellState _stateFor(int hour, DayAvailability availability) {
    final start = selectedStart;
    if (start != null && hour >= start && hour < start + hours) {
      return hour == start ? _CellState.startOfSelection : _CellState.inSelection;
    }
    if (availability.isHourTaken(hour)) return _CellState.taken;
    if (availability.isHourPast(hour)) return _CellState.past;
    return _CellState.free;
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({required this.hour, required this.state, required this.onTap});

  final int hour;
  final _CellState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (bg, fg, border) = switch (state) {
      _CellState.free => (
          scheme.surface,
          scheme.onSurface,
          scheme.outlineVariant,
        ),
      // Taken and past are drawn differently on purpose. Both are unbookable
      // and they mean opposite things about the ground: one says somebody
      // else has it, the other says you are asking too late.
      _CellState.taken => (
          scheme.errorContainer.withValues(alpha: 0.5),
          scheme.onErrorContainer,
          Colors.transparent,
        ),
      _CellState.past => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant.withValues(alpha: 0.6),
          Colors.transparent,
        ),
      _CellState.inSelection ||
      _CellState.startOfSelection =>
        (scheme.primary, scheme.onPrimary, Colors.transparent),
    };

    return SizedBox(
      width: 82,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  groundHourLabel(hour),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: state == _CellState.startOfSelection
                        ? FontWeight.w800
                        : FontWeight.w600,
                    decoration: state == _CellState.taken
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (state == _CellState.taken)
                  Text(
                    'Booked',
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget swatch(Color color, String label, {Color? border}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: border == null ? null : Border.all(color: border),
              ),
            ),
            const SizedBox(width: 5),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        );

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        swatch(scheme.surface, 'Free', border: scheme.outlineVariant),
        swatch(scheme.errorContainer.withValues(alpha: 0.5), 'Booked'),
        swatch(scheme.surfaceContainerHighest, 'Gone'),
        swatch(scheme.primary, 'Your slot'),
      ],
    );
  }
}
