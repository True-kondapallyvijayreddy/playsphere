import 'package:flutter/material.dart';

import '../../../domain/scoring/scoring_plugin.dart';
import '../../../shared/ui_kit.dart';

/// The scoring pad for a rally sport: two halves of a court, one per side.
///
/// ## Why this is a different pad and not a restyled one
///
/// Badminton, tennis and table tennis have exactly one event that happens
/// forty to sixty times a game — "that side won the rally" — and it is entered
/// by somebody standing beside the court, watching the shuttle rather than the
/// phone. The generic pad answered that with two 84pt buttons in a row of six,
/// which asks the scorer to aim. Aiming means looking down, and looking down
/// during a rally is how a point gets missed and how the scorer stops trusting
/// the app.
///
/// So each side gets half the screen, side by side the way the two ends of a
/// court are, and the whole card scores. The target is impossible to miss with
/// a thumb, and "which card is Anand" is answered by a solid bar of his own
/// colour rather than by reading a name.
///
/// ## What each card carries beyond the number
///
/// A grid of one box per point of the period, ticked as they are won. The
/// number already says 17; the empty boxes say *four from the game*, which is
/// the question everybody beside the court is actually asking and the one a
/// scoreboard normally leaves to arithmetic.
///
/// Under it, the three actions that belong to that side and only to it: the
/// point, the correction, and the retirement. They are labelled, small, and
/// well away from the surface being hit without looking — a scorer who wants
/// the sure thing taps the card, and a scorer who wants the careful thing
/// aims for a button.
///
/// Everything belonging to neither side — an interval, a change of ends, a
/// reopen — stays in the tray at the bottom.
class DuelPad extends StatelessWidget {
  const DuelPad({
    super.key,
    required this.board,
    required this.groups,
    required this.onControl,
    required this.onUndo,
    required this.canUndo,
    this.enabled = true,
  });

  final DuelBoard board;
  final List<ScoreControlGroup> groups;
  final void Function(ScoreControl) onControl;
  final VoidCallback onUndo;
  final bool canUndo;

  /// False while a write is in flight, so a double tap on a fast phone cannot
  /// enter the same rally twice.
  final bool enabled;

  /// Side A is the brand green, side B a distinct blue.
  ///
  /// Fixed rather than derived from the sport: the scorer learns "top is
  /// green is Anand" in the first thirty seconds and then never reads the
  /// name again, which is the whole point. A colour that changed per sport
  /// would make them re-learn it every match.
  static const _accentA = Ps.primary;
  static const _accentB = Color(0xFF2563EB);

  static Color accentFor(Side side) => side == Side.a ? _accentA : _accentB;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;

    // Height, not `Expanded`: the pad lives inside the screen's scroll view,
    // which also carries the scorecard, the photos and the admin actions. It
    // takes most of the first screenful — enough that both cards are big
    // targets — and lets the rest scroll up under it rather than being
    // unreachable behind a full-height pad.
    //
    // Sized so the headline ABOVE and the ends strip BELOW both fit on the
    // first screenful with it. That is not tidiness: "Undo last" lives in the
    // strip, it has to be reachable in one tap (CLAUDE.md §6), and a pad tall
    // enough to push it under the fold turns the one-tap correction into a
    // scroll-then-tap in front of two waiting players.
    final padHeight = wide
        ? (size.height * 0.54).clamp(240.0, 430.0)
        : (size.height * 0.50).clamp(280.0, 470.0);

    Widget half(Side side) => _Half(
          side: side,
          data: board[side],
          pipTarget: board.pipTarget,
          point: ScoringPlugin.primaryFor(groups, side),
          correction: ScoringPlugin.correctionFor(groups, side),
          retire: _dangerFor(side),
          onControl: onControl,
          enabled: enabled,
          showHint: _atStartOfPeriod,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(board: board),
        const SizedBox(height: 10),
        // Side by side, always, including on a phone. The two halves are the
        // two ends of a court and a scorer reads them the way they are
        // standing — left player left. Stacking them in portrait, which is
        // what this pad used to do, put the far player at the bottom of the
        // screen and was read as "who is winning" rather than "who is where"
        // more than once.
        SizedBox(
          height: padHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: half(Side.a)),
              const SizedBox(width: 8),
              Expanded(child: half(Side.b)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _EndsStrip(
          board: board,
          onUndo: onUndo,
          canUndo: canUndo && enabled,
        ),
        if (_trayControls.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Tray(controls: _trayControls, onControl: onControl, enabled: enabled),
        ],
      ],
    );
  }

  /// The destructive control belonging to one side — a retirement, in every
  /// sport that has one.
  ///
  /// Found by STYLE, not by action name. The pad must not know the word
  /// "retire" any more than it knows what a raid is: a plugin says a control
  /// is destructive and belongs to side A, and the pad draws it in red on
  /// side A's card. A sport whose withdrawal is called something else gets
  /// the same treatment for free.
  ScoreControl? _dangerFor(Side side) {
    for (final g in groups) {
      for (final c in g.controls) {
        if (c.side == side && c.style == ControlStyle.danger) return c;
      }
    }
    return null;
  }

  /// True at the start of a game, when the "tap your side" hint is worth
  /// showing. It disappears after the first point of every game rather than
  /// being dismissed forever: a scorer who picks up somebody else's phone
  /// mid-tournament gets the same one-line introduction.
  bool get _atStartOfPeriod {
    final current = board.periods.where((p) => p.current);
    if (current.isEmpty) return false;
    final p = current.first;
    return p.a == 0 && p.b == 0;
  }

  /// Everything the two cards do not already carry.
  ///
  /// The cards now hold each side's point, correction and retirement, so the
  /// tray is what is left: an interval, a change of ends, a reopen. Anything
  /// a plugin adds later lands here automatically rather than needing this
  /// widget changed, which is the whole reason the pad is generated from
  /// [ScoringPlugin.controls] instead of written per sport.
  List<ScoreControl> get _trayControls {
    final claimed = <ScoreControl?>{
      for (final side in [Side.a, Side.b]) ...[
        ScoringPlugin.primaryFor(groups, side),
        ScoringPlugin.correctionFor(groups, side),
        _dangerFor(side),
      ],
    };
    return [
      for (final g in groups)
        for (final c in g.controls)
          if (!claimed.any((x) => identical(x, c))) c,
    ];
  }
}

class _Half extends StatefulWidget {
  const _Half({
    required this.side,
    required this.data,
    required this.pipTarget,
    required this.point,
    required this.correction,
    required this.retire,
    required this.onControl,
    required this.enabled,
    required this.showHint,
  });

  final Side side;
  final DuelSide data;
  final int? pipTarget;
  final ScoreControl? point;
  final ScoreControl? correction;
  final ScoreControl? retire;
  final void Function(ScoreControl) onControl;
  final bool enabled;
  final bool showHint;

  @override
  State<_Half> createState() => _HalfState();
}

class _HalfState extends State<_Half> {
  /// Drives the press-down shrink. A tap on a target this large has no
  /// pointer to follow and no button edge to see move, so without this the
  /// only confirmation is the number changing — and the number is exactly
  /// what the scorer is not looking at.
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final accent = DuelPad.accentFor(widget.side);
    final live = widget.point != null && widget.enabled;
    final data = widget.data;

    return AnimatedScale(
      scale: _down ? 0.985 : 1,
      duration: const Duration(milliseconds: 90),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: data.serving ? 0.16 : 0.08),
              accent.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(
            // The serving side is outlined. It is the one piece of state a
            // racket scorer checks constantly and cannot read off the score,
            // and an outline says it without spending a line of text.
            color: data.serving ? accent : Ps.border,
            width: data.serving ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTapDown: live ? (_) => setState(() => _down = true) : null,
            onTapCancel: live ? () => setState(() => _down = false) : null,
            onTap: live
                ? () {
                    setState(() => _down = false);
                    widget.onControl(widget.point!);
                  }
                : null,
            // Long press takes the point back. Deliberately not a second
            // tap target: a correction is rare, and anything quicker than a
            // long press on a surface this size would fire by accident.
            onLongPress: widget.correction != null && widget.enabled
                ? () => widget.onControl(widget.correction!)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The name sits on a solid bar of the side's own colour, so
                // "which card is mine" is answered by colour from across a
                // hall rather than by reading a name at 12pt.
                _NameBar(data: data, accent: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        _BigScore(value: data.score, accent: accent),
                        if (data.pips != null && widget.pipTarget != null) ...[
                          const SizedBox(height: 8),
                          _PipGrid(
                            filled: data.pips!,
                            target: widget.pipTarget!,
                          ),
                        ],
                        const Spacer(),
                        if (data.sub != null)
                          Text(
                            data.sub!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Ps.muted,
                            ),
                          ),
                        if (data.serverName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              data.serverName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Ps.faint,
                              ),
                            ),
                          ),
                        if (data.tag != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _Tag(text: data.tag!, accent: accent),
                          )
                        else if (widget.showHint && live)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'tap to score',
                              style: TextStyle(
                                fontSize: 11,
                                color: Ps.faint,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // The card is still one big target — the whole surface above
                // scores. These are the labelled way to do the same thing,
                // plus the two actions that must never be a gesture: taking a
                // point back, and ending somebody's match.
                _CardActions(
                  accent: accent,
                  enabled: widget.enabled,
                  point: widget.point,
                  correction: widget.correction,
                  retire: widget.retire,
                  onControl: widget.onControl,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The number that fills the half.
///
/// Animated on change so a point registers peripherally: the scorer's eyes
/// are on the court, and movement is the only thing they will catch there.
class _BigScore extends StatelessWidget {
  const _BigScore({required this.value, required this.accent});

  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
      child: FittedBox(
        key: ValueKey(value),
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: TextStyle(
            fontSize: 84,
            height: 1,
            fontWeight: FontWeight.w800,
            color: accent,
            // Tabular figures, so the number does not jitter sideways as it
            // goes 9 → 10 → 11. On a display this size the shift is a
            // centimetre.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: accent,
        ),
      ),
    );
  }
}

class _PeriodBox extends StatelessWidget {
  const _PeriodBox({required this.period});

  final DuelPeriod period;

  @override
  Widget build(BuildContext context) {
    final current = period.current;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: current ? Ps.primary.withValues(alpha: 0.08) : Ps.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: current ? Ps.primary.withValues(alpha: 0.4) : Ps.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            period.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: current ? Ps.primary : Ps.faint,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${period.a}-${period.b}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything the sport can record that is not a point.
class _Tray extends StatelessWidget {
  const _Tray({
    required this.controls,
    required this.onControl,
    required this.enabled,
  });

  final List<ScoreControl> controls;
  final void Function(ScoreControl) onControl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in controls)
          _TrayChip(
            control: c,
            onPressed: enabled ? () => onControl(c) : null,
          ),
      ],
    );
  }
}

class _TrayChip extends StatelessWidget {
  const _TrayChip({required this.control, required this.onPressed});

  final ScoreControl control;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final sided = control.side != Side.neutral;
    final accent = sided ? DuelPad.accentFor(control.side) : Ps.muted;
    final danger = control.style == ControlStyle.danger;
    final colour = danger ? Ps.live : accent;

    return Material(
      color: colour.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Ps.radiusSm),
            border: Border.all(color: colour.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A colour chip rather than the side's name repeated in every
              // label. The halves above have already taught which colour is
              // which, and "−1" beside a green dot is read faster than
              // "−1 Anand Kumar" is read at all.
              if (sided) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                control.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: onPressed == null ? Ps.faint : Ps.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Half3 extends StatelessWidget {
  const _Half3({required this.value, required this.accent});

  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        ),
        child: Text(
          value,
          key: ValueKey(value),
          style: TextStyle(
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
}

/// The solid colour bar carrying one side's name and its serve light.
class _NameBar extends StatelessWidget {
  const _NameBar({required this.data, required this.accent});

  final DuelSide data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // A filled dot for the server, a hollow one for the receiver.
          // Present on both cards rather than only on the server's, because a
          // mark that appears and disappears is read as a rendering glitch
          // where two states of the same mark are read as a state.
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: data.serving ? Colors.white : Colors.transparent,
              border: Border.all(
                color: Colors.white.withValues(alpha: data.serving ? 1 : 0.55),
                width: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One box per point of the period, filled as they are won.
///
/// ## Why a scoreboard gets a diagram
///
/// The number already says 17. What the number does not say, without
/// arithmetic nobody does mid-rally, is *how close this is to over* — and
/// that is the question every person beside the court is actually asking. Four
/// empty boxes answers it in the time it takes to glance.
///
/// Capped rather than grown: a deuce that runs to 27-25 fills every box and
/// stops, because a grid that reflows at 22 would move the whole card under
/// the scorer's thumb at the tensest moment of the match.
class _PipGrid extends StatelessWidget {
  const _PipGrid({required this.filled, required this.target});

  final int filled;
  final int target;

  static const _perRow = 7;

  /// Every box is outlined and every won point is a red tick, on BOTH sides.
  ///
  /// Not the side's own colour, which is what this drew first and what made
  /// the grid unreadable: a green square on a green-tinted card and a blue
  /// square on a blue one are two different-looking marks for the same fact,
  /// and neither reads as "won" — they read as decoration. Whose points these
  /// are is already said by the colour bar at the top of the card and by
  /// which half of the screen they are on. What the grid has to say is
  /// *ticked or not ticked*, and one mark in one colour says it.
  static const _tick = Ps.live;

  @override
  Widget build(BuildContext context) {
    if (target <= 0 || target > 40) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized from the card, so the same grid works on a phone and on the
        // laptop at the scorer's table without a breakpoint. The floor is
        // what a tick needs to still be a tick rather than a red smudge.
        final box = ((constraints.maxWidth - (_perRow - 1) * 4) / _perRow)
            .clamp(13.0, 22.0);

        return Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < target; i++)
              Container(
                width: box,
                height: box,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Ps.surface,
                  // Every box keeps its outline, ticked or not: the empty
                  // ones are the half of the grid that says how much is left.
                  border: Border.all(color: Ps.faint, width: 1.1),
                ),
                child: i < filled
                    ? Icon(Icons.check_rounded, size: box - 3, color: _tick)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// The three labelled actions on a side's own card.
class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.accent,
    required this.enabled,
    required this.point,
    required this.correction,
    required this.retire,
    required this.onControl,
  });

  final Color accent;
  final bool enabled;
  final ScoreControl? point;
  final ScoreControl? correction;
  final ScoreControl? retire;
  final void Function(ScoreControl) onControl;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required ScoreControl? control,
      required Widget child,
      required Color color,
      int flex = 1,
    }) {
      final live = control != null && enabled;
      return Expanded(
        flex: flex,
        child: Opacity(
          opacity: live ? 1 : 0.4,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: live ? () => onControl(control) : null,
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          button(
            control: point,
            color: accent,
            child: Text(
              '+1',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 6),
          button(
            control: correction,
            color: accent,
            child: Icon(Icons.undo_rounded, size: 17, color: accent),
          ),
          if (retire != null) ...[
            const SizedBox(width: 6),
            button(
              control: retire,
              color: Ps.live,
              flex: 2,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flag_outlined, size: 14, color: Ps.live),
                  SizedBox(width: 4),
                  Text(
                    'RETIRE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Ps.live,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The card above the pad: who is winning the match, set by set.
///
/// Two questions, side by side, because a scorer and a spectator ask
/// different ones and both are looking at the same phone. On the left, "who
/// is winning" — the games or sets won, which is the only number that decides
/// anything. On the right, "how did we get here" — every period of the match
/// with its score, including the one being played.
class _Headline extends StatelessWidget {
  const _Headline({required this.board});

  final DuelBoard board;

  @override
  Widget build(BuildContext context) {
    final score = board.matchScore;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The left column exists for either fact on its own: a sport with
          // no tier above the running score still has a format worth stating,
          // and dropping the note with the score is how "21 points per game"
          // disappeared from every board that had no games.
          if (score != null || board.pointsNote != null) ...[
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (score != null) ...[
                  Text(
                    score.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      color: Ps.faint,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Half3(
                        value: '${score.a}',
                        accent: DuelPad.accentFor(Side.a),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '-',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                            color: Ps.faint,
                          ),
                        ),
                      ),
                      _Half3(
                        value: '${score.b}',
                        accent: DuelPad.accentFor(Side.b),
                      ),
                    ],
                  ),
                  ],
                  if (board.pointsNote != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      board.pointsNote!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5, color: Ps.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (board.periods.isNotEmpty)
              Container(
                width: 1,
                height: 54,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Ps.border,
              ),
          ],
          if (board.periods.isNotEmpty)
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in board.periods)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _PeriodBox(period: p),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the players are standing, and the way back from a mistake.
///
/// The ends line is here rather than on a card because it is a fact about the
/// COURT, not about either side — and because a scorer who has just swapped
/// ends needs to check it against what is in front of them, once, and then
/// forget it again.
class _EndsStrip extends StatelessWidget {
  const _EndsStrip({
    required this.board,
    required this.onUndo,
    required this.canUndo,
  });

  final DuelBoard board;
  final VoidCallback onUndo;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final note = board.endsNote;
    final status = board.status;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Ps.canvas,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded, size: 17, color: Ps.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status != null)
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Ps.ink,
                    ),
                  ),
                if (note != null)
                  Text(
                    note,
                    style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                  ),
              ],
            ),
          ),
          // The last resort, and the only control on the pad that undoes a
          // real event rather than entering a compensating one. Kept off the
          // side cards deliberately: "undo the last thing that happened" is
          // not a fact about either side, and a scorer reaching for it is
          // usually unsure which side it was.
          TextButton.icon(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.replay_rounded, size: 16),
            label: const Text('Undo last'),
            style: TextButton.styleFrom(
              foregroundColor: Ps.muted,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
