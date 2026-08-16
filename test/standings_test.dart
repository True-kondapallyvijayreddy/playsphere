import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/standings/standings_calculator.dart';

/// The league table was the most visible thing lost when the app was rebuilt
/// on Firebase: the `Standing` model survived but nothing ever computed it.
/// These tests pin the ordering rules that make a table trustworthy.
void main() {
  const calc = StandingsCalculator();

  Competition competition({
    int win = 3,
    int draw = 1,
    int loss = 0,
  }) =>
      Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'League',
        sportId: 'football',
        sportName: 'Football',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        format: CompetitionFormat.leagueTable,
        status: CompetitionStatus.inProgress,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        pointsForWin: win,
        pointsForDraw: draw,
        pointsForLoss: loss,
      );

  List<Entrant> entrants(List<String> names) => [
        for (final n in names)
          Entrant(id: n, displayName: n, entrantType: EntrantType.team),
      ];

  /// A PLACEHOLDER match, as `generateDraftSchedule` writes them: a bracket
  /// laid out against synthetic entrants before anybody has registered.
  ///
  /// Built directly rather than by `played(...).copyWith(isDraft: true)`,
  /// because `Fixture.copyWith` deliberately refuses to carry `isDraft` — no
  /// ordinary write path may launder a placeholder into a real match, which
  /// is exactly the invariant these two tests rest on.
  Fixture placeholder(String home, String away) => Fixture(
        id: '$home-$away-draft',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: home,
        entrantBId: away,
        entrantAName: home,
        entrantBName: away,
        status: FixtureStatus.scheduled,
        scoringPluginKey: 'goal_based',
        isDraft: true,
      );

  /// A finished match. [a] and [b] are goals, used both to decide the winner
  /// and to exercise score difference.
  Fixture played(String home, String away, int a, int b) {
    final drawn = a == b;
    return Fixture(
      id: '$home-$away',
      orgId: 'o1',
      compId: 'c1',
      entrantAId: home,
      entrantBId: away,
      entrantAName: home,
      entrantBName: away,
      status: FixtureStatus.completed,
      scoringPluginKey: 'goal_based',
      // The plugin reads score from state, so the projection must look like a
      // finished goal-based match for score difference to be counted.
      scoreState: {
        'a': a,
        'b': b,
        'period': 1,
        'complete': true,
        'draw': drawn,
        'winner': drawn ? null : (a > b ? 'a' : 'b'),
      },
      winnerEntrantId: drawn ? null : (a > b ? home : away),
      isDraw: drawn,
    );
  }

  group('points', () {
    test('a win is worth the configured points and a loss nothing', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [played('Alpha', 'Beta', 2, 0)],
      );

      final alpha = table.firstWhere((r) => r.entrantId == 'Alpha');
      final beta = table.firstWhere((r) => r.entrantId == 'Beta');
      expect(alpha.points, 3);
      expect(alpha.won, 1);
      expect(beta.points, 0);
      expect(beta.lost, 1);
    });

    test('a draw gives both sides the draw points', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [played('Alpha', 'Beta', 1, 1)],
      );
      expect(table.every((r) => r.points == 1), isTrue);
      expect(table.every((r) => r.drawn == 1), isTrue);
    });

    test('points configuration is honoured, not hardcoded', () {
      final table = calc.compute(
        competition: competition(win: 2, draw: 1, loss: -1),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [played('Alpha', 'Beta', 3, 1)],
      );
      expect(table.firstWhere((r) => r.entrantId == 'Alpha').points, 2);
      expect(table.firstWhere((r) => r.entrantId == 'Beta').points, -1);
    });
  });

  group('ordering', () {
    test('ranks by points first', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta', 'Gamma']),
        fixtures: [
          played('Alpha', 'Beta', 1, 0),
          played('Alpha', 'Gamma', 1, 0),
          played('Beta', 'Gamma', 1, 0),
        ],
      );
      expect(table.map((r) => r.entrantId), ['Alpha', 'Beta', 'Gamma']);
      expect(table.map((r) => r.rank), [1, 2, 3]);
    });

    test('breaks a points tie on score difference', () {
      // Both win once and lose once, so both are on 3 points. Alpha's win was
      // by four goals, Beta's by one — Alpha must rank higher.
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [
          played('Alpha', 'Beta', 4, 0),
          played('Beta', 'Alpha', 1, 0),
        ],
      );
      expect(table.first.entrantId, 'Alpha');
      expect(table.first.scoreDifference, 3);
      expect(table.last.scoreDifference, -3);
    });

    test('is stable when rows are genuinely identical', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Zulu', 'Alpha']),
        fixtures: const [],
      );
      // No results at all: falls back to name so the table does not reshuffle
      // itself on every rebuild.
      expect(table.map((r) => r.entrantId), ['Alpha', 'Zulu']);
    });
  });

  group('what must NOT count', () {
    test('an entrant with no matches still appears, on zero', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta', 'Ghost']),
        fixtures: [played('Alpha', 'Beta', 1, 0)],
      );
      final ghost = table.firstWhere((r) => r.entrantId == 'Ghost');
      expect(ghost.played, 0);
      expect(ghost.points, 0);
      expect(table.length, 3);
    });

    test('a live match does not move the table', () {
      final live = played('Alpha', 'Beta', 3, 0);
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: [
          Fixture(
            id: live.id,
            orgId: 'o1',
            compId: 'c1',
            entrantAId: 'Alpha',
            entrantBId: 'Beta',
            entrantAName: 'Alpha',
            entrantBName: 'Beta',
            status: FixtureStatus.live,
            scoringPluginKey: 'goal_based',
            scoreState: live.scoreState,
          ),
        ],
      );
      expect(table.every((r) => r.played == 0), isTrue);
      expect(table.every((r) => r.points == 0), isTrue);
    });

    test('an abandoned match is not a draw', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: const [
          Fixture(
            id: 'x',
            orgId: 'o1',
            compId: 'c1',
            entrantAId: 'Alpha',
            entrantBId: 'Beta',
            entrantAName: 'Alpha',
            entrantBName: 'Beta',
            status: FixtureStatus.abandoned,
            scoringPluginKey: 'goal_based',
          ),
        ],
      );
      // Abandoned is not `isResulted`, so nobody is credited a point.
      expect(table.every((r) => r.points == 0), isTrue);
      expect(table.every((r) => r.played == 0), isTrue);
    });

    test('a walkover counts as a win for the awarded side', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha', 'Beta']),
        fixtures: const [
          Fixture(
            id: 'w',
            orgId: 'o1',
            compId: 'c1',
            entrantAId: 'Alpha',
            entrantBId: 'Beta',
            entrantAName: 'Alpha',
            entrantBName: 'Beta',
            status: FixtureStatus.walkover,
            scoringPluginKey: 'goal_based',
            winnerEntrantId: 'Alpha',
          ),
        ],
      );
      expect(table.firstWhere((r) => r.entrantId == 'Alpha').won, 1);
      expect(table.firstWhere((r) => r.entrantId == 'Beta').lost, 1);
    });

    test('a fixture naming an unknown entrant is ignored, not crashed on', () {
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha']),
        fixtures: [played('Alpha', 'Withdrawn', 1, 0)],
      );
      expect(table.length, 1);
      expect(table.first.played, 0);
    });

    test('a DRAFT fixture may name entrants that do not exist yet', () {
      // The other side of the rule above, and the reason it has to be stated
      // as a pair. `generateDraftSchedule` lays a bracket out against
      // placeholders before registration has produced anybody, so a draft
      // table has to invent its rows or the preview is blank — while a played
      // fixture naming a stranger stays ignored, because there the same shape
      // means stale data rather than a placeholder.
      final table = calc.compute(
        competition: competition(),
        entrants: const [],
        fixtures: [
          placeholder('Team A', 'Team B'),
        ],
      );
      expect(table.length, 2);
      expect(
        table.map((r) => r.displayName).toSet(),
        {'Team A', 'Team B'},
      );
    });

    test('a played fixture does not resurrect an entrant a draft invented', () {
      // Mixed input: the placeholder is only carried by the draft fixture, so
      // the stranger on the completed one must still be dropped.
      final table = calc.compute(
        competition: competition(),
        entrants: entrants(['Alpha']),
        fixtures: [
          played('Alpha', 'Withdrawn', 1, 0),
          placeholder('Team A', 'Team B'),
        ],
      );
      expect(
        table.map((r) => r.entrantId).toSet(),
        {'Alpha', 'Team A', 'Team B'},
        reason: '"Withdrawn" is on a played fixture and is not an entrant',
      );
    });
  });
}
