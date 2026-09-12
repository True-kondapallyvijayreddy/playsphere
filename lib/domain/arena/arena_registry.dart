import 'arena_game.dart';
import 'games/checkers_game.dart';
import 'games/chess_game.dart';
import 'games/connect_four_game.dart';
import 'games/go_game.dart';
import 'games/gomoku_game.dart';
import 'games/reversi_game.dart';

/// Every game the Arena can play, and the only place that list is written.
///
/// Ordered the way the grid shows them: the two most people already know
/// first, then the ones worth discovering. A seventh game is one line here
/// and one file in `games/` — nothing in the screens changes, which is the
/// whole point of the plugin shape.
abstract final class ArenaGames {
  static const chess = ChessGame();
  static const checkers = CheckersGame();
  static const connectFour = ConnectFourGame();
  static const reversi = ReversiGame();
  static const gomoku = GomokuGame();
  static const go = GoGame();

  static const List<ArenaGame> all = [
    chess,
    checkers,
    connectFour,
    reversi,
    gomoku,
    go,
  ];

  /// The engine for a stored match, or null when a document names a game this
  /// build does not have.
  ///
  /// Returning null rather than falling back to chess is deliberate: an old
  /// client opening a match from a game it has never heard of must say "update
  /// the app", not silently draw a chessboard over somebody's go game.
  static ArenaGame? byId(String? id) {
    for (final game in all) {
      if (game.id == id) return game;
    }
    return null;
  }
}
