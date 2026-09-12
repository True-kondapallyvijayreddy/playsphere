import 'package:flutter/material.dart';

import '../../../core/layout/responsive.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../shared/ui_kit.dart';
import 'pad_chrome.dart' show padColumnSpan;
import 'pad_theme.dart';

/// The scoring pad for cricket: the crease, the recent balls, and a keypad.
///
/// ## Why this is a fourth pad and not a restyled stacked one
///
/// The stacked pad draws a headline and every legal control in a wrap. For
/// twelve sports that is right. For cricket it produced a screen with a score
/// on it and thirty-one buttons under it, and it left out the only three
/// facts the scorer is actually holding in their head:
///
///  * **Who is on strike.** It rotates on every odd run and again at the end
///    of every over, so it changes without anybody pressing anything to
///    change it. A scorer who loses it puts the runs on the wrong batter, and
///    once two players' figures are mixed no later care can separate them.
///  * **Who is bowling, and how far into their over.** The pad enforces a new
///    bowler every over; the scorer needs to see it coming.
///  * **What the last few balls were.** "Two dots and a wide" is the unit
///    everyone at a ground thinks in, and a running total cannot express it.
///
/// So this pad states the crease continuously and puts the keypad under it —
/// which is also, not coincidentally, how every paper scorebook and every
/// cricket app that scorers actually use is laid out.
///
/// ## What it knows about cricket
///
/// Nothing. Every string on it — the overs notation, the strike rate, the
/// economy, the chase — is computed by the engine and handed over on a
/// [CreaseBoard], for the reason set out there: those are conventions, not
/// arithmetic, and a pad that computed them would be a pad that knows the
/// laws of the game. The keypad is built from [ScoreControlGroup]s exactly as
/// every other pad's is, and the `+` drawers come from
/// [ScoreControl.variants], which is a general facility rather than a cricket
/// one.
class CreasePad extends StatelessWidget {
  const CreasePad({
    super.key,
    required this.board,
    required this.groups,
    required this.enabled,
    required this.canUndo,
    required this.onUndo,
    required this.onControl,
    this.showShortcuts = false,
  });

  final CreaseBoard board;
  final List<ScoreControlGroup> groups;
  final bool enabled;
  final bool canUndo;
  final VoidCallback onUndo;
  final void Function(ScoreControl) onControl;
  final bool showShortcuts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScoreHead(board: board),
        const SizedBox(height: 12),
        _CreaseTable(board: board),
        const SizedBox(height: 10),
        _BallStrip(balls: board.timeline, canUndo: canUndo, onUndo: onUndo),
        const SizedBox(height: 6),
        for (final group in groups) ...[
          _GroupHeading(group.title),
          _Keypad(
            controls: group.controls,
            enabled: enabled,
            onControl: onControl,
            showShortcuts: showShortcuts,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// The scoreboard: who is batting, the total, and the chase.
///
/// Dark, and the only dark thing on the screen. Everything below it is an
/// input surface and everything in it is a readout, and a scorer glancing up
/// from the pitch has to find the total without reading — the same reason the
/// board at a ground is a black rectangle.
class _ScoreHead extends StatelessWidget {
  const _ScoreHead({required this.board});

  final CreaseBoard board;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Ps.radius + 2),
        border: Border.all(color: PadInk.boardEdge),
        boxShadow: PadInk.board,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PadInk.boardTop, PadInk.boardMid, PadInk.boardBottom],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Column(
        children: [
          // The batting side, as a lit pill rather than a line of text. It is
          // the one label on the board that answers "whose innings is this",
          // and after the break it is the answer that changed.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Ps.primary.withValues(alpha: 0.14),
              border: Border.all(color: Ps.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Ps.primary,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    board.battingTeam.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (board.inningsLabel case final label?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: Ps.faint),
              ),
            ),
          const SizedBox(height: 8),
          // The total changes on nearly every press, so it animates. A scorer
          // glancing up from the pitch catches the movement well before they
          // read the number — and on a board this size, movement is the only
          // confirmation that a tap landed at all.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
            ),
            child: FittedBox(
              key: ValueKey(board.score),
              child: Text(
                board.score,
                style: TextStyle(
                  fontSize: 56,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  color: Colors.white,
                  fontFeatures: PadInk.figures,
                  // The green is the glow rather than the fill. As a fill it
                  // sat at about 3:1 on near-black; as light behind white
                  // numerals it keeps the brand on the board and the total at
                  // full contrast.
                  shadows: [
                    Shadow(
                      color: Ps.primary.withValues(alpha: 0.55),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (board.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [for (final n in board.notes) _NoteChip(n)],
            ),
          ],
          const SizedBox(height: 14),
          // The three numbers that qualify the total. Every scoreboard in
          // cricket carries them and none of them fits in the total itself.
          //
          // Set on their own inset rail, divided. Spread across the bare
          // board they read as three loose labels; boxed and ruled they read
          // as an instrument panel, and the eye finds "Ov" in one move.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(Ps.radiusSm),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                if (board.extras case final e?) ...[
                  Expanded(child: _HeadStat('Ex', '$e')),
                  const _StatRule(),
                ],
                Expanded(
                  child: _HeadStat(
                    'Ov',
                    board.oversOf == null
                        ? board.overs
                        : '${board.overs} / ${board.oversOf}',
                    emphasis: true,
                  ),
                ),
                if (board.runRate case final rr?) ...[
                  const _StatRule(),
                  Expanded(child: _HeadStat('CRR', rr)),
                ],
              ],
            ),
          ),
          if (board.chaseLine != null || board.chaseNeed != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(color: PadInk.amber.withValues(alpha: 0.3)),
                gradient: LinearGradient(
                  colors: [
                    PadInk.amber.withValues(alpha: 0.16),
                    PadInk.amber.withValues(alpha: 0.06),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.flag_rounded,
                          size: 14, color: PadInk.amber),
                      const SizedBox(width: 6),
                      if (board.chaseLine case final line?)
                        Flexible(
                          child: Text(
                            line,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              fontFeatures: PadInk.figures,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (board.chaseNeed case final need?)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        need,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PadInk.boardMuted,
                          fontFeatures: PadInk.figures,
                        ),
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

class _HeadStat extends StatelessWidget {
  const _HeadStat(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: PadInk.boardMuted,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          child: Text(
            value,
            style: TextStyle(
              fontSize: emphasis ? 16 : 14,
              fontWeight: FontWeight.w800,
              color: emphasis ? Colors.white : const Color(0xFFE2E8F0),
              fontFeatures: PadInk.figures,
            ),
          ),
        ),
      ],
    );
  }
}

/// The hairline between two head stats.
class _StatRule extends StatelessWidget {
  const _StatRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: Colors.white.withValues(alpha: 0.09),
    );
  }
}

/// 'FREE HIT', 'NEW BATTER'. Amber, because each one changes what the next
/// press is allowed to be and a scorer who misses it enters an illegal
/// delivery and has to undo it in front of the players.
class _NoteChip extends StatelessWidget {
  const _NoteChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: amber.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
          color: amber,
        ),
      ),
    );
  }
}

/// The two batters and the bowler, as the two little tables every scorecard
/// in the world uses. The column headings are the abbreviations a cricketer
/// reads without thinking — R B 4s 6s SR, then O M R W Eco.
class _CreaseTable extends StatelessWidget {
  const _CreaseTable({required this.board});

  final CreaseBoard board;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
        boxShadow: PadInk.panel,
      ),
      child: Column(
        children: [
          const _TableHead(
            icon: Icons.sports_cricket,
            label: 'Batter',
            columns: ['R', 'B', '4s', '6s', 'SR'],
          ),
          if (board.batters.isEmpty)
            const _EmptyRow('Nobody at the crease yet')
          else
            for (final b in board.batters) _BatterRow(batter: b),
          const Divider(height: 1, color: Ps.border),
          const _TableHead(
            icon: Icons.sports_baseball_outlined,
            label: 'Bowler',
            columns: ['O', 'M', 'R', 'W', 'Eco'],
          ),
          if (board.bowler case final b?)
            _StatRow(
              name: b.name,
              highlight: false,
              cells: [
                b.overs,
                '${b.maidens}',
                '${b.runs}',
                '${b.wickets}',
                b.economy
              ],
            )
          else
            const _EmptyRow('Nobody named to bowl'),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead({
    required this.icon,
    required this.label,
    required this.columns,
  });

  final IconData icon;
  final String label;
  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Ps.canvas,
      child: Row(
        children: [
          Icon(icon, size: 14, color: Ps.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: Ps.muted,
              ),
            ),
          ),
          for (final c in columns)
            SizedBox(
              width: _cellWidth,
              child: Text(
                c,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Ps.faint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const double _cellWidth = 38;

class _BatterRow extends StatelessWidget {
  const _BatterRow({required this.batter});

  final CreaseBatter batter;

  @override
  Widget build(BuildContext context) {
    return _StatRow(
      // The asterisk is not decoration. It is the notation every scorecard
      // uses for "not out and on strike", and a scorer who has ever kept a
      // book reads it faster than any highlight.
      name: batter.onStrike ? '${batter.name} *' : batter.name,
      highlight: batter.onStrike,
      cells: [
        '${batter.runs}',
        '${batter.balls}',
        '${batter.fours}',
        '${batter.sixes}',
        batter.strikeRate,
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.name,
    required this.highlight,
    required this.cells,
  });

  final String name;
  final bool highlight;
  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
      decoration: BoxDecoration(
        gradient: highlight
            ? LinearGradient(
                colors: [
                  Ps.primary.withValues(alpha: 0.12),
                  Ps.primary.withValues(alpha: 0.02),
                ],
              )
            : null,
      ),
      child: Row(
        children: [
          // The striker's rail. The asterisk is the notation, and it stays —
          // but it is four pixels wide at arm's length, and the row it marks
          // is the one fact on this panel the scorer must never lose.
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: highlight ? Ps.primary : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
                color: highlight ? Ps.primary : Ps.ink,
              ),
            ),
          ),
          for (final c in cells)
            SizedBox(
              width: _cellWidth,
              child: Text(
                c,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  color: highlight ? Ps.ink : Ps.muted,
                  fontFeatures: PadInk.figures,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(fontSize: 12.5, color: Ps.muted),
        ),
      ),
    );
  }
}

/// The recent deliveries, newest on the right, with the undo beside them.
///
/// Undo lives here on purpose. It is the button a scorer reaches for the
/// instant they see a wrong ball in this strip, and putting the two together
/// means the mistake and its correction are in the same glance rather than at
/// opposite ends of a scrolling page.
class _BallStrip extends StatelessWidget {
  const _BallStrip({
    required this.balls,
    required this.canUndo,
    required this.onUndo,
  });

  final List<BallChip> balls;
  final bool canUndo;
  final VoidCallback onUndo;

  /// How many are drawn. Ten is what a scorer is asked for — "what have the
  /// last ten balls been" — and it is also about two overs, which is the
  /// window in which anything is still worth correcting.
  static const _shown = 10;

  @override
  Widget build(BuildContext context) {
    final recent =
        balls.length <= _shown ? balls : balls.sublist(balls.length - _shown);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
        boxShadow: PadInk.panel,
      ),
      child: Row(
        children: [
          Expanded(
            child: recent.isEmpty
                ? const Text(
                    'No balls bowled yet',
                    style: TextStyle(fontSize: 12.5, color: Ps.muted),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // Reversed so the newest ball is pinned in view without a
                    // scroll controller to drive to the end after every tap.
                    reverse: true,
                    child: Row(
                      children: [
                        for (final ball in recent) ...[
                          _BallDot(ball, newest: ball == recent.last),
                          if (ball.endsOver && ball != recent.last)
                            const _OverBreak(),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(width: 4),
          // Undo is a labelled key, not a bare glyph.
          //
          // It is the most consequential control on the pad — it deletes a
          // recorded ball in front of the players — and as a borderless icon
          // it looked like a decoration on the end of the strip. Given the
          // same moulded treatment as the keypad, it reads as a control, and
          // its red says what kind.
          Tooltip(
            message: 'Undo the last ball',
            child: PadPressable(
              onTap: canUndo ? onUndo : null,
              builder: (context, pressed) => AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                  color: canUndo ? null : Ps.canvas,
                  gradient: canUndo ? PadInk.keyGhost(Ps.live) : null,
                  border: Border.all(
                    color: Ps.live.withValues(alpha: canUndo ? 0.3 : 0.12),
                  ),
                  boxShadow: !canUndo
                      ? null
                      : pressed
                          ? PadInk.keyPressed(Ps.live)
                          : PadInk.key(Ps.live, filled: false),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.undo_rounded,
                      size: 16,
                      color: canUndo ? Ps.live : Ps.faint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Undo',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: canUndo ? Ps.live : Ps.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BallDot extends StatelessWidget {
  const _BallDot(this.ball, {this.newest = false});

  final BallChip ball;

  /// The ball just bowled. Ringed, so the scorer's eye lands on the ball they
  /// are most likely to want to undo without counting along the strip.
  final bool newest;

  @override
  Widget build(BuildContext context) {
    // Colour carries the meaning; the label carries the detail. A scorer
    // scanning the strip for the last wicket finds red before they read
    // anything.
    final (bg, fg) = switch (ball.kind) {
      BallKind.dot => (Ps.canvas, Ps.muted),
      BallKind.runs => (const Color(0xFF334155), Colors.white),
      BallKind.boundary => (const Color(0xFF2563EB), Colors.white),
      BallKind.maximum => (const Color(0xFF7C3AED), Colors.white),
      BallKind.wicket => (Ps.live, Colors.white),
      BallKind.extra => (const Color(0xFFF59E0B), Colors.white),
    };

    final solid = ball.kind != BallKind.dot;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: EdgeInsets.only(right: 6, top: newest ? 0 : 1),
      constraints: const BoxConstraints(minWidth: 34),
      height: newest ? 36 : 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        gradient: solid
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(bg, Colors.white, 0.16)!, bg],
              )
            : null,
        color: solid ? null : bg,
        border: Border.all(
          color: newest
              ? (solid ? Colors.white.withValues(alpha: 0.85) : Ps.muted)
              : (solid ? Colors.transparent : Ps.border),
          width: newest ? 1.6 : 1,
        ),
        boxShadow: solid
            ? [
                BoxShadow(
                  color: bg.withValues(alpha: newest ? 0.45 : 0.28),
                  blurRadius: newest ? 8 : 5,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        ball.label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: fg,
          fontFeatures: PadInk.figures,
        ),
      ),
    );
  }
}

class _OverBreak extends StatelessWidget {
  const _OverBreak();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 14,
      margin: const EdgeInsets.only(right: 8, left: 2),
      decoration: BoxDecoration(
        color: Ps.faint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8, left: 2),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Ps.muted,
            ),
          ),
          const SizedBox(width: 10),
          // The rule carries the eye across to the keys the heading names,
          // which is what separates four stacked groups into four groups
          // rather than one wall of keys with words in it.
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Ps.border, Ps.border.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A group of controls, drawn as an even grid.
///
/// A grid rather than a wrap because these are a keypad: 0-6 in equal tiles
/// is a shape a thumb learns in one match, and the same six controls laid out
/// as pill buttons of varying width have to be read every time.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.controls,
    required this.enabled,
    required this.onControl,
    required this.showShortcuts,
  });

  final List<ScoreControl> controls;
  final bool enabled;
  final void Function(ScoreControl) onControl;
  final bool showShortcuts;

  @override
  Widget build(BuildContext context) {
    // Each control is one tile; one with a drawer is two — itself, and the
    // `+` that opens the rest. See [ScoreControl.variants].
    // A tile and the number of columns its LABEL needs. "4" and "W" want one
    // each; "Wicket — run out" wants three, and squeezing it into one is what
    // the `FittedBox` inside [_PadTile] used to do — shrinking 17pt type to
    // about 7pt, on a pad held at arm's length in daylight. The keypad shape
    // is worth keeping for the digits, so the fix is to let a long label take
    // the room it needs rather than to abandon the grid.
    final tiles = <(Widget, int)>[];
    for (final c in controls) {
      tiles.add((
        _PadTile(
          label: c.label,
          shortcut: showShortcuts ? c.shortcut : null,
          tooltip: c.tooltip,
          style: c.style,
          onTap: enabled ? () => onControl(c) : null,
        ),
        padColumnSpan(c.label),
      ));
      if (c.variants.isNotEmpty) {
        tiles.add((
          _PadTile(
            label: '${c.label}+',
            tooltip: 'More ${c.label.toLowerCase()} options',
            style: c.style,
            outlined: true,
            onTap: enabled ? () => _openDrawer(context, c) : null,
          ),
          padColumnSpan('${c.label}+'),
        ));
      }
    }
    if (tiles.isEmpty) return const SizedBox.shrink();

    final perRow = context.responsive<int>(compact: 4, medium: 6, expanded: 7);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final column = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (tile, span) in tiles)
              SizedBox(
                // A span never exceeds the row, so a very long label on a
                // narrow phone becomes a full-width button rather than one
                // that runs off the side.
                width: column * span.clamp(1, perRow) +
                    gap * (span.clamp(1, perRow) - 1),
                child: tile,
              ),
          ],
        );
      },
    );
  }

  Future<void> _openDrawer(BuildContext context, ScoreControl parent) async {
    // Scroll-controlled and scrollable, both.
    //
    // A default sheet is capped at half the screen and lays its child out
    // unbounded, so the no-ball drawer — six graded options plus a heading —
    // overflowed off the bottom, taking NB+5 and NB+6 with it. Those are the
    // rarest extras in the list and therefore the exact ones a scorer opens
    // the drawer to find; a drawer that hides its tail is worse than the flat
    // wall of buttons it replaced.
    final picked = await showModalBottomSheet<ScoreControl>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                parent.label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Ps.ink,
                ),
              ),
            ),
            if (parent.tooltip case final t?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  t,
                  style: const TextStyle(fontSize: 13, color: Ps.muted),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final v in parent.variants)
                    ListTile(
                      title: Text(
                        v.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: v.tooltip == null ? null : Text(v.tooltip!),
                      onTap: () => Navigator.pop(sheet, v),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) onControl(picked);
  }
}

/// One key. Square-ish, big, and labelled by what it records.
///
/// Drawn as a moulded key rather than a flat rectangle: a gradient fill, a
/// shadow tinted with the key's own accent, and a sink under the thumb. See
/// [PadInk] for why a pad earns depth the rest of the app does not.
class _PadTile extends StatelessWidget {
  const _PadTile({
    required this.label,
    required this.style,
    required this.onTap,
    this.shortcut,
    this.tooltip,
    this.outlined = false,
  });

  final String label;
  final String? shortcut;
  final String? tooltip;
  final ControlStyle style;
  final VoidCallback? onTap;

  /// The `+` twin of a control with a drawer: same colour, hollow, so the pair
  /// reads as one thing with a door on it rather than as two commands.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final danger = style == ControlStyle.danger;
    final primary = style == ControlStyle.primary;
    final accent = danger
        ? Ps.live
        : primary
            ? Ps.primary
            : PadInk.slate;

    final disabled = onTap == null;
    final filled = (primary || danger) && !outlined;
    final foreground = disabled
        ? Ps.faint
        : filled
            ? Colors.white
            : accent;

    final radius = BorderRadius.circular(Ps.radiusSm + 2);
    final height = context.responsive<double>(
      compact: 58,
      medium: 54,
      expanded: 50,
    );

    return Tooltip(
      message: tooltip ?? '',
      child: PadPressable(
        onTap: onTap,
        borderRadius: radius,
        builder: (context, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                  : accent.withValues(alpha: disabled ? 0.12 : 0.28),
              width: outlined ? 1.4 : 1,
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
              FittedBox(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: foreground,
                    fontFeatures: PadInk.figures,
                    // A solid key carries its label over a mid-tone fill. The
                    // shadow is what keeps a white "4" legible on green in
                    // direct sun, which is the light this pad is used in.
                    shadows: filled
                        ? const [
                            Shadow(
                              color: Color(0x33000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              if (shortcut != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    shortcut!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: filled
                          ? Colors.white.withValues(alpha: 0.7)
                          : Ps.faint,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
