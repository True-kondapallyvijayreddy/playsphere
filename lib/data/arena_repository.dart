import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/arena_match.dart';
import '../core/models/arena_stats.dart';
import '../domain/arena/arena_game.dart';
import '../domain/arena/arena_registry.dart';
import 'org_repository.dart' show guardStream;

/// Reads and writes for `arenaMatches/{matchId}`.
///
/// ## Why every move goes through a transaction
///
/// Two phones are looking at the same document and both may tap at the same
/// moment — one player moving while the other resigns, or a double tap
/// arriving twice over a flaky connection. The transaction re-reads the
/// document, checks that the move being submitted is the NEXT one
/// (`ply == moves.length`) and that it is legal in the position that
/// re-read produces, and only then appends.
///
/// The check is deliberately done against the freshly read document rather
/// than the model the screen was holding. A screen's copy can be a second
/// stale, and a move validated against a stale board is exactly how a move
/// list ends up containing something the engine will later refuse to replay.
///
/// ## Results stop here
///
/// Finishing a game writes `status`, `result` and nothing else. No rating
/// document, no career tally, no fixture. See [ArenaResult] for why that is
/// the design and not an omission.
class ArenaRepository {
  const ArenaRepository({FirebaseFirestore? firestore, Random? random})
      : _db = firestore,
        _random = random;

  final FirebaseFirestore? _db;
  final Random? _random;

  FirebaseFirestore get _firestore => _db ?? Refs.db;

  // --- Reading -----------------------------------------------------------

  Stream<List<ArenaMatch>> watchMyMatches(String uid) => guardStream(
        () => Refs.arenaMatchesFor(uid).snapshots().map(
              (snap) => snap.docs
                  .map((d) => ArenaMatch.fromDoc(d.data(), d.id))
                  .toList(),
            ),
      );

  Stream<ArenaMatch?> watchMatch(String matchId) => guardStream(
        () => Refs.arenaMatch(matchId).snapshots().map(
              (doc) => doc.exists
                  ? ArenaMatch.fromDoc(doc.data()!, doc.id)
                  : null,
            ),
      );

  /// The Arena ladder. Fifty rows is a club, not a country — this is a
  /// leaderboard for people who know each other.
  Stream<List<ArenaStats>> watchLeaderboard() => guardStream(
        () => Refs.arenaLeaderboard.snapshots().map(
              (snap) => snap.docs
                  .map((d) => ArenaStats.fromDoc(d.data(), d.id))
                  .toList(),
            ),
      );

  /// One player's record, including their own when they are nowhere near the
  /// top of the table — which is most people, and no reason to hide it.
  Stream<ArenaStats?> watchStats(String uid) => guardStream(
        () => Refs.arenaStatsFor(uid).snapshots().map(
              (doc) => doc.exists
                  ? ArenaStats.fromDoc(doc.data()!, doc.id)
                  : null,
            ),
      );

  // --- Starting a game ---------------------------------------------------

  /// Sends a challenge. Returns the new match id.
  ///
  /// Sides are drawn at random rather than given to the challenger. In chess
  /// and connect four the first move is a real advantage, and letting the
  /// person who issues the challenge always take it would make "challenge
  /// them back" the only fair way to play — which nobody does. A coin removes
  /// the question.
  Future<String> challenge({
    required ArenaGame game,
    required GameVariant variant,
    required AppUser from,
    required AppUser to,
    String? orgId,
    String? orgName,
    String? message,
  }) async {
    if (from.uid == to.uid) {
      throw const ValidationException('You cannot challenge yourself.');
    }

    final rng = _random ?? Random();
    final challengerFirst = rng.nextBool();
    final players = challengerFirst
        ? [from.uid, to.uid]
        : [to.uid, from.uid];

    final match = ArenaMatch(
      id: '',
      gameId: game.id,
      variantId: variant.id,
      config: variant.config,
      players: players,
      names: {from.uid: from.displayName, to.uid: to.displayName},
      photos: {
        if (from.photoUrl != null) from.uid: from.photoUrl!,
        if (to.photoUrl != null) to.uid: to.photoUrl!,
      },
      status: ArenaStatus.pending,
      challengerUid: from.uid,
      orgId: orgId,
      orgName: orgName,
      message: (message ?? '').trim().isEmpty ? null : message!.trim(),
    );

    final ref = await Refs.arenaMatches.add(match.toCreate());
    return ref.id;
  }

  /// The opponent accepts. Only they may, and only while it is pending.
  Future<void> accept(String matchId, String uid) async {
    await _firestore.runTransaction((tx) async {
      final ref = Refs.arenaMatch(matchId);
      final snap = await tx.get(ref);
      final match = _require(snap);

      if (match.status != ArenaStatus.pending) {
        throw const ValidationException('This challenge has been answered.');
      }
      if (match.challengerUid == uid) {
        throw const ValidationException(
          'Wait for them to accept — you sent this one.',
        );
      }
      if (!match.players.contains(uid)) {
        throw const PermissionDeniedException();
      }

      tx.update(ref, {
        'status': ArenaStatus.active.wire,
        'turnUid': match.players[0],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Declining, or the challenger withdrawing before it is answered.
  Future<void> withdraw(String matchId, String uid) async {
    await _firestore.runTransaction((tx) async {
      final ref = Refs.arenaMatch(matchId);
      final snap = await tx.get(ref);
      final match = _require(snap);

      if (match.status != ArenaStatus.pending) {
        throw const ValidationException('This challenge has been answered.');
      }
      if (!match.players.contains(uid)) {
        throw const PermissionDeniedException();
      }

      tx.update(ref, {
        'status': match.challengerUid == uid
            ? ArenaStatus.cancelled.wire
            : ArenaStatus.declined.wire,
        'turnUid': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // --- Playing -----------------------------------------------------------

  /// Appends one move, and finishes the game if that move ended it.
  ///
  /// [expectedPly] is the number of moves the caller believed had been played.
  /// It is the whole concurrency story: a second tap, a retried write or a
  /// move sent from a screen that had not yet seen the opponent's reply all
  /// arrive with a stale ply and are refused rather than corrupting the list.
  Future<void> submitMove({
    required String matchId,
    required String uid,
    required ArenaMove move,
    required int expectedPly,
  }) async {
    await _firestore.runTransaction((tx) async {
      final ref = Refs.arenaMatch(matchId);
      final snap = await tx.get(ref);
      final match = _require(snap);

      if (match.status != ArenaStatus.active) {
        throw const ValidationException('This game is not in play.');
      }
      final game = match.game;
      if (game == null) {
        throw const ValidationException(
          'This game needs a newer version of the app.',
        );
      }
      if (match.moves.length != expectedPly) {
        // The default message for this type talks about scoring a delivery,
        // which would be baffling here.
        throw const ConflictException(
          'Your opponent moved first — catching up to the live board.',
        );
      }

      // Rebuild from the document just read, never from the caller's copy.
      final replay = match.replay();
      if (replay.truncatedAt != null) {
        throw const ValidationException(
          'This game could not be replayed and is out of step.',
        );
      }

      final position = replay.current;
      final side = position.turn;
      if (side >= match.players.length || match.players[side] != uid) {
        throw const ValidationException('It is not your turn.');
      }

      final legal = game.legalMoves(position, match.gameConfig);
      final chosen = legal.where((m) => m.key == move.key);
      if (chosen.isEmpty) {
        throw const ValidationException('That move is not legal.');
      }

      final record = ArenaMoveRecord(
        ply: expectedPly,
        uid: uid,
        side: side,
        notation: game.notation(position, chosen.first, match.gameConfig),
        move: chosen.first,
      );

      final after = game.apply(position, chosen.first, match.gameConfig);
      final outcome = game.outcome(
        after,
        [...replay.positions, after],
        match.gameConfig,
      );

      tx.update(ref, {
        'moves': FieldValue.arrayUnion([record.toMap()]),
        // A standing draw offer does not survive the position changing.
        'drawOfferBy': FieldValue.delete(),
        'lastMoveAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (outcome == null) ...{
          'turnUid': match.players[after.turn],
        } else ...{
          'status': ArenaStatus.finished.wire,
          'turnUid': null,
          'result': ArenaResult(
            winnerUid: outcome.winner == null
                ? null
                : match.players[outcome.winner!],
            reason: outcome.reason,
            scores: outcome.scores ?? const [],
          ).toMap(),
        },
      });
    });
  }

  /// Giving up. Always available to either player while a game is live —
  /// there is no position from which a player may not resign.
  Future<void> resign(String matchId, String uid) async {
    await _firestore.runTransaction((tx) async {
      final ref = Refs.arenaMatch(matchId);
      final snap = await tx.get(ref);
      final match = _require(snap);

      if (match.status != ArenaStatus.active) {
        throw const ValidationException('This game is not in play.');
      }
      final opponent = match.opponentOf(uid);
      if (opponent == null) throw const PermissionDeniedException();

      tx.update(ref, {
        'status': ArenaStatus.finished.wire,
        'turnUid': null,
        'result': ArenaResult(
          winnerUid: opponent,
          reason: '${match.nameOf(uid)} resigned',
        ).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Closes a game whose opponent stopped playing.
  ///
  /// Only the player who is NOT holding things up may call it, and only once
  /// the ten minutes have genuinely elapsed against the document's own
  /// timestamps rather than the caller's clock — a phone with its clock wound
  /// forward would otherwise be able to claim a win at will. The same check
  /// exists in `firestore.rules`, so this is defence in depth rather than the
  /// only gate.
  Future<void> claimTimeout(String matchId, String uid) async {
    await _firestore.runTransaction((tx) async {
      final ref = Refs.arenaMatch(matchId);
      final snap = await tx.get(ref);
      final match = _require(snap);

      if (match.status != ArenaStatus.active) {
        throw const ValidationException('This game is not in play.');
      }
      if (!match.players.contains(uid)) {
        throw const PermissionDeniedException();
      }
      if (match.turnUid == uid) {
        throw const ValidationException(
          'It is your move — the clock is running on you.',
        );
      }
      final since = match.idleSince;
      if (since == null ||
          DateTime.now().toUtc().difference(since) < ArenaMatch.idleLimit) {
        throw const ValidationException(
          'Give them the full ten minutes first.',
        );
      }

      tx.update(ref, {
        'status': ArenaStatus.finished.wire,
        'turnUid': null,
        'result': ArenaResult(
          winnerUid: uid,
          reason: '${match.nameOf(match.turnUid)} stopped playing',
        ).toMap(),
        'closedBy': 'timeout',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Offering a draw, or withdrawing an offer by calling it with a null uid.
  Future<void> offerDraw(String matchId, String uid) async {
    await Refs.arenaMatch(matchId).update({
      'drawOfferBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> withdrawDraw(String matchId) async {
    await Refs.arenaMatch(matchId).update({
      'drawOfferBy': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Accepting the opponent's offer. Only the player who did NOT make the
  /// offer can agree to it, which is the check that stops a draw being taken
  /// unilaterally by offering and immediately accepting.
  Future<void> acceptDraw(String matchId, String uid) async {
    await _firestore.runTransaction((tx) async {
      final ref = Refs.arenaMatch(matchId);
      final snap = await tx.get(ref);
      final match = _require(snap);

      if (match.status != ArenaStatus.active) {
        throw const ValidationException('This game is not in play.');
      }
      if (match.drawOfferBy == null || match.drawOfferBy == uid) {
        throw const ValidationException('There is no offer to accept.');
      }
      if (!match.players.contains(uid)) {
        throw const PermissionDeniedException();
      }

      tx.update(ref, {
        'status': ArenaStatus.finished.wire,
        'turnUid': null,
        'drawOfferBy': FieldValue.delete(),
        'result': const ArenaResult(reason: 'Draw agreed').toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  ArenaMatch _require(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) throw const NotFoundException();
    return ArenaMatch.fromDoc(data, snap.id);
  }
}

/// The games list, for the challenge screen. Lives here so a screen imports
/// one thing rather than reaching into the registry directly.
List<ArenaGame> get arenaGames => ArenaGames.all;
