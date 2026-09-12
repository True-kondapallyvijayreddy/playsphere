import '../arena_game.dart';

/// Go — surround territory, capture stones.
///
/// ## What is implemented, and what is deliberately not
///
/// Placement, capture by removing groups with no liberties, the suicide ban,
/// simple ko, passing, and **Chinese area scoring** with komi. That is a
/// complete, playable game.
///
/// What is not here is dead-stone negotiation. In a real game the two players
/// agree at the end which stones are dead and lift them before counting; that
/// agreement is a whole protocol — mark, disagree, resume play — and getting
/// it wrong is worse than not having it. Area scoring lets us do without: a
/// group that is dead is one the opponent can simply capture, and under
/// Chinese counting playing it out costs nothing, because a stone inside your
/// own territory scores the same as the empty point it filled. So the honest
/// instruction, which the board screen shows, is "capture what is dead before
/// you both pass".
///
/// Ko is the simple rule — you may not immediately recreate the position your
/// opponent just left. Full positional superko is rarer than the bugs that
/// come with implementing it hastily.
class GoGame extends ArenaGame {
  const GoGame();

  static const gameId = 'go';
  static const _stone = 1;

  @override
  String get id => gameId;

  @override
  String get name => 'Go';

  @override
  String get tagline => 'Surround territory, capture stones';

  @override
  String get duration => '25 min';

  @override
  MoveInput get input => MoveInput.place;

  @override
  bool get allowsPass => true;

  @override
  List<String> get sideNames => const ['Black', 'White'];

  @override
  List<int> get sideColors => const [0xFF111827, 0xFFFAFAFA];

  @override
  List<GameVariant> get variants => const [
        GameVariant(
          id: '9x9',
          label: '9 × 9',
          note: 'Where everyone should start',
          config: {'size': 9, 'komi': 5.5},
        ),
        GameVariant(
          id: '13x13',
          label: '13 × 13',
          note: 'Room for a real fight',
          config: {'size': 13, 'komi': 6.5},
        ),
        GameVariant(
          id: '19x19',
          label: '19 × 19',
          note: 'Full board — long game',
          config: {'size': 19, 'komi': 6.5},
        ),
      ];

  @override
  BoardSpec board(GameConfig config) {
    final size = config.integer('size', 9);
    return BoardSpec(
      cols: size,
      rows: size,
      style: BoardStyle.lines,
      surface: 0xFFE3B564,
    );
  }

  double _komi(GameConfig config) => config.decimal('komi', 5.5);

  @override
  ArenaPosition initial(GameConfig config) => ArenaPosition(
        cells: List<int>.filled(board(config).cells, 0),
        turn: 0,
        meta: const {'passes': 0, 'caps': [0, 0]},
      );

  List<int> _neighbours(BoardSpec b, int index) {
    final col = b.colOf(index);
    final row = b.rowOf(index);
    return [
      if (col > 0) index - 1,
      if (col < b.cols - 1) index + 1,
      if (row > 0) index - b.cols,
      if (row < b.rows - 1) index + b.cols,
    ];
  }

  /// The connected group containing [index], and whether it has any liberty.
  ///
  /// Returned together because every caller wants both and walking the group
  /// twice is the whole cost of the capture check.
  (List<int> group, bool alive) _group(List<int> cells, BoardSpec b, int index) {
    final code = cells[index];
    final seen = <int>{index};
    final stack = <int>[index];
    final group = <int>[];
    var alive = false;
    while (stack.isNotEmpty) {
      final at = stack.removeLast();
      group.add(at);
      for (final n in _neighbours(b, at)) {
        if (cells[n] == 0) {
          alive = true;
        } else if (cells[n] == code && seen.add(n)) {
          stack.add(n);
        }
      }
    }
    return (group, alive);
  }

  /// Plays a stone and lifts whatever it kills. Returns null if the move is
  /// suicide, which is the one placement the rules forbid outright.
  (List<int> cells, int captured)? _resolve(
    ArenaPosition p,
    BoardSpec b,
    int index,
    int side,
  ) {
    final cells = List<int>.from(p.cells);
    cells[index] = ArenaPosition.coded(_stone, side);

    // Opponent groups die first — which is what makes a move that would
    // otherwise be suicide legal when it captures.
    var captured = 0;
    for (final n in _neighbours(b, index)) {
      if (cells[n] == 0 || ArenaPosition.sideOf(cells[n]) == side) continue;
      final (group, alive) = _group(cells, b, n);
      if (!alive) {
        for (final g in group) {
          cells[g] = 0;
        }
        captured += group.length;
      }
    }

    final (_, alive) = _group(cells, b, index);
    if (!alive) return null;
    return (cells, captured);
  }

  @override
  List<ArenaMove> legalMoves(ArenaPosition p, GameConfig config) {
    if (outcome(p, const [], config) != null) return const [];
    final b = board(config);
    final ko = p.meta['ko'];
    final moves = <ArenaMove>[const ArenaMove.pass()];
    for (var i = 0; i < p.cells.length; i++) {
      if (p.cells[i] != 0) continue;
      final resolved = _resolve(p, b, i, p.turn);
      if (resolved == null) continue;
      // Simple ko: the position the opponent just left may not be recreated.
      if (ko is String && resolved.$1.join(',') == ko) continue;
      moves.add(ArenaMove(
        to: i,
        kind: resolved.$2 > 0 ? MoveKind.capture : MoveKind.normal,
      ));
    }
    return moves;
  }

  @override
  ArenaPosition apply(ArenaPosition p, ArenaMove m, GameConfig config) {
    final caps = List<int>.from(
      (p.meta['caps'] as List?)?.map((e) => (e as num).toInt()) ?? const [0, 0],
    );

    if (m.kind == MoveKind.pass) {
      return ArenaPosition(
        cells: p.cells,
        turn: p.opponent,
        meta: {
          'passes': ((p.meta['passes'] as num?)?.toInt() ?? 0) + 1,
          'caps': caps,
        },
      );
    }

    final b = board(config);
    final resolved = _resolve(p, b, m.to, p.turn)!;
    caps[p.turn] += resolved.$2;

    return ArenaPosition(
      cells: resolved.$1,
      turn: p.opponent,
      meta: {
        'passes': 0,
        'caps': caps,
        'last': m.to,
        // The board as it stood BEFORE this move, so the opponent cannot
        // simply take back the stone that was just taken.
        'ko': p.cells.join(','),
      },
    );
  }

  /// Chinese area score: living stones plus the empty points only your own
  /// colour reaches. Komi is added to White.
  List<double> score(ArenaPosition p, GameConfig config) {
    final b = board(config);
    final area = [0.0, 0.0];
    for (final c in p.cells) {
      final side = ArenaPosition.sideOf(c);
      if (side >= 0) area[side] += 1;
    }

    final seen = <int>{};
    for (var i = 0; i < p.cells.length; i++) {
      if (p.cells[i] != 0 || seen.contains(i)) continue;
      // Flood the empty region and note every colour on its border. A region
      // touching both colours is neutral and scores for nobody.
      final region = <int>[];
      final borders = <int>{};
      final stack = <int>[i];
      seen.add(i);
      while (stack.isNotEmpty) {
        final at = stack.removeLast();
        region.add(at);
        for (final n in _neighbours(b, at)) {
          if (p.cells[n] == 0) {
            if (seen.add(n)) stack.add(n);
          } else {
            borders.add(ArenaPosition.sideOf(p.cells[n]));
          }
        }
      }
      if (borders.length == 1) area[borders.first] += region.length;
    }

    area[1] += _komi(config);
    return area;
  }

  @override
  GameOutcome? outcome(
    ArenaPosition p,
    List<ArenaPosition> history,
    GameConfig config,
  ) {
    final passes = (p.meta['passes'] as num?)?.toInt() ?? 0;
    if (passes < 2) return null;

    final s = score(p, config);
    if (s[0] == s[1]) return GameOutcome.draw('${s[0]} all');
    final winner = s[0] > s[1] ? 0 : 1;
    final margin = (s[0] - s[1]).abs();
    return GameOutcome(
      winner: winner,
      reason: '${sideNames[winner]} by $margin',
      scores: s,
    );
  }

  @override
  List<int> highlights(ArenaPosition p, GameConfig config) {
    final last = p.meta['last'];
    return last is int ? [last] : const [];
  }

  @override
  String? sideSummary(ArenaPosition p, int side, GameConfig config) {
    final caps = (p.meta['caps'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [0, 0];
    final komi = side == 1 ? ' · +${_komi(config)}' : '';
    return '${caps[side]} captured$komi';
  }

  /// Go columns skip the letter I, which is not a quirk worth "fixing" — every
  /// book, every server and every player writes it that way to keep I and J
  /// apart on a handwritten score sheet.
  static String columnLabel(int col) {
    const letters = 'ABCDEFGHJKLMNOPQRST';
    return col < letters.length ? letters[col] : '?';
  }

  @override
  String notation(ArenaPosition before, ArenaMove m, GameConfig config) {
    if (m.kind == MoveKind.pass) return 'pass';
    final b = board(config);
    return '${columnLabel(b.colOf(m.to))}${b.rows - b.rowOf(m.to)}';
  }

  @override
  String describe(ArenaPosition before, ArenaMove m, GameConfig config) {
    final side = sideNames[before.turn];
    if (m.kind == MoveKind.pass) return '$side passes';
    final point = notation(before, m, config);
    final after = apply(before, m, config);
    final taken = _capturedBy(before, after, before.turn);
    if (taken == 0) return '$side plays $point';
    return '$side plays $point, capturing '
        '$taken ${taken == 1 ? 'stone' : 'stones'}';
  }

  int _capturedBy(ArenaPosition before, ArenaPosition after, int side) {
    int caps(ArenaPosition p) =>
        ((p.meta['caps'] as List?)?[side] as num?)?.toInt() ?? 0;
    return caps(after) - caps(before);
  }

  @override
  PieceArt? art(int code) {
    final side = ArenaPosition.sideOf(code);
    return side < 0 ? null : PieceArt(side: side, scale: 0.94);
  }
}
