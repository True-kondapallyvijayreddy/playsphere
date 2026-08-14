import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/sport_stat_row.dart';
import 'package:playsphere/core/providers.dart';
import 'package:playsphere/features/sports/sports_directory_screen.dart';
import 'package:playsphere/shared/ui_kit.dart';

/// The sports directory.
///
/// What is worth protecting here is not the layout but the three ways this
/// screen can quietly lie: showing a sport the filter excludes, showing a
/// blank row for a sport the nightly rollup has not reached yet, and
/// labelling an individual sport's entrants as "Teams". Each of those looks
/// like a working screen and reads as wrong to anyone who knows the sport.
void main() {
  Widget harness({Map<String, SportStatRow> stats = const {}}) {
    return ProviderScope(
      overrides: [
        sportStatsProvider.overrideWith((ref) => Stream.value(stats)),
      ],
      child: const MaterialApp(home: SportsDirectoryScreen()),
    );
  }

  testWidgets('a sport with no rollup row yet renders at zero, not blank',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Cricket'), findsOneWidget);
    // Zero is the honest reading for a sport nobody has run an event in, and
    // it must render rather than leaving the row's second line empty.
    expect(
      find.textContaining('0 Tournaments'),
      findsWidgets,
      reason: 'a sport absent from sportStats should still show its row',
    );
  });

  testWidgets('counts come from the rollup and are grouped', (tester) async {
    await tester.pumpWidget(harness(stats: {
      'cricket': const SportStatRow(
        sportId: 'cricket',
        tournamentCount: 1245,
        teamCount: 8456,
        playerCount: 120,
      ),
    }));
    await tester.pumpAndSettle();

    expect(find.textContaining('1,245 Tournaments'), findsOneWidget);
    expect(find.textContaining('8,456 Teams'), findsOneWidget);
  });

  testWidgets('an individual-shaped sport reads Players, not Teams',
      (tester) async {
    await tester.pumpWidget(harness(stats: {
      'badminton': const SportStatRow(
        sportId: 'badminton',
        tournamentCount: 1102,
        teamCount: 4,
        playerCount: 7312,
      ),
    }));
    await tester.pumpAndSettle();

    expect(find.textContaining('7,312 Players'), findsOneWidget);
  });

  testWidgets('the Team Sports filter hides racket-only sports',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Tennis'), findsOneWidget);

    await tester.tap(find.text('Team Sports'));
    await tester.pumpAndSettle();

    expect(find.text('Cricket'), findsOneWidget);
    expect(find.text('Tennis'), findsNothing);
  });

  testWidgets('table tennis appears under Indoor as well as Racket',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indoor Sports'));
    await tester.pumpAndSettle();

    // The multi-group case: a sport belonging to two categories must appear
    // under both, or filtering feels arbitrary.
    expect(find.text('Table Tennis'), findsOneWidget);
    expect(find.text('Chess'), findsOneWidget);
    expect(find.text('Cricket'), findsNothing);
  });

  testWidgets('search narrows to a matching sport', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search sports'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'kab');
    await tester.pumpAndSettle();

    expect(find.text('Kabaddi'), findsOneWidget);
    expect(find.text('Cricket'), findsNothing);
  });

  testWidgets('a search matching nothing explains itself', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search sports'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quidditch');
    await tester.pumpAndSettle();

    expect(find.text('No sports match that'), findsOneWidget);
  });

  group('psGrouped', () {
    test('groups in thousands without abbreviating', () {
      // Not "8.5K": these numbers are read against each other, and a rounded
      // one is worse than a long one.
      expect(psGrouped(0), '0');
      expect(psGrouped(999), '999');
      expect(psGrouped(1000), '1,000');
      expect(psGrouped(8456), '8,456');
      expect(psGrouped(1234567), '1,234,567');
    });
  });
}
