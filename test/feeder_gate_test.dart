import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/draw_slot.dart' show Bracket;
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/schedule/feeder_gate.dart';

/// The last thing the season test run left open: a final could be decided while
/// the semi-final feeding it was under protest, which is how one season ended
/// up with a walkover final sitting over a disputed semi and a champion
/// published out of a result nobody had agreed.
///
/// Marking the sport "Needs a ruling" made that visible. These pin the part
/// that refuses it.
void main() {
  Fixture fx(
    String id, {
    FixtureStatus status = FixtureStatus.scheduled,
    String? feedsWinnerTo,
    String? feedsLoserTo,
    String? roundLabel,
    String a = 'Priyanka Reddy',
    String b = 'Vijay Reddy',
    Bracket bracket = Bracket.knockout,
  }) =>
      Fixture(
        id: id,
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: a,
        entrantBName: b,
        status: status,
        roundLabel: roundLabel,
        bracket: bracket,
        feedsWinnerToFixtureId: feedsWinnerTo,
        feedsWinnerToSlot: feedsWinnerTo == null ? null : 'a',
        feedsLoserToFixtureId: feedsLoserTo,
        feedsLoserToSlot: feedsLoserTo == null ? null : 'b',
      );

  group('which matches feed a later one', () {
    test('the arrow is walked backwards, from feeder to target', () {
      // The draw only ever writes it forwards, because advancement is a write
      // on the match that just finished. Asking "may this final be decided"
      // needs the other direction, and nothing else in the app had it.
      final semi1 = fx('s1', feedsWinnerTo: 'final');
      final semi2 = fx('s2', feedsWinnerTo: 'final');
      final other = fx('x1', feedsWinnerTo: 'third_place');
      final theFinal = fx('final');

      final feeders = feedersOf(theFinal, [semi1, semi2, other, theFinal]);

      expect(feeders.map((f) => f.id), unorderedEquals(['s1', 's2']));
    });

    test('a losers-bracket arrow counts as a feeder too', () {
      // Double elimination sends the loser somewhere real. A protest on that
      // match changes who arrives there just as much as a protest on a
      // winners-bracket semi.
      final wb = fx('wb1', feedsWinnerTo: 'wb_final', feedsLoserTo: 'lb1');
      final lb = fx('lb1');

      expect(feedersOf(lb, [wb, lb]).map((f) => f.id), ['wb1']);
    });

    test('a match never feeds itself', () {
      final self = fx('f1', feedsWinnerTo: 'f1');
      expect(feedersOf(self, [self]), isEmpty);
    });
  });

  group('what blocks a result', () {
    test('a semi-final under protest blocks the final', () {
      final semi = fx('s1',
          status: FixtureStatus.disputed,
          feedsWinnerTo: 'final',
          roundLabel: 'Semi-final');
      final theFinal = fx('final', roundLabel: 'Final');

      expect(protestedFeeders(theFinal, [semi, theFinal]).map((f) => f.id),
          ['s1']);

      final message = feederProtestBlock(theFinal, [semi, theFinal]);
      expect(message, isNotNull);
      // It has to name the match, or an organizer is told to go and decide a
      // protest without being told which one.
      expect(message, contains('Semi-final'));
      expect(message, contains('Priyanka Reddy v Vijay Reddy'));
      expect(message, contains('under protest'));
    });

    test('a settled feeder blocks nothing', () {
      for (final status in [
        FixtureStatus.completed,
        FixtureStatus.walkover,
        FixtureStatus.abandoned,
        FixtureStatus.scheduled,
        FixtureStatus.live,
      ]) {
        final semi = fx('s1', status: status, feedsWinnerTo: 'final');
        final theFinal = fx('final');
        expect(
          feederProtestBlock(theFinal, [semi, theFinal]),
          isNull,
          reason: '$status should not hold up the next round',
        );
      }
    });

    test('a protest on an unrelated match blocks nothing', () {
      // Two sports run on the same day. A disputed cricket match must not
      // freeze a badminton final.
      final elsewhere =
          fx('other', status: FixtureStatus.disputed, feedsWinnerTo: 'other_f');
      final theFinal = fx('final');

      expect(feederProtestBlock(theFinal, [elsewhere, theFinal]), isNull);
    });

    test('both semis under protest are named together', () {
      final s1 = fx('s1',
          status: FixtureStatus.disputed,
          feedsWinnerTo: 'final',
          roundLabel: 'Semi-final 1');
      final s2 = fx('s2',
          status: FixtureStatus.disputed,
          feedsWinnerTo: 'final',
          roundLabel: 'Semi-final 2');
      final theFinal = fx('final');

      final message = feederProtestBlock(theFinal, [s1, s2, theFinal]);
      expect(message, contains('Semi-final 1'));
      expect(message, contains('Semi-final 2'));
      expect(message, contains('are under protest'));
    });

    test('a group match is not gated', () {
      // Group matches feed a table, not a slot, and a protest in one does not
      // make the rest of the group unplayable. The service skips the check
      // entirely for them; this pins the domain answer that matches it.
      final g1 = fx('g1', status: FixtureStatus.disputed, bracket: Bracket.group);
      final g2 = fx('g2', bracket: Bracket.group);

      expect(feederProtestBlock(g2, [g1, g2]), isNull);
    });
  });
}
