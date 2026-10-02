import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_slot.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/core/models/match_official.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/models/tournament_official.dart';
import 'package:playsphere/data/scoring_service.dart';
import 'package:playsphere/domain/schedule/match_phase.dart';
import 'package:playsphere/domain/tournament/season_sports.dart';

final now = DateTime(2026, 9, 13, 12);

Fixture fx(
  String id, {
  String comp = 'bad1',
  FixtureStatus status = FixtureStatus.scheduled,
  DateTime? at,
  DateTime? lastEventAt,
  int lastSeq = 0,
  String summary = '',
  MatchResultType resultType = MatchResultType.normal,
  List<String> scorerUids = const [],
  List<MatchOfficial> officials = const [],
  String? winner,
  bool isDraft = false,
}) =>
    Fixture(
      id: id,
      orgId: 'org1',
      compId: comp,
      entrantAId: 'a',
      entrantBId: 'b',
      entrantAName: 'Asha',
      entrantBName: 'Bina',
      status: status,
      scheduledAt: at,
      lastEventAt: lastEventAt,
      lastSeq: lastSeq,
      summary: summary,
      resultType: resultType,
      scorerUids: scorerUids,
      officials: officials,
      winnerEntrantId: winner,
      isDraft: isDraft,
    );

Competition event(String id, String sportId, String sportName) => Competition(
      id: id,
      orgId: 'org1',
      name: 'Event $id',
      sportId: sportId,
      sportName: sportName,
      archetype: CompetitionArchetype.versus,
      entrantType: EntrantType.individual,
      format: CompetitionFormat.knockout,
      status: CompetitionStatus.inProgress,
      category: const CompetitionCategory(label: 'Open'),
      scoringPluginKey: 'badminton',
      tournamentId: 's1',
    );

void main() {
  group('result markers — the score is kept and marked', () {
    test('a retirement reads as its score with (R)', () {
      final f = fx('f',
          status: FixtureStatus.completed,
          lastSeq: 30,
          summary: '21-15, 8-3',
          resultType: MatchResultType.retired);
      expect(f.scoreLine, '21-15, 8-3 (R)');
    });

    test('a disqualification is (D), a walkover with a score (W/O)', () {
      expect(
        fx('f', summary: '11-4', resultType: MatchResultType.disqualified)
            .scoreLine,
        '11-4 (D)',
      );
      expect(
        fx('f', summary: '11-4', resultType: MatchResultType.walkover)
            .scoreLine,
        '11-4 (W/O)',
      );
    });

    test('a normal result carries no marker', () {
      expect(fx('f', summary: '21-19, 21-17').scoreLine, '21-19, 21-17');
    });

    test('a token is never marked — "walkover (W/O)" says it twice', () {
      final f = fx('f',
          summary: 'walkover', resultType: MatchResultType.walkover);
      expect(f.summaryIsScore, isFalse);
      expect(f.scoreLine, 'walkover');
    });

    test('a walkover on a match in progress keeps the score it reached', () {
      final live = fx('f',
          status: FixtureStatus.live, lastSeq: 22, summary: '21-15, 8-3');
      expect(
        ScoringService.outcomeSummary(live, FixtureStatus.walkover),
        '21-15, 8-3',
      );
      expect(
        ScoringService.outcomeSummary(live, FixtureStatus.abandoned),
        '21-15, 8-3',
      );
    });

    test('a walkover before a ball is still the translatable token', () {
      final fresh = fx('f');
      expect(
        ScoringService.outcomeSummary(fresh, FixtureStatus.walkover),
        'walkover',
      );
    });

    test('a dispute is a freeze, and still says so', () {
      final done = fx('f',
          status: FixtureStatus.completed, lastSeq: 40, summary: '21-9, 21-8');
      expect(
        ScoringService.outcomeSummary(done, FixtureStatus.disputed),
        'disputed',
      );
    });
  });

  group('who may set a stream link', () {
    const umpire = MatchOfficial(uid: 'ump', name: 'Ump');
    final f = fx('f', scorerUids: ['scorer'], officials: [umpire]);

    test('organizers, this match\'s scorers and umpires, the season panel', () {
      expect(f.canSetStreamBy('owner', isOrganizer: true), isTrue);
      expect(f.canSetStreamBy('scorer', isOrganizer: false), isTrue);
      expect(f.canSetStreamBy('ump', isOrganizer: false), isTrue);
      expect(
        f.canSetStreamBy('panel', isOrganizer: false, onSeasonPanel: true),
        isTrue,
      );
    });

    test('nobody who is only watching', () {
      expect(f.canSetStreamBy('fan', isOrganizer: false), isFalse);
    });

    test('only as far as the rules can index the officials', () {
      final crowded = fx('f', officials: [
        for (var i = 0; i < 5; i++) MatchOfficial(uid: 'u$i', name: 'U$i'),
      ]);
      expect(crowded.canSetStreamBy('u3', isOrganizer: false), isTrue);
      expect(crowded.canSetStreamBy('u4', isOrganizer: false), isFalse);
    });
  });

  group('MatchPhase', () {
    test('live, paused, finished, halted, late, upcoming', () {
      expect(
        MatchPhase.of(
          fx('f',
              status: FixtureStatus.live,
              lastSeq: 3,
              lastEventAt: now.subtract(const Duration(minutes: 1))),
          now,
        ),
        MatchPhase.live,
      );
      expect(
        MatchPhase.of(
          fx('f',
              status: FixtureStatus.live,
              lastSeq: 3,
              lastEventAt: now.subtract(const Duration(days: 2))),
          now,
        ),
        MatchPhase.paused,
      );
      expect(MatchPhase.of(fx('f', status: FixtureStatus.completed), now),
          MatchPhase.finished);
      expect(MatchPhase.of(fx('f', status: FixtureStatus.walkover), now),
          MatchPhase.finished);
      expect(MatchPhase.of(fx('f', status: FixtureStatus.abandoned), now),
          MatchPhase.halted);
      expect(
        MatchPhase.of(
            fx('f', at: now.subtract(const Duration(minutes: 40))), now),
        MatchPhase.overdue,
      );
      expect(
        MatchPhase.of(
            fx('f', at: now.subtract(const Duration(minutes: 5))), now),
        MatchPhase.upcoming,
        reason: 'inside the grace period a match is not late yet',
      );
      expect(MatchPhase.of(fx('f'), now), MatchPhase.upcoming);
    });

    test('a tally ignores drafts and splits what is left', () {
      final t = MatchTally.of([
        fx('1', status: FixtureStatus.completed),
        fx('2', status: FixtureStatus.abandoned),
        fx('3',
            status: FixtureStatus.live,
            lastSeq: 1,
            lastEventAt: now.subtract(const Duration(minutes: 1))),
        fx('4', at: now.subtract(const Duration(hours: 1))),
        fx('5', at: now.add(const Duration(hours: 1))),
        fx('6', isDraft: true),
      ], now);
      expect(t.total, 5);
      expect(t.played, 1);
      expect(t.halted, 1);
      expect(t.inProgress, 1);
      expect(t.ahead, 2);
      expect(t.overdue, 1);
    });
  });

  group('SeasonSport.split', () {
    final events = [
      event('bad1', 'badminton', 'Badminton'),
      event('bad2', 'badminton', 'Badminton'),
      event('cri1', 'cricket', 'Cricket'),
    ];
    const ravi = MatchOfficial(uid: 'ravi', name: 'Ravi');
    final fixtures = [
      fx('b1', comp: 'bad1', status: FixtureStatus.completed, winner: 'a'),
      fx('b2', comp: 'bad2', at: now.add(const Duration(hours: 2))),
      fx('b3',
          comp: 'bad2',
          at: now.add(const Duration(hours: 1)),
          officials: [ravi]),
      fx('c1', comp: 'cri1', at: now.subtract(const Duration(hours: 1))),
      fx('x', comp: 'not-in-season', status: FixtureStatus.completed),
    ];
    const tournament = Tournament(
      id: 's1',
      orgId: 'org1',
      name: 'Summer season',
      status: TournamentStatus.inProgress,
      sportLeads: {
        'cricket': [SportLead(uid: 'priya', name: 'Priya')],
      },
    );

    final sports = SeasonSport.split(
      tournament: tournament,
      events: events,
      fixtures: fixtures,
      leaderboard: null,
      roster: const [
        TournamentOfficial(uid: 'meena', name: 'Meena', sports: ['cricket']),
        TournamentOfficial(uid: 'any', name: 'Anyone'),
      ],
      now: now,
    );

    test('one entry per sport, alphabetical, events grouped under it', () {
      expect(sports.map((s) => s.sportName), ['Badminton', 'Cricket']);
      expect(sports.first.events.map((e) => e.competition.id),
          ['bad1', 'bad2']);
    });

    test('matches belong to the sport of their event', () {
      expect(sports.first.tally.total, 3);
      expect(sports.last.tally.total, 1);
      expect(sports.first.tally.played, 1);
      expect(sports.first.stage, SportStage.running);
      expect(sports.last.stage, SportStage.notStarted);
    });

    test('up next is soonest first; late matches count as next', () {
      expect(sports.first.upNext.map((f) => f.id), ['b3', 'b2']);
      expect(sports.last.upNext.single.id, 'c1');
      expect(sports.last.tally.overdue, 1);
    });

    test('umpires: the panel for the sport plus whoever is on its matches',
        () {
      expect(
        sports.first.umpires.map((u) => u.uid),
        ['ravi', 'any'],
        reason: 'busiest first; Meena only covers cricket',
      );
      expect(sports.first.umpires.first.onPanel, isFalse);
      expect(sports.last.umpires.map((u) => u.uid).toSet(), {'meena', 'any'});
      expect(sports.first.aheadWithoutUmpire, 1);
    });

    test('leads come from the season, per sport', () {
      expect(sports.last.leads.single.name, 'Priya');
      expect(sports.first.leads, isEmpty);
    });
  });

  group('SportTable — the simple leaderboard per group', () {
    Fixture game(String id, String a, String b, String? winner,
            {String? group = 'A',
            Bracket bracket = Bracket.group,
            String comp = 'g1',
            bool draft = false}) =>
        Fixture(
          id: id,
          orgId: 'org1',
          compId: comp,
          entrantAId: a,
          entrantBId: b,
          entrantAName: a.toUpperCase(),
          entrantBName: b.toUpperCase(),
          status: winner == null
              ? FixtureStatus.scheduled
              : FixtureStatus.completed,
          winnerEntrantId: winner,
          bracket: bracket,
          groupId: group,
          isDraft: draft,
        );

    Competition comp(String id, CompetitionFormat format,
            {EntrantType type = EntrantType.team}) =>
        Competition(
          id: id,
          orgId: 'org1',
          name: 'Event $id',
          sportId: 'cricket',
          sportName: 'Cricket',
          archetype: CompetitionArchetype.versus,
          entrantType: type,
          format: format,
          status: CompetitionStatus.inProgress,
          category: const CompetitionCategory(label: 'Open'),
          scoringPluginKey: 'goal_based',
        );

    test('one table per group, ranked, with the qualifying places', () {
      final tables = SportTable.of(
        comp('g1', CompetitionFormat.groupThenKnockout),
        [
          game('1', 'a', 'b', 'a'),
          game('2', 'a', 'c', 'a'),
          game('3', 'b', 'c', null),
          game('4', 'd', 'e', 'e', group: 'B'),
          game('k', 'a', 'e', null, group: null, bracket: Bracket.knockout),
          game('x', 'p', 'q', 'p', draft: true),
        ],
      );
      expect(tables.map((t) => t.title),
          ['Event g1 · Group A', 'Event g1 · Group B']);
      final a = tables.first;
      expect(a.rows.first.displayName, 'A');
      expect(a.rows.first.won, 2);
      expect(a.qualifiers, 2);
      expect(a.played, 2);
      expect(a.total, 3);
      expect(a.isTeams, isTrue);
      expect(tables.last.rows.first.displayName, 'E');
    });

    test('a league with no groups is one table, nothing promotes', () {
      final tables = SportTable.of(
        comp('g1', CompetitionFormat.leagueTable, type: EntrantType.individual),
        [
          game('1', 'a', 'b', 'b', group: null, bracket: Bracket.knockout),
        ],
      );
      expect(tables.single.groupId, isNull);
      expect(tables.single.title, 'Event g1');
      expect(tables.single.qualifiers, 0);
      expect(tables.single.rows.first.displayName, 'B');
      expect(tables.single.isTeams, isFalse);
    });

    test('a plain knockout has no table', () {
      expect(
        SportTable.of(comp('g1', CompetitionFormat.knockout), [
          game('1', 'a', 'b', 'a', group: null, bracket: Bracket.knockout),
        ]),
        isEmpty,
      );
    });
  });

  group('SportLead.mapFrom', () {
    test('reads the stored shape and skips anything malformed', () {
      final leads = SportLead.mapFrom({
        'cricket': [
          {'uid': 'p', 'name': 'Priya'},
          {'name': 'no uid'},
          'junk',
        ],
        'chess': 'not a list',
        'kabaddi': <Object>[],
      });
      expect(leads.keys, ['cricket']);
      expect(leads['cricket']!.single.uid, 'p');
    });
  });
}
