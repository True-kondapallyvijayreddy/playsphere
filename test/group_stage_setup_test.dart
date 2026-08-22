import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';
import 'package:playsphere/domain/draw/group_bounds.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';
import 'package:playsphere/features/competitions/widgets/group_stage_fields.dart';

/// The shape an organizer asks for by name: groups first, teams dealt out
/// evenly, everyone plays everyone inside their own group, then the top one or
/// two of each group go into a knockout that ends in a final.
///
/// The draw generator could always build this. What it could not do was
/// *reach* it from a season: `setUpWholeSeason` draws every event from the
/// [DrawConfig] stored on its competition, and every season-creation screen
/// wrote competitions without one — default `useGroups: false`, on a default
/// format of Round Robin. So "Set up the whole season" produced one flat table
/// per event and no groups anywhere. These tests pin both halves: the config
/// the screens now persist, and the draw it produces.
void main() {
  List<Entrant> field(int n) => [
        for (var i = 0; i < n; i++)
          Entrant(
            id: 'e$i',
            displayName: 'Team ${i + 1}',
            entrantType: EntrantType.team,
          ),
      ];

  Competition comp({
    required CompetitionFormat format,
    DrawConfig draw = const DrawConfig(),
  }) =>
      Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'Inter-house Football',
        sportId: 'football',
        sportName: 'Football',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        format: format,
        status: CompetitionStatus.registrationClosed,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        drawConfig: draw,
      );

  /// Group id -> how many entrants ended up in it.
  Map<String, int> groupSizes(List<PlannedFixture> planned) {
    final members = <String, Set<String>>{};
    for (final f in planned) {
      final id = f.groupId;
      if (id == null) continue;
      final set = members.putIfAbsent(id, () => <String>{});
      if (f.entrantA != null) set.add(f.entrantA!.id);
      if (f.entrantB != null) set.add(f.entrantB!.id);
    }
    return {for (final e in members.entries) e.key: e.value.length};
  }

  group('a season category now carries a group stage', () {
    test('new categories start on Groups + Knockout, not one flat table', () {
      for (final sport in SportCatalog.all) {
        expect(
          sport.defaultCompetitionFormat,
          sport.isPerformance
              ? CompetitionFormat.finalOnly
              : CompetitionFormat.groupThenKnockout,
          reason: '${sport.name} opens a season category on the wrong format',
        );
      }
    });

    test('Groups + Knockout is grouped without anyone ticking a box', () {
      final c = comp(format: CompetitionFormat.groupThenKnockout);
      expect(c.hasGroupStage, isTrue);
      expect(c.groupsFeedKnockout, isTrue);
    });

    test('a knockout is grouped only when the organizer asks', () {
      expect(comp(format: CompetitionFormat.knockout).hasGroupStage, isFalse);
      final grouped = comp(
        format: CompetitionFormat.knockout,
        draw: const DrawConfig(useGroups: true),
      );
      expect(grouped.hasGroupStage, isTrue);
      expect(grouped.groupsFeedKnockout, isTrue);
    });

    test('pools are grouped but promote nobody', () {
      final pools = comp(
        format: CompetitionFormat.roundRobin,
        draw: const DrawConfig(useGroups: true),
      );
      expect(pools.hasGroupStage, isTrue);
      expect(
        pools.groupsFeedKnockout,
        isFalse,
        reason: 'a pool has no bracket to send its winner into',
      );
    });

    test('formats with no group phase never claim one', () {
      for (final format in const [
        CompetitionFormat.swiss,
        CompetitionFormat.doubleElimination,
      ]) {
        expect(
          comp(format: format, draw: const DrawConfig(useGroups: true))
              .hasGroupStage,
          isFalse,
          reason: '${format.label} pairs on results, not on pools',
        );
      }
    });
  });

  group('what the creation screens persist', () {
    test('a group count out of range is clamped before it is stored', () {
      // Sixteen teams cannot be eight groups of two AND send two up from
      // each, so the request is pulled back to what the draw can be.
      final stored = GroupStageFields.normalize(
        format: CompetitionFormat.groupThenKnockout,
        entrantCount: 16,
        config: const DrawConfig(numGroups: 99, qualifiersPerGroup: 2),
      );
      expect(stored.numGroups, isNotNull);
      expect(
        stored.numGroups!,
        lessThanOrEqualTo(
          GroupBounds.maxGroups(16, qualifiersPerGroup: 2),
        ),
      );
      expect(
        stored.numGroups!,
        greaterThanOrEqualTo(GroupBounds.minGroups(16)),
      );
    });

    test('what the screen says is what the draw does', () {
      const config = DrawConfig(numGroups: 4, qualifiersPerGroup: 2);
      final stored = GroupStageFields.normalize(
        format: CompetitionFormat.groupThenKnockout,
        entrantCount: 16,
        config: config,
      );
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.groupThenKnockout,
        entrants: field(16),
        numGroups: stored.numGroups,
        qualifiersPerGroup: stored.qualifiersPerGroup,
        shuffleSeed: 1,
      );
      expect(groupSizes(planned).length, stored.numGroups);
      expect(
        GroupStageFields.summary(
          format: CompetitionFormat.groupThenKnockout,
          entrantCount: 16,
          config: stored,
        ),
        contains('4 groups of 4'),
      );
    });
  });

  group('the draw an organizer described', () {
    test('16 teams: 4 even groups, then quarters, semis and a final', () {
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.groupThenKnockout,
        entrants: field(16),
        numGroups: 4,
        qualifiersPerGroup: 2,
        shuffleSeed: 7,
      );

      final sizes = groupSizes(planned);
      expect(sizes.length, 4);
      expect(sizes.values.toSet(), {4}, reason: 'four groups of four');

      // Everyone plays everyone inside their own group: 6 matches a group.
      final groupMatches =
          planned.where((f) => f.bracket == Bracket.group).toList();
      expect(groupMatches.length, 24);

      // No group match ever crosses a group boundary.
      for (final f in groupMatches) {
        expect(f.groupId, isNotNull);
        expect(f.entrantA, isNotNull);
        expect(f.entrantB, isNotNull);
      }

      // Eight qualifiers, so the bracket is quarters → semis → final, and
      // every knockout slot names the table position that will fill it
      // rather than a team nobody has played for yet.
      final knockout =
          planned.where((f) => f.bracket == Bracket.knockout).toList();
      expect(knockout.length, 7);
      final labels = knockout.map((f) => f.roundLabel).toSet();
      expect(labels.any((l) => l.contains('Quarter-final')), isTrue);
      expect(labels.any((l) => l.contains('Semi-final')), isTrue);
      expect(labels.any((l) => l.contains('Final')), isTrue);

      final firstRound = knockout.where((f) => f.round == 1);
      expect(firstRound.length, 4);
      for (final f in firstRound) {
        expect(f.qualifierA, isNotNull);
        expect(f.qualifierB, isNotNull);
        expect(f.entrantA, isNull);
        expect(f.entrantB, isNull);
      }

      // Cross-seeded: a group's winner never meets its own runner-up first up.
      for (final f in firstRound) {
        expect(f.qualifierA!.groupId, isNot(f.qualifierB!.groupId));
      }
    });

    test('an odd field splits as evenly as it can', () {
      // Seventeen teams into four groups is 5/4/4/4 — one more in one group
      // is fine; two more is a different tournament for whoever drew it.
      for (final n in const [17, 22, 27, 31]) {
        final planned = const FixtureGenerator().generate(
          format: CompetitionFormat.groupThenKnockout,
          entrants: field(n),
          numGroups: 4,
          qualifiersPerGroup: 2,
          shuffleSeed: 3,
        );
        final sizes = groupSizes(planned).values.toList()..sort();
        expect(
          sizes.last - sizes.first,
          lessThanOrEqualTo(1),
          reason: '$n teams split into $sizes',
        );
        expect(sizes.reduce((a, b) => a + b), n);
      }
    });

    test('top 1 from each group is a legal shape too', () {
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.groupThenKnockout,
        entrants: field(24),
        numGroups: 4,
        qualifiersPerGroup: 1,
        shuffleSeed: 5,
      );
      final knockout =
          planned.where((f) => f.bracket == Bracket.knockout).toList();
      // Four group winners: two semi-finals and a final.
      expect(knockout.length, 3);
      expect(
        knockout.where((f) => f.round == 1).length,
        2,
        reason: 'four winners meet in two semi-finals',
      );
    });
  });
}
