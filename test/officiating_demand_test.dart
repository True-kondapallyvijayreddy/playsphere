import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_official.dart';
import 'package:playsphere/core/models/tournament_official.dart';
import 'package:playsphere/domain/tournament/officiating_demand.dart';

/// A season is not one officiating problem, it is one per sport. The number
/// that decides whether Saturday works is not "nine on the panel" — it is
/// that eight of the nine are badminton umpires and the kabaddi has nobody.
void main() {
  Competition event(String id, String sportId, String name) => Competition(
        id: id,
        orgId: 'club',
        name: name,
        sportId: sportId,
        sportName: sportId,
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        format: CompetitionFormat.roundRobin,
        status: CompetitionStatus.scheduled,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: sportId,
      );

  Fixture match(
    String id,
    String compId, {
    DateTime? at,
    bool staffed = false,
    FixtureStatus status = FixtureStatus.scheduled,
    String? groupId,
  }) =>
      Fixture(
        id: id,
        orgId: 'club',
        compId: compId,
        matchIndex: 0,
        round: 1,
        entrantAId: 'a',
        entrantAName: 'A',
        entrantBId: 'b',
        entrantBName: 'B',
        status: status,
        scheduledAt: at,
        bracket: groupId == null ? Bracket.knockout : Bracket.group,
        groupId: groupId,
        officials: staffed
            ? const [MatchOfficial(uid: 'u', name: 'Umpire')]
            : const [],
      );

  TournamentOfficial panelist(String uid, {List<String> sports = const []}) =>
      TournamentOfficial(uid: uid, name: uid, sports: sports);

  final sat = DateTime(2026, 9, 12, 9);
  final sun = DateTime(2026, 9, 13, 9);

  test('a sport nobody on the panel covers is flagged, and sorted first', () {
    final demand = officiatingDemand(
      events: [
        event('e1', 'badminton', 'Badminton Open'),
        event('e2', 'kabaddi', 'Kabaddi U-14'),
      ],
      fixtures: [
        match('b1', 'e1', at: sat),
        match('k1', 'e2', at: sat),
        match('k2', 'e2', at: sat),
      ],
      roster: [panelist('shuttle', sports: const ['badminton'])],
    );

    expect(demand.first.sportId, 'kabaddi');
    expect(demand.first.hasNobody, isTrue);
    expect(demand.first.panelCount, 0);

    final badminton = demand.firstWhere((d) => d.sportId == 'badminton');
    expect(badminton.hasNobody, isFalse);
    expect(badminton.panelCount, 1);
  });

  test('an official who named no sport counts towards every sport', () {
    // The default has to stay open, or a panel built in a hurry reads as a
    // panel that covers nothing.
    final demand = officiatingDemand(
      events: [event('e1', 'kho_kho', 'Kho Kho')],
      fixtures: [match('m1', 'e1', at: sat)],
      roster: [panelist('generalist')],
    );
    expect(demand.single.panelCount, 1);
    expect(demand.single.hasNobody, isFalse);
  });

  test('played matches are not still work to do', () {
    final demand = officiatingDemand(
      events: [event('e1', 'cricket', 'Cricket')],
      fixtures: [
        match('done', 'e1', at: sat, status: FixtureStatus.completed),
        match('todo', 'e1', at: sat),
      ],
      roster: const [],
    );
    expect(demand.single.total, 1);
    expect(demand.single.needed, 1);
  });

  test('untimed matches are counted apart from the ones needing an umpire',
      () {
    // A different job: the assigner cannot place a match with no window, and
    // the fix is to schedule it, not to find more officials.
    final demand = officiatingDemand(
      events: [event('e1', 'cricket', 'Cricket')],
      fixtures: [
        match('timed', 'e1', at: sat),
        match('tbd', 'e1'),
      ],
      roster: const [],
    );
    expect(demand.single.total, 1);
    expect(demand.single.unscheduled, 1);
  });

  test('staffed matches come off the gap', () {
    final demand = officiatingDemand(
      events: [event('e1', 'cricket', 'Cricket')],
      fixtures: [
        match('m1', 'e1', at: sat, staffed: true),
        match('m2', 'e1', at: sat),
      ],
      roster: [panelist('u')],
    );
    expect(demand.single.staffed, 1);
    expect(demand.single.needed, 1);
    expect(demand.single.isCovered, isFalse);
  });

  test('group matches still needing somebody are counted per group', () {
    // A five-group event is thirty matches to the knockout's seven, and
    // "the groups" is how a day is actually staffed.
    final demand = officiatingDemand(
      events: [event('e1', 'football', 'Football')],
      fixtures: [
        match('g1', 'e1', at: sat, groupId: 'A'),
        match('g2', 'e1', at: sat, groupId: 'A'),
        match('g3', 'e1', at: sat, groupId: 'B'),
        match('g4', 'e1', at: sat, groupId: 'B', staffed: true),
      ],
      roster: const [],
    );
    expect(demand.single.groups['Football · Group A'], 2);
    expect(demand.single.groups['Football · Group B'], 1);
  });

  test('the days a sport actually plays on are collected', () {
    final demand = officiatingDemand(
      events: [event('e1', 'hockey', 'Hockey')],
      fixtures: [
        match('m1', 'e1', at: sat),
        match('m2', 'e1', at: sun),
        match('m3', 'e1', at: sat),
      ],
      roster: const [],
    );
    expect(demand.single.dayKeys, ['2026-09-12', '2026-09-13']);
  });

  test('two draws of one sport are one staffing question', () {
    final demand = officiatingDemand(
      events: [
        event('e1', 'badminton', 'Singles'),
        event('e2', 'badminton', 'Doubles'),
      ],
      fixtures: [match('m1', 'e1', at: sat), match('m2', 'e2', at: sat)],
      roster: const [],
    );
    expect(demand, hasLength(1));
    expect(demand.single.total, 2);
    expect(demand.single.events, ['Doubles', 'Singles']);
  });

  test('season days come from the fixtures, not the season dates', () {
    // The stored start/end are wrong in opposite directions often enough
    // that deriving from them would offer a day nothing is played on and
    // miss the day a season overran onto.
    expect(
      seasonDayKeys([
        match('m1', 'e1', at: sun),
        match('m2', 'e1', at: sat),
        match('m3', 'e1'),
      ]),
      ['2026-09-12', '2026-09-13'],
    );
  });
}
