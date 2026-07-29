import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/domain/career/career_stats.dart';
import 'package:playsphere/domain/scoring/plugins/football_plugin.dart';
import 'package:playsphere/domain/scoring/plugins/hockey_plugin.dart';
import 'package:playsphere/domain/scoring/scoring_plugin.dart';

void main() {
  // ==========================================================================
  // Hockey
  // ==========================================================================
  group('Hockey', () {
    const hockey = HockeyPlugin();

    final ctx = ScoringContext(
      entrantAName: 'Hyderabad',
      entrantBName: 'Sangareddy',
      config: const {'periods': 4, 'allowDraw': true},
      lineupA: [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: 'A$n', name: 'A Player $n'),
      ],
      lineupB: [
        for (var n = 1; n <= 11; n++)
          MatchPlayer(id: 'B$n', name: 'B Player $n'),
      ],
    );

    Map<String, dynamic> play(List<ScoreAction> actions) {
      var s = hockey.initialState(ctx);
      for (final a in actions) {
        final r = hockey.apply(s, a, ctx);
        expect(r.isAccepted, isTrue, reason: '${a.type}: ${r.rejection}');
        s = r.state;
      }
      return s;
    }

    test('how a goal was scored is recorded, not just that it was', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'how': 'field'},
        ),
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'how': 'penalty_corner'},
        ),
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A7', 'how': 'penalty_stroke'},
        ),
      ]);
      final box = hockey.boxScore(s, ctx, Side.a);
      final a9 = box.players.firstWhere((p) => p.playerId == 'A9');

      expect(a9['goals'], 2);
      expect(a9['fieldGoals'], 1);
      expect(a9['pcGoals'], 1);
      expect(box.players.firstWhere((p) => p.playerId == 'A7')['psGoals'], 1);
      expect(s['a'], 3);
    });

    test('penalty corner conversion needs corners awarded, not just scored', () {
      final s = play([
        // Four corners won, one converted.
        for (var n = 0; n < 4; n++)
          const ScoreAction(type: 'penalty_corner', side: Side.a),
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A9', 'how': 'penalty_corner'},
        ),
      ]);
      expect(hockey.pcConversion(s, ctx, Side.a), 0.25);
    });

    test('conversion is zero rather than a crash when no corners were won', () {
      final s = play([]);
      expect(hockey.pcConversion(s, ctx, Side.a), 0);
    });

    test('cards are three tiers, and only a red removes a player', () {
      var s = play([
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A4', 'colour': 'green'},
        ),
        const ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A4', 'colour': 'yellow'},
        ),
      ]);
      final a4 = hockey
          .boxScore(s, ctx, Side.a)
          .players
          .firstWhere((p) => p.playerId == 'A4');
      expect(a4['greenCards'], 1);
      expect(a4['yellowCards'], 1);

      // A green and a yellow are not a sending-off — the player plays on.
      final stillPlaying = hockey.apply(
        s,
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A4', 'how': 'field'},
        ),
        ctx,
      );
      expect(stillPlaying.isAccepted, isTrue);

      s = play(const [
        ScoreAction(
          type: 'card',
          side: Side.a,
          payload: {'playerId': 'A4', 'colour': 'red'},
        ),
      ]);
      final afterRed = hockey.apply(
        s,
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'A4', 'how': 'field'},
        ),
        ctx,
      );
      expect(afterRed.isAccepted, isFalse);
    });

    test('a penalty stroke has no assist', () {
      final s = play([
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {
            'playerId': 'A9',
            'how': 'penalty_stroke',
            'assistId': 'A8',
          },
        ),
      ]);
      expect(
        hockey.boxScore(s, ctx, Side.a).players.firstWhere((p) => p.playerId == 'A8')['assists'],
        0,
      );
    });
  });

  // ==========================================================================
  // Career aggregation — across sports, across clubs, across years
  // ==========================================================================
  group('Career statistics', () {
    const aggregator = CareerAggregator();
    const football = FootballPlugin();

    /// A squad where some players have accounts and one does not.
    const ctx = ScoringContext(
      entrantAName: 'Warangal',
      entrantBName: 'Nizamabad',
      config: {'periods': 2},
      lineupA: [
        MatchPlayer(id: 'p1', name: 'Ravi', uid: 'uid_ravi'),
        MatchPlayer(id: 'p2', name: 'Sunil', uid: 'uid_sunil'),
        // Borrowed from the crowd; no account.
        MatchPlayer(id: 'guest_1', name: 'Anon'),
      ],
      lineupB: [
        MatchPlayer(id: 'p3', name: 'Kiran', uid: 'uid_kiran'),
      ],
    );

    Map<String, dynamic> matchWhereRaviScoresTwice() {
      var s = football.initialState(ctx);
      for (final a in [
        const ScoreAction(
          type: 'goal',
          side: Side.a,
          payload: {'playerId': 'p1', 'assistId': 'p2'},
        ),
        const ScoreAction(type: 'goal', side: Side.a, payload: {'playerId': 'p1'}),
        const ScoreAction(type: 'save', side: Side.b, payload: {'playerId': 'p3'}),
        const ScoreAction(type: 'goal', side: Side.a, payload: {'playerId': 'guest_1'}),
      ]) {
        s = football.apply(s, a, ctx).state;
      }
      return s;
    }

    test('a match contributes to every registered player who took part', () {
      final contributions = aggregator.contributionsFrom(
        scoreState: matchWhereRaviScoresTwice(),
        ctx: ctx,
        sportId: 'football',
        orgId: 'club_warangal',
        playedAt: DateTime(2026, 3, 1),
      );

      final uids = contributions.map((c) => c.uid).toSet();
      expect(uids, {'uid_ravi', 'uid_sunil', 'uid_kiran'});
    });

    test('a guest appears on the scorecard but has no career', () {
      final state = matchWhereRaviScoresTwice();
      // The guest's goal is on the sheet…
      expect(
        football.boxScore(state, ctx, Side.a).teamTotals['goals'],
        3,
      );
      // …but contributes to nobody's lifetime record, because there is no
      // identity to attach it to.
      final contributions = aggregator.contributionsFrom(
        scoreState: state,
        ctx: ctx,
        sportId: 'football',
        orgId: 'club_warangal',
        playedAt: DateTime(2026, 3, 1),
      );
      expect(contributions.any((c) => c.tally['goals'] == 1 && c.uid.contains('guest')), isFalse);
      expect(contributions.length, 3);
    });

    test('a squad member who never touched the ball is not credited a match', () {
      const bench = ScoringContext(
        entrantAName: 'A',
        entrantBName: 'B',
        lineupA: [
          MatchPlayer(id: 'p1', name: 'Ravi', uid: 'uid_ravi'),
          MatchPlayer(id: 'p9', name: 'Benched', uid: 'uid_benched'),
        ],
        lineupB: [MatchPlayer(id: 'p3', name: 'Kiran', uid: 'uid_kiran')],
      );
      var s = football.initialState(bench);
      s = football
          .apply(s, const ScoreAction(type: 'goal', side: Side.a, payload: {'playerId': 'p1'}), bench)
          .state;

      final contributions = aggregator.contributionsFrom(
        scoreState: s,
        ctx: bench,
        sportId: 'football',
        orgId: 'club',
        playedAt: DateTime(2026, 3, 1),
      );
      expect(contributions.map((c) => c.uid), ['uid_ravi']);
    });

    test('careers accumulate across matches, clubs and years', () {
      final march = aggregator.contributionsFrom(
        scoreState: matchWhereRaviScoresTwice(),
        ctx: ctx,
        sportId: 'football',
        orgId: 'club_warangal',
        playedAt: DateTime(2020, 3, 1),
      );
      final later = aggregator.contributionsFrom(
        scoreState: matchWhereRaviScoresTwice(),
        ctx: ctx,
        sportId: 'football',
        // The same player, years later, at a different club — the whole point
        // of a portable identity.
        orgId: 'delhi_university',
        playedAt: DateTime(2030, 11, 4),
      );

      var careers = aggregator.accumulate(march);
      careers = aggregator.accumulate(later, existing: careers);

      final ravi = careers['uid_ravi::football']!;
      expect(ravi.matchesPlayed, 2);
      expect(ravi['goals'], 4, reason: 'two goals in each of two matches');
      expect(ravi.clubsPlayedFor, {'club_warangal', 'delhi_university'});
      expect(ravi.firstPlayedAt, DateTime(2020, 3, 1));
      expect(ravi.lastPlayedAt, DateTime(2030, 11, 4));
      expect(ravi.per('goals'), 2.0);
    });

    test('sports are kept apart, never merged', () {
      final asFootball = aggregator.contributionsFrom(
        scoreState: matchWhereRaviScoresTwice(),
        ctx: ctx,
        sportId: 'football',
        orgId: 'club',
        playedAt: DateTime(2026, 1, 1),
      );
      final asHockey = aggregator.contributionsFrom(
        scoreState: matchWhereRaviScoresTwice(),
        ctx: ctx,
        sportId: 'hockey',
        orgId: 'club',
        playedAt: DateTime(2026, 2, 1),
      );

      var careers = aggregator.accumulate(asFootball);
      careers = aggregator.accumulate(asHockey, existing: careers);

      // A batting average and a raid average are not the same quantity;
      // summing across sports would produce a number that means nothing.
      expect(careers['uid_ravi::football']!.matchesPlayed, 1);
      expect(careers['uid_ravi::hockey']!.matchesPlayed, 1);
    });

    test('a player with no matches averages zero rather than dividing by it', () {
      const empty = CareerStats(
        uid: 'uid_x',
        sportId: 'football',
        matchesPlayed: 0,
        tally: {},
      );
      expect(empty.per('goals'), 0);
      expect(empty['goals'], 0);
    });

    test('the headline skips counters nobody ever moved', () {
      final careers = aggregator.accumulate(
        aggregator.contributionsFrom(
          scoreState: matchWhereRaviScoresTwice(),
          ctx: ctx,
          sportId: 'football',
          orgId: 'club',
          playedAt: DateTime(2026, 1, 1),
        ),
      );
      final rows = aggregator.headline(
        careers['uid_ravi::football']!,
        FootballPlugin.columns,
      );
      final labels = rows.map((r) => r.$1).toList();

      expect(labels.first, 'Matches');
      expect(labels, contains('Goals'));
      // Ravi never took a card; a zero row is noise on a profile.
      expect(labels, isNot(contains('Red cards')));
    });
  });
}
