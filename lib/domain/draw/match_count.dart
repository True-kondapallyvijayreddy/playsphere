import 'dart:math' as math;

import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import 'group_bounds.dart';

/// How many matches a draw will produce, before it is drawn.
///
/// ## Why this has to be answerable in advance
///
/// The feasibility question an organizer needs answered — "do 45 cricket
/// matches fit on one ground in six days?" — is asked *before* any draw
/// exists. Counting the fixtures cannot answer it, because there are none; a
/// season that could only be tested by generating it would have to be
/// generated to be found impossible, which is exactly the discovery this is
/// meant to move earlier.
///
/// Every formula here is the same arithmetic `FixtureGenerator` performs when
/// it actually builds the bracket. It is duplicated deliberately rather than
/// obtained by running the generator: the generator needs a settled field of
/// [Entrant] documents, and the point is to answer from an entrant *count*.
class MatchCount {
  const MatchCount._();

  /// Matches a draw of [entrants] produces under [format] and [config].
  ///
  /// Returns zero for a field too small to play anybody, which is the honest
  /// answer and keeps a half-registered event from inflating a capacity check.
  static int forDraw({
    required CompetitionFormat format,
    required DrawConfig config,
    required int entrants,
  }) {
    if (entrants < 2) return 0;

    switch (format) {
      case CompetitionFormat.singleMatch:
        return 1;

      case CompetitionFormat.finalOnly:
        return 1;

      case CompetitionFormat.heatsThenFinal:
        // Heats of eight, then one final. The generator's own default.
        return (entrants / 8).ceil() + 1;

      case CompetitionFormat.swiss:
        final rounds =
            config.swissRounds ?? math.max(1, (math.log(entrants) / math.ln2).ceil());
        return rounds * (entrants ~/ 2);

      case CompetitionFormat.doubleElimination:
        return (2 * entrants - 2) + (config.bracketReset ? 1 : 0);

      case CompetitionFormat.roundRobin:
      case CompetitionFormat.leagueTable:
      case CompetitionFormat.knockout:
      case CompetitionFormat.groupThenKnockout:
        break;
    }

    final grouped = config.isGroupedUnder(format);
    if (!grouped) {
      if (format == CompetitionFormat.knockout) return entrants - 1;
      final legs = config.doubleRoundRobin ? 2 : 1;
      return entrants * (entrants - 1) ~/ 2 * legs;
    }

    final groups = GroupBounds.resolve(
      entrants: entrants,
      requested: config.numGroups ??
          (config.groupSize != null && config.groupSize! > 0
              ? (entrants / config.groupSize!).ceil()
              : null),
      qualifiersPerGroup: config.qualifiersPerGroup,
    );

    // Groups are dealt round-robin, so sizes differ by at most one — and the
    // difference matters: five groups of 4 is 30 matches, four of 5 is 40.
    final base = entrants ~/ groups;
    final withOneExtra = entrants % groups;
    final legs = config.doubleRoundRobin ? 2 : 1;

    var total = 0;
    for (var i = 0; i < groups; i++) {
      final size = base + (i < withOneExtra ? 1 : 0);
      if (size < 2) continue;
      total += size * (size - 1) ~/ 2 * legs;
    }

    if (config.feedsKnockoutUnder(format)) {
      final perGroup =
          config.qualifiersPerGroup < 1 ? 1 : config.qualifiersPerGroup;
      final qualifiers = groups * perGroup;
      if (qualifiers >= 2) total += qualifiers - 1;
    }
    return total;
  }
}
