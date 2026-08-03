import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/match_player.dart';
import 'package:playsphere/data/rating_service.dart';
import 'package:playsphere/domain/scoring/match_award.dart';
import 'package:playsphere/domain/scoring/player_stats.dart';

/// Step 10 of the flow: a finished match declares a winner AND a best
/// performer.
///
/// The award is computed from the same contribution points that decide how a
/// team result is distributed across a squad's ratings, so these tests also
/// guard that the two never drift into naming one player the best and handing
/// a different one the biggest rating gain in the same match.
MatchPlayer player(String id, {bool guest = false}) =>
    MatchPlayer(id: id, name: 'Player $id', uid: guest ? null : id);

Map<String, dynamic> stateWith(Map<String, Map<String, num>> tallies) {
  var state = <String, dynamic>{};
  for (final entry in tallies.entries) {
    state = PlayerTally.addAll(state, entry.key, entry.value);
  }
  return state;
}

void main() {
  group('picking the best performer', () {
    test('names the highest contribution across both squads', () {
      final award = selectMvp(
        scoreState: stateWith({
          'a1': {'runsScored': 20},
          'b1': {'runsScored': 75},
        }),
        lineupA: [player('a1')],
        lineupB: [player('b1')],
        entrantAId: 'A',
        entrantBId: 'B',
        winnerEntrantId: 'A',
      );

      // 75 runs plus the fifty milestone beats 20 runs, even though the
      // player is on the losing side. A loser has to be better, not equal.
      expect(award?.playerId, 'b1');
      expect(award?.onWinningSide, isFalse);
    });

    test('a bowler can beat a batter — every sport is scored on one scale', () {
      final award = selectMvp(
        scoreState: stateWith({
          'a1': {'runsScored': 40},
          'b1': {'wickets': 5},
        }),
        lineupA: [player('a1')],
        lineupB: [player('b1')],
        entrantAId: 'A',
        entrantBId: 'B',
      );
      // 5 wickets = 5*20 + 20 milestone = 120, against 40 runs.
      expect(award?.playerId, 'b1');
      expect(award?.points, 120);
    });

    test('a tie goes to the winning side', () {
      final award = selectMvp(
        scoreState: stateWith({
          'a1': {'runsScored': 30},
          'b1': {'runsScored': 30},
        }),
        lineupA: [player('a1')],
        lineupB: [player('b1')],
        entrantAId: 'A',
        entrantBId: 'B',
        winnerEntrantId: 'B',
      );
      expect(award?.playerId, 'b1');
      expect(award?.onWinningSide, isTrue);
    });

    test('a tie in a draw falls to lineup order, and stays there', () {
      Map<String, dynamic> state() => stateWith({
            'a1': {'runsScored': 30},
            'b1': {'runsScored': 30},
          });

      // Stability matters: a match that renamed its MVP every time it was
      // rebuilt from the event log would be worse than one that never named
      // one at all.
      for (var i = 0; i < 5; i++) {
        final award = selectMvp(
          scoreState: state(),
          lineupA: [player('a1')],
          lineupB: [player('b1')],
          entrantAId: 'A',
          entrantBId: 'B',
        );
        expect(award?.playerId, 'a1');
      }
    });

    test('nobody is named when no tally moved', () {
      final award = selectMvp(
        scoreState: const {},
        lineupA: [player('a1'), player('a2')],
        lineupB: [player('b1')],
        entrantAId: 'A',
        entrantBId: 'B',
        winnerEntrantId: 'A',
      );
      // An award on no evidence would always be the first player in the list,
      // and every club would notice within a week.
      expect(award, isNull);
    });

    test('a player who did nothing is not a candidate', () {
      final award = selectMvp(
        scoreState: stateWith({
          'a2': {'runsScored': 5},
        }),
        lineupA: [player('a1'), player('a2')],
        lineupB: [player('b1')],
        entrantAId: 'A',
        entrantBId: 'B',
      );
      expect(award?.playerId, 'a2');
    });

    test('a guest can be the best player of a match they were best in', () {
      final award = selectMvp(
        scoreState: stateWith({
          'g1': {'goals': 3},
          'b1': {'goals': 1},
        }),
        lineupA: [player('g1', guest: true)],
        lineupB: [player('b1')],
        entrantAId: 'A',
        entrantBId: 'B',
        winnerEntrantId: 'A',
      );
      expect(award?.playerId, 'g1');
      // Nothing accrues to a profile that does not exist.
      expect(award?.uid, isNull);
    });

    test('an empty match names nobody rather than throwing', () {
      expect(
        selectMvp(
          scoreState: const {},
          lineupA: const [],
          lineupB: const [],
          entrantAId: 'A',
          entrantBId: 'B',
        ),
        isNull,
      );
    });
  });

  group('the award survives a round trip', () {
    test('serialises and reads back', () {
      const award = MatchAward(
        playerId: 'u1',
        uid: 'u1',
        name: 'Ravi Kumar',
        points: 120.5,
        onWinningSide: true,
      );
      final back = MatchAward.fromMap(
        Map<String, dynamic>.from(award.toMap()),
      );
      expect(back?.playerId, 'u1');
      expect(back?.name, 'Ravi Kumar');
      expect(back?.points, 120.5);
      expect(back?.onWinningSide, isTrue);
    });

    test('a malformed or absent award reads as no award', () {
      expect(MatchAward.fromMap(null), isNull);
      expect(MatchAward.fromMap(<String, dynamic>{}), isNull);
      expect(MatchAward.fromMap({'playerId': 'u1'}), isNull);
    });
  });

  group('one definition of contribution', () {
    test('the rating weights and the award read the same table', () {
      // These were two separate tables. The app would have named one player
      // the best and given a different one the biggest rating gain, in the
      // same match, and both numbers would have been indefensible.
      expect(
        RatingService.contributionWeights,
        same(ContributionScoring.weights),
      );
    });

    test('milestones apply on top of the per-unit weights', () {
      // 50 runs = 50*1.0, plus the fifty bonus.
      expect(ContributionScoring.pointsFrom({'runsScored': 50}), 65.0);
      expect(ContributionScoring.pointsFrom({'runsScored': 49}), 49.0);
    });

    test('an unknown statistic contributes nothing', () {
      expect(ContributionScoring.pointsFrom({'somethingElse': 999}), 0.0);
    });
  });
}
