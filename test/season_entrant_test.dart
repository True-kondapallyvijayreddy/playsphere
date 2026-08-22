import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/tournament/season_entrant.dart';

/// Tapping a team on a season's board asks "how are they doing in THIS
/// season". Everything here is about answering exactly that and nothing
/// wider — a career page is a different question.
void main() {
  Competition event(
    String id,
    String name, {
    CompetitionFormat format = CompetitionFormat.knockout,
    String sport = 'badminton',
    int qualifiersPerGroup = 2,
  }) =>
      Competition(
        id: id,
        orgId: 'club',
        name: name,
        sportId: sport,
        sportName: sport,
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.team,
        format: format,
        status: CompetitionStatus.inProgress,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: sport,
        tournamentId: 't1',
        drawConfig: DrawConfig(qualifiersPerGroup: qualifiersPerGroup),
      );

  Fixture match(
    String id,
    String compId, {
    required String a,
    required String b,
    String? winner,
    FixtureStatus status = FixtureStatus.scheduled,
    DateTime? at,
    int round = 1,
    int index = 0,
    String? groupId,
    String summary = '',
  }) =>
      Fixture(
        id: id,
        orgId: 'club',
        compId: compId,
        matchIndex: index,
        round: round,
        entrantAId: a,
        entrantAName: a.toUpperCase(),
        entrantBId: b,
        entrantBName: b.toUpperCase(),
        status: status,
        winnerEntrantId: winner,
        scheduledAt: at,
        summary: summary,
        bracket: groupId == null ? Bracket.knockout : Bracket.group,
        groupId: groupId,
      );

  final mon = DateTime(2026, 9, 14, 9);
  final tue = DateTime(2026, 9, 15, 9);
  final wed = DateTime(2026, 9, 16, 9);

  test('only their matches are collected, out of the whole season', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('m1', 'e1', a: 'us', b: 'them', at: mon),
        match('m2', 'e1', a: 'other', b: 'another', at: mon),
      ],
    );
    expect(record.upcoming, hasLength(1));
    expect(record.upcoming.single.id, 'm1');
    expect(record.displayName, 'US');
  });

  test('the record is won/lost from THEIR side', () {
    // A page that reports the match winner instead makes the reader do the
    // swap on every row.
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('m1', 'e1',
            a: 'us',
            b: 'x',
            winner: 'us',
            status: FixtureStatus.completed,
            at: mon),
        match('m2', 'e1',
            a: 'y',
            b: 'us',
            winner: 'y',
            status: FixtureStatus.completed,
            at: tue),
      ],
    );
    expect(record.won, 1);
    expect(record.lost, 1);
    expect(record.matchesPlayed, 2);
  });

  test('the next match is the earliest unplayed one', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('later', 'e1', a: 'us', b: 'x', at: wed),
        match('sooner', 'e1', a: 'us', b: 'y', at: tue),
        match('done', 'e1',
            a: 'us',
            b: 'z',
            winner: 'us',
            status: FixtureStatus.completed,
            at: mon),
      ],
    );
    expect(record.nextMatch?.id, 'sooner');
  });

  test('an untimed match is not "next"', () {
    // It is not yet arranged, so putting it at the top of the page would
    // answer "when do they play" with a match that has no when.
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('tbd', 'e1', a: 'us', b: 'x'),
        match('timed', 'e1', a: 'us', b: 'y', at: wed),
      ],
    );
    expect(record.nextMatch?.id, 'timed');
  });

  test('played matches are newest first', () {
    // The one that just ended is the one being discussed.
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('old', 'e1',
            a: 'us', b: 'x', winner: 'us',
            status: FixtureStatus.completed, at: mon),
        match('new', 'e1',
            a: 'us', b: 'y', winner: 'us',
            status: FixtureStatus.completed, at: wed),
      ],
    );
    expect(record.played.first.id, 'new');
  });

  test('a team in three draws of a season is one page, not three', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [
        event('e1', 'Singles'),
        event('e2', 'Doubles'),
        event('e3', 'Mixed'),
      ],
      fixtures: [
        match('a', 'e1', a: 'us', b: 'x', at: mon),
        match('b', 'e2', a: 'us', b: 'y', at: tue),
        match('c', 'e3', a: 'us', b: 'z', at: wed),
      ],
    );
    expect(record.runs, hasLength(3));
    expect(record.upcoming, hasLength(3));
  });

  test('winning the deciding match of a knockout is a title', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('semi', 'e1',
            a: 'us', b: 'x', winner: 'us',
            status: FixtureStatus.completed, round: 1, at: mon),
        match('final', 'e1',
            a: 'us', b: 'y', winner: 'us',
            status: FixtureStatus.completed, round: 2, at: tue),
      ],
    );
    expect(record.titles, 1);
    expect(record.runs.single.isChampion, isTrue);
    expect(record.runs.single.outcome, 'Champion');
  });

  test('losing the deciding match is runner-up, not knocked out', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('final', 'e1',
            a: 'us', b: 'y', winner: 'y',
            status: FixtureStatus.completed, round: 2, at: tue),
      ],
    );
    expect(record.runs.single.isRunnerUp, isTrue);
    expect(record.runs.single.isChampion, isFalse);
    expect(record.runs.single.outcome, 'Runner-up');
  });

  test('a league awards no title from its last match', () {
    // Mirrors the leaderboard's rule: a league is decided by the table, and
    // crediting whoever played last would be meaningless.
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'League', format: CompetitionFormat.roundRobin)],
      fixtures: [
        match('m1', 'e1',
            a: 'us', b: 'x', winner: 'us',
            status: FixtureStatus.completed, at: mon),
      ],
    );
    expect(record.titles, 0);
  });

  test('a group position is their position in their own group', () {
    // Not the event-wide table they are not actually competing in.
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [
        event('e1', 'Pool play', format: CompetitionFormat.groupThenKnockout),
      ],
      fixtures: [
        match('g1', 'e1',
            a: 'us', b: 'x', winner: 'us',
            status: FixtureStatus.completed, groupId: 'A', at: mon),
        match('g2', 'e1',
            a: 'us', b: 'z', winner: 'z',
            status: FixtureStatus.completed, groupId: 'A', at: tue),
        match('g3', 'e1',
            a: 'z', b: 'x', winner: 'z',
            status: FixtureStatus.completed, groupId: 'A', at: wed),
        // Another group entirely — must not affect their standing.
        match('g4', 'e1',
            a: 'p', b: 'q', winner: 'p',
            status: FixtureStatus.completed, groupId: 'B', at: mon),
      ],
    );
    final run = record.runs.single;
    expect(run.groupId, 'A');
    expect(run.groupSize, 3);
    expect(run.groupRank, 2);
    expect(run.outcome, contains('Group A'));
  });

  test('a champion is never reported as knocked out', () {
    // Their own matches are all played, and so is the event's — reading that
    // as elimination would be a remarkable way to report a title.
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('final', 'e1',
            a: 'us', b: 'y', winner: 'us',
            status: FixtureStatus.completed, round: 2, at: tue),
      ],
    );
    expect(record.runs.single.isOut, isFalse);
  });

  test('an entrant with nothing in this season reads as empty', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'stranger',
      events: [event('e1', 'Cup')],
      fixtures: [match('m1', 'e1', a: 'us', b: 'them', at: mon)],
    );
    expect(record.isEmpty, isTrue);
  });

  test('win rate stays blank below three matches', () {
    final record = SeasonEntrantRecord.from(
      entrantId: 'us',
      events: [event('e1', 'Cup')],
      fixtures: [
        match('m1', 'e1',
            a: 'us', b: 'x', winner: 'us',
            status: FixtureStatus.completed, at: mon),
      ],
    );
    expect(record.winRate, isNull);
  });
}
