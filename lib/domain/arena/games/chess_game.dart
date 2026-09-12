import '../arena_game.dart';

/// Chess, complete: castling, en passant, promotion, check, checkmate,
/// stalemate, the fifty-move rule, threefold repetition and insufficient
/// material.
///
/// ## Why all of it, in an unrated arena
///
/// The temptation with a casual game is to implement the moves and stop —
/// skip en passant, call it "checkmate" when the king is taken. That fails in
/// the one place it must not: a beginner learning the game here would learn it
/// wrong, and a club player would find the app broken in the first ten games.
/// Rules are the cheap part; a half-implemented ruleset is a permanent tax.
///
/// ## Legality is generated, never validated
///
/// [legalMoves] produces pseudo-legal moves, plays each one, and keeps only
/// those that leave the mover's own king off an attacked square. There is no
/// separate "is this legal" path, which means pins, discovered checks and the
/// rule that a king may not castle through an attacked square all fall out of
/// one mechanism rather than being three special cases somebody has to
/// remember. The board screen never sees an illegal move to reject, because
/// one is never offered.
class ChessGame extends ArenaGame {
  const ChessGame();

  static const gameId = 'chess';

  static const pawn = 1;
  static const knight = 2;
  static const bishop = 3;
  static const rook = 4;
  static const queen = 5;
  static const king = 6;

  static const _size = 8;

  @override
  String get id => gameId;

  @override
  String get name => 'Chess';

  @override
  String get tagline => 'The whole game — castling, en passant, promotion';

  @override
  String get duration => '20 min';

  @override
  MoveInput get input => MoveInput.fromTo;

  @override
  List<String> get sideNames => const ['White', 'Black'];

  /// Ivory and near-black, not white and slate.
  ///
  /// Pure white against a mid-grey looked fine blown up and was genuinely
  /// hard to read at the ~40dp a square gets on a phone: the grey sat close
  /// enough to the dark squares of the board that a black knight on a dark
  /// square disappeared into it. Warm ivory separates from both board
  /// colours, and taking the dark side almost to black doubles the distance
  /// between the two armies.
  @override
  List<int> get sideColors => const [0xFFF4EBDC, 0xFF16161A];

  @override
  List<GameVariant> get variants => const [
        GameVariant(
          id: 'standard',
          label: 'Standard',
          note: 'The normal starting position',
          config: {},
        ),
      ];

  /// Squares deliberately lower in contrast than the pieces.
  ///
  /// The board is the background: if its two colours are as far apart as the
  /// two armies, every piece competes with the square under it. Muting the
  /// dark square towards a soft olive-brown leaves the strongest contrast on
  /// the board where it belongs — between the pieces.
  @override
  BoardSpec board(GameConfig config) => const BoardSpec(
        cols: _size,
        rows: _size,
        style: BoardStyle.checkered,
        lightSquare: 0xFFE8D3B0,
        darkSquare: 0xFFA8875F,
        showFileRank: true,
      );

  static const _b = BoardSpec(
    cols: _size,
    rows: _size,
    style: BoardStyle.checkered,
  );

  // Row 0 is the eighth rank, so Black sits on rows 0–1 and White on 6–7 and
  // White's pawns advance towards row 0.
  int _forward(int side) => side == 0 ? -1 : 1;
  int _pawnStartRow(int side) => side == 0 ? 6 : 1;
  int _promoRow(int side) => side == 0 ? 0 : 7;

  @override
  ArenaPosition initial(GameConfig config) {
    const backRank = [rook, knight, bishop, queen, king, bishop, knight, rook];
    final cells = List<int>.filled(_size * _size, 0);
    for (var col = 0; col < _size; col++) {
      cells[_b.index(col, 0)] = ArenaPosition.coded(backRank[col], 1);
      cells[_b.index(col, 1)] = ArenaPosition.coded(pawn, 1);
      cells[_b.index(col, 6)] = ArenaPosition.coded(pawn, 0);
      cells[_b.index(col, 7)] = ArenaPosition.coded(backRank[col], 0);
    }
    return ArenaPosition(
      cells: cells,
      turn: 0,
      meta: const {'castle': 'KQkq', 'ep': -1, 'half': 0, 'repeat': 'KQkq|-1'},
    );
  }

  // --- Attack detection --------------------------------------------------

  static const _knightHops = [
    [1, 2], [2, 1], [2, -1], [1, -2],
    [-1, -2], [-2, -1], [-2, 1], [-1, 2],
  ];
  static const _diagonals = [
    [1, 1], [1, -1], [-1, 1], [-1, -1],
  ];
  static const _orthogonals = [
    [1, 0], [-1, 0], [0, 1], [0, -1],
  ];

  /// Whether [side] attacks [target], read off the board rather than from a
  /// move list — which is what lets it answer for squares a king only passes
  /// through while castling, where no move is being made at all.
  bool _attacks(List<int> cells, int target, int side) {
    final tc = _b.colOf(target);
    final tr = _b.rowOf(target);

    for (final h in _knightHops) {
      final c = tc + h[0];
      final r = tr + h[1];
      if (!_b.inBounds(c, r)) continue;
      final code = cells[_b.index(c, r)];
      if (ArenaPosition.sideOf(code) == side &&
          ArenaPosition.kindOf(code) == knight) {
        return true;
      }
    }

    for (final d in [..._diagonals, ..._orthogonals]) {
      final c = tc + d[0];
      final r = tr + d[1];
      if (!_b.inBounds(c, r)) continue;
      final code = cells[_b.index(c, r)];
      if (ArenaPosition.sideOf(code) == side &&
          ArenaPosition.kindOf(code) == king) {
        return true;
      }
    }

    // A pawn attacks forwards, so we look BACKWARDS from the target along
    // the attacker's direction of travel.
    final back = -_forward(side);
    for (final dc in const [-1, 1]) {
      final c = tc + dc;
      final r = tr + back;
      if (!_b.inBounds(c, r)) continue;
      final code = cells[_b.index(c, r)];
      if (ArenaPosition.sideOf(code) == side &&
          ArenaPosition.kindOf(code) == pawn) {
        return true;
      }
    }

    for (final entry in const [
      [_diagonals, bishop],
      [_orthogonals, rook],
    ]) {
      final dirs = entry[0] as List<List<int>>;
      final sliding = entry[1] as int;
      for (final d in dirs) {
        var c = tc + d[0];
        var r = tr + d[1];
        while (_b.inBounds(c, r)) {
          final code = cells[_b.index(c, r)];
          if (code != 0) {
            final kind = ArenaPosition.kindOf(code);
            if (ArenaPosition.sideOf(code) == side &&
                (kind == sliding || kind == queen)) {
              return true;
            }
            break;
          }
          c += d[0];
          r += d[1];
        }
      }
    }
    return false;
  }

  int _kingSquare(List<int> cells, int side) {
    final want = ArenaPosition.coded(king, side);
    final at = cells.indexOf(want);
    // A position with no king cannot arise from legal play, but replay of a
    // corrupt move list should degrade rather than crash.
    return at;
  }

  bool inCheck(ArenaPosition p, int side) {
    final k = _kingSquare(p.cells, side);
    return k >= 0 && _attacks(p.cells, k, 1 - side);
  }

  // --- Move generation ---------------------------------------------------

  List<ArenaMove> _pseudoMoves(ArenaPosition p, int side) {
    final out = <ArenaMove>[];
    final ep = (p.meta['ep'] as num?)?.toInt() ?? -1;
    final rights = (p.meta['castle'] as String?) ?? '';

    for (var from = 0; from < p.cells.length; from++) {
      final code = p.cells[from];
      if (ArenaPosition.sideOf(code) != side) continue;
      final kind = ArenaPosition.kindOf(code);
      final col = _b.colOf(from);
      final row = _b.rowOf(from);

      switch (kind) {
        case pawn:
          final fwd = _forward(side);
          final oneRow = row + fwd;
          if (_b.inBounds(col, oneRow)) {
            final one = _b.index(col, oneRow);
            if (p.cells[one] == 0) {
              _addPawn(out, from, one, side, oneRow, MoveKind.normal);
              final twoRow = row + fwd * 2;
              if (row == _pawnStartRow(side) &&
                  p.cells[_b.index(col, twoRow)] == 0) {
                out.add(ArenaMove(
                  from: from,
                  to: _b.index(col, twoRow),
                  extra: const {'double': true},
                ));
              }
            }
          }
          for (final dc in const [-1, 1]) {
            final c = col + dc;
            final r = row + fwd;
            if (!_b.inBounds(c, r)) continue;
            final to = _b.index(c, r);
            final target = p.cells[to];
            if (target != 0 && ArenaPosition.sideOf(target) != side) {
              _addPawn(out, from, to, side, r, MoveKind.capture);
            } else if (to == ep && target == 0) {
              // The captured pawn is beside the mover, not on the square it
              // is moving to — the one capture in chess that removes a piece
              // from a square the moving piece never occupies.
              out.add(ArenaMove(
                from: from,
                to: to,
                kind: MoveKind.enPassant,
                extra: {'takes': _b.index(c, row)},
              ));
            }
          }

        case knight:
          for (final h in _knightHops) {
            _addStep(out, p, from, col + h[0], row + h[1], side);
          }

        case king:
          for (final d in [..._diagonals, ..._orthogonals]) {
            _addStep(out, p, from, col + d[0], row + d[1], side);
          }
          _addCastles(out, p, side, rights, from);

        default:
          final dirs = switch (kind) {
            bishop => _diagonals,
            rook => _orthogonals,
            _ => [..._diagonals, ..._orthogonals],
          };
          for (final d in dirs) {
            var c = col + d[0];
            var r = row + d[1];
            while (_b.inBounds(c, r)) {
              final to = _b.index(c, r);
              final target = p.cells[to];
              if (target == 0) {
                out.add(ArenaMove(from: from, to: to));
              } else {
                if (ArenaPosition.sideOf(target) != side) {
                  out.add(
                      ArenaMove(from: from, to: to, kind: MoveKind.capture));
                }
                break;
              }
              c += d[0];
              r += d[1];
            }
          }
      }
    }
    return out;
  }

  void _addStep(
    List<ArenaMove> out,
    ArenaPosition p,
    int from,
    int c,
    int r,
    int side,
  ) {
    if (!_b.inBounds(c, r)) return;
    final to = _b.index(c, r);
    final target = p.cells[to];
    if (target == 0) {
      out.add(ArenaMove(from: from, to: to));
    } else if (ArenaPosition.sideOf(target) != side) {
      out.add(ArenaMove(from: from, to: to, kind: MoveKind.capture));
    }
  }

  /// A pawn arriving on the last rank is four different moves, not one.
  ///
  /// Generating them separately is what lets the board screen ask which piece
  /// without knowing that promotion exists: two legal moves share a from and
  /// a to, so it offers the choice, using each move's own [ArenaMove.label].
  void _addPawn(
    List<ArenaMove> out,
    int from,
    int to,
    int side,
    int toRow,
    MoveKind kind,
  ) {
    if (toRow != _promoRow(side)) {
      out.add(ArenaMove(from: from, to: to, kind: kind));
      return;
    }
    const names = {queen: 'Queen', rook: 'Rook', bishop: 'Bishop', knight: 'Knight'};
    for (final entry in names.entries) {
      out.add(ArenaMove(
        from: from,
        to: to,
        kind: MoveKind.promote,
        extra: {'promo': entry.key},
        label: entry.value,
      ));
    }
  }

  static const _castleSpecs = [
    // side, right, kingFrom, kingTo, rookFrom, rookTo, squares that must be
    // empty, squares the king may not be attacked on.
    (0, 'K', 60, 62, 63, 61, [61, 62], [60, 61, 62]),
    (0, 'Q', 60, 58, 56, 59, [57, 58, 59], [60, 59, 58]),
    (1, 'k', 4, 6, 7, 5, [5, 6], [4, 5, 6]),
    (1, 'q', 4, 2, 0, 3, [1, 2, 3], [4, 3, 2]),
  ];

  void _addCastles(
    List<ArenaMove> out,
    ArenaPosition p,
    int side,
    String rights,
    int kingFrom,
  ) {
    for (final spec in _castleSpecs) {
      if (spec.$1 != side || !rights.contains(spec.$2)) continue;
      if (kingFrom != spec.$3) continue;
      if (p.cells[spec.$5] != ArenaPosition.coded(rook, side)) continue;
      if (spec.$7.any((sq) => p.cells[sq] != 0)) continue;
      // Out of, through, and into check are all forbidden, so all three
      // squares are tested here rather than leaving the last one to the
      // legality filter.
      if (spec.$8.any((sq) => _attacks(p.cells, sq, 1 - side))) continue;
      out.add(ArenaMove(
        from: spec.$3,
        to: spec.$4,
        kind: MoveKind.castle,
        extra: {'rookFrom': spec.$5, 'rookTo': spec.$6},
      ));
    }
  }

  @override
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config) {
    final out = <ArenaMove>[];
    for (final m in _pseudoMoves(p, p.turn)) {
      final after = apply(p, m, config);
      if (!inCheck(after, p.turn)) out.add(m);
    }
    return out;
  }

  // --- Applying ----------------------------------------------------------

  @override
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config) {
    final cells = List<int>.from(p.cells);
    final moving = cells[m.from];
    final kind = ArenaPosition.kindOf(moving);
    final side = p.turn;
    final captured = cells[m.to] != 0 || m.kind == MoveKind.enPassant;

    cells[m.from] = 0;
    cells[m.to] = moving;

    if (m.kind == MoveKind.enPassant) {
      final takes = (m.extra['takes'] as num?)?.toInt();
      if (takes != null) cells[takes] = 0;
    }
    if (m.kind == MoveKind.castle) {
      final rf = (m.extra['rookFrom'] as num).toInt();
      final rt = (m.extra['rookTo'] as num).toInt();
      cells[rt] = cells[rf];
      cells[rf] = 0;
    }
    if (m.kind == MoveKind.promote) {
      final promo = (m.extra['promo'] as num?)?.toInt() ?? queen;
      cells[m.to] = ArenaPosition.coded(promo, side);
    }

    final rights = _rightsAfter(
      (p.meta['castle'] as String?) ?? '',
      m,
      kind,
      side,
    );

    // The en-passant square exists for exactly one ply.
    var ep = -1;
    if (kind == pawn && m.extra['double'] == true) {
      ep = _b.index(_b.colOf(m.from), (_b.rowOf(m.from) + _b.rowOf(m.to)) ~/ 2);
    }

    final half = (captured || kind == pawn)
        ? 0
        : ((p.meta['half'] as num?)?.toInt() ?? 0) + 1;

    return ArenaPosition(
      cells: cells,
      turn: p.opponent,
      meta: {
        'castle': rights,
        'ep': ep,
        'half': half,
        'last': m.to,
        'from': m.from,
        // Two boards with the same pieces are only the same POSITION if the
        // same castling and en-passant options exist, which is what threefold
        // repetition is actually counting.
        'repeat': '$rights|$ep',
      },
    );
  }

  /// Castling rights, once this move has been made.
  ///
  /// Rights are lost by the king or rook moving, and — the case that is easy
  /// to miss — by the rook being CAPTURED on its original square, which is
  /// why the destination is checked as well as the origin.
  String _rightsAfter(String rights, ArenaMove m, int kind, int side) {
    var out = rights;
    if (kind == king) {
      out = side == 0
          ? out.replaceAll('K', '').replaceAll('Q', '')
          : out.replaceAll('k', '').replaceAll('q', '');
    }
    const rookRights = {63: 'K', 56: 'Q', 7: 'k', 0: 'q'};
    for (final square in [m.from, m.to]) {
      final right = rookRights[square];
      if (right != null) out = out.replaceAll(right, '');
    }
    return out;
  }

  // --- Outcome -----------------------------------------------------------

  @override
  GameOutcome? outcome(
    ArenaPosition p,
    List<ArenaPosition> history,
    GameConfig config,
  ) {
    if (legalMoves(p, config).isEmpty) {
      return inCheck(p, p.turn)
          ? GameOutcome(
              winner: p.opponent,
              reason: 'Checkmate',
            )
          : const GameOutcome.draw('Stalemate');
    }
    if (((p.meta['half'] as num?)?.toInt() ?? 0) >= 100) {
      return const GameOutcome.draw('Fifty-move rule');
    }
    if (_insufficient(p)) {
      return const GameOutcome.draw('Insufficient material');
    }
    if (history.isNotEmpty) {
      final key = p.repeatKey;
      final seen = history.where((h) => h.repeatKey == key).length;
      if (seen >= 3) return const GameOutcome.draw('Threefold repetition');
    }
    return null;
  }

  /// Positions from which no sequence of legal moves can produce a mate:
  /// bare kings, king and a single minor piece, and same-coloured bishops.
  bool _insufficient(ArenaPosition p) {
    final minors = <int>[];
    for (var i = 0; i < p.cells.length; i++) {
      final kind = ArenaPosition.kindOf(p.cells[i]);
      if (kind == 0 || kind == king) continue;
      if (kind == pawn || kind == rook || kind == queen) return false;
      minors.add(i);
    }
    if (minors.length <= 1) return true;
    if (minors.length == 2) {
      final both = minors.every(
        (i) => ArenaPosition.kindOf(p.cells[i]) == bishop,
      );
      if (!both) return false;
      // Bishops that can never meet: same square colour, no mate available.
      final colourA = (_b.colOf(minors[0]) + _b.rowOf(minors[0])) % 2;
      final colourB = (_b.colOf(minors[1]) + _b.rowOf(minors[1])) % 2;
      final sideA = ArenaPosition.sideOf(p.cells[minors[0]]);
      final sideB = ArenaPosition.sideOf(p.cells[minors[1]]);
      return colourA == colourB && sideA != sideB;
    }
    return false;
  }

  @override
  List<int> highlights(ArenaPosition p, GameConfig config) {
    final out = <int>[];
    final from = p.meta['from'];
    final last = p.meta['last'];
    if (from is int) out.add(from);
    if (last is int) out.add(last);
    if (inCheck(p, p.turn)) {
      final k = _kingSquare(p.cells, p.turn);
      if (k >= 0) out.add(k);
    }
    return out;
  }

  // --- Notation ----------------------------------------------------------

  static const _values = {pawn: 1, knight: 3, bishop: 3, rook: 5, queen: 9};
  static const _letters = {
    knight: 'N',
    bishop: 'B',
    rook: 'R',
    queen: 'Q',
    king: 'K',
  };
  static String square(int index) =>
      '${String.fromCharCode(97 + _b.colOf(index))}${_size - _b.rowOf(index)}';

  @override
  String notation(ArenaPosition before, ArenaMove m, GameConfig config) {
    if (m.kind == MoveKind.castle) {
      final side = _b.colOf(m.to) > _b.colOf(m.from) ? 'O-O' : 'O-O-O';
      return '$side${_suffix(before, m, config)}';
    }

    final moving = before.cells[m.from];
    final kind = ArenaPosition.kindOf(moving);
    final captures =
        before.cells[m.to] != 0 || m.kind == MoveKind.enPassant;
    final dest = square(m.to);
    final buffer = StringBuffer();

    if (kind == pawn) {
      if (captures) {
        buffer.write(String.fromCharCode(97 + _b.colOf(m.from)));
        buffer.write('x');
      }
      buffer.write(dest);
      if (m.kind == MoveKind.promote) {
        final promo = (m.extra['promo'] as num?)?.toInt() ?? queen;
        buffer.write('=${_letters[promo]}');
      }
    } else {
      buffer.write(_letters[kind] ?? '');
      buffer.write(_disambiguate(before, m, kind, config));
      if (captures) buffer.write('x');
      buffer.write(dest);
    }
    buffer.write(_suffix(before, m, config));
    return buffer.toString();
  }

  /// "Rae1" rather than "Re1", but only where it is genuinely needed.
  ///
  /// The file alone if that separates the candidates, the rank if it does
  /// not, both if neither does — which is the actual SAN rule and matters on
  /// a board with three queens.
  String _disambiguate(
    ArenaPosition before,
    ArenaMove m,
    int kind,
    GameConfig config,
  ) {
    final rivals = legalMoves(before, config)
        .where((o) =>
            o.to == m.to &&
            o.from != m.from &&
            ArenaPosition.kindOf(before.cells[o.from]) == kind)
        .toList();
    if (rivals.isEmpty) return '';

    final file = String.fromCharCode(97 + _b.colOf(m.from));
    final rank = '${_size - _b.rowOf(m.from)}';
    final sameFile = rivals.any((o) => _b.colOf(o.from) == _b.colOf(m.from));
    final sameRank = rivals.any((o) => _b.rowOf(o.from) == _b.rowOf(m.from));
    if (!sameFile) return file;
    if (!sameRank) return rank;
    return '$file$rank';
  }

  String _suffix(ArenaPosition before, ArenaMove m, GameConfig config) {
    final after = apply(before, m, config);
    if (!inCheck(after, after.turn)) return '';
    return legalMoves(after, config).isEmpty ? '#' : '+';
  }

  static const _names = {
    pawn: 'Pawn',
    knight: 'Knight',
    bishop: 'Bishop',
    rook: 'Rook',
    queen: 'Queen',
    king: 'King',
  };

  @override
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final side = sideNames[before.turn];
    final moving = before.cells[m.from];
    final kind = ArenaPosition.kindOf(moving);
    final name = _names[kind] ?? 'Piece';

    if (m.kind == MoveKind.castle) {
      final short = _b.colOf(m.to) > _b.colOf(m.from);
      return '$side castles ${short ? 'kingside' : 'queenside'} '
          '(king ${square(m.from)} → ${square(m.to)})';
    }

    final buffer = StringBuffer('$side ');

    if (m.kind == MoveKind.enPassant) {
      buffer.write(
        'pawn ${square(m.from)} → ${square(m.to)}, taking the pawn '
        'in passing',
      );
    } else if (m.kind == MoveKind.promote) {
      final promo = (m.extra['promo'] as num?)?.toInt() ?? queen;
      final taken = before.cells[m.to];
      buffer.write('pawn ${square(m.from)} → ${square(m.to)}');
      if (taken != 0) {
        buffer.write(
          ', taking the ${(_names[ArenaPosition.kindOf(taken)] ?? 'piece')
              .toLowerCase()}',
        );
      }
      buffer.write(
        ', promoted to a ${(_names[promo] ?? 'queen').toLowerCase()}',
      );
    } else {
      final taken = before.cells[m.to];
      if (taken != 0) {
        final victim =
            (_names[ArenaPosition.kindOf(taken)] ?? 'piece').toLowerCase();
        buffer.write(
          '${name.toLowerCase()} ${square(m.from)} takes the $victim '
          'on ${square(m.to)}',
        );
      } else {
        buffer.write(
          '${name.toLowerCase()} ${square(m.from)} → ${square(m.to)}',
        );
      }
    }

    // Whether the move gave check is the single most useful thing to see when
    // reading a game back, so it is spelled out rather than left as a '+'.
    final after = apply(before, m, config);
    if (inCheck(after, after.turn)) {
      buffer.write(
        legalMoves(after, config).isEmpty ? ' — checkmate' : ' — check',
      );
    }
    return buffer.toString();
  }

  /// Material advantage, as "+3" beside the player who is ahead. Shown rather
  /// than a piece list because a number is readable at a glance on a phone.
  @override
  String? sideSummary(ArenaPosition p, int side, GameConfig config) {
    var mine = 0;
    var theirs = 0;
    for (final code in p.cells) {
      final value = _values[ArenaPosition.kindOf(code)] ?? 0;
      if (value == 0) continue;
      if (ArenaPosition.sideOf(code) == side) {
        mine += value;
      } else {
        theirs += value;
      }
    }
    final edge = mine - theirs;
    return edge > 0 ? '+$edge' : null;
  }

  @override
  PieceArt? art(int code) {
    final side = ArenaPosition.sideOf(code);
    if (side < 0) return null;
    return PieceArt(
      side: side,
      // One silhouette per kind, tinted by side — so a black knight is the
      // white knight filled dark, and the two sides always match in weight.
      figure: ArenaPosition.kindOf(code),
      scale: 0.88,
    );
  }
}
