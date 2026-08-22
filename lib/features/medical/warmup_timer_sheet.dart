import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/medical/sports_medicine_library.dart';
import '../../shared/ui_kit.dart';

/// Runs a warm-up, one exercise at a time.
///
/// A sheet rather than a route: it is opened from a card, used for ten
/// minutes with the phone propped against a kit bag, and dismissed. Nothing
/// about it belongs in the back stack, and a deep link into "step 4 of the
/// FIFA 11+" is not a thing anybody wants.
Future<void> showWarmupTimer(BuildContext context, PreMatchWorkout workout) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Ps.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Ps.radius)),
    ),
    builder: (_) => _WarmupTimerSheet(workout: workout),
  );
}

class _WarmupTimerSheet extends StatefulWidget {
  const _WarmupTimerSheet({required this.workout});

  final PreMatchWorkout workout;

  @override
  State<_WarmupTimerSheet> createState() => _WarmupTimerSheetState();
}

class _WarmupTimerSheetState extends State<_WarmupTimerSheet> {
  int _index = 0;
  int _elapsed = 0;
  bool _running = false;
  Timer? _ticker;

  /// A stopwatch counting up, not a countdown.
  ///
  /// Deliberate. Half these exercises are counted in reps — "2 × 10 each
  /// side" — and a countdown would have to invent a duration for them and
  /// then be wrong about it, cutting somebody off mid-set or leaving them
  /// standing. Counting up puts the timing where it belongs, with the person
  /// doing the work, and still answers the question a warm-up timer is
  /// actually for: how long have we been at this.
  void _toggle() {
    setState(() => _running = !_running);
    _ticker?.cancel();
    if (!_running) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
    });
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.workout.steps.length) return;
    setState(() => _index = next);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _clock {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.workout.steps;
    final step = steps[_index];
    final isLast = _index == steps.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Ps.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Text(
                  widget.workout.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Ps.muted,
                  ),
                ),
              ),
              Text(
                _clock,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: Ps.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          LinearProgressIndicator(
            value: (_index + 1) / steps.length,
            minHeight: 5,
            backgroundColor: Ps.canvas,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 20),

          Text(
            'EXERCISE ${_index + 1} OF ${steps.length}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Ps.faint,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.name,
            style: const TextStyle(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.dose,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Ps.primary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Ps.canvas,
              borderRadius: BorderRadius.circular(Ps.radiusSm),
              border: Border.all(color: Ps.border),
            ),
            child: Text(
              step.cue,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Ps.ink,
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              IconButton.outlined(
                onPressed: _index == 0 ? null : () => _go(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous exercise',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _toggle,
                  icon: Icon(
                    _running ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                  label: Text(_running ? 'Pause' : 'Start'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                onPressed: isLast ? null : () => _go(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next exercise',
              ),
            ],
          ),
          if (isLast) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done — warmed up'),
            ),
          ],
        ],
      ),
    );
  }
}
