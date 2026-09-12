import 'package:flutter/foundation.dart';

/// A board game playable inside the Arena.
///
/// ## Why this is a plugin and not six screens
///
/// The Arena ships chess, checkers, go, reversi, connect four and gomoku, and
/// the temptation with six games is six screens — six board painters, six tap
/// handlers, six move lists. That is how a seventh game becomes a fortnight of
/// work and how the fifth one quietly ends up with no move history because
/// somebody forgot to copy that part across.
///
/// So this file borrows the shape the scoring engines already use
/// (`domain/scoring/scoring_plugin.dart`): the game DECLARES what it needs —
/// how big the board is, whether stones sit on squares or on the crossings,
/// whether a move is a tap or a drag, what a piece looks like — and the board
/// screen reads those declarations. `ArenaBoardView` does not know what a
/// knight is, that go has a ko rule, or that connect four falls downwards.
/// Adding draughts variants or shogi later is a file in `games/`, not a screen
/// change.
///
/// ## The engine is pure
///
/// Nothing here touches Firestore, Flutter state, or the clock. A game is a
/// function from position and move to a new position, which is what makes the
/// whole Arena replayable: the stored move list is the source of truth and
/// every position is derived by feeding those moves back through [apply]. A
/// board state cached in the document is a convenience, never an authority —
/// see `ArenaMatch.replay`.
@immutable
abstract class ArenaGame {
  const ArenaGame();

  /// Stable wire id. Written into every match document, so it may never
  /// change once games exist in the wild.
  String get id;

  /// "Chess", "Connect Four".
  String get name;

  /// One line under the name in the games grid: what the game IS, for a
  /// member who has not played it.
  String get tagline;

  /// Rough minutes for a casual game, shown on the tile so somebody knows
  /// whether they are starting a five-minute thing or a forty-minute thing.
  String get duration;

  /// The variants a challenger may pick between — board sizes, mostly. The
  /// first is the default. A game with nothing to choose returns one entry,
  /// which keeps the challenge screen from special-casing it.
  List<GameVariant> get variants;

  GameVariant variant(String? id) => variants.firstWhere(
        (v) => v.id == id,
        orElse: () => variants.first,
      );

  /// How the board is drawn and how big it is, for a given variant config.
  BoardSpec board(GameConfig config);

  /// How a move is entered.
  MoveInput get input;

  /// Whether a player may pass their turn. True for go and reversi, where
  /// passing is part of the rules; false everywhere else, where it would just
  /// be a way to stall.
  bool get allowsPass => false;

  /// Whether "offer a draw" makes sense. Connect four and gomoku draw only by
  /// filling the board, so there is nothing to agree to.
  bool get allowsDrawOffer => true;

  /// What the two sides are called in this game — ("White", "Black"),
  /// ("Red", "Yellow"). Index 0 always moves first.
  List<String> get sideNames;

  /// The colours the two sides' pieces are drawn in.
  List<int> get sideColors;

  /// The opening position.
  ArenaPosition initial(GameConfig config);

  /// Every move the side to play may legally make.
  ///
  /// The board screen drives entirely off this list — a square is only
  /// tappable if some legal move starts there, and the destinations it
  /// highlights are the ones legal moves lead to. No screen anywhere
  /// reimplements a rule, which is why an illegal move cannot be entered
  /// even by a hand-built tap.
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config);

  /// Plays [m], which the caller has already taken from [legalMoves].
  ///
  /// Must be deterministic and free of side effects: replay depends on the
  /// same move producing the same position on both players' phones and on
  /// every later viewing of the game.
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config);

  /// The result, or null while the game is still going.
  ///
  /// [history] is every position from the opening to [p] inclusive, because
  /// threefold repetition cannot be seen from one position. Games that do not
  /// care simply ignore it.
  GameOutcome? outcome(
    ArenaPosition p,
    List<ArenaPosition> history,
    GameConfig config,
  );

  /// How the move reads in the move list — "Nf3", "e5", "D4", "12-16".
  ///
  /// Taken against the position BEFORE the move, because chess disambiguation
  /// ("Rae1") depends on what else could have gone there.
  String notation(ArenaPosition before, ArenaMove m, GameConfig config);

  /// The move in plain words, for the game record — "King d6 → d7",
  /// "Knight takes the bishop on f6", "Black plays D4, capturing 2".
  ///
  /// Separate from [notation] because the two answer different questions.
  /// Notation is the compact form a player who already knows the game reads
  /// while playing ("Nxf6"); this is the sentence somebody reads AFTERWARDS,
  /// going back through a game to work out where it went wrong. A beginner
  /// cannot learn from "Nxf6" — that is the whole point of keeping it.
  ///
  /// The default covers the placement games, where "Black plays D4" really is
  /// the whole of what happened. Games with pieces that have names and things
  /// they can do to each other override it.
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final side = sideNames[before.turn];
    if (m.kind == MoveKind.pass) return '$side passes';
    return '$side plays ${notation(before, m, config)}';
  }

  /// How a piece code is drawn. Null for an empty square.
  PieceArt? art(int code);

  /// Squares the board should call attention to in the CURRENT position — the
  /// four that won a connect four game, a king that stands in check.
  ///
  /// The game decides, because "what matters here" is a rule. A screen that
  /// tried to work it out would need to know what check is.
  List<int> highlights(ArenaPosition p, GameConfig config) => const [];

  /// The running figure shown over each player's name — a chess material
  /// count, a go score, a reversi disc count. Null where there is nothing
  /// meaningful to show mid-game.
  String? sideSummary(ArenaPosition p, int side, GameConfig config) => null;
}

/// A choice offered before the game starts. Board size, mostly.
@immutable
class GameVariant {
  const GameVariant({
    required this.id,
    required this.label,
    this.note,
    this.config = const {},
  });

  final String id;

  /// "9×9", "Standard".
  final String label;

  /// "Quick, good on a phone".
  final String? note;

  /// Merged into the match's config and handed to every engine call.
  final Map<String, dynamic> config;
}

/// The frozen settings a match is played under.
///
/// A thin wrapper over the map rather than the raw map, so an engine reading
/// a size it was never given gets its own default instead of a null crash.
@immutable
class GameConfig {
  const GameConfig(this.values);

  static const empty = GameConfig({});

  final Map<String, dynamic> values;

  int integer(String key, int fallback) {
    final v = values[key];
    return v is num ? v.toInt() : fallback;
  }

  double decimal(String key, double fallback) {
    final v = values[key];
    return v is num ? v.toDouble() : fallback;
  }

  bool boolean(String key, bool fallback) {
    final v = values[key];
    return v is bool ? v : fallback;
  }
}

/// How the pieces and the grid are drawn.
enum BoardStyle {
  /// Alternating light and dark squares, pieces sitting on them: chess,
  /// checkers.
  checkered,

  /// A ruled grid with stones on the CROSSINGS rather than in the cells:
  /// go, gomoku. The difference is not decorative — the playable points of a
  /// 9×9 go board are its 81 intersections, so the geometry the tap handler
  /// works in is genuinely different.
  lines,

  /// Flat cells with a hairline between them: reversi, connect four.
  cells,
}

/// How a player enters a move.
enum MoveInput {
  /// Tap the piece, then tap where it goes. Chess, checkers.
  fromTo,

  /// Tap an empty point. Go, gomoku, reversi.
  place,

  /// Tap anywhere in a column and the piece falls. Connect four.
  column,
}

@immutable
class BoardSpec {
  const BoardSpec({
    required this.cols,
    required this.rows,
    required this.style,
    this.lightSquare = 0xFFF0D9B5,
    this.darkSquare = 0xFFB58863,
    this.surface = 0xFFEBC98A,
    this.showFileRank = false,
    this.flipForSideOne = true,
  });

  final int cols;
  final int rows;
  final BoardStyle style;

  /// Only read for [BoardStyle.checkered].
  final int lightSquare;
  final int darkSquare;

  /// The board colour for the other two styles — the wood of a go board, the
  /// green of a reversi table, the blue of a connect four frame.
  final int surface;

  /// Whether to draw a–h / 1–8 down the edges. Chess players expect them;
  /// on a connect four grid they are noise.
  final bool showFileRank;

  /// Whether the player on side 1 sees the board from their own end.
  ///
  /// True for every game where the two sides face each other across the
  /// board. False for connect four, where gravity has a direction and
  /// flipping the board would put it upside down.
  final bool flipForSideOne;

  int get cells => cols * rows;

  int index(int col, int row) => row * cols + col;
  int colOf(int index) => index % cols;
  int rowOf(int index) => index ~/ cols;
  bool inBounds(int col, int row) =>
      col >= 0 && col < cols && row >= 0 && row < rows;
}

/// What a piece looks like, described so the painter never needs to know
/// which game it is drawing.
@immutable
class PieceArt {
  const PieceArt({
    required this.side,
    this.figure,
    this.crowned = false,
    this.scale = 0.86,
  });

  /// 0 or 1. The painter takes the actual colour from [ArenaGame.sideColors],
  /// so a game does not restate its palette on every piece.
  final int side;

  /// Which figure to draw, for games whose pieces are distinguishable — the
  /// [ChessGame] piece kinds. Null means a plain disc, which is every stone
  /// game.
  ///
  /// An integer the painter looks up rather than a character to typeset. It
  /// started as the Unicode figurines ('♞'), which is the obvious choice and
  /// the wrong one: those code points live in a symbol font the device may
  /// simply not have, and a missing glyph is not a slightly worse knight, it
  /// is a tofu box on a chessboard. Vector paths render the same on every
  /// phone, at every size, and cost nothing to ship.
  final int? figure;

  /// Draws a crown mark on top: a checkers king.
  final bool crowned;

  /// Fraction of the cell the piece occupies.
  final double scale;
}

/// One position: the board, whose turn it is, and whatever else the rules
/// need to remember.
///
/// [cells] is a flat row-major array of piece codes, 0 for empty. Codes are
/// signed so the side owning a piece is readable without a lookup: positive
/// belongs to side 0, negative to side 1, and the magnitude is the kind.
/// [sideOf] and [kindOf] are the only places that convention is written down.
@immutable
class ArenaPosition {
  const ArenaPosition({
    required this.cells,
    required this.turn,
    this.meta = const {},
  });

  final List<int> cells;

  /// 0 or 1 — who moves next.
  final int turn;

  /// Rules state that is not on the board: castling rights, the en-passant
  /// square, the halfmove clock, go captures, a checkers piece part-way
  /// through a multi-jump.
  final Map<String, dynamic> meta;

  int get opponent => 1 - turn;

  static int sideOf(int code) => code == 0 ? -1 : (code > 0 ? 0 : 1);
  static int kindOf(int code) => code.abs();
  static int coded(int kind, int side) => side == 0 ? kind : -kind;

  int at(int index) => cells[index];

  ArenaPosition copyWith({
    List<int>? cells,
    int? turn,
    Map<String, dynamic>? meta,
  }) =>
      ArenaPosition(
        cells: cells ?? this.cells,
        turn: turn ?? this.turn,
        meta: meta ?? this.meta,
      );

  /// Identity for repetition detection: the board, the side to move, and any
  /// rights that make otherwise-identical boards genuinely different
  /// positions. Chess adds castling and en passant to this via [repeatKey].
  String get boardKey => '${cells.join(',')}|$turn';

  String get repeatKey {
    final extra = meta['repeat'];
    return extra is String ? '$boardKey|$extra' : boardKey;
  }
}

/// A single move, in whatever shape the game needs.
///
/// Deliberately one class for all six games rather than a sealed hierarchy:
/// a move has to survive a round trip through Firestore as a plain map, and
/// six subclasses would mean six codecs. [from], [to] and [kind] cover
/// everything the board screen needs to know; [extra] carries the rest, which
/// only the engine that wrote it ever reads.
@immutable
class ArenaMove {
  const ArenaMove({
    this.from = -1,
    this.to = -1,
    this.kind = MoveKind.normal,
    this.extra = const {},
    this.label,
  });

  const ArenaMove.pass()
      : from = -1,
        to = -1,
        kind = MoveKind.pass,
        extra = const {},
        label = 'Pass';

  /// Origin square, or -1 for a placement.
  final int from;

  /// Destination square, or -1 for a pass.
  final int to;

  final MoveKind kind;

  /// Promotion piece, captured squares, the jumped square — engine's own.
  final Map<String, dynamic> extra;

  /// Shown when the board has to ASK which of several moves was meant, which
  /// happens whenever two legal moves share a from and a to: a promoting
  /// pawn is the only case today. Null everywhere else.
  final String? label;

  /// What makes two moves the same move for the purpose of matching a tap
  /// against the legal list.
  String get key => '$from>$to:${kind.name}:${_extraKey()}';

  String _extraKey() {
    if (extra.isEmpty) return '';
    final keys = extra.keys.toList()..sort();
    return keys.map((k) => '$k=${extra[k]}').join(',');
  }

  Map<String, Object?> toMap() => {
        if (from >= 0) 'from': from,
        if (to >= 0) 'to': to,
        if (kind != MoveKind.normal) 'kind': kind.name,
        if (extra.isNotEmpty) 'extra': extra,
      };

  static ArenaMove fromMap(Map<String, dynamic> m) => ArenaMove(
        from: m['from'] is num ? (m['from'] as num).toInt() : -1,
        to: m['to'] is num ? (m['to'] as num).toInt() : -1,
        kind: MoveKind.values.firstWhere(
          (k) => k.name == m['kind'],
          orElse: () => MoveKind.normal,
        ),
        extra: m['extra'] is Map
            ? Map<String, dynamic>.from(m['extra'] as Map)
            : const {},
      );

  @override
  bool operator ==(Object other) => other is ArenaMove && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

enum MoveKind { normal, capture, pass, castle, promote, enPassant }

/// How a finished game finished.
@immutable
class GameOutcome {
  const GameOutcome({
    required this.winner,
    required this.reason,
    this.scores,
  });

  const GameOutcome.draw(String reason) : this(winner: null, reason: reason);

  /// 0, 1, or null for a draw.
  final int? winner;

  /// "Checkmate", "Stalemate", "Four in a row", "White wins by 6.5".
  final String reason;

  /// Final points per side, where the game has them — go area, reversi discs.
  final List<double>? scores;

  bool get isDraw => winner == null;
}
