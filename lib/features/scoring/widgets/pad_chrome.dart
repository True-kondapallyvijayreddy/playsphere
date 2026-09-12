import 'package:flutter/material.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/models/fixture.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../shared/live_dot.dart';
import '../../../shared/ui_kit.dart';
import 'duel_pad.dart';
import 'pad_theme.dart';

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
        borderRadius: BorderRadius.circular(Ps.radius + 2),
        border: Border.all(color: PadInk.boardEdge),
        boxShadow: PadInk.board,
        // The same board the cricket pad states its total on, for the reason
        // that pad gives: a scoreboard is a readout, and every readout in the
        // product should be the one dark surface among the input surfaces.
        // Two scoreboards in two palettes is how a scorer switching sports
        // has to learn the screen twice.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PadInk.boardTop, PadInk.boardMid, PadInk.boardBottom],
          stops: [0, 0.55, 1],
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
                  fontSize: context.isCompact ? 46 : 54,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: [
                    Shadow(
                      color: Ps.primary.withValues(alpha: 0.5),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (status != null && status!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Ps.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Ps.primary.withValues(alpha: 0.35)),
              ),
              child: Text(
                status!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
          if (summary.isNotEmpty && summary != headline) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: PadInk.boardMuted),
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
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.6),
                blurRadius: 8,
              ),
            ],
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
            color: won ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
      ],
    );
  }
}

/// How many grid columns a control's label needs to stay readable.
///
/// The scoring pads lay their primary controls out as an even grid — a keypad
/// shape a thumb learns in one match — and an even grid has one width for
/// every tile. That is right for "0" through "6" and wrong for the moment a
/// sport hands the same grid "Technical point (defence)": the tile shrank the
/// type to fit, which on a phone at a boundary in daylight is the same as not
/// drawing it.
///
/// So a long label is given more columns instead of a smaller font. The
/// thresholds are character counts rather than a measured `TextPainter`,
/// deliberately: this is called once per control inside a `LayoutBuilder`, on
/// every frame of a scroll, and the answer only ever needs to be right to the
/// nearest column.
///
/// Shared by every pad so the same label is never one width on the cricket pad
/// and another on the kabaddi one.
int padColumnSpan(String label) {
  final n = label.length;
  if (n <= 3) return 1;
  if (n <= 8) return 2;
  if (n <= 16) return 3;
  return 4;
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
          // The row's width is handed down to every button in it.
          //
          // A `Wrap` lays its children out with UNBOUNDED width, so a button
          // whose label is long — "Wicket — caught behind", "Technical point
          // (defence)" — grew past the edge of the phone and was clipped with
          // an overflow stripe. The scorer got a truncated word and no way to
          // tell two similar controls apart, on the one screen where reading
          // the wrong button is a wrong scoreline.
          //
          // Capping at the row width is what turns that into the behaviour
          // that was wanted all along: a long label makes the button WIDER,
          // up to the full width of the pad, and wraps onto a second line only
          // when even that is not enough. Short labels are unaffected.
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in group.controls)
                  PadButton(
                    control: c,
                    maxWidth: box.maxWidth,
                    onPressed: enabled ? () => onControl(c) : null,
                    showShortcut: showShortcuts,
                  ),
              ],
            ),
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
    this.maxWidth,
  });

  final ScoreControl control;
  final VoidCallback? onPressed;
  final bool showShortcut;

  /// The widest this button may grow before its label wraps.
  ///
  /// Null means unbounded, which is only safe where the caller has already
  /// bounded it — a `SizedBox` in a grid. Inside a `Wrap` it must be the
  /// row's width, or a long label runs off the screen. See [ControlDeck].
  final double? maxWidth;

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

    final radius = BorderRadius.circular(Ps.radiusSm + 2);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minHeight,
        minWidth: 88,
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: Tooltip(
        message: control.tooltip ?? '',
        // The same moulded key the cricket pad uses, so a scorer who has kept
        // one match knows what a control looks like in any sport. See
        // [PadInk].
        child: PadPressable(
          onTap: onPressed,
          borderRadius: radius,
          builder: (context, pressed) => AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: disabled
                  ? null
                  : filled
                      ? PadInk.keyFill(accent)
                      : PadInk.keyGhost(accent),
              color: disabled ? Ps.canvas : null,
              border: Border.all(
                color: filled
                    ? Colors.black.withValues(alpha: 0.06)
                    : accent.withValues(alpha: disabled ? 0.15 : 0.28),
              ),
              boxShadow: disabled
                  ? null
                  : pressed
                      ? PadInk.keyPressed(accent)
                      : PadInk.key(accent, filled: filled),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  control.label,
                  textAlign: TextAlign.center,
                  // Two lines before anything is dropped. With the width cap
                  // above, a label only reaches a second line once it has
                  // already taken the full width of the pad — at which point
                  // wrapping is the honest thing to do and shrinking the
                  // type would be the alternative.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
      if (started != null) (Icons.timer_outlined, 'Elapsed', _elapsed(started)),
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
