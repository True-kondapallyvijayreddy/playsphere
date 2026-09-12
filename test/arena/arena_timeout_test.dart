import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/arena_match.dart';

/// The ten-minute idle clock.
///
/// A turn-based board rots when games are walked away from: the opponent is
/// left with a row that will never resolve. These tests pin the rule that
/// closes them, and — just as importantly — pin who is allowed to invoke it,
/// because "close this game and give me the win" is exactly the button a
/// losing player would press if it were offered to them.
void main() {
  const me = 'uid_me';
  const them = 'uid_them';
  final t0 = DateTime.utc(2026, 9, 4, 12);

  ArenaMatch match({
    required List<String> players,
    ArenaStatus status = ArenaStatus.active,
    DateTime? lastMoveAt,
    DateTime? updatedAt,
    List<ArenaMoveRecord> moves = const [],
  }) =>
      ArenaMatch(
        id: 'm1',
        gameId: 'chess',
        variantId: 'standard',
        config: const {},
        players: players,
        names: const {me: 'Me', them: 'Ravi'},
        status: status,
        challengerUid: them,
        moves: moves,
        lastMoveAt: lastMoveAt,
        updatedAt: updatedAt ?? t0,
      );

  test('the clock runs from the last move', () {
    final m = match(players: const [me, them], lastMoveAt: t0);
    expect(m.timeLeft(t0), const Duration(minutes: 10));
    expect(m.timeLeft(t0.add(const Duration(minutes: 4))),
        const Duration(minutes: 6));
    expect(m.hasTimedOut(t0.add(const Duration(minutes: 9))), isFalse);
    expect(m.hasTimedOut(t0.add(const Duration(minutes: 11))), isTrue);
  });

  test('a game with no moves runs from when it was accepted', () {
    // Otherwise a challenge accepted and then ignored would never expire,
    // because there is no last move to measure from.
    final m = match(players: const [me, them], updatedAt: t0);
    expect(m.idleSince, t0);
    expect(m.hasTimedOut(t0.add(const Duration(minutes: 11))), isTrue);
  });

  test('the clock never goes negative', () {
    final m = match(players: const [me, them], lastMoveAt: t0);
    expect(m.timeLeft(t0.add(const Duration(hours: 3))), Duration.zero);
  });

  test('only a game in play has a clock at all', () {
    for (final status in const [
      ArenaStatus.pending,
      ArenaStatus.finished,
      ArenaStatus.declined,
      ArenaStatus.cancelled,
    ]) {
      final m = match(
        players: const [me, them],
        status: status,
        lastMoveAt: t0,
      );
      expect(m.timeLeft(t0), isNull, reason: '$status should not tick');
      expect(m.hasTimedOut(t0.add(const Duration(hours: 1))), isFalse);
    }
  });

  group('who may close it', () {
    test('the player kept waiting can, once the time is up', () {
      // players[0] is to move with no moves played, so it is Ravi holding
      // things up and me doing the waiting.
      final m = match(players: const [them, me], lastMoveAt: t0);
      expect(m.turnUid, them);

      expect(m.canClaimTimeout(me, t0.add(const Duration(minutes: 9))),
          isFalse, reason: 'not yet');
      expect(m.canClaimTimeout(me, t0.add(const Duration(minutes: 11))),
          isTrue);
    });

    test('the player holding everyone up cannot claim their own timeout', () {
      // The whole point. Without this a player losing on the board could sit
      // out ten minutes and take the win.
      final m = match(players: const [me, them], lastMoveAt: t0);
      expect(m.turnUid, me, reason: 'it is my move');
      expect(m.canClaimTimeout(me, t0.add(const Duration(minutes: 30))),
          isFalse);
    });

    test('a stranger cannot close somebody else\'s game', () {
      final m = match(players: const [them, me], lastMoveAt: t0);
      expect(
        m.canClaimTimeout('uid_someone_else', t0.add(const Duration(hours: 1))),
        isFalse,
      );
    });

    test('a finished game cannot be claimed again', () {
      final m = match(
        players: const [them, me],
        status: ArenaStatus.finished,
        lastMoveAt: t0,
      );
      expect(m.canClaimTimeout(me, t0.add(const Duration(hours: 1))), isFalse);
    });
  });
}
