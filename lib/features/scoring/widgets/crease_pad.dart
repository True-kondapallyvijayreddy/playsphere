import 'package:flutter/material.dart';

import '../../../core/layout/responsive.dart';
import '../../../domain/scoring/scoring_plugin.dart';
import '../../../shared/ui_kit.dart';

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
        const SizedBox(height: 10),
        _CreaseTable(board: board),
        const SizedBox(height: 10),
        _BallStrip(balls: board.timeline, canUndo: canUndo, onUndo: onUndo),
        const SizedBox(height: 14),
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
    const ink = Color(0xFF0B1220);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(Ps.radius),
      ),
      child: Column(
        children: [
          Text(
            board.battingTeam.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Colors.white,
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
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              board.score,
              style: const TextStyle(
                fontSize: 52,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
                color: Ps.primary,
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
          const SizedBox(height: 12),
          // The three numbers that qualify the total. Every scoreboard in
          // cricket carries them and none of them fits in the total itself.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (board.extras case final e?) _HeadStat('Ex', '$e'),
              _HeadStat(
                'Ov',
                board.oversOf == null
                    ? board.overs
                    : '${board.overs} / ${board.oversOf}',
                emphasis: true,
              ),
              if (board.runRate case final rr?) _HeadStat('CRR', rr),
            ],
          ),
          if (board.chaseLine != null || board.chaseNeed != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(Ps.radiusSm),
              ),
              child: Column(
                children: [
                  if (board.chaseLine case final line?)
                    Text(
                      line,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  if (board.chaseNeed case final need?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        need,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Ps.faint,
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
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Ps.faint,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasis ? 15 : 13.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
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
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
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
            for (final b in board.batters)
              _BatterRow(batter: b),
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
              cells: [b.overs, '${b.maidens}', '${b.runs}', '${b.wickets}',
                  b.economy],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Ps.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Ps.ink,
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
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: highlight ? Ps.primary.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
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
                  color: Ps.ink,
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
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radius),
        border: Border.all(color: Ps.border),
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
                          _BallDot(ball),
                          if (ball.endsOver && ball != recent.last)
                            const _OverBreak(),
                        ],
                      ],
                    ),
                  ),
          ),
          IconButton(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.backspace_outlined),
            tooltip: 'Undo the last ball',
            style: IconButton.styleFrom(foregroundColor: Ps.live),
          ),
        ],
      ),
    );
  }
}

class _BallDot extends StatelessWidget {
  const _BallDot(this.ball);

  final BallChip ball;

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

    return Container(
      margin: const EdgeInsets.only(right: 6),
      constraints: const BoxConstraints(minWidth: 34),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(100),
        border: ball.kind == BallKind.dot
            ? Border.all(color: Ps.border)
            : null,
      ),
      child: Text(
        ball.label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: fg,
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
      width: 1,
      height: 18,
      margin: const EdgeInsets.only(right: 6),
      color: Ps.border,
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 2),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Ps.faint,
        ),
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
    final tiles = <Widget>[];
    for (final c in controls) {
      tiles.add(
        _PadTile(
          label: c.label,
          shortcut: showShortcuts ? c.shortcut : null,
          tooltip: c.tooltip,
          style: c.style,
          onTap: enabled ? () => onControl(c) : null,
        ),
      );
      if (c.variants.isNotEmpty) {
        tiles.add(
          _PadTile(
            label: '${c.label}+',
            tooltip: 'More ${c.label.toLowerCase()} options',
            style: c.style,
            outlined: true,
            onTap: enabled ? () => _openDrawer(context, c) : null,
          ),
        );
      }
    }
    if (tiles.isEmpty) return const SizedBox.shrink();

    final perRow = context.responsive<int>(compact: 4, medium: 6, expanded: 7);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width =
            (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
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
            : const Color(0xFF334155);

    final disabled = onTap == null;
    final filled = (primary || danger) && !outlined;
    final foreground = disabled
        ? Ps.faint
        : filled
            ? Colors.white
            : accent;

    final height = context.responsive<double>(
      compact: 58,
      medium: 54,
      expanded: 50,
    );

    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: disabled
            ? Ps.canvas
            : filled
                ? accent
                : accent.withValues(alpha: outlined ? 0.04 : 0.08),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Ps.radiusSm),
              border: Border.all(
                color: filled
                    ? Colors.transparent
                    : accent.withValues(alpha: disabled ? 0.15 : 0.35),
                width: outlined ? 1.4 : 1,
              ),
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
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: foreground,
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
      ),
    );
  }
}
