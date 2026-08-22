import 'package:flutter/material.dart';

import '../../core/layout/responsive.dart';
import '../../domain/medical/sports_medicine_library.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ui_kit.dart';
import 'video_link_button.dart';
import 'warmup_timer_sheet.dart';

/// Pre-match warm-ups, sport by sport.
///
/// Reads entirely from `SportsMedicineLibrary`, which is `const` and ships
/// with the app — see that library for why this content is code rather than a
/// Firestore collection. The practical consequence is the one that matters
/// here: this screen opens instantly on a ground with no signal, which is
/// exactly where a warm-up is read.
class SportsWarmupsScreen extends StatefulWidget {
  const SportsWarmupsScreen({super.key, this.initialSportId});

  final String? initialSportId;

  @override
  State<SportsWarmupsScreen> createState() => _SportsWarmupsScreenState();
}

class _SportsWarmupsScreenState extends State<SportsWarmupsScreen> {
  String? _sportId;

  @override
  void initState() {
    super.initState();
    _sportId = widget.initialSportId;
  }

  @override
  Widget build(BuildContext context) {
    final list = SportsMedicineLibrary.workoutsFor(_sportId);

    return AppScaffold(
      title: 'Pre-match warm-ups',
      subtitle: 'Raise, activate, mobilise, potentiate',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ContentBounds(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(
                    'A warm-up is not stretching. It raises temperature, '
                    'switches on the muscles that protect joints, moves those '
                    'joints through the range the sport demands, and finishes '
                    'at match intensity — so the first sprint of the game is '
                    'not the first sprint of the day.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Ps.muted,
                    ),
                  ),
                ),

                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('All sports'),
                          selected: _sportId == null,
                          onSelected: (_) => setState(() => _sportId = null),
                        ),
                      ),
                      for (final sport in SportCatalog.all)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(sport.name),
                            selected: _sportId == sport.id,
                            onSelected: (on) => setState(
                              () => _sportId = on ? sport.id : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                if (list.isEmpty)
                  const EmptyState(
                    icon: Icons.directions_run_outlined,
                    title: 'Nothing written for this sport yet',
                    message: 'The general routines below apply to any sport — '
                        'clear the filter to see them.',
                  )
                else
                  for (final w in list) _WorkoutCard(workout: w),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One routine, expandable to the full exercise list.
///
/// Collapsed by default and expandable in place rather than opening a detail
/// route, because the comparison a coach is making — "which of these three do
/// we have time for" — needs the durations side by side, and a route per
/// routine would make that four taps instead of none.
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.workout});

  final PreMatchWorkout workout;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Theme(
        // The default divider lines under an ExpansionTile cut across the
        // card border; removed rather than styled, because the card edge
        // already does the separating.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Ps.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Ps.radiusSm),
            ),
            child: Text(
              '${workout.durationMinutes}′',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Ps.primary,
              ),
            ),
          ),
          title: Text(
            workout.title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${workout.phase.label} · ${workout.totalSteps} exercises',
            style: const TextStyle(fontSize: 12, color: Ps.muted),
          ),
          children: [
            Text(
              workout.summary,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Ps.ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in workout.targets)
                  Chip(
                    label: Text(t, style: const TextStyle(fontSize: 11.5)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 14),

            for (var i = 0; i < workout.steps.length; i++)
              _StepRow(index: i + 1, step: workout.steps[i]),

            // Named only where the routine really is a published programme.
            // Attributing generic mobility work to a study would be a
            // citation nobody could check.
            if (workout.evidence != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.menu_book_outlined,
                      size: 15, color: Ps.faint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      workout.evidence!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Ps.faint,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showWarmupTimer(context, workout),
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('Run it'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: VideoLinkButton(video: workout.video),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step});

  final int index;
  final WorkoutStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Ps.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: Ps.border),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Ps.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        step.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Ps.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      step.dose,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Ps.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // The coaching point, always shown. Without it these are
                // just names of exercises, which is how warm-ups get done
                // badly by people who think they are doing them.
                Text(
                  step.cue,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Ps.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
