import 'package:flutter/material.dart';

import '../../../core/models/arena_match.dart';
import '../../../domain/arena/arena_game.dart';
import '../../../shared/ui_kit.dart';

/// The full game record: every move by both players, in words.
///
/// This is the thing the move strip along the bottom of the board cannot be.
/// The strip is for orientation while playing — it has to stay one line tall,
/// so it can only carry notation. This is for afterwards: "Knight g1 → f3",
/// "Bishop f8 takes the knight on c3 — check", one row per move, with the
/// position one tap away.
///
/// Descriptions are computed here rather than stored on the document. Replay
/// already reconstructs every position the game passed through, and a
/// description is a pure function of the position a move was made in — so
/// storing it would be duplicating derivable data, and would freeze the
/// wording of every game ever played at whatever it said the day it was
/// written.
class ArenaMoveRecordSheet extends StatelessWidget {
  const ArenaMoveRecordSheet({
    super.key,
    required this.match,
    required this.game,
    required this.viewerUid,
    required this.onReview,
  });

  final ArenaMatch match;
  final ArenaGame game;
  final String viewerUid;

  /// Rewinds the board to the position after this many moves. Null is live.
  final ValueChanged<int?> onReview;

  @override
  Widget build(BuildContext context) {
    final replay = match.replay();
    final config = match.gameConfig;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Game record',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Every move, both players. Tap one to see the board '
                        'as it stood.',
                        style: TextStyle(fontSize: 11.5, color: Ps.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: match.moves.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No moves yet. Every one you play is kept here, so you '
                        'can walk back through the game afterwards.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Ps.muted),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: controller,
                    itemCount: match.moves.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, index) {
                      final record = match.moves[index];
                      // The position the move was made IN, which is what a
                      // description has to be computed against.
                      final before = index < replay.positions.length
                          ? replay.positions[index]
                          : null;
                      final description = before == null
                          ? record.notation
                          : game.describe(before, record.move, config);

                      return _MoveRow(
                        number: index + 1,
                        notation: record.notation,
                        description: description,
                        who: record.uid == viewerUid
                            ? 'You'
                            : match.nameOf(record.uid),
                        colour: Color(game.sideColors[record.side]),
                        onTap: () {
                          Navigator.of(context).pop();
                          onReview(
                            index == match.moves.length - 1 ? null : index + 1,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.number,
    required this.notation,
    required this.description,
    required this.who,
    required this.colour,
    required this.onTap,
  });

  final int number;
  final String notation;
  final String description;
  final String who;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '$number.',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Ps.faint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  border: Border.all(color: Ps.border),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                  Text(
                    '$who · $notation',
                    style: const TextStyle(fontSize: 11, color: Ps.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
