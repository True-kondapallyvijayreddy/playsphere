import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/models/arena_match.dart';
import '../../core/providers.dart';
import '../../domain/arena/arena_game.dart';
import '../../shared/identity.dart';
import '../../shared/ui_kit.dart';
import 'arena_providers.dart';
import 'widgets/arena_board_view.dart';
import 'widgets/arena_move_record.dart';

/// One game, live.
///
/// The screen holds three pieces of state and derives everything else: which
/// square is picked up, which ply is being reviewed, and whether a write is in
/// flight. The position, whose turn it is, what is legal and whether the game
/// is over all come from replaying the document — so two phones showing the
/// same match cannot disagree, and there is no local board to fall out of
/// sync with the server.
class ArenaBoardScreen extends ConsumerStatefulWidget {
  const ArenaBoardScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<ArenaBoardScreen> createState() => _ArenaBoardScreenState();
}

class _ArenaBoardScreenState extends ConsumerState<ArenaBoardScreen> {
  int? _selected;

  /// Which ply the board is showing, or null for "the live position".
  ///
  /// Reviewing is a read-only mode rather than a separate screen: the board
  /// is the same widget with no legal moves passed to it, which is the whole
  /// reason [ArenaBoardView] takes the move list as a parameter instead of
  /// asking the engine itself.
  int? _reviewPly;

  bool _busy = false;
  bool? _flipOverride;

  /// Drives the idle countdown. One second is the coarsest tick that still
  /// looks like a clock, and it only runs while a game is actually live —
  /// a finished game repainting once a second forever is a flat battery.
  Timer? _tick;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final async = ref.watch(arenaMatchProvider(widget.matchId));

    return Scaffold(
      backgroundColor: Ps.canvas,
      appBar: AppBar(
        title: Text(async.valueOrNull?.game?.name ?? 'Arena'),
        actions: [
          IconButton(
            tooltip: 'Game record',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () {
              final match = async.valueOrNull;
              final game = match?.game;
              if (match == null || game == null || uid == null) return;
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Ps.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(Ps.radius)),
                ),
                builder: (_) => ArenaMoveRecordSheet(
                  match: match,
                  game: game,
                  viewerUid: uid,
                  onReview: (ply) => setState(() {
                    _reviewPly = ply;
                    _selected = null;
                  }),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Flip the board',
            icon: const Icon(Icons.swap_vert),
            onPressed: () {
              // Toggles from whatever is on screen, which is the stored
              // override if there is one and otherwise the orientation the
              // player's own side implies.
              final match = async.valueOrNull;
              final game = match?.game;
              final current = _flipOverride ??
                  (game != null &&
                      uid != null &&
                      game.board(match!.gameConfig).flipForSideOne &&
                      match.sideOf(uid) == 1);
              setState(() => _flipOverride = !current);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          text: e is AppException ? e.message : 'Could not open this game.',
        ),
        data: (match) {
          if (match == null) {
            return const _Message(text: 'This game no longer exists.');
          }
          if (uid == null || !match.players.contains(uid)) {
            return const _Message(text: 'This game is not yours to watch.');
          }
          final game = match.game;
          if (game == null) {
            return const _Message(
              text: 'This game needs a newer version of PlaySphere.',
            );
          }
          return _body(context, match, game, uid);
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ArenaMatch match,
    ArenaGame game,
    String uid,
  ) {
    final mySide = match.sideOf(uid);
    final board = game.board(match.gameConfig);
    final flipped = _flipOverride ??
        (board.flipForSideOne && mySide == 1);

    final live = match.replay();
    final reviewing = _reviewPly != null && _reviewPly! < live.ply;
    final shown =
        reviewing ? match.replay(upToPly: _reviewPly).current : live.current;

    final myTurn = match.status == ArenaStatus.active &&
        !reviewing &&
        live.current.turn == mySide &&
        !_busy;

    final legal = myTurn ? game.legalMoves(shown, match.gameConfig) : const <ArenaMove>[];

    // A checkers piece part-way through a chain is already picked up: the
    // player has no choice about which piece moves next, so making them tap
    // it again would be busywork.
    final chain = shown.meta['chain'];
    final selected = chain is int && myTurn ? chain : _selected;

    final opponentUid = match.opponentOf(uid);

    return Column(
      children: [
        _PlayerBar(
          match: match,
          game: game,
          uid: opponentUid,
          position: live.current,
          isTurn: match.turnUid == opponentUid,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Center(
              child: ArenaBoardView(
                game: game,
                config: match.gameConfig,
                position: shown,
                legalMoves: legal,
                flipped: flipped,
                interactive: myTurn,
                selected: selected,
                lastMove: reviewing ? const [] : _lastMoveSquares(match),
                onTapSquare: (index) =>
                    _onTapSquare(match, game, shown, legal, selected, index),
              ),
            ),
          ),
        ),
        _PlayerBar(
          match: match,
          game: game,
          uid: uid,
          position: live.current,
          isTurn: match.turnUid == uid,
          isYou: true,
        ),
        _StatusLine(
          match: match,
          game: game,
          uid: uid,
          replay: live,
          reviewing: reviewing,
          now: _now,
        ),
        _MoveStrip(
          match: match,
          reviewPly: _reviewPly,
          onSelect: (ply) => setState(() {
            _reviewPly = ply;
            _selected = null;
          }),
        ),
        _ActionBar(
          match: match,
          game: game,
          uid: uid,
          busy: _busy,
          canAct: myTurn,
          legalMoves: legal,
          canClaimTimeout: match.canClaimTimeout(uid, _now),
          onClaimTimeout: () => _run(() => ref
              .read(arenaRepositoryProvider)
              .claimTimeout(match.id, uid)),
          onAccept: () => _run(() => ref
              .read(arenaRepositoryProvider)
              .accept(match.id, uid)),
          onWithdraw: () => _run(() => ref
              .read(arenaRepositoryProvider)
              .withdraw(match.id, uid)),
          onResign: () => _confirmResign(match, uid),
          onOfferDraw: () => _run(() => ref
              .read(arenaRepositoryProvider)
              .offerDraw(match.id, uid)),
          onAcceptDraw: () => _run(() => ref
              .read(arenaRepositoryProvider)
              .acceptDraw(match.id, uid)),
          onDeclineDraw: () => _run(
              () => ref.read(arenaRepositoryProvider).withdrawDraw(match.id)),
          onPass: () {
            final pass = legal.where((m) => m.kind == MoveKind.pass);
            if (pass.isNotEmpty) _submit(match, pass.first);
          },
        ),
      ],
    );
  }

  List<int> _lastMoveSquares(ArenaMatch match) {
    if (match.moves.isEmpty) return const [];
    final last = match.moves.last.move;
    return [if (last.from >= 0) last.from, if (last.to >= 0) last.to];
  }

  // --- Interaction -------------------------------------------------------

  Future<void> _onTapSquare(
    ArenaMatch match,
    ArenaGame game,
    ArenaPosition position,
    List<ArenaMove> legal,
    int? selected,
    int index,
  ) async {
    if (game.input == MoveInput.fromTo) {
      // Tapping the piece you are already holding puts it down.
      if (selected == index) {
        setState(() => _selected = null);
        return;
      }

      // A destination for the held piece beats picking up a new one. The two
      // can never both apply: no legal move in either from–to game lands on a
      // square your own piece is standing on.
      if (selected != null) {
        final candidates =
            legal.where((m) => m.from == selected && m.to == index).toList();
        if (candidates.isNotEmpty) {
          await _play(match, candidates);
          return;
        }
      }

      final canStart = legal.any((m) => m.from == index);
      setState(() => _selected = canStart ? index : null);
      return;
    }

    // Placement and column games: the square IS the move.
    final candidates = legal.where((m) => m.to == index).toList();
    if (candidates.isEmpty) return;
    await _play(match, candidates);
  }

  /// Plays the move, asking first when the tap does not name one uniquely.
  ///
  /// Promotion is the only case today — four legal moves share a from and a
  /// to — and the screen handles it without knowing what promotion is,
  /// because the engine labelled the alternatives.
  Future<void> _play(ArenaMatch match, List<ArenaMove> candidates) async {
    var move = candidates.first;
    if (candidates.length > 1) {
      final picked = await showModalBottomSheet<ArenaMove>(
        context: context,
        backgroundColor: Ps.surface,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Which piece?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              for (final option in candidates)
                ListTile(
                  title: Text(option.label ?? 'Play'),
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      move = picked;
    }
    setState(() => _selected = null);
    await _submit(match, move);
  }

  Future<void> _submit(ArenaMatch match, ArenaMove move) => _run(
        () => ref.read(arenaRepositoryProvider).submitMove(
              matchId: match.id,
              uid: ref.read(currentUidProvider)!,
              move: move,
              expectedPly: match.moves.length,
            ),
      );

  Future<void> _confirmResign(ArenaMatch match, String uid) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign this game?'),
        content: Text(
          '${match.nameOf(match.opponentOf(uid))} wins. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => ref.read(arenaRepositoryProvider).resign(match.id, uid));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _reviewPly = null);
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ---------------------------------------------------------------------------

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.match,
    required this.game,
    required this.uid,
    required this.position,
    required this.isTurn,
    this.isYou = false,
  });

  final ArenaMatch match;
  final ArenaGame game;
  final String? uid;
  final ArenaPosition position;
  final bool isTurn;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final side = uid == null ? -1 : match.sideOf(uid!);
    final summary = side < 0
        ? null
        : game.sideSummary(position, side, match.gameConfig);
    final colour =
        side < 0 ? Ps.muted : Color(game.sideColors[side]);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: isTurn ? Ps.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: Row(
        children: [
          PsAvatar(
            name: match.nameOf(uid),
            photoUrl: match.photos[uid],
            seed: uid,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isYou ? 'You' : match.nameOf(uid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        border: Border.all(color: Ps.border),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      side < 0 ? '' : game.sideNames[side],
                      style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                    ),
                    if (summary != null) ...[
                      const Text(' · ',
                          style: TextStyle(fontSize: 11.5, color: Ps.faint)),
                      Text(
                        summary,
                        style:
                            const TextStyle(fontSize: 11.5, color: Ps.muted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isTurn)
            const Icon(Icons.more_horiz, color: Ps.primary, size: 20),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.match,
    required this.game,
    required this.uid,
    required this.replay,
    required this.reviewing,
    required this.now,
  });

  final ArenaMatch match;
  final ArenaGame game;
  final String uid;
  final ArenaReplay replay;
  final bool reviewing;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (text, tone) = _message();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: tone.withValues(alpha: 0.10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  (String, Color) _message() {
    if (replay.truncatedAt != null) {
      return (
        'This game could not be replayed past move ${replay.truncatedAt}. '
        'Please report it.',
        Ps.live,
      );
    }
    if (reviewing) {
      return ('Reviewing an earlier position — tap Live to return.', Ps.muted);
    }
    final result = match.result;
    if (match.status == ArenaStatus.finished && result != null) {
      if (result.isDraw) return ('Drawn — ${result.reason}', Ps.muted);
      final youWon = result.winnerUid == uid;
      return (
        '${youWon ? 'You won' : '${match.nameOf(result.winnerUid)} won'}'
        ' — ${result.reason}',
        youWon ? Ps.primary : Ps.ink,
      );
    }
    if (match.status == ArenaStatus.declined) {
      return ('Challenge declined.', Ps.muted);
    }
    if (match.status == ArenaStatus.cancelled) {
      return ('Challenge withdrawn.', Ps.muted);
    }
    if (match.status == ArenaStatus.pending) {
      return match.challengerUid == uid
          ? ('Waiting for ${match.nameOf(match.opponentOf(uid))} to accept.',
              Ps.muted)
          : ('${match.nameOf(match.challengerUid)} challenged you.', Ps.primary);
    }
    if (match.drawOfferBy != null) {
      return match.drawOfferBy == uid
          ? ('You offered a draw.', Ps.muted)
          : ('${match.nameOf(match.drawOfferBy)} offers a draw.', Ps.primary);
    }
    final left = match.timeLeft(now);
    final clock = left == null ? '' : ' · ${_clock(left)}';

    // Go and reversi both reach positions where the only legal act is a pass,
    // and saying so beats leaving somebody tapping a board that will not move.
    if (match.isTurn(uid)) {
      final legal = game.legalMoves(replay.current, match.gameConfig);
      if (legal.length == 1 && legal.first.kind == MoveKind.pass) {
        return ('No legal move — you must pass.$clock', Ps.live);
      }
      // The last two minutes turn red: the clock is only fair if it is
      // impossible to miss before it runs out.
      final urgent = left != null && left.inSeconds <= 120;
      return (
        'Your move.$clock',
        urgent ? Ps.live : Ps.primary,
      );
    }
    if (match.hasTimedOut(now)) {
      return (
        '${match.nameOf(match.turnUid)} has not moved for ten minutes.',
        Ps.live,
      );
    }
    return ('Waiting for ${match.nameOf(match.turnUid)}.$clock', Ps.muted);
  }
}

/// The move list, and the traceback.
///
/// Horizontal rather than a panel because on a phone the board must keep the
/// screen. Every ply is tappable and rewinds the board to that position, which
/// is the whole "record each step" requirement made usable: a game is not just
/// stored move by move, it can be walked through move by move.
/// "9:58" — minutes and seconds, because the whole window is ten minutes and
/// "10m" would sit unchanged for the first sixty seconds of it.
String _clock(Duration left) {
  final minutes = left.inMinutes;
  final seconds = left.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')} left';
}

class _MoveStrip extends StatelessWidget {
  const _MoveStrip({
    required this.match,
    required this.reviewPly,
    required this.onSelect,
  });

  final ArenaMatch match;
  final int? reviewPly;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (match.moves.isEmpty) {
      return const SizedBox(height: 4);
    }
    final live = reviewPly == null;
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Ps.surface,
        border: Border(top: BorderSide(color: Ps.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: match.moves.length,
              itemBuilder: (context, i) {
                // Reversed so the newest move is always in view without a
                // scroll controller chasing it.
                final index = match.moves.length - 1 - i;
                final record = match.moves[index];
                final active = reviewPly == index + 1 ||
                    (live && index == match.moves.length - 1);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 2, vertical: 7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Ps.radiusSm),
                    onTap: () => onSelect(
                      index == match.moves.length - 1 ? null : index + 1,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: active ? Ps.primary : Ps.canvas,
                        borderRadius: BorderRadius.circular(Ps.radiusSm),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${index + 1}.',
                            style: TextStyle(
                              fontSize: 10,
                              color: active ? Colors.white70 : Ps.faint,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            record.notation,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: active ? Colors.white : Ps.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!live)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => onSelect(null),
                child: const Text('Live'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.match,
    required this.game,
    required this.uid,
    required this.busy,
    required this.canAct,
    required this.legalMoves,
    required this.canClaimTimeout,
    required this.onClaimTimeout,
    required this.onAccept,
    required this.onWithdraw,
    required this.onResign,
    required this.onOfferDraw,
    required this.onAcceptDraw,
    required this.onDeclineDraw,
    required this.onPass,
  });

  final ArenaMatch match;
  final ArenaGame game;
  final String uid;
  final bool busy;
  final bool canAct;
  final List<ArenaMove> legalMoves;

  /// Whether the ten minutes have run out on the OTHER player.
  final bool canClaimTimeout;
  final VoidCallback onClaimTimeout;
  final VoidCallback onAccept;
  final VoidCallback onWithdraw;
  final VoidCallback onResign;
  final VoidCallback onOfferDraw;
  final VoidCallback onAcceptDraw;
  final VoidCallback onDeclineDraw;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (match.status == ArenaStatus.pending) {
      if (match.challengerUid == uid) {
        children.add(_button('Withdraw', onWithdraw, tonal: true));
      } else {
        children
          ..add(_button('Decline', onWithdraw, tonal: true))
          ..add(_button('Accept', onAccept, filled: true));
      }
    } else if (match.status == ArenaStatus.active) {
      final offered = match.drawOfferBy;
      if (canClaimTimeout) {
        // Nothing else matters while the opponent is gone — the only useful
        // action is to close the game, so it is the only one offered.
        children.add(_button('Claim the win', onClaimTimeout, filled: true));
      } else if (offered != null && offered != uid) {
        children
          ..add(_button('Decline draw', onDeclineDraw, tonal: true))
          ..add(_button('Agree draw', onAcceptDraw, filled: true));
      } else {
        if (game.allowsPass && canAct &&
            legalMoves.any((m) => m.kind == MoveKind.pass)) {
          children.add(_button('Pass', onPass, tonal: true));
        }
        if (game.allowsDrawOffer && offered == null) {
          children.add(_button('Offer draw', onOfferDraw, tonal: true));
        }
        children.add(_button('Resign', onResign, tonal: true, danger: true));
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Ps.surface,
          border: Border(top: BorderSide(color: Ps.border)),
        ),
        child: Row(
          children: [
            for (final child in children) ...[
              Expanded(child: child),
              if (child != children.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _button(
    String label,
    VoidCallback onTap, {
    bool filled = false,
    bool tonal = false,
    bool danger = false,
  }) {
    final action = busy ? null : onTap;
    if (filled) {
      return FilledButton(onPressed: action, child: Text(label));
    }
    return OutlinedButton(
      onPressed: action,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? Ps.live : Ps.ink,
        side: BorderSide(color: danger ? Ps.live.withValues(alpha: 0.4) : Ps.border),
      ),
      child: Text(label),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Ps.muted),
          ),
        ),
      );
}
