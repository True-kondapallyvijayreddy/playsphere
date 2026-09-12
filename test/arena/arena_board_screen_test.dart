import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/arena_match.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/arena_repository.dart';
import 'package:playsphere/domain/arena/arena_game.dart';
import 'package:playsphere/domain/arena/games/chess_game.dart';
import 'package:playsphere/features/arena/arena_board_screen.dart';
import 'package:playsphere/features/arena/arena_providers.dart';
import 'package:playsphere/features/arena/widgets/arena_board_view.dart';

/// Accepting a challenge has to put a PLAYABLE board in front of both people.
///
/// The two halves of that are easy to get separately and wrong together: the
/// invited player is already looking at the board when they tap Accept, and
/// the challenger is looking at the same board from the other side with no
/// tap of their own to trigger anything. Both must go from "waiting" to "your
/// move" off the same document change, which is what these tests pin down.
void main() {
  const me = 'uid_me';
  const them = 'uid_them';

  ArenaMatch chess({
    required ArenaStatus status,
    String challenger = them,
    List<String> players = const [me, them],
    List<ArenaMoveRecord> moves = const [],
  }) =>
      ArenaMatch(
        id: 'match1',
        gameId: 'chess',
        variantId: 'standard',
        config: const {},
        players: players,
        names: const {me: 'Me', them: 'Ravi'},
        status: status,
        challengerUid: challenger,
        moves: moves,
      );

  /// Drives the screen off a controller so a test can push the accepted
  /// document exactly the way Firestore's listener would.
  Future<StreamController<ArenaMatch?>> pump(
    WidgetTester tester,
    ArenaMatch initial, {
    _FakeArenaRepository? repo,
    Size? surface,
    double textScale = 1,
  }) async {
    if (surface != null) {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final controller = StreamController<ArenaMatch?>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          if (repo != null) arenaRepositoryProvider.overrideWithValue(repo),
          arenaMatchProvider('match1').overrideWith(
            (ref) async* {
              yield initial;
              yield* controller.stream;
            },
          ),
        ],
        child: MaterialApp(
          home: const ArenaBoardScreen(matchId: 'match1'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the invited player sees the board, not a bare accept prompt',
      (tester) async {
    await pump(tester, chess(status: ArenaStatus.pending));

    // The board is on screen while the challenge is still pending — you can
    // see what you are being invited to before you say yes.
    expect(find.byType(ArenaBoardView), findsOneWidget);
    expect(find.text('Ravi challenged you.'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    final board = tester.widget<ArenaBoardView>(find.byType(ArenaBoardView));
    expect(board.interactive, isFalse, reason: 'nothing to play yet');
    expect(board.legalMoves, isEmpty);
  });

  testWidgets('accepting turns the same board playable', (tester) async {
    final repo = _FakeArenaRepository();
    final controller =
        await pump(tester, chess(status: ArenaStatus.pending), repo: repo);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(repo.accepted, ['match1']);

    // Firestore echoes the accepted document back.
    controller.add(chess(status: ArenaStatus.active));
    await tester.pumpAndSettle();

    final board = tester.widget<ArenaBoardView>(find.byType(ArenaBoardView));
    expect(board.interactive, isTrue);
    expect(board.legalMoves.length, 20,
        reason: 'twenty legal opening moves in chess');
    expect(find.text('Your move.'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Resign'), findsOneWidget);
  });

  testWidgets('the challenger waiting on the board is switched in too',
      (tester) async {
    // They sent it and never left the screen. Nothing they tap makes this
    // happen — it has to arrive from the document.
    final controller = await pump(
      tester,
      chess(status: ArenaStatus.pending, challenger: me),
    );

    expect(find.text('Waiting for Ravi to accept.'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
    expect(
      tester.widget<ArenaBoardView>(find.byType(ArenaBoardView)).interactive,
      isFalse,
    );

    controller.add(chess(status: ArenaStatus.active, challenger: me));
    await tester.pumpAndSettle();

    expect(find.text('Your move.'), findsOneWidget);
    expect(
      tester.widget<ArenaBoardView>(find.byType(ArenaBoardView)).interactive,
      isTrue,
    );
  });

  testWidgets('the player who is not to move gets a live but read-only board',
      (tester) async {
    // Sides are drawn at random, so half the time accepting hands the first
    // move to the other person. The board must still be shown, and must not
    // be playable.
    final controller = await pump(
      tester,
      chess(status: ArenaStatus.pending, players: const [them, me]),
    );
    controller.add(
      chess(status: ArenaStatus.active, players: const [them, me]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ArenaBoardView), findsOneWidget);
    expect(find.text('Waiting for Ravi.'), findsOneWidget);
    expect(
      tester.widget<ArenaBoardView>(find.byType(ArenaBoardView)).interactive,
      isFalse,
    );
  });

  testWidgets('a declined challenge says so and offers nothing to play',
      (tester) async {
    final controller =
        await pump(tester, chess(status: ArenaStatus.pending));
    controller.add(chess(status: ArenaStatus.declined));
    await tester.pumpAndSettle();

    expect(find.text('Challenge declined.'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(
      tester.widget<ArenaBoardView>(find.byType(ArenaBoardView)).interactive,
      isFalse,
    );
  });

  testWidgets('tapping a piece then a square submits that move',
      (tester) async {
    final repo = _FakeArenaRepository();
    final controller = await pump(
      tester,
      chess(status: ArenaStatus.pending),
      repo: repo,
    );
    controller.add(chess(status: ArenaStatus.active));
    await tester.pumpAndSettle();

    // e2 is index 52 on the board, e4 is 36. Tap the pawn, then its square.
    final rect = tester.getRect(find.byType(ArenaBoardView));
    Offset squareCentre(int index) {
      final cell = rect.width / 8;
      return rect.topLeft +
          Offset((index % 8 + 0.5) * cell, (index ~/ 8 + 0.5) * cell);
    }

    await tester.tapAt(squareCentre(52));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ArenaBoardView>(find.byType(ArenaBoardView)).selected,
      52,
      reason: 'the pawn is picked up',
    );

    await tester.tapAt(squareCentre(36));
    await tester.pumpAndSettle();

    expect(repo.submitted.length, 1);
    expect(repo.submitted.single.from, 52);
    expect(repo.submitted.single.to, 36);
  });

  // The board has to share a phone screen with two player bars, a status
  // line, the move strip and the action bar. It is the one thing that must
  // stay square and stay big, so these check it does both at real sizes.
  group('fits on a phone', () {
    const sizes = <String, Size>{
      'a small phone (320dp)': Size(320, 568),
      'a common Android phone (360dp)': Size(360, 640),
      'a modern phone (390dp)': Size(390, 844),
    };

    sizes.forEach((label, size) {
      testWidgets('lays out without overflowing on $label', (tester) async {
        final controller =
            await pump(tester, chess(status: ArenaStatus.pending),
                surface: size);
        controller.add(chess(status: ArenaStatus.active));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final board = tester.getRect(find.byType(ArenaBoardView));
        expect(board.width, board.height,
            reason: 'the board must stay square');
        expect(board.width, greaterThan(size.width * 0.6),
            reason: 'and must not be squeezed into a strip');
        expect(board.width, lessThanOrEqualTo(size.width));
      });
    });

    testWidgets('survives a system font scaled up for accessibility',
        (tester) async {
      final controller = await pump(
        tester,
        chess(status: ArenaStatus.pending),
        surface: const Size(360, 640),
        textScale: 1.5,
      );
      controller.add(chess(status: ArenaStatus.active));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ArenaBoardView), findsOneWidget);
    });

    testWidgets('a long move list does not push the board off screen',
        (tester) async {
      // Twenty plies of a real game, which is where a move strip that grew
      // with its contents rather than scrolling would start stealing height.
      const game = ChessGame();
      var position = game.initial(GameConfig.empty);
      final moves = <ArenaMoveRecord>[];
      for (var i = 0; i < 20; i++) {
        final legal = game.legalMoves(position, GameConfig.empty);
        final move = legal.first;
        moves.add(ArenaMoveRecord(
          ply: i,
          uid: position.turn == 0 ? me : them,
          side: position.turn,
          notation: game.notation(position, move, GameConfig.empty),
          move: move,
        ));
        position = game.apply(position, move, GameConfig.empty);
      }

      await pump(
        tester,
        chess(status: ArenaStatus.active, moves: moves),
        surface: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      final board = tester.getRect(find.byType(ArenaBoardView));
      expect(board.width, board.height);
      expect(board.bottom, lessThanOrEqualTo(640));
    });
  });
}

/// Records what the screen asked for instead of talking to Firestore.
///
/// Instance fields rather than statics: two tests sharing a tally is how a
/// suite starts passing for the wrong reason.
class _FakeArenaRepository extends ArenaRepository {
  final accepted = <String>[];
  final submitted = <ArenaMove>[];

  @override
  Future<void> accept(String matchId, String uid) async {
    accepted.add(matchId);
  }

  @override
  Future<void> submitMove({
    required String matchId,
    required String uid,
    required ArenaMove move,
    required int expectedPly,
  }) async {
    submitted.add(move);
  }
}
