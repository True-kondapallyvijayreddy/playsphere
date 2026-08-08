import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../domain/draw/schedule_shift.dart';
import '../../../shared/app_scaffold.dart';

/// The organizer's free hand over a day that is not going to plan.
///
/// A generated schedule solves an allocation — courts, order, rest gaps,
/// round dependencies — and every one of those constraints is *relative*.
/// When the first round starts an hour late, none of them becomes wrong; only
/// the clock does. Regenerating would re-solve the whole allocation and could
/// hand a player a different court and a different place in the order for
/// reasons nobody in the hall can see.
///
/// So this moves the announced plan bodily and changes nothing else. Two taps
/// for the common case, a time picker for the exact one.
class RunningLateCard extends ConsumerStatefulWidget {
  const RunningLateCard({
    super.key,
    required this.fixtures,
    required this.onShift,
  });

  /// Every match in the tournament or event this card governs.
  final List<Fixture> fixtures;

  /// Applies the shift. Returns what actually moved, for the confirmation.
  final Future<ShiftPlan> Function({Duration? by, DateTime? newStart}) onShift;

  @override
  ConsumerState<RunningLateCard> createState() => _RunningLateCardState();
}

class _RunningLateCardState extends ConsumerState<RunningLateCard> {
  bool _busy = false;
  String? _result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = ScheduleShift.earliestPending(widget.fixtures);

    // Nothing left to move — the day is done, or nothing has been scheduled.
    if (next == null) return const SizedBox.shrink();

    // Bug #1 / #15: use activity-aware isLiveAt rather than the raw status
    // field, so a match abandoned by its scorer days ago counts as pending
    // (and therefore movable) rather than in-progress.
    final now = DateTime.now();
    final pending = widget.fixtures
        .where((f) => f.scheduledAt != null && !f.status.isResulted && !f.isLiveAt(now))
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('Running late?', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Next up is ${_hhmm(next)}. Moving the start moves everything '
                'still to be played by the same amount — same courts, same '
                'order, same gaps. Matches already played or in progress stay '
                'where they are.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [15, 30, 60])
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _apply(by: Duration(minutes: minutes)),
                      child: Text('+$minutes min'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickTime(next),
                    icon: const Icon(Icons.access_time, size: 18),
                    label: const Text('Start at…'),
                  ),
                  TextButton(
                    onPressed:
                        _busy ? null : () => _apply(by: const Duration(minutes: -15)),
                    child: const Text('−15 min'),
                  ),
                ],
              ),

              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_result != null) ...[
                const SizedBox(height: 10),
                Text(_result!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 4),
              Text(
                '$pending match${pending == 1 ? '' : 'es'} would move.',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime(DateTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'New start time for the next match',
    );
    if (picked == null) return;
    // Anchored to the day the next match is already on, so picking 10:30 means
    // half past ten today rather than half past ten on some other date.
    await _apply(
      newStart: DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _apply({Duration? by, DateTime? newStart}) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final plan = await widget.onShift(by: by, newStart: newStart);
      if (!mounted) return;
      setState(() {
        if (plan.isEmpty) {
          _result = 'Nothing to move.';
          return;
        }
        final held = plan.skippedPlayed + plan.skippedLive;
        _result = [
          '${plan.movedCount} match'
              '${plan.movedCount == 1 ? '' : 'es'} moved '
              '${_describe(plan.by)}.',
          if (plan.newFirstStart != null)
            'Next up is now ${_hhmm(plan.newFirstStart!)}'
                '${plan.newLastStart != null ? ', last starts '
                    '${_hhmm(plan.newLastStart!)}' : ''}.',
          if (held > 0)
            '$held already played or in progress and stayed put.',
        ].join('\n');
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _describe(Duration d) {
    final minutes = d.inMinutes;
    if (minutes == 0) return 'by no time at all';
    final abs = minutes.abs();
    final hours = abs ~/ 60;
    final rest = abs % 60;
    final parts = [
      if (hours > 0) '${hours}h',
      if (rest > 0) '${rest}m',
    ].join(' ');
    return minutes > 0 ? 'later by $parts' : 'earlier by $parts';
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
