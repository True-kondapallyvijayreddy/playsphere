import 'package:flutter/material.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/fixture.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../shared/live_dot.dart';
import '../../../shared/ui_kit.dart';
import 'duel_pad.dart';

/// The scoreboard at the top of a stacked pad, and of the live view somebody
/// watching a match they are not scoring sees.
///
/// One widget for both because they are the same object: a scoreboard does not
/// become a different thing when the person reading it cannot press anything.
/// Two implementations is how the live view ends up a version behind the pad.
class PadScoreboard extends StatelessWidget {
  const PadScoreboard({
    super.key,
    required this.fixture,
    required this.headline,
    required this.status,
    required this.summary,
    this.live = true,
  });

  final Fixture fixture;

  /// The number that matters right now, from the plugin: "142/3", "19 - 12".
  final String headline;
  final String? status;
  final String summary;

  /// Draws the pulsing dot. False for a match that has finished.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final winner = fixture.winnerEntrantId;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9)],
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamName(
                  name: fixture.entrantAName,
                  accent: DuelPad.accentFor(Side.a),
                  won: winner != null && winner == fixture.entrantAId,
                  align: TextAlign.left,
                ),
              ),
              if (live)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: LiveDot(),
                )
              else
                const SizedBox(width: 16),
              Expanded(
                child: _TeamName(
                  name: fixture.entrantBName,
                  accent: DuelPad.accentFor(Side.b),
                  won: winner != null && winner == fixture.entrantBId,
                  align: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The headline changes on every single event, so it animates: a
          // scorer glancing up from the pitch catches movement long before
          // they read a number.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.85, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
                child: child,
              ),
            ),
            child: FittedBox(
              key: ValueKey(headline),
              fit: BoxFit.scaleDown,
              child: Text(
                headline,
                style: TextStyle(
                  fontSize: context.isCompact ? 44 : 52,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: Ps.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (status != null && status!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Ps.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Ps.primary,
                ),
              ),
            ),
          ],
          if (summary.isNotEmpty && summary != headline) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Ps.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamName extends StatelessWidget {
  const _TeamName({
    required this.name,
    required this.accent,
    required this.won,
    required this.align,
  });

  final String name;
  final Color accent;
  final bool won;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align == TextAlign.left
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Container(
          width: 26,
          height: 3,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: won ? FontWeight.w900 : FontWeight.w600,
            color: Ps.ink,
          ),
        ),
      ],
    );
  }
}

/// The stacked pad's controls: one section per group the plugin declared.
///
/// ## What changed and why it was not only decoration
///
/// This was a `Wrap` of identical grey buttons under a plain heading. Every
/// control looked the same, which meant the scorer read every label every
/// time — including on cricket, where "4" and "W" sit in the same row and one
/// of them ends somebody's innings. Now the side a control belongs to is
/// carried by colour (the same green/blue as the two-sided pad, so the two
/// layouts teach each other), a destructive control is red, and the primary
/// action of each group is visibly the primary action.
class ControlDeck extends StatelessWidget {
  const ControlDeck({
    super.key,
    required this.groups,
    required this.onControl,
    required this.enabled,
    required this.showShortcuts,
  });

  final List<ScoreControlGroup> groups;
  final void Function(ScoreControl) onControl;
  final bool enabled;

  /// Keyboard hints, shown on a laptop where they are several times faster
  /// than aiming a mouse during play, and hidden on a phone where they are
  /// noise.
  final bool showShortcuts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 8, left: 2),
            child: Text(
              group.title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Ps.faint,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in group.controls)
                PadButton(
                  control: c,
                  onPressed: enabled ? () => onControl(c) : null,
                  showShortcut: showShortcuts,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One control, drawn by what it does rather than by where it sits.
class PadButton extends StatelessWidget {
  const PadButton({
    super.key,
    required this.control,
    required this.onPressed,
    this.showShortcut = false,
  });

  final ScoreControl control;
  final VoidCallback? onPressed;
  final bool showShortcut;

  @override
  Widget build(BuildContext context) {
    final sided = control.side != Side.neutral;
    final danger = control.style == ControlStyle.danger;
    final primary = control.style == ControlStyle.primary;
    final accent = danger
        ? Ps.live
        : sided
            ? DuelPad.accentFor(control.side)
            : Ps.primary;

    // Touch targets stay generous on phones — a scorer's thumb is not precise
    // while they are watching play.
    final minHeight = context.responsive<double>(
      compact: primary ? 64 : 52,
      medium: primary ? 58 : 48,
      expanded: primary ? 54 : 44,
    );

    final filled = primary || danger;
    final disabled = onPressed == null;
    final foreground = disabled
        ? Ps.faint
        : filled
            ? Colors.white
            : Ps.ink;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight, minWidth: 88),
      child: Tooltip(
        message: control.tooltip ?? '',
        child: Material(
          color: disabled
              ? Ps.canvas
              : filled
                  ? accent
                  : accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(
                  color: filled
                      ? Colors.transparent
                      : accent.withValues(alpha: disabled ? 0.15 : 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    control.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: primary ? 16.5 : 14.5,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                    ),
                  ),
                  if (showShortcut && control.shortcut != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        control.shortcut!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: filled
                              ? Colors.white.withValues(alpha: 0.75)
                              : Ps.faint,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The four facts that identify a match rather than describe it: which match,
/// where, when it started, how long it has been running.
///
/// Bottom of the pad, deliberately. None of it changes during a rally and none
/// of it is ever urgent — but all four are what somebody types into a message
/// when there is a dispute ("court 2, 11:45 match"), and hunting for them
/// meant leaving the pad mid-match.
class MatchMetaStrip extends StatelessWidget {
  const MatchMetaStrip({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final started = fixture.startedAt;
    final court = fixture.courtId ?? fixture.venue;

    final items = <(IconData, String, String)>[
      (Icons.tag_rounded, 'Match', fixture.id.substring(0, 6).toUpperCase()),
      if (court != null && court.isNotEmpty)
        (Icons.place_outlined, 'Court', court),
      if (started != null)
        (
          Icons.schedule_outlined,
          'Started',
          TimeOfDay.fromDateTime(started.toLocal()).format(context),
        ),
      if (started != null)
        (Icons.timer_outlined, 'Elapsed', _elapsed(started)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          for (final (icon, label, value) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: Ps.faint),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 9.5, color: Ps.faint),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Wall-clock elapsed, not playing time. A racket match has no clock, so
  /// this is honestly "how long have we been here" — which is the number an
  /// organizer running six courts actually wants.
  static String _elapsed(DateTime from) {
    final d = DateTime.now().difference(from);
    if (d.isNegative) return '—';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h ${m}m' : '${d.inMinutes}m';
  }
}
