import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/features/home/event_feed.dart';

/// [groupEventFeed] is what turns a season's five sport competitions back
/// into one row in an events list — see the doc comment on the function for
/// why that grouping has to happen at all. These pin the grouping rules
/// themselves, independent of any screen that renders them.
void main() {
  Competition comp(
    String id, {
    String orgId = 'o1',
    String? tournamentId,
  }) =>
      Competition(
        id: id,
        orgId: orgId,
        name: 'Event $id',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.registrationOpen,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        tournamentId: tournamentId,
      );

  test('a standalone competition passes through untouched', () {
    final feed = groupEventFeed([comp('c1')]);
    expect(feed, hasLength(1));
    expect(feed.single, isA<EventFeedSingle>());
    expect((feed.single as EventFeedSingle).competition.id, 'c1');
  });

  test('every sport of one season collapses into a single entry', () {
    final feed = groupEventFeed([
      comp('cricket', tournamentId: 't1'),
      comp('chess', tournamentId: 't1'),
      comp('kabaddi', tournamentId: 't1'),
    ]);

    expect(feed, hasLength(1));
    final season = feed.single as EventFeedSeason;
    expect(season.tournamentId, 't1');
    expect(season.competitions.map((c) => c.id),
        ['cricket', 'chess', 'kabaddi']);
  });

  test('two different seasons stay apart, and a standalone event beside '
      'them stays its own row', () {
    final feed = groupEventFeed([
      comp('a1', tournamentId: 't1'),
      comp('solo'),
      comp('b1', tournamentId: 't2'),
      comp('a2', tournamentId: 't1'),
    ]);

    expect(feed, hasLength(3));
    expect((feed[0] as EventFeedSeason).tournamentId, 't1');
    expect((feed[0] as EventFeedSeason).competitions.map((c) => c.id),
        ['a1', 'a2']);
    expect((feed[1] as EventFeedSingle).competition.id, 'solo');
    expect((feed[2] as EventFeedSeason).tournamentId, 't2');
  });

  test('the same tournament id in two different clubs never merges', () {
    final feed = groupEventFeed([
      comp('a1', orgId: 'o1', tournamentId: 't1'),
      comp('b1', orgId: 'o2', tournamentId: 't1'),
    ]);

    expect(feed, hasLength(2));
    expect(feed.every((i) => i is EventFeedSeason), isTrue);
  });

  test('a season keeps the list position of its first sport', () {
    final feed = groupEventFeed([
      comp('solo1'),
      comp('a1', tournamentId: 't1'),
      comp('solo2'),
      comp('a2', tournamentId: 't1'),
    ]);

    expect(feed, hasLength(3));
    expect((feed[0] as EventFeedSingle).competition.id, 'solo1');
    expect((feed[1] as EventFeedSeason).tournamentId, 't1');
    expect((feed[2] as EventFeedSingle).competition.id, 'solo2');
  });
}
