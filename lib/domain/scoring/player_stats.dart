import '../../core/models/match_player.dart';
import 'scoring_plugin.dart';

/// A generic per-player tally, and the box score built from it.
///
/// Cricket needed a bespoke card because its statistics are structurally
/// unlike anything else — an innings, two disciplines, a batting order. Every
/// other sport in the spec is the same shape: a list of players, each with a
/// bag of counters, some of which are derived from others. Football counts
/// goals and assists, basketball counts points and rebounds, kabaddi counts
/// raid and tackle points; the *bookkeeping* is identical.
///
/// Sharing it means adding a sport is an event vocabulary plus a set of column
/// definitions, not another hand-rolled accumulator with its own rounding bugs.

/// One statistic as it should appear in a box score.
class StatColumn {
  const StatColumn({
    required this.key,
    required this.label,
    required this.shortLabel,
    this.derive,
    this.decimals = 0,
    this.isPercentage = false,
  });

  /// Key inside the player's tally, or the identifier of a derived value.
  final String key;

  final String label;

  /// Column heading in a table — "PTS", "REB", "G", "A".
  final String shortLabel;

  /// Computes a value from the raw tally rather than storing it. Shooting
  /// percentages and per-minute rates must be derived, never accumulated:
  /// storing a percentage and updating it incrementally is how box scores end
  /// up not summing to the team total.
  final double Function(Map<String, num> tally)? derive;

  final int decimals;
  final bool isPercentage;

  bool get isDerived => derive != null;

  num valueFrom(Map<String, num> tally) =>
      derive != null ? derive!(tally) : (tally[key] ?? 0);

  String format(Map<String, num> tally) {
    final v = valueFrom(tally);
    if (isPercentage) return '${(v * 100).toStringAsFixed(decimals)}%';
    return decimals == 0
        ? v.toInt().toString()
        : v.toDouble().toStringAsFixed(decimals);
  }
}

/// One player's line in a box score.
class PlayerStatLine {
  const PlayerStatLine({
    required this.playerId,
    required this.name,
    required this.tally,
    required this.appeared,
  });

  final String playerId;
  final String name;
  final Map<String, num> tally;

  /// False for a named squad member who never took part. They appear on the
  /// sheet as "did not play" rather than as a row of zeroes, which reads as a
  /// player who contributed nothing.
  final bool appeared;

  num operator [](String key) => tally[key] ?? 0;
}

/// A whole side's statistics for a match.
class BoxScore {
  const BoxScore({
    required this.side,
    required this.teamName,
    required this.columns,
    required this.players,
  });

  final Side side;
  final String teamName;
  final List<StatColumn> columns;
  final List<PlayerStatLine> players;

  /// Team totals, summed from the players rather than tracked separately.
  ///
  /// Deriving guarantees the columns add up. A separately-maintained team
  /// total is the classic source of a box score whose parts do not sum to its
  /// whole, and once they disagree nobody can tell which is wrong.
  Map<String, num> get teamTotals {
    final totals = <String, num>{};
    for (final p in players) {
      for (final entry in p.tally.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }
    return totals;
  }

  List<PlayerStatLine> get appeared =>
      players.where((p) => p.appeared).toList();
}

/// Reads and writes the per-player tallies held inside a plugin's state.
///
/// Kept here rather than in each engine so the storage shape is identical
/// across sports, which is what lets one career-statistics aggregator read
/// every sport later without knowing anything about any of them.
class PlayerTally {
  const PlayerTally._();

  static const stateKey = 'players';

  /// Adds [amount] to one counter for one player, returning new state.
  static Map<String, dynamic> add(
    Map<String, dynamic> state,
    String playerId,
    String key,
    num amount,
  ) {
    final all = Map<String, dynamic>.from(
      state[stateKey] as Map? ?? const <String, dynamic>{},
    );
    final mine = Map<String, dynamic>.from(
      all[playerId] as Map? ?? const <String, dynamic>{},
    );
    mine[key] = ((mine[key] as num?) ?? 0) + amount;
    all[playerId] = mine;
    return {...state, stateKey: all};
  }

  /// Applies several counters at once — one event usually moves more than one
  /// number, and doing them individually would rebuild the map each time.
  static Map<String, dynamic> addAll(
    Map<String, dynamic> state,
    String playerId,
    Map<String, num> deltas,
  ) {
    final all = Map<String, dynamic>.from(
      state[stateKey] as Map? ?? const <String, dynamic>{},
    );
    final mine = Map<String, dynamic>.from(
      all[playerId] as Map? ?? const <String, dynamic>{},
    );
    for (final d in deltas.entries) {
      mine[d.key] = ((mine[d.key] as num?) ?? 0) + d.value;
    }
    all[playerId] = mine;
    return {...state, stateKey: all};
  }

  static Map<String, num> of(Map<String, dynamic> state, String playerId) {
    final all = state[stateKey] as Map? ?? const {};
    final mine = all[playerId] as Map? ?? const {};
    return {
      for (final e in mine.entries)
        e.key.toString(): (e.value as num?) ?? 0,
    };
  }

  /// Every player's tally from this one match, summed into one counter map —
  /// "the club's total" rather than any one person's. Used by
  /// `ClubSportStats`, which credits a club with everything either side's
  /// players did, not any single player's line.
  static Map<String, num> everyone(Map<String, dynamic> state) {
    final all = state[stateKey] as Map? ?? const {};
    final out = <String, num>{};
    for (final playerTally in all.values) {
      if (playerTally is! Map) continue;
      for (final e in playerTally.entries) {
        final v = e.value;
        if (v is num) {
          final key = e.key.toString();
          out[key] = (out[key] ?? 0) + v;
        }
      }
    }
    return out;
  }

  /// Builds the box score for one side.
  static BoxScore boxScore({
    required Map<String, dynamic> state,
    required ScoringContext ctx,
    required Side side,
    required List<StatColumn> columns,
  }) {
    final squad = ctx.lineupFor(side);
    final all = state[stateKey] as Map? ?? const {};

    return BoxScore(
      side: side,
      teamName: ctx.nameFor(side),
      columns: columns,
      players: [
        for (final MatchPlayer p in squad)
          PlayerStatLine(
            playerId: p.id,
            name: p.name,
            tally: of(state, p.id),
            appeared: all.containsKey(p.id),
          ),
      ],
    );
  }
}
