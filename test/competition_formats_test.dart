import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/domain/scoring/scoring_registry.dart';

/// Every screen that sets a sport up — standalone event creation, season
/// creation, adding a sport to an existing season — reads its format choices
/// from [SportSpec.competitionFormats]. This pins that a normal (non
/// performance) sport actually offers every format the draw generator
/// supports, not just Round Robin — the bug that prompted this getter to
/// exist as one shared list instead of three drifting copies.
void main() {
  test('a versus sport offers every draw format the generator supports', () {
    final formats = SportCatalog.byId('cricket').competitionFormats;

    expect(formats, contains(CompetitionFormat.roundRobin));
    expect(formats, contains(CompetitionFormat.knockout));
    expect(formats, contains(CompetitionFormat.groupThenKnockout));
    expect(formats, contains(CompetitionFormat.doubleElimination));
    expect(formats, contains(CompetitionFormat.swiss));
    expect(formats, contains(CompetitionFormat.leagueTable));
    // Single match is its own event type, chosen a screen earlier — never a
    // draw format an organizer picks from this list.
    expect(formats, isNot(contains(CompetitionFormat.singleMatch)));
    expect(formats.first, CompetitionFormat.roundRobin);
  });

  test('a performance sport only offers final-only or heats-then-final', () {
    final formats = SportCatalog.byId('athletics_sprint').competitionFormats;

    expect(
      formats,
      [CompetitionFormat.finalOnly, CompetitionFormat.heatsThenFinal],
    );
  });
}
