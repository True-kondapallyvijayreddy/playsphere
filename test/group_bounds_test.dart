import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/draw/fixture_generator.dart';
import 'package:playsphere/domain/draw/group_bounds.dart';

/// The rule an organizer was promised: no group smaller than two, none larger
/// than eight. It had been stated in a generator nothing called while the
/// screen that mattered defaulted to groups of ten.
void main() {
  group('group bounds', () {
    test('every field size resolves to groups of between 2 and 8', () {
      for (var n = 2; n <= 128; n++) {
        final groups = GroupBounds.resolve(entrants: n);
        final largest = GroupBounds.largestGroupSize(n, groups);
        final smallest = GroupBounds.smallestGroupSize(n, groups);

        expect(
          largest,
          lessThanOrEqualTo(GroupBounds.maxPerGroup),
          reason: '$n entrants in $groups groups leaves a group of $largest',
        );
        // Three entrants in two groups is a 2 and a 1; the floor is what
        // stops that, so it is checked wherever the arithmetic allows it.
        if (n >= GroupBounds.minPerGroup * groups) {
          expect(
            smallest,
            greaterThanOrEqualTo(GroupBounds.minPerGroup),
            reason: '$n entrants in $groups groups leaves a group of $smallest',
          );
        }
      }
    });

    test('an organizer asking for too few groups is pulled up to the floor',
        () {
      // One group of forty was previously accepted verbatim.
      expect(GroupBounds.resolve(entrants: 40, requested: 1), 5);
      expect(GroupBounds.largestGroupSize(40, 5), 8);
    });

    test('an organizer asking for too many groups is pulled down to the cap',
        () {
      // Twenty groups from eight entrants is nineteen walkovers.
      expect(GroupBounds.resolve(entrants: 8, requested: 20), 4);
      expect(GroupBounds.smallestGroupSize(8, 4), 2);
    });

    test('a choice inside the bounds is left exactly as asked', () {
      expect(GroupBounds.resolve(entrants: 24, requested: 4), 4);
      expect(GroupBounds.resolve(entrants: 24, requested: 6), 6);
    });

    test('the default aims at five a group, not ten', () {
      expect(GroupBounds.resolve(entrants: 20), 4);
      expect(GroupBounds.largestGroupSize(20, 4), 5);
      // The old default derived one group per ten entrants, which put 40
      // entrants into 4 groups of 10 — two over the cap.
      expect(GroupBounds.resolve(entrants: 40), 8);
      expect(GroupBounds.largestGroupSize(40, 8), 5);
    });

    test('groups stay large enough to supply their qualifiers', () {
      // Four through from each group means no group may be smaller than four,
      // so sixteen entrants cannot be split more than four ways.
      final groups =
          GroupBounds.maxGroups(16, qualifiersPerGroup: 4);
      expect(groups, 4);
      expect(GroupBounds.smallestGroupSize(16, groups), 4);
    });

    test('a field too small for the qualifier count still yields a draw', () {
      // Five entrants advancing three apiece satisfies nothing; the floor
      // wins rather than the bounds crossing and returning nonsense.
      final groups = GroupBounds.resolve(entrants: 5, qualifiersPerGroup: 3);
      expect(groups, greaterThanOrEqualTo(1));
      expect(GroupBounds.largestGroupSize(5, groups),
          lessThanOrEqualTo(GroupBounds.maxPerGroup));
    });

    test('degenerate fields do not divide by zero', () {
      expect(GroupBounds.resolve(entrants: 0), 1);
      expect(GroupBounds.minGroups(0), 1);
      expect(GroupBounds.maxGroups(0), 1);
      expect(GroupBounds.resolve(entrants: 2), 1);
    });
  });

  group('groups are not welded to one format', () {
    List<Entrant> field(int n) => [
          for (var i = 0; i < n; i++)
            Entrant(
              id: 'e$i',
              displayName: 'Player $i',
              entrantType: EntrantType.individual,
            ),
        ];

    test('a round robin with groups becomes pools, with no knockout', () {
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.roundRobin,
        entrants: field(30),
        useGroups: true,
        numGroups: 6,
        shuffleSeed: 1,
      );

      expect(planned, isNotEmpty);
      expect(
        planned.every((f) => f.bracket == Bracket.group),
        isTrue,
        reason: 'pools have no knockout stage to feed',
      );
      // Six groups of five: 10 matches each, 60 in all — against 435 for one
      // round robin of thirty, which is the whole point.
      expect(planned.length, 60);
      expect(planned.map((f) => f.groupId).toSet().length, 6);
    });

    test('a knockout with groups gains a group stage in front of it', () {
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.knockout,
        entrants: field(16),
        useGroups: true,
        numGroups: 4,
        qualifiersPerGroup: 2,
        shuffleSeed: 1,
      );

      expect(planned.any((f) => f.bracket == Bracket.group), isTrue);
      expect(planned.any((f) => f.bracket == Bracket.knockout), isTrue);
    });

    test('a knockout without groups stays a plain knockout', () {
      final planned = const FixtureGenerator().generate(
        format: CompetitionFormat.knockout,
        entrants: field(16),
        shuffleSeed: 1,
      );
      expect(planned.any((f) => f.bracket == Bracket.group), isFalse);
    });

    test('pools still obey the 2-8 rule when nobody names a count', () {
      for (final n in const [4, 9, 17, 30, 64, 100]) {
        final planned = const FixtureGenerator().generate(
          format: CompetitionFormat.roundRobin,
          entrants: field(n),
          useGroups: true,
          shuffleSeed: 1,
        );
        final sizes = <String, int>{};
        for (final f in planned) {
          final id = f.groupId;
          if (id == null) continue;
          sizes[id] = (sizes[id] ?? 0) + 1;
        }
        final groups = sizes.length;
        expect(
          GroupBounds.largestGroupSize(n, groups),
          lessThanOrEqualTo(GroupBounds.maxPerGroup),
          reason: '$n entrants fell into $groups groups',
        );
      }
    });
  });
}
