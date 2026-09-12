import '../arena_game.dart';

/// The four directions a line can run in on a grid: across, down, and the two
/// diagonals. Their opposites are covered by scanning from every cell, so
/// eight would double the work for no extra lines.
const List<List<int>> lineDirections = [
  [1, 0],
  [0, 1],
  [1, 1],
  [1, -1],
];

/// The run of [need]-or-more identical stones through [index], if there is
/// one.
///
/// Shared by connect four and gomoku, which differ in board size and in what
/// counts as long enough and in nothing else at all. Returned as the list of
/// squares rather than a bool so the board can light them up — the moment a
/// game ends is exactly when somebody wants to see WHY.
List<int>? runThrough(
  ArenaPosition p,
  BoardSpec board,
  int index,
  int need,
) {
  final code = p.cells[index];
  if (code == 0) return null;
  final col = board.colOf(index);
  final row = board.rowOf(index);

  for (final dir in lineDirections) {
    final line = <int>[index];

    // Walk both ways from the stone just played, so a five made in the middle
    // of an existing run is found from wherever the last stone landed.
    for (final sign in const [1, -1]) {
      var c = col + dir[0] * sign;
      var r = row + dir[1] * sign;
      while (board.inBounds(c, r) && p.cells[board.index(c, r)] == code) {
        line.add(board.index(c, r));
        c += dir[0] * sign;
        r += dir[1] * sign;
      }
    }

    if (line.length >= need) {
      line.sort();
      return line;
    }
  }
  return null;
}

/// The winning run anywhere on the board, scanning every occupied square.
///
/// [runThrough] is the cheap check after a move; this is the one that answers
/// for a position arrived at by replay, where there is no "last move" to
/// start from.
List<int>? anyRun(ArenaPosition p, BoardSpec board, int need) {
  for (var i = 0; i < p.cells.length; i++) {
    if (p.cells[i] == 0) continue;
    final line = runThrough(p, board, i, need);
    if (line != null) return line;
  }
  return null;
}

/// Column letters for notation — A, B, … Z, then AA. Boards never get that
/// wide, but a fallback that produces a readable string beats one that throws.
String fileLabel(int col) {
  if (col < 26) return String.fromCharCode(65 + col);
  return '${fileLabel(col ~/ 26 - 1)}${fileLabel(col % 26)}';
}
