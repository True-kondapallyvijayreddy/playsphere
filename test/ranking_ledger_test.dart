import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/ranking_entry.dart';

/// A rolling 52-week window is not expressible as a stored total: points have
/// to *leave* it as they age out, and a total cannot forget. These pin the
/// summing rules that follow from keeping the individual results instead.
void main() {
  final now = DateTime(2026, 8, 3);

  RankingEntry entry(
    String uid,
    int points, {
    String round = 'winner',
    int expiresInDays = 200,
    DateTime? awardedAt,
    String name = 'Player',
  }) =>
      RankingEntry(
        id: '$uid-$points-$expiresInDays',
        uid: uid,
        displayName: name,
        points: points,
        round: round,
        sportId: 'badminton',
        awardedAt: awardedAt,
        expiresAt: now.add(Duration(days: expiresInDays)),
      );

  group('summing the window', () {
    test('a player total is the sum of their current results', () {
      final rows = buildRanking(
        [entry('a', 300), entry('a', 180), entry('b', 400)],
        now: now,
      );
      expect(rows.first.uid, 'a', reason: '300 + 180 beats 400');
      expect(rows.first.points, 480);
      expect(rows.first.eventsCounted, 2);
      expect(rows[1].uid, 'b');
      expect(rows[1].points, 400);
    });

    test('an expired result stops counting', () {
      final rows = buildRanking(
        [entry('a', 300, expiresInDays: -1), entry('a', 100)],
        now: now,
      );
      expect(rows.single.points, 100);
      expect(rows.single.eventsCounted, 1);
    });

    test('a player whose every result expired leaves the list', () {
      // A ranking has to be defended rather than banked.
      final rows = buildRanking(
        [entry('gone', 900, expiresInDays: -30)],
        now: now,
      );
      expect(rows, isEmpty);
    });

    test('ranks are assigned in order, from one', () {
      final rows = buildRanking(
        [entry('a', 100), entry('b', 300), entry('c', 200)],
        now: now,
      );
      expect(rows.map((r) => r.uid), ['b', 'c', 'a']);
      expect(rows.map((r) => r.rank), [1, 2, 3]);
    });

    test('the same total from fewer events ranks higher', () {
      final rows = buildRanking(
        [
          entry('efficient', 300),
          entry('grinder', 100),
          entry('grinder', 100),
          entry('grinder', 100),
        ],
        now: now,
      );
      expect(rows.first.uid, 'efficient');
    });

    test('an entry with no uid is ignored rather than crashing', () {
      final rows = buildRanking([entry('', 500), entry('real', 10)], now: now);
      expect(rows.single.uid, 'real');
    });

    test('the most recent name wins', () {
      // People change how they are listed; a ranking showing a name they no
      // longer use reads as somebody else.
      final rows = buildRanking(
        [
          entry('a', 100,
              name: 'Old Name', awardedAt: DateTime(2025, 1, 1)),
          entry('a', 50, name: 'New Name', awardedAt: DateTime(2026, 6, 1)),
        ],
        now: now,
      );
      expect(rows.single.displayName, 'New Name');
    });

    test('a results list is ordered best first', () {
      final rows = buildRanking(
        [entry('a', 60), entry('a', 300), entry('a', 120)],
        now: now,
      );
      expect(rows.single.entries.map((e) => e.points), [300, 120, 60]);
      expect(rows.single.best!.points, 300);
    });
  });

  group('expiry reporting', () {
    test('days remaining counts down to the drop-off', () {
      expect(entry('a', 100, expiresInDays: 45).daysRemainingAt(now), 45);
      expect(entry('a', 100, expiresInDays: -5).daysRemainingAt(now), -5);
    });

    test('an entry with no expiry never drops off', () {
      const forever = RankingEntry(
        id: 'x',
        uid: 'a',
        displayName: 'A',
        points: 10,
        round: 'winner',
        sportId: 'badminton',
      );
      expect(forever.isCurrentAt(now), isTrue);
      expect(forever.daysRemainingAt(now), isNull);
    });
  });
}
