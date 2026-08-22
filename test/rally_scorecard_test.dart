import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/set_based_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/table_tennis_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

/// The serve split under a racket pad.
///
/// Derived by replay rather than entered, so what these pin is that the
/// attribution follows each sport's OWN serving law: badminton's serve moves
/// to whoever won the rally, table tennis's moves every two points regardless
/// of who won. A single rule implemented in shared code would be right for one
/// of them and quietly wrong for the other.
void main() {
  const ctx = ScoringContext(
    entrantAName: 'Anand',
    entrantBName: 'Bhavani',
    lineupA: [MatchPlayer(id: 'p1', name: 'Anand')],
    lineupB: [MatchPlayer(id: 'p2', name: 'Bhavani')],
    config: {'pointsPerSet': 21, 'setsToWin': 2, 'hardCap': 30},
  );

  /// A log of rallies, as the pad would have written it.
  List<MatchEvent> log(List<Side> winners, {String type = 'rally'}) => [
        for (final (i, side) in winners.indexed)
          MatchEvent(
            seq: i + 1,
            type: type,
            payload: {'side': side.wire},
            byUid: 'scorer',
          ),
      ];

  group('badminton — the server is whoever won the last rally', () {
    const plugin = BadmintonPlugin();

    test('a side that keeps winning keeps serving, so all but the first count '
        'as serve points', () {
      // A serves first at 0-0. Winning the rally keeps the serve, so from the
      // second point on every one of A's points is won on serve.
      final card = plugin.rallyScorecard(log([Side.a, Side.a, Side.a]), ctx)!;

      expect(card.totalA, 3);
      expect(card.serveWonA, 3);
      expect(card.periods.single.receiveWonA, 0);
    });

    test('winning against the serve is counted as a receive point', () {
      // A serves first; B wins it, which is a point against the serve. B now
      // serves, and wins the next — that one is on serve.
      final card = plugin.rallyScorecard(log([Side.b, Side.b]), ctx)!;

      expect(card.totalB, 2);
      expect(card.serveWonB, 1);
      expect(card.periods.single.receiveWonB, 1);
    });

    test('splits by game, and the running game is its own row', () {
      final winners = [
        for (var i = 0; i < 21; i++) Side.a, // takes game 1
        Side.b,
        Side.b,
      ];
      final card = plugin.rallyScorecard(log(winners), ctx)!;

      expect(card.periods.length, 2);
      expect(card.periods.first.pointsA, 21);
      expect(card.periods.last.pointsB, 2);
      expect(card.totalA, 21);
      expect(card.periodNoun, 'Game');
    });

    test('an undone point is not counted, in the card or the percentage', () {
      final events = [
        ...log([Side.a, Side.a]),
        // The pad's own undo, naming the sequence it withdraws.
        const MatchEvent(
          seq: 3,
          type: ScoringPlugin.undoActionType,
          payload: {'reversesSeq': 2},
          byUid: 'scorer',
        ),
      ];
      final card = plugin.rallyScorecard(events, ctx)!;

      expect(card.totalA, 1, reason: 'the withdrawn point must not be counted');
    });

    test('a windowed log is refused rather than half-counted', () {
      // The stream drops the earliest events on a long match. A replay from
      // an arbitrary point produces confident, wrong totals.
      final events = [
        for (var i = 0; i < 3; i++)
          MatchEvent(
            seq: 40 + i,
            type: 'rally',
            payload: {'side': Side.a.wire},
            byUid: 'scorer',
          ),
      ];
      expect(plugin.rallyScorecard(events, ctx), isNull);
    });
  });

  group('table tennis — the serve moves every two points', () {
    const plugin = TableTennisPlugin();

    test('the same run of points splits differently than in badminton', () {
      // A serves points 1 and 2, B serves 3 and 4. A winning the first four
      // means two on serve and two against it — where badminton would have
      // called all four serve points.
      final card =
          plugin.rallyScorecard(log([Side.a, Side.a, Side.a, Side.a], type: 'point'), ctx)!;

      expect(card.totalA, 4);
      expect(card.serveWonA, 2);
      expect(card.periods.single.receiveWonA, 2);
    });
  });

  group('a sport that does not track serve', () {
    test('produces no card at all rather than a fabricated one', () {
      // Volleyball's engine here has no serving side, so there is nothing
      // honest to put in the columns.
      const plugin = SetBasedPlugin();
      expect(
        plugin.rallyScorecard(log([Side.a, Side.b], type: 'point'), ctx),
        isNull,
      );
    });
  });

  group('the percentage', () {
    const plugin = BadmintonPlugin();

    test('is null for a side that has not scored, not zero', () {
      final card = plugin.rallyScorecard(log([Side.a]), ctx)!;
      expect(card.serveShareB(), isNull,
          reason: '0% would claim they served and lost');
      expect(card.serveShareA(), 1.0);
    });
  });
}
