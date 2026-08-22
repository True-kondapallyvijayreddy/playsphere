import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/scoring/plugins/badminton_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/set_based_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

const _ctx = ScoringContext(
  entrantAName: 'Team A',
  entrantBName: 'Team B',
  // A 5-point set keeps the fixtures readable; the engine reads it from
  // config exactly as it would read 21.
  config: {'pointsPerSet': 5, 'winBy': 2, 'setsToWin': 2},
);

const _plugin = SetBasedPlugin();

var _seq = 0;

MatchEvent _point(String side, {DateTime? at}) => MatchEvent(
      seq: ++_seq,
      type: 'point',
      payload: {'side': side},
      byUid: 'scorer',
      at: at,
    );

MatchEvent _undo(int reverses) => MatchEvent(
      seq: ++_seq,
      type: 'undo',
      payload: {'reversesSeq': reverses},
      byUid: 'scorer',
    );

/// Points to [side], as one call.
List<MatchEvent> _run(String side, int n) =>
    [for (var i = 0; i < n; i++) _point(side)];

void main() {
  setUp(() => _seq = 0);

  group('rally timeline', () {
    test('every point becomes a line in the order it was entered', () {
      final entries = _plugin.timeline(
        [_point('a'), _point('b'), _point('b')],
        _ctx,
      );

      expect(entries.map((e) => e.line.text), [
        'Team A +1',
        'Team B +1',
        'Team B +1',
      ]);
    });

    test('each line carries the score that point produced', () {
      final entries = _plugin.timeline(
        [_point('a'), _point('a'), _point('b')],
        _ctx,
      );

      // This is the whole reason the timeline replays: the score beside a
      // point is a fact about every point before it, not about that point.
      expect(entries.map((e) => e.line.detail), ['1 - 0', '2 - 0', '2 - 1']);
    });

    test('the point that closes a set becomes the set break', () {
      final entries = _plugin.timeline(
        [..._run('a', 5)],
        _ctx,
      );

      final last = entries.last;
      expect(last.line.isMilestone, isTrue);
      expect(last.line.text, 'Set 1');
      expect(last.line.detail, 'Team A 5 - 0 Team B');
    });

    test('the next set starts from zero in the log, not from the old score',
        () {
      final entries = _plugin.timeline(
        [..._run('a', 5), _point('b')],
        _ctx,
      );

      expect(entries.last.line.text, 'Team B +1');
      expect(entries.last.line.detail, '0 - 1');
    });

    test('an undone point is kept, struck, and stops counting', () {
      // A, A, then the second A is withdrawn, then B.
      final a1 = _point('a');
      final a2 = _point('a');
      final undo = _undo(a2.seq);
      final b1 = _point('b');

      final entries = _plugin.timeline([a1, a2, undo, b1], _ctx);

      // The undo itself is not a row — its effect is the strike-through.
      expect(entries.length, 3);
      expect(entries[1].withdrawn, isTrue);
      expect(entries[1].line.text, 'Team A +1');
      // ...and the score after it reflects the withdrawal: 1-1, not 2-1.
      expect(entries.last.line.detail, '1 - 1');
    });

    test('an undo that is itself undone restores the point', () {
      final a1 = _point('a');
      final undo = _undo(a1.seq);
      final undoTheUndo = _undo(undo.seq);
      final b1 = _point('b');

      final entries = _plugin.timeline([a1, undo, undoTheUndo, b1], _ctx);

      expect(entries.first.withdrawn, isFalse);
      expect(entries.last.line.detail, '1 - 1');
    });

    test('a retirement reads as one, and breaks the log', () {
      final entries = _plugin.timeline(
        [
          _point('a'),
          MatchEvent(
            seq: ++_seq,
            type: 'retire',
            payload: const {'side': 'b'},
            byUid: 'scorer',
          ),
        ],
        _ctx,
      );

      expect(entries.last.line.text, contains('retired'));
      expect(entries.last.line.isMilestone, isTrue);
    });

    test('lines are attributed to the side that caused them', () {
      final entries = _plugin.timeline([_point('a'), _point('b')], _ctx);

      expect(entries[0].line.side, Side.a);
      expect(entries[1].line.side, Side.b);
    });

    test('events out of order are sorted by seq, not by arrival', () {
      // The offline queue replays out of order routinely; the log must not.
      final first = _point('a');
      final second = _point('b');

      final entries = _plugin.timeline([second, first], _ctx);

      expect(entries.map((e) => e.event.seq), [first.seq, second.seq]);
      expect(entries.map((e) => e.line.detail), ['1 - 0', '1 - 1']);
    });

    test('the timeline agrees with the scoreboard it sits under', () {
      final events = [..._run('a', 5), ..._run('b', 3), ..._run('a', 2)];

      final replayed = _plugin.rebuild(
        [
          for (final e in events)
            LoggedAction(seq: e.seq, action: ScoringPlugin.actionOf(e)),
        ],
        _ctx,
      );
      final entries = _plugin.timeline(events, _ctx);

      // The last non-milestone line's detail is the live score, which is what
      // the pad above it is showing. If these two ever disagree the log is
      // worthless as an audit trail.
      expect(entries.last.line.detail, _plugin.headline(replayed, _ctx));
    });
  });

  group('sets-won headline', () {
    test('the board reports sets separately from points', () {
      final state = _plugin.rebuild(
        [
          for (final e in [..._run('a', 5), ..._run('a', 3)])
            LoggedAction(seq: e.seq, action: ScoringPlugin.actionOf(e)),
        ],
        _ctx,
      );

      final board = _plugin.duelBoard(state, _ctx)!;

      expect(board.matchScore, isNotNull);
      expect(board.matchScore!.a, 1);
      expect(board.matchScore!.b, 0);
      expect(board.matchScore!.label, 'SETS WON');
      // ...while the halves still show the points in the set being played.
      expect(board.a.score, '3');
    });
  });

  group('each engine names its own point event', () {
    test('badminton logs a rally and still reads as "+1"', () {
      const badminton = BadmintonPlugin();
      const bctx = ScoringContext(
        entrantAName: 'Anand',
        entrantBName: 'Bhavani',
        config: {'pointsPerSet': 21, 'setsToWin': 2},
      );

      final entries = badminton.timeline(
        const [
          MatchEvent(
            seq: 1,
            // Badminton's engine calls this 'rally'. A mixin that assumed
            // 'point' would render "Anand — rally" here.
            type: 'rally',
            payload: {'side': 'a'},
            byUid: 'scorer',
          ),
        ],
        bctx,
      );

      expect(entries.single.line.text, 'Anand +1');
      expect(entries.single.line.detail, '1 - 0');
    });
  });

  group('a windowed log', () {
    test('shows the points but not scores it cannot derive', () {
      // The stream is capped, so on a long match the earliest points are not
      // in the list. Replaying what IS here from 0-0 would print a confident
      // wrong score beside every line.
      const truncated = [
        MatchEvent(
          seq: 61,
          type: 'point',
          payload: {'side': 'a'},
          byUid: 'scorer',
        ),
        MatchEvent(
          seq: 62,
          type: 'point',
          payload: {'side': 'b'},
          byUid: 'scorer',
        ),
      ];

      final entries = _plugin.timeline(truncated, _ctx);

      expect(entries.map((e) => e.line.text), ['Team A +1', 'Team B +1']);
      expect(entries.every((e) => e.line.detail == null), isTrue);
    });

    test('a complete log still gets its scores', () {
      final entries = _plugin.timeline([_point('a')], _ctx);
      expect(entries.single.line.detail, '1 - 0');
    });
  });
}
