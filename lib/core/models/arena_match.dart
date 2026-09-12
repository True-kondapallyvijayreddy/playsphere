import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/arena/arena_game.dart';
import '../../domain/arena/arena_registry.dart';
import 'firestore_codec.dart';

/// Where a game is in its life.
enum ArenaStatus {
  /// Sent, waiting on the opponent.
  pending('pending'),

  /// Accepted and being played.
  active('active'),

  /// Over — won, drawn or resigned.
  finished('finished'),

  /// The opponent said no.
  declined('declined'),

  /// The challenger took it back before it was answered.
  cancelled('cancelled');

  const ArenaStatus(this.wire);
  final String wire;

  static ArenaStatus fromWire(String? w) => ArenaStatus.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => ArenaStatus.pending,
      );

  bool get isOver =>
      this == finished || this == declined || this == cancelled;
}

/// How a finished game finished, as stored.
///
/// Deliberately NOT a Glicko input, and there is no rating field anywhere on
/// this document. Arena results are visible on the Arena and nowhere else:
/// they do not reach `onMatchSettled`, they do not write
/// `users/{uid}/ratings/*`, and they do not touch career totals. Two members
/// playing chess on a phone are not producing evidence about anybody's
/// sporting ability, and an unsupervised online board is trivially cheated,
/// so the honest thing is to keep the result inside the room it was made in.
class ArenaResult {
  const ArenaResult({
    required this.reason,
    this.winnerUid,
    this.scores = const [],
  });

  /// Null for a draw.
  final String? winnerUid;

  /// "Checkmate", "Resigned", "Black by 6.5", "Board full".
  final String reason;

  /// Final points per side where the game keeps them.
  final List<double> scores;

  bool get isDraw => winnerUid == null;

  static ArenaResult? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    return ArenaResult(
      winnerUid: Fs.strOrNull(m['winnerUid']),
      reason: Fs.str(m['reason'], 'Finished'),
      scores: (m['scores'] as List?)
              ?.whereType<num>()
              .map((e) => e.toDouble())
              .toList() ??
          const [],
    );
  }

  Map<String, Object?> toMap() => {
        'winnerUid': winnerUid,
        'reason': reason,
        if (scores.isNotEmpty) 'scores': scores,
      };
}

/// One move as it sits in the document.
///
/// Carries its own notation rather than deriving it on read, because notation
/// depends on the position the move was made in, and a move list must stay
/// readable even to a client whose engine has since changed. The [move] itself
/// is what gets replayed; the notation is what a person reads.
class ArenaMoveRecord {
  const ArenaMoveRecord({
    required this.ply,
    required this.uid,
    required this.side,
    required this.notation,
    required this.move,
    this.at,
  });

  /// 0-based index in the move list. Doubles as the optimistic-concurrency
  /// token: a move is only accepted when its ply equals the current length,
  /// so two taps that race cannot both land.
  final int ply;

  final String uid;
  final int side;
  final String notation;
  final ArenaMove move;
  final DateTime? at;

  static ArenaMoveRecord fromMap(Map<String, dynamic> m) => ArenaMoveRecord(
        ply: Fs.integer(m['ply']),
        uid: Fs.str(m['uid']),
        side: Fs.integer(m['side']),
        notation: Fs.str(m['notation'], '?'),
        move: ArenaMove.fromMap(Fs.map(m['move'])),
        at: Fs.dateOrNull(m['at']),
      );

  Map<String, Object?> toMap() => {
        'ply': ply,
        'uid': uid,
        'side': side,
        'notation': notation,
        'move': move.toMap(),
        // Not a server timestamp: `FieldValue.serverTimestamp()` cannot be
        // written inside an array element. The wall clock here is a display
        // detail — nothing depends on it, because the ply decides order.
        'at': Timestamp.fromDate(DateTime.now().toUtc()),
      };
}

/// Every position a game passed through, and where it stands now.
class ArenaReplay {
  const ArenaReplay({
    required this.positions,
    required this.outcome,
    required this.truncatedAt,
  });

  /// [0] is the opening position; [n] is the board after n moves. Never empty.
  final List<ArenaPosition> positions;

  /// The result the RULES give, which is not the same as the stored result —
  /// a resignation ends a game the rules would have let continue.
  final GameOutcome? outcome;

  /// The ply at which replay had to stop because a stored move was not legal
  /// in the position it claimed to be made in, or null when the whole list
  /// replayed cleanly.
  ///
  /// This should never fire. It exists because the alternative to noticing is
  /// drawing a board that silently disagrees with the opponent's, and a
  /// visible "this game could not be replayed" is far better than two players
  /// staring at two different positions.
  final int? truncatedAt;

  ArenaPosition get current => positions.last;
  int get ply => positions.length - 1;
}

/// A game of chess, checkers, go, reversi, connect four or gomoku, played
/// between two members — `arenaMatches/{matchId}`.
///
/// ## The move list is the truth
///
/// The document stores the moves and nothing else about the board. No FEN, no
/// cached grid. Every position is recomputed by feeding the list back through
/// the engine ([replay]), which buys three things that a stored board does
/// not: the two phones cannot drift apart, because they derive rather than
/// receive; any position in the game can be shown for review by replaying a
/// prefix; and a stored move that does not fit the rules is *detectable*
/// rather than authoritative.
///
/// It costs a full replay on every snapshot. For the longest game here — a
/// 19×19 go board — that is a few hundred cheap array operations, which is
/// nothing next to the frame it is drawn on.
class ArenaMatch {
  const ArenaMatch({
    required this.id,
    required this.gameId,
    required this.variantId,
    required this.config,
    required this.players,
    required this.names,
    required this.status,
    required this.challengerUid,
    this.photos = const {},
    this.moves = const [],
    this.result,
    this.orgId,
    this.orgName,
    this.message,
    this.drawOfferBy,
    this.createdAt,
    this.updatedAt,
    this.lastMoveAt,
  });

  final String id;

  /// An [ArenaGames] id. The engine is looked up from it, and a match whose
  /// game this build does not know is shown as "update the app" rather than
  /// opened.
  final String gameId;
  final String variantId;

  /// The settings frozen at challenge time — board size, komi. Frozen for the
  /// same reason `Fixture.scoringConfig` is: changing a default later must not
  /// retroactively change a game somebody already played.
  final Map<String, dynamic> config;

  /// The two players, indexed by SIDE. `players[0]` moves first.
  final List<String> players;

  final Map<String, String> names;
  final Map<String, String> photos;

  final ArenaStatus status;

  /// Who sent the challenge. Not necessarily `players[0]` — the challenger
  /// does not automatically get the first move, which in chess is an
  /// advantage; see `ArenaRepository.challenge`.
  final String challengerUid;

  final List<ArenaMoveRecord> moves;
  final ArenaResult? result;

  /// The club the challenge was sent inside, when it was. Arena games are
  /// personal, so this is a label and a filter, never a permission.
  final String? orgId;
  final String? orgName;

  final String? message;

  /// Whose draw offer is standing, if any. Cleared by the next move either
  /// way, so an offer cannot linger across a change in the position.
  final String? drawOfferBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastMoveAt;

  /// How long a live game may sit with nobody moving before it is closed.
  ///
  /// Games that are simply walked away from are the main way a turn-based
  /// board rots: the opponent is left with a row in "Their move" that will
  /// never resolve, and no way to tell a slow thinker from somebody who shut
  /// their phone in a bus three days ago. Ten minutes is short because these
  /// are meant to be played through in one sitting.
  ///
  /// The clock is enforced in three places, deliberately: the board counts it
  /// down so it is never a surprise, the waiting player may close the game
  /// themselves the moment it expires, and a scheduled function sweeps up the
  /// games nobody is looking at. The rule in `firestore.rules` checks the same
  /// ten minutes, so a client cannot claim early.
  static const idleLimit = Duration(minutes: 10);

  /// When the clock last restarted — the last move, or the moment the
  /// challenge was accepted for a game where nobody has moved yet.
  DateTime? get idleSince => lastMoveAt ?? updatedAt ?? createdAt;

  /// When this game closes itself if nobody moves.
  DateTime? get idleDeadline => idleSince?.add(idleLimit);

  /// What is left on the clock. Null when no clock is running.
  Duration? timeLeft(DateTime now) {
    if (status != ArenaStatus.active) return null;
    final deadline = idleDeadline;
    if (deadline == null) return null;
    final left = deadline.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool hasTimedOut(DateTime now) =>
      status == ArenaStatus.active &&
      (idleDeadline?.isBefore(now) ?? false);

  /// Whether [uid] may close this game because their opponent stopped
  /// playing. Never the player who is themselves holding everybody up.
  bool canClaimTimeout(String uid, DateTime now) =>
      hasTimedOut(now) && players.contains(uid) && turnUid != uid;

  ArenaGame? get game => ArenaGames.byId(gameId);

  GameConfig get gameConfig => GameConfig(config);

  int sideOf(String uid) => players.indexOf(uid);

  String? opponentOf(String uid) {
    for (final p in players) {
      if (p != uid) return p;
    }
    return null;
  }

  String nameOf(String? uid) =>
      uid == null ? 'Unknown' : (names[uid] ?? 'Player');

  /// Whose move it is, or null before the game starts and after it ends.
  String? get turnUid {
    if (status != ArenaStatus.active) return null;
    final game = this.game;
    if (game == null) return null;
    final side = replay().current.turn;
    return side < players.length ? players[side] : null;
  }

  bool isTurn(String uid) => turnUid == uid;

  /// Rebuilds every position from the move list.
  ///
  /// A move that is not legal in the position it claims to belong to stops the
  /// replay rather than being forced through — see [ArenaReplay.truncatedAt].
  ArenaReplay replay({int? upToPly}) {
    final game = this.game;
    if (game == null) {
      return const ArenaReplay(
        positions: [ArenaPosition(cells: [], turn: 0)],
        outcome: null,
        truncatedAt: 0,
      );
    }

    final config = gameConfig;
    final positions = <ArenaPosition>[game.initial(config)];
    final limit = upToPly ?? moves.length;
    int? truncated;

    for (var i = 0; i < moves.length && i < limit; i++) {
      final current = positions.last;
      final legal = game.legalMoves(current, config);
      final wanted = moves[i].move;
      final match = legal.where((m) => m.key == wanted.key);
      if (match.isEmpty) {
        truncated = i;
        break;
      }
      positions.add(game.apply(current, match.first, config));
    }

    return ArenaReplay(
      positions: positions,
      outcome: game.outcome(positions.last, positions, config),
      truncatedAt: truncated,
    );
  }

  static ArenaMatch fromDoc(Map<String, dynamic> m, String id) => ArenaMatch(
        id: id,
        gameId: Fs.str(m['gameId']),
        variantId: Fs.str(m['variantId'], 'standard'),
        config: Fs.map(m['config']),
        players: Fs.strList(m['players']),
        names: _stringMap(m['names']),
        photos: _stringMap(m['photos']),
        status: ArenaStatus.fromWire(Fs.strOrNull(m['status'])),
        challengerUid: Fs.str(m['challengerUid']),
        moves: (m['moves'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    ArenaMoveRecord.fromMap(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        result: ArenaResult.fromMap(m['result']),
        orgId: Fs.strOrNull(m['orgId']),
        orgName: Fs.strOrNull(m['orgName']),
        message: Fs.strOrNull(m['message']),
        drawOfferBy: Fs.strOrNull(m['drawOfferBy']),
        createdAt: Fs.dateOrNull(m['createdAt']),
        updatedAt: Fs.dateOrNull(m['updatedAt']),
        lastMoveAt: Fs.dateOrNull(m['lastMoveAt']),
      );

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out;
  }

  Map<String, Object?> toCreate() => {
        'gameId': gameId,
        'variantId': variantId,
        'config': config,
        'players': players,
        'names': names,
        'photos': photos,
        'status': status.wire,
        'challengerUid': challengerUid,
        'moves': const <Map<String, Object?>>[],
        'orgId': orgId,
        'orgName': orgName,
        'message': message,
        // Denormalised so the "waiting on you" list is one indexed query
        // rather than a replay of every game the member is in.
        'turnUid': players.isEmpty ? null : players[0],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
