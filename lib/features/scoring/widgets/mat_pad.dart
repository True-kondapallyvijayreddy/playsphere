import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/scoring/scoring_plugin.dart';
import '../../../shared/ui_kit.dart';
import 'duel_pad.dart' show DuelPad;
import 'pad_chrome.dart' show PadButton;

/// The scoring pad for a mat sport: kabaddi and kho-kho.
///
/// ## Why this is a third pad
///
/// A rally pad is two big targets ([DuelPad]); a stacked pad is a scoreboard
/// and a tray of labelled events. Neither can score a raid, and the reason is
/// one number: **how many defenders are on the mat.** That number decides
/// whether the next tackle is worth one point or two, whether the bonus line
/// exists at all, and whether the side is one touch from an all-out. On a
/// stacked pad it is not on screen, so the scorer counts players by eye,
/// under a thirty-second raid clock, while the next raider is already
/// crossing the line. They get it wrong, and a wrong super tackle is a point
/// that decides matches.
///
/// So the mat is the pad. Both rosters are on screen with who is out and in
/// what order they come back, the count is a row of dots that can be read at
/// a glance rather than counted, and the actions are a grid of six large
/// tiles that each say what they are worth.
///
/// ## The pending queue is the point
///
/// Everything below the grid exists because of one rule: **the score never
/// waits for a name.** The engine accepts every action with nobody named and
/// parks what is missing (see `KabaddiPlugin`), and the queue in the third
/// column is where those come back — at a timeout, at half time, or after the
/// match. A pad that blocked on "who raided?" would lose the next raid, and a
/// scorer who loses a raid stops using the app.
class MatPad extends StatelessWidget {
  const MatPad({
    super.key,
    required this.board,
    required this.groups,
    required this.onControl,
    required this.onUndo,
    required this.canUndo,
    this.enabled = true,
  });

  final MatBoard board;
  final List<ScoreControlGroup> groups;
  final void Function(ScoreControl) onControl;
  final VoidCallback onUndo;
  final bool canUndo;

  /// False while a write is in flight, so a double tap on a fast phone cannot
  /// enter the same raid twice.
  final bool enabled;

  /// The controls the grid draws — everything the plugin offered except what
  /// the pending panel is already asking.
  ///
  /// A plugin has to offer its unfinished details as ordinary controls, or a
  /// stacked pad could never clear them. This pad draws them properly, in
  /// their own panel with the question and the score attached, so drawing
  /// them a second time as anonymous tiles would be the same job done twice
  /// and worse. Matched on the action the panel is already handling rather
  /// than on any sport's vocabulary.
  List<ScoreControlGroup> get _gridGroups {
    final claimed = {for (final d in board.pending) d.complete.action};
    if (claimed.isEmpty) return groups;
    return [
      for (final g in groups)
        if (g.controls.where((c) => !claimed.contains(c.action)).toList()
            case final kept when kept.isNotEmpty)
          ScoreControlGroup(title: g.title, controls: kept),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;

    final rosterA = _Roster(side: Side.a, data: board.a);
    final rosterB = _Roster(side: Side.b, data: board.b);
    final centre = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (board.turn != null) ...[
          _TurnCard(
            turn: board.turn!,
            onControl: onControl,
            enabled: enabled,
          ),
          const SizedBox(height: 10),
        ],
        _ActionGrid(
          groups: _gridGroups,
          onControl: onControl,
          enabled: enabled,
          columns: wide ? 3 : 2,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Scoreboard(board: board),
        const SizedBox(height: 10),
        if (wide)
          // Top-aligned rather than equal-height: the action grid measures
          // itself against the width it is given, so asking this row for an
          // intrinsic height would ask a LayoutBuilder a question it cannot
          // answer.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 172, child: rosterA),
              const SizedBox(width: 10),
              Expanded(child: centre),
              const SizedBox(width: 10),
              SizedBox(width: 172, child: rosterB),
            ],
          )
        else ...[
          // On a phone the actions come first and the rosters below them.
          // The grid is what the scorer's thumb is on for the whole match;
          // the rosters are what they read between raids.
          centre,
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: rosterA),
              const SizedBox(width: 10),
              Expanded(child: rosterB),
            ],
          ),
        ],
        const SizedBox(height: 10),
        _UndoBar(onUndo: onUndo, enabled: canUndo && enabled),
        const SizedBox(height: 10),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _History(plays: board.history)),
              const SizedBox(width: 10),
              Expanded(
                child: _Pending(
                  details: board.pending,
                  onControl: onControl,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _Scorecard(board: board)),
            ],
          )
        else ...[
          // The queue outranks the ledger on a small screen: it is the only
          // panel here that is a to-do rather than a record.
          _Pending(
            details: board.pending,
            onControl: onControl,
            enabled: enabled,
          ),
          const SizedBox(height: 10),
          _Scorecard(board: board),
          const SizedBox(height: 10),
          _History(plays: board.history),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The board
// ---------------------------------------------------------------------------

/// The dark header: both scores, the breakdown, the clock and the raid timer.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.board});

  final MatBoard board;

  static const _ink = Color(0xFF0B1220);

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final clock = _Clock(board: board);

    return Container(
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(Ps.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: narrow
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ScoreHalf(
                        side: Side.a,
                        data: board.a,
                        alignEnd: false,
                      ),
                    ),
                    Expanded(
                      child: _ScoreHalf(
                        side: Side.b,
                        data: board.b,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                clock,
              ],
            )
          // Intrinsic height so the clock column fills the bar rather than
          // floating in the middle of it. `stretch` alone would ask for an
          // infinite height here: the pad lives inside the screen's scroll
          // view, so nothing above it bounds the row.
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ScoreHalf(
                      side: Side.a,
                      data: board.a,
                      alignEnd: false,
                    ),
                  ),
                  clock,
                  Expanded(
                    child: _ScoreHalf(
                      side: Side.b,
                      data: board.b,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScoreHalf extends StatelessWidget {
  const _ScoreHalf({
    required this.side,
    required this.data,
    required this.alignEnd,
  });

  final Side side;
  final MatSide data;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final accent = DuelPad.accentFor(side);
    final cross =
        alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final name = Text(
      data.name.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
        color: Colors.white,
      ),
    );

    final score = Text(
      '${data.score}',
      style: const TextStyle(
        fontSize: 46,
        height: 1,
        fontWeight: FontWeight.w900,
        color: Colors.white,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          end: alignEnd ? Alignment.centerLeft : Alignment.centerRight,
          colors: [accent.withValues(alpha: 0.55), Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment:
                alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (alignEnd) ...[score, const SizedBox(width: 12)],
              Flexible(
                child: Column(
                  crossAxisAlignment: cross,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    name,
                    const SizedBox(height: 3),
                    Text(
                      [for (final c in data.chips) '${c.label}: ${c.value}']
                          .join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              if (!alignEnd) ...[const SizedBox(width: 12), score],
            ],
          ),
          const SizedBox(height: 8),
          _Strength(
            strength: data.strength,
            full: data.fullStrength,
            accent: accent,
            alignEnd: alignEnd,
          ),
          if (data.alert != null) ...[
            const SizedBox(height: 6),
            _AlertPill(text: data.alert!),
          ],
        ],
      ),
    );
  }
}

/// The mat count, as dots rather than a number.
///
/// Seven dots with two dark is read without counting; "5" has to be trusted.
/// The distinction matters because this is the number the scorer is checking
/// while a raid is in progress, and a glance is all they have.
class _Strength extends StatelessWidget {
  const _Strength({
    required this.strength,
    required this.full,
    required this.accent,
    required this.alignEnd,
  });

  final int strength;
  final int full;
  final Color accent;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (full <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        for (var i = 0; i < full; i++)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < strength
                    ? accent
                    : Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlertPill extends StatelessWidget {
  const _AlertPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Ps.live,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
      );
}

/// The match clock, and the countdown for one turn.
class _Clock extends StatelessWidget {
  const _Clock({required this.board});

  final MatBoard board;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        color: Colors.black.withValues(alpha: 0.35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (board.periodLabel != null)
              Text(
                board.periodLabel!.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            if (board.clock != null)
              Text(
                board.clock!,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFACC15),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            if (board.clockOf != null)
              Text(
                board.clockOf!,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            if (board.actionClockSeconds > 0) ...[
              const SizedBox(height: 6),
              _TurnClock(
                seconds: board.actionClockSeconds,
                label: board.actionClockLabel,
                // Restarting on the turn number is what makes this a raid
                // clock rather than a stopwatch: every recorded raid resets
                // it, which is exactly when a real one restarts.
                restartKey: board.history.length,
              ),
            ],
          ],
        ),
      );
}

/// The per-turn countdown.
///
/// Run here and not in the engine, deliberately. A reducer that read a wall
/// clock would rebuild the same event log to a different score depending on
/// when it was replayed, which would take the audit trail — the thing the
/// whole design rests on — with it.
class _TurnClock extends StatefulWidget {
  const _TurnClock({
    required this.seconds,
    required this.restartKey,
    this.label,
  });

  final int seconds;
  final String? label;
  final int restartKey;

  @override
  State<_TurnClock> createState() => _TurnClockState();
}

class _TurnClockState extends State<_TurnClock> {
  Timer? _timer;
  late int _left = widget.seconds;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_TurnClock old) {
    super.didUpdateWidget(old);
    if (old.restartKey != widget.restartKey ||
        old.seconds != widget.seconds) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    setState(() => _left = widget.seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _left <= 5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          '${_left}s',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: urgent ? Ps.live : const Color(0xFF4ADE80),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rosters
// ---------------------------------------------------------------------------

/// One side's players, split into who is on the mat and who is waiting to be
/// revived — in the order they will come back.
class _Roster extends StatelessWidget {
  const _Roster({required this.side, required this.data});

  final Side side;
  final MatSide data;

  @override
  Widget build(BuildContext context) {
    final accent = DuelPad.accentFor(side);
    // Nothing to draw for a match nobody entered a line-up for, and drawing an
    // empty box would say the squad is empty rather than unrecorded.
    if (data.active.isEmpty && data.out.isEmpty) {
      return const SizedBox.shrink();
    }

    return PsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Ps.radius),
              ),
            ),
            child: Text(
              data.onTheAttack
                  ? '${data.name} — raiding'.toUpperCase()
                  : data.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _RosterLabel('On the mat (${data.strength})'),
                for (final p in data.active) _PlayerRow(p: p, out: false),
                if (data.out.isNotEmpty) ...[
                  const Divider(height: 16, color: Ps.border),
                  _RosterLabel('Out (${data.out.length})', danger: true),
                  for (final p in data.out) _PlayerRow(p: p, out: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterLabel extends StatelessWidget {
  const _RosterLabel(this.text, {this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
            color: danger ? Ps.live : Ps.faint,
          ),
        ),
      );
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.p, required this.out});

  final MatPlayerChip p;
  final bool out;

  @override
  Widget build(BuildContext context) {
    final colour = out ? Ps.live : Ps.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              p.number ?? '·',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: colour,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: p.isActor ? FontWeight.w800 : FontWeight.w500,
                color: out ? Ps.muted : Ps.ink,
                decoration: out ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (p.isActor)
            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The turn
// ---------------------------------------------------------------------------

/// Who is taking this turn, and the one number that decides what it is worth.
class _TurnCard extends StatelessWidget {
  const _TurnCard({
    required this.turn,
    required this.onControl,
    required this.enabled,
  });

  final MatTurn turn;
  final void Function(ScoreControl) onControl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = DuelPad.accentFor(turn.side);
    return PsCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  turn.actorNumber ?? '?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MicroLabel(turn.title),
                  Text(
                    // Not naming the raider is a legitimate way to score a
                    // match, so this says so plainly rather than reading as a
                    // field somebody forgot.
                    turn.actorName ?? 'Not named',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: turn.actorName == null ? Ps.faint : Ps.ink,
                    ),
                  ),
                ],
              ),
              if (turn.change != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed:
                      enabled ? () => onControl(turn.change!) : null,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(turn.change!.label),
                ),
              ],
            ],
          ),
          if (turn.counterLabel != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MicroLabel(turn.counterLabel!),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${turn.counterValue ?? 0}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Ps.ink,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.groups_rounded,
                        size: 16, color: Ps.muted),
                  ],
                ),
              ],
            ),
          if (turn.nextTitle != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _MicroLabel(turn.nextTitle!),
                Text(
                  turn.nextName ?? '—',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Ps.muted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MicroLabel extends StatelessWidget {
  const _MicroLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Ps.faint,
        ),
      );
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// The quick-scoring grid: every action the plugin is offering right now,
/// each tile saying what it is worth.
///
/// The value is on the tile because a scorer under a raid clock should not
/// have to remember that a super tackle is two and a bonus is one — and
/// because those numbers are configurable per league, so what this pad is
/// worth in one competition is not what it is worth in the next. The plugin
/// puts the real figure in the control's tooltip; the tile prints it.
class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.groups,
    required this.onControl,
    required this.enabled,
    required this.columns,
  });

  final List<ScoreControlGroup> groups;
  final void Function(ScoreControl) onControl;
  final bool enabled;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 7, left: 2),
            child: Text(
              group.title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Ps.faint,
              ),
            ),
          ),
          if (group.controls.any((c) => c.style == ControlStyle.primary))
            LayoutBuilder(
              builder: (context, box) {
                const gap = 8.0;
                final width =
                    (box.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final c in group.controls)
                      SizedBox(
                        width: width,
                        child: _ActionTile(
                          control: c,
                          onPressed:
                              enabled ? () => onControl(c) : null,
                        ),
                      ),
                  ],
                );
              },
            )
          else
            // A group with no primary in it is housekeeping — timeouts, the
            // half-time button, the referee's calls. Ordinary chips, so it
            // cannot be confused with the grid a thumb lives on.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in group.controls)
                  PadButton(
                    control: c,
                    onPressed: enabled ? () => onControl(c) : null,
                  ),
              ],
            ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

/// One large tile: what it does, and what it is worth.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.control, required this.onPressed});

  final ScoreControl control;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final danger = control.style == ControlStyle.danger;
    final primary = control.style == ControlStyle.primary;
    final subtle = control.style == ControlStyle.subtle;

    final accent = danger
        ? Ps.live
        : control.side != Side.neutral
            ? DuelPad.accentFor(control.side)
            : Ps.primary;

    final filled = primary || danger;
    final disabled = onPressed == null;
    final background = disabled
        ? Ps.border
        : filled
            ? accent
            : subtle
                ? Ps.surface
                : accent.withValues(alpha: 0.10);
    final foreground = disabled
        ? Ps.faint
        : filled
            ? Colors.white
            : subtle
                ? Ps.ink
                : accent;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: filled ? Colors.transparent : Ps.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                control.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
              if (control.tooltip != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    control.tooltip!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: foreground.withValues(alpha: 0.8),
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

class _UndoBar extends StatelessWidget {
  const _UndoBar({required this.onUndo, required this.enabled});

  final VoidCallback onUndo;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: enabled ? onUndo : null,
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text('Undo last'),
        ),
      );
}

// ---------------------------------------------------------------------------
// Panels
// ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.badge});

  final String title;
  final Widget child;
  final int? badge;

  @override
  Widget build(BuildContext context) => PsCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Ps.faint,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Ps.live,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

/// The play-by-play, newest first.
class _History extends StatelessWidget {
  const _History({required this.plays});

  final List<MatPlay> plays;

  /// Twelve lines, because this is a glance-and-check panel rather than the
  /// archive — the full log lives in the match timeline below the pad, and
  /// rendering eighty rows here would push everything else off the screen.
  static const _visible = 12;

  @override
  Widget build(BuildContext context) {
    final recent = plays.reversed.take(_visible).toList();
    return _Panel(
      title: 'Raid history',
      child: recent.isEmpty
          ? const _Empty('No raids recorded yet.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in recent) _HistoryRow(play: p),
              ],
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.play});

  final MatPlay play;

  @override
  Widget build(BuildContext context) {
    final accent = DuelPad.accentFor(play.side);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              play.isTurn ? '#${play.no}' : '·',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Ps.faint,
              ),
            ),
          ),
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  play.result,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
                if (play.actor != null || play.at != null)
                  Text(
                    [if (play.actor != null) play.actor!, if (play.at != null) play.at!]
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Ps.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (play.points > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '+${play.points}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '${play.scoreA}-${play.scoreB}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Ps.muted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The unfinished details — the second half of "score first, details second".
class _Pending extends StatelessWidget {
  const _Pending({
    required this.details,
    required this.onControl,
    required this.enabled,
  });

  final List<MatDetail> details;
  final void Function(ScoreControl) onControl;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Pending details',
        badge: details.length,
        child: details.isEmpty
            ? const _Empty(
                'Nothing waiting. Every point so far has a name against it.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in details)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: DuelPad.accentFor(d.side),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  d.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Ps.ink,
                                  ),
                                ),
                                Text(
                                  d.question,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Ps.live,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed:
                                enabled ? () => onControl(d.complete) : null,
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(d.complete.label),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
}

/// The team scorecard: where every point came from.
class _Scorecard extends StatelessWidget {
  const _Scorecard({required this.board});

  final MatBoard board;

  @override
  Widget build(BuildContext context) {
    if (board.scorecard.isEmpty) return const SizedBox.shrink();
    return _Panel(
      title: 'Scorecard',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 28,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 34,
          horizontalMargin: 0,
          columnSpacing: 14,
          columns: [
            const DataColumn(label: Text('Team', style: _head)),
            for (final c in board.scorecardColumns)
              DataColumn(label: Text(c, style: _head), numeric: true),
          ],
          rows: [
            for (final row in board.scorecard)
              DataRow(cells: [
                DataCell(Text(
                  row.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: DuelPad.accentFor(row.side),
                  ),
                )),
                for (var i = 0; i < row.values.length; i++)
                  DataCell(Text(
                    '${row.values[i]}',
                    style: TextStyle(
                      fontSize: 12.5,
                      // The last column is the total, and it is the one a
                      // captain checks against the board on the wall.
                      fontWeight: i == row.values.length - 1
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: Ps.ink,
                    ),
                  )),
              ]),
          ],
        ),
      ),
    );
  }

  static const _head = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    color: Ps.faint,
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Ps.faint,
          ),
        ),
      );
}
