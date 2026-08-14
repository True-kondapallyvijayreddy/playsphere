import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:playsphere/core/providers.dart';
import 'package:playsphere/domain/gov/age_group.dart';
import 'package:playsphere/domain/scout/talent_board.dart';
import 'package:playsphere/features/scout/rising_talent_screen.dart';

/// The Rising Talent feed — §6's discovery surface.
///
/// The interesting behaviour to protect here is not the layout: it is that
/// every control rewrites a *document id*, and that the under-18 toggle is
/// only offered to an account that could actually use it. A screen that
/// showed the toggle to everyone would invite a tap that silently returns an
/// empty board, and one that built the wrong id would show the wrong scope's
/// players under the right scope's heading.
void main() {
  TalentBoard boardFor(TalentBoardKey key) => TalentBoard(
        key: key,
        windowDays: 90,
        playerPoolSize: 2,
        teamPoolSize: 1,
        computedAt: DateTime.now().subtract(const Duration(hours: 3)),
        players: const [
          RisingPlayerEntry(
            uid: 'u_asha',
            displayName: 'Asha',
            rank: 1,
            score: 62.5,
            ratingDelta: 100,
            matchesInWindow: 5,
            ageGroupLabel: 'U-17',
            districtLabel: 'Nalgonda',
            provisional: true,
          ),
          RisingPlayerEntry(
            uid: 'u_ravi',
            displayName: 'Ravi',
            rank: 2,
            score: 30,
            ratingDelta: 60,
            matchesInWindow: 4,
            ageGroupLabel: 'Senior',
          ),
        ],
        teams: [
          const RisingTeamEntry(
            orgId: 'o_falcons',
            orgName: 'Falcons',
            rank: 1,
            score: 0.9,
            matchesInWindow: 8,
            winsInWindow: 6,
            recentWinRate: 0.75,
            momentum: 0.5,
            tournamentWins: 2,
          ),
        ],
      );

  /// Records every board id the screen asks for, so a test can assert on the
  /// key the filters produced rather than on pixels.
  late List<String> requested;

  Widget harness({
    bool isScout = false,
    TalentBoard? Function(TalentBoardKey)? respond,
  }) {
    requested = [];
    final router = GoRouter(
      initialLocation: '/scout/rising',
      routes: [
        GoRoute(
          path: '/scout/rising',
          builder: (_, __) => const RisingTalentScreen(),
        ),
        GoRoute(
          path: '/player/:uid',
          builder: (_, s) =>
              Scaffold(body: Center(child: Text('AT ${s.uri.path}'))),
        ),
        GoRoute(
          path: '/org/:orgId',
          builder: (_, s) =>
              Scaffold(body: Center(child: Text('AT ${s.uri.path}'))),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        isScoutProvider.overrideWith((ref) async => isScout),
        talentBoardProvider.overrideWith((ref) {
          final key = ref.watch(talentBoardKeyProvider);
          requested.add(key.docId);
          return Stream.value(
            respond != null ? respond(key) : boardFor(key),
          );
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('opens on the national all-ages public cricket board',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(requested.first, 'cricket___any___any___any__public');
    expect(find.text('All India · All ages'), findsOneWidget);
  });

  testWidgets('renders players and clubs with the numbers a scout reads',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    // The raw rating gain, not the shrunk internal score.
    expect(find.text('+100'), findsOneWidget);
    expect(find.text('+60'), findsOneWidget);
    expect(find.textContaining('U-17 · Nalgonda · 5 matches'), findsOneWidget);

    expect(find.text('Falcons'), findsOneWidget);
    expect(find.textContaining('6/8 won (75%)'), findsOneWidget);
    expect(find.textContaining('2 titles'), findsOneWidget);
  });

  testWidgets('picking a sport rewrites the board id', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Kabaddi'));
    await tester.pumpAndSettle();

    expect(requested.last, 'kabaddi___any___any___any__public');
  });

  testWidgets('picking an age band rewrites only the age segment',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, AgeGroup.u17.label));
    await tester.pumpAndSettle();

    expect(requested.last, 'cricket___any___any__u17__public');
    expect(find.text('All India · U-17'), findsOneWidget);
  });

  testWidgets('a state and district slug into the id and the header',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'State'), 'Telangana');
    await tester.enterText(
        find.widgetWithText(TextField, 'District'), 'Nalgonda');
    await tester.tap(find.byTooltip('Apply place'));
    await tester.pumpAndSettle();

    expect(requested.last, 'cricket__telangana__nalgonda___any__public');
    expect(find.text('Nalgonda · All ages'), findsOneWidget);
  });

  testWidgets('clearing the state clears the district with it, rather than '
      'building an incoherent key', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'State'), 'Telangana');
    await tester.enterText(
        find.widgetWithText(TextField, 'District'), 'Nalgonda');
    await tester.tap(find.byTooltip('Apply place'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'State'), '');
    await tester.tap(find.byTooltip('Apply place'));
    await tester.pumpAndSettle();

    expect(requested.last, 'cricket___any___any___any__public');
    expect(TalentBoardKey.parse(requested.last)!.isCoherent, isTrue);
  });

  testWidgets('the under-18 toggle is hidden from an ordinary account',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Include under-18 players'), findsNothing);
    // And nothing it could do by accident: every id asked for is public.
    expect(requested.every((id) => id.endsWith('__public')), isTrue);
  });

  testWidgets('a scout sees the toggle and it switches the board audience',
      (tester) async {
    await tester.pumpWidget(harness(isScout: true));
    await tester.pumpAndSettle();

    expect(find.text('Include under-18 players'), findsOneWidget);
    expect(find.textContaining('Public board — adults only'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(requested.last, 'cricket___any___any___any__scout');
    expect(
      find.textContaining('Contacting one still requires guardian consent'),
      findsOneWidget,
    );
  });

  testWidgets('a board that has never been built reads as empty, not broken',
      (tester) async {
    await tester.pumpWidget(harness(respond: (_) => null));
    await tester.pumpAndSettle();

    expect(find.text('Nobody is on this board yet'), findsOneWidget);
  });

  testWidgets('tapping a player opens their profile', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();

    expect(find.text('AT /player/u_asha'), findsOneWidget);
  });

  testWidgets('tapping a club opens the club', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // The clubs section sits below the players on an 800×600 surface.
    await tester.ensureVisible(find.text('Falcons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Falcons'));
    await tester.pumpAndSettle();

    expect(find.text('AT /org/o_falcons'), findsOneWidget);
  });
}
