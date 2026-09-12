import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:playsphere/core/models/arena_match.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/data/arena_repository.dart';
import 'package:playsphere/core/errors/app_exception.dart';
import 'package:playsphere/features/arena/arena_home_screen.dart';
import 'package:playsphere/features/arena/arena_providers.dart';

/// The Arena list, and the one thing it must not make people hunt for:
/// answering a challenge and landing on the board.
void main() {
  const me = 'uid_me';
  const them = 'uid_them';

  ArenaMatch chess({
    required ArenaStatus status,
    String id = 'match1',
    String challenger = them,
    List<String> players = const [me, them],
  }) =>
      ArenaMatch(
        id: id,
        gameId: 'chess',
        variantId: 'standard',
        config: const {},
        players: players,
        names: const {me: 'Me', them: 'Ravi'},
        status: status,
        challengerUid: challenger,
      );

  Future<void> pump(
    WidgetTester tester,
    List<ArenaMatch> matches, {
    ArenaRepository? repo,
    Size? surface,
    double textScale = 1,
  }) async {
    if (surface != null) {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final router = GoRouter(
      initialLocation: '/arena',
      routes: [
        GoRoute(path: '/arena', builder: (_, __) => const ArenaHomeScreen()),
        GoRoute(
          path: '/arena/game/:matchId',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('BOARD ${state.pathParameters['matchId']}'),
            ),
          ),
        ),
        GoRoute(
          path: '/arena/new/:gameId',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('NEW ${state.pathParameters['gameId']}'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(me),
          if (repo != null) arenaRepositoryProvider.overrideWithValue(repo),
          myArenaMatchesProvider.overrideWith((ref) => Stream.value(matches)),
          // The ladder link reads this; left alone it reaches for a Firestore
          // that `flutter test` never starts.
          myArenaStatsProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the Arena list until [finder] is on screen.
  ///
  /// The list is long — a note, the ladder link, any invitations, six game
  /// tiles, then the game sections — and on a 320dp phone most of it starts
  /// below the fold. A test that asserts on something without scrolling to it
  /// is testing the viewport height, not the screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says plainly that nothing here is rated', (tester) async {
    await pump(tester, const []);
    // The note is a RichText — its bold lead-in and the rest are one
    // paragraph — so the finder has to be told to look inside the spans.
    expect(
      find.textContaining('Nothing here is rated', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('do not touch your Glicko', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('lists every game and opens the challenge flow',
      (tester) async {
    await pump(tester, const []);

    for (final name in const [
      'Chess',
      'Checkers',
      'Connect Four',
      'Reversi',
      'Gomoku',
      'Go',
    ]) {
      await reveal(tester, find.text(name));
      expect(find.text(name), findsOneWidget, reason: '$name tile is missing');
    }

    await reveal(tester, find.text('Chess'));
    await tester.tap(find.text('Chess'));
    await tester.pumpAndSettle();
    expect(find.text('NEW chess'), findsOneWidget);
  });

  testWidgets('accepting from the list opens the board', (tester) async {
    final repo = _FakeArenaRepository();
    await pump(tester, [chess(status: ArenaStatus.pending)], repo: repo);

    expect(find.text('Waiting for you'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(repo.accepted, ['match1'], reason: 'the challenge was accepted');
    expect(find.text('BOARD match1'), findsOneWidget,
        reason: 'and the board is what comes next');
  });

  testWidgets('a refused acceptance stays on the list and says why',
      (tester) async {
    final repo = _FakeArenaRepository()..failAccept = true;
    await pump(tester, [chess(status: ArenaStatus.pending)], repo: repo);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('BOARD match1'), findsNothing);
    expect(find.text('This challenge has been answered.'), findsOneWidget);
  });

  testWidgets('declining answers it without opening anything',
      (tester) async {
    final repo = _FakeArenaRepository();
    await pump(tester, [chess(status: ArenaStatus.pending)], repo: repo);

    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(repo.withdrawn, ['match1']);
    expect(find.text('BOARD match1'), findsNothing);
  });

  testWidgets('a challenge you sent offers no buttons to answer it',
      (tester) async {
    await pump(
      tester,
      [chess(status: ArenaStatus.pending, challenger: me)],
    );

    await reveal(tester, find.text('Challenges you sent'));
    expect(find.text('Challenges you sent'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('a live game where it is your move is called out',
      (tester) async {
    await pump(tester, [chess(status: ArenaStatus.active)]);

    expect(find.text('Your move'), findsWidgets);
    await tester.tap(find.text('Ravi').first);
    await tester.pumpAndSettle();
    expect(find.text('BOARD match1'), findsOneWidget);
  });

  // Overflow is the failure mode a grid of six tiles actually has, and it only
  // shows up at a real phone width — a widget test's default 800x600 surface
  // is wider than any phone and hid it completely.
  group('fits on a phone', () {
    const sizes = <String, Size>{
      'a small phone (320dp)': Size(320, 568),
      'a common Android phone (360dp)': Size(360, 640),
      'a modern phone (390dp)': Size(390, 844),
      'a tablet (768dp)': Size(768, 1024),
    };

    sizes.forEach((label, size) {
      testWidgets('renders without overflowing on $label', (tester) async {
        await pump(tester, const [], surface: size);
        expect(tester.takeException(), isNull);
        // Every tile is still there and still readable, not clipped away.
        await reveal(tester, find.text('Connect Four'));
        expect(find.text('Connect Four'), findsOneWidget);
        expect(find.text('Chess'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('survives a system font scaled up for accessibility',
        (tester) async {
      // The case that broke the fixed-ratio grid: same width, taller text.
      await pump(
        tester,
        const [],
        surface: const Size(360, 640),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits with games and invitations above the grid',
        (tester) async {
      await pump(
        tester,
        [
          chess(status: ArenaStatus.pending),
          chess(status: ArenaStatus.active, id: 'match2'),
        ],
        surface: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      // The invitation buttons are the widest thing in a card, and a narrow
      // phone is where they would be squeezed out first.
      await reveal(tester, find.text('Play'));
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('drops to two tiles across on a phone and three on a tablet',
        (tester) async {
      Future<int> columnsAt(Size size) async {
        await pump(tester, const [], surface: size);
        await reveal(tester, find.text('Go'));
        // Tiles sharing a top edge are one row.
        final tops = <double>{};
        for (final name in const [
          'Chess',
          'Checkers',
          'Connect Four',
          'Reversi',
          'Gomoku',
          'Go',
        ]) {
          tops.add(tester.getRect(find.text(name)).top);
        }
        return 6 ~/ tops.length;
      }

      expect(await columnsAt(const Size(360, 640)), 2);
      expect(await columnsAt(const Size(768, 1024)), 3);
    });
  });

  testWidgets('a game waiting on the opponent is not called out',
      (tester) async {
    await pump(
      tester,
      [chess(status: ArenaStatus.active, players: const [them, me])],
    );

    await reveal(tester, find.text('Their move'));
    expect(find.text('Their move'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
  });
}

class _FakeArenaRepository extends ArenaRepository {
  final accepted = <String>[];
  final withdrawn = <String>[];
  bool failAccept = false;

  @override
  Future<void> accept(String matchId, String uid) async {
    if (failAccept) {
      throw const ValidationException('This challenge has been answered.');
    }
    accepted.add(matchId);
  }

  @override
  Future<void> withdraw(String matchId, String uid) async {
    withdrawn.add(matchId);
  }
}
