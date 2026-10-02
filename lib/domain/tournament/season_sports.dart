import '../../core/models/competition.dart';
import '../../core/models/draw_slot.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/tournament.dart';
import '../../core/models/tournament_official.dart';
import '../schedule/match_phase.dart';
import '../standings/standings_calculator.dart';
import 'tournament_leaderboard.dart';
import 'tournament_overview.dart';

/// Where one sport is in its season, in one word.
enum SportStage {
  /// No draw yet, or nothing scheduled.
  notDrawn,

  /// Drawn and scheduled, nothing played.
  notStarted,

  /// Something played or being played, something still to play.
  running,

  /// Nothing left to play, but a match is abandoned or under protest, so the
  /// sport has no result yet. Used to read "Complete" — with a disputed
  /// semi-final the card said the sport was over while no champion could
  /// exist, and nothing on the page pointed at the match holding it up.
  needsRuling,

  /// Every match done.
  complete,
}

/// One umpire's part in one sport: on the season panel for it, named on its
/// matches, or both.
class SportUmpire {
  const SportUmpire({
    required this.uid,
    required this.name,
    required this.onPanel,
    required this.matches,
  });

  final String uid;
  final String name;

  /// On the season's officials roster for this sport.
  final bool onPanel;

  /// How many of this sport's matches name them.
  final int matches;
}

/// One points table in a sport: a group of a groups-and-knockout draw, a pool,
/// or a whole league.
class SportTable {
  const SportTable({
    required this.eventId,
    required this.eventName,
    required this.groupId,
    required this.rows,
    required this.qualifiers,
    required this.played,
    required this.total,
    required this.isTeams,
  });

  final String eventId;
  final String eventName;

  /// Null for a league or round robin with no groups — one table for the
  /// whole event.
  final String? groupId;

  /// Ranked, top first.
  final List<Standing> rows;

  /// How many go through to the knockout. Zero where nothing promotes — a
  /// league, or pools of a round robin.
  final int qualifiers;

  final int played;
  final int total;

  /// Teams rather than individual players, for the column heading.
  final bool isTeams;

  String get title => groupId == null ? eventName : '$eventName · Group $groupId';

  bool get isComplete => total > 0 && played == total;

  /// Formats whose standings are a table even without groups.
  static const tableFormats = {
    CompetitionFormat.roundRobin,
    CompetitionFormat.leagueTable,
    CompetitionFormat.swiss,
  };

  /// Every table [event] has, from its real (non-draft) matches.
  ///
  /// Rows are built from the names the fixtures carry — the same trade
  /// `StandingsCalculator.computeFromFixtures` makes — so a season page of
  /// six sports costs no entrant reads. A knockout with no group stage has no
  /// table and returns none: its standings are its bracket.
  static List<SportTable> of(Competition event, List<Fixture> fixtures) {
    const calc = StandingsCalculator();
    final own = [
      for (final f in fixtures)
        if (f.compId == event.id && !f.isDraft) f,
    ];
    if (own.isEmpty) return const [];
    final isTeams = event.entrantType == EntrantType.team;

    final grouped = [
      for (final f in own)
        if (f.bracket == Bracket.group && f.groupId != null) f,
    ];
    if (grouped.isNotEmpty) {
      final names = <String, String>{};
      for (final f in grouped) {
        if (f.entrantAId.isNotEmpty) names[f.entrantAId] = f.entrantAName;
        if (f.entrantBId.isNotEmpty) names[f.entrantBId] = f.entrantBName;
      }
      final tables = calc.computeGroups(
        competition: event,
        entrants: [
          for (final e in names.entries)
            Entrant(
              id: e.key,
              displayName: e.value,
              entrantType: event.entrantType,
            ),
        ],
        fixtures: grouped,
      );
      final promotes = event.drawConfig.feedsKnockoutUnder(event.format);
      final ids = tables.keys.toList()..sort();
      return [
        for (final id in ids)
          SportTable(
            eventId: event.id,
            eventName: event.name,
            groupId: id,
            rows: tables[id]!,
            qualifiers: promotes ? event.drawConfig.qualifiersPerGroup : 0,
            played: grouped
                .where((f) => f.groupId == id && f.status.isResulted)
                .length,
            total: grouped.where((f) => f.groupId == id).length,
            isTeams: isTeams,
          ),
      ];
    }

    if (!tableFormats.contains(event.format)) return const [];
    return [
      SportTable(
        eventId: event.id,
        eventName: event.name,
        groupId: null,
        rows: calc.computeFromFixtures(competition: event, fixtures: own),
        qualifiers: 0,
        played: own.where((f) => f.status.isResulted).length,
        total: own.length,
        isTeams: isTeams,
      ),
    ];
  }
}

/// One sport of a season, read as the tournament it really is.
///
/// ## Why the season page is built from these
///
/// A season is several tournaments under one roof — the cricket league, the
/// badminton knockouts, the kho-kho — sharing grounds, dates and a club, and
/// run by different people. An organizer opening the season asks the same
/// five questions of each: how far through is it, who is winning, what is on
/// and what is next, who is umpiring, and who is in charge. The page used to
/// answer them for the season as a whole — one progress bar across every
/// sport, one leaderboard, one list of events — which is the answer to a
/// question nobody running a multi-sport day asks.
///
/// Everything here is derived from the streams the season page already has
/// open. Nothing is stored, so none of it can disagree with the matches.
class SeasonSport {
  const SeasonSport({
    required this.sportId,
    required this.sportName,
    required this.events,
    required this.fixtures,
    required this.tally,
    required this.stage,
    required this.onNow,
    required this.upNext,
    required this.latestResults,
    required this.leaders,
    required this.tables,
    required this.umpires,
    required this.aheadWithoutUmpire,
    required this.leads,
  });

  final String sportId;
  final String sportName;

  /// This sport's events, each with its own progress and champion.
  final List<EventSummary> events;

  /// Every real match in this sport — drafts excluded.
  final List<Fixture> fixtures;

  final MatchTally tally;
  final SportStage stage;

  /// Live or paused, in this sport.
  final List<Fixture> onNow;

  /// The next matches to be played, soonest first — late ones included,
  /// because a late match is the most "next" a match can be.
  final List<Fixture> upNext;

  /// The most recently finished, newest first.
  final List<Fixture> latestResults;

  /// The best records in this sport, by titles then wins — the board for a
  /// sport whose events are knockouts and so have no [tables].
  final List<PlayerRecord> leaders;

  /// Every points table in this sport, event by event, group by group.
  final List<SportTable> tables;

  /// Everyone umpiring this sport, busiest first.
  final List<SportUmpire> umpires;

  /// Matches still to play that nobody has been named to officiate — the
  /// number that tells an organizer the panel is not done yet.
  final int aheadWithoutUmpire;

  /// Who is in charge of this sport. See [Tournament.sportLeads].
  final List<SportLead> leads;

  static const int _shortList = 3;
  static const int _boardLength = 8;

  /// Splits a season into its sports, alphabetically.
  ///
  /// A fixture belongs to the sport of its EVENT, not to its own `sportId`:
  /// that field is null on matches written before it existed, and the event
  /// is where the organizer chose the sport.
  static List<SeasonSport> split({
    required Tournament? tournament,
    required List<Competition> events,
    required List<Fixture> fixtures,
    required TournamentLeaderboard? leaderboard,
    required List<TournamentOfficial> roster,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final overview = TournamentOverview.from(
      events: events,
      fixtures: fixtures,
      now: clock,
    );
    final summaryOf = {for (final e in overview.events) e.competition.id: e};

    final eventsBySport = <String, List<Competition>>{};
    final names = <String, String>{};
    for (final e in events) {
      eventsBySport.putIfAbsent(e.sportId, () => []).add(e);
      names[e.sportId] = e.sportName;
    }
    final sportOfEvent = {for (final e in events) e.id: e.sportId};

    final fixturesBySport = <String, List<Fixture>>{};
    for (final f in fixtures) {
      if (f.isDraft) continue;
      final sport = sportOfEvent[f.compId];
      if (sport == null) continue;
      fixturesBySport.putIfAbsent(sport, () => []).add(f);
    }

    final ids = eventsBySport.keys.toList()
      ..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));

    return [
      for (final id in ids)
        _one(
          sportId: id,
          sportName: names[id] ?? id,
          events: [
            for (final e in eventsBySport[id]!)
              summaryOf[e.id] ??
                  EventSummary(
                    competition: e,
                    total: 0,
                    played: 0,
                    live: 0,
                    champion: null,
                  ),
          ]..sort((a, b) => a.competition.name.compareTo(b.competition.name)),
          fixtures: fixturesBySport[id] ?? const [],
          leaderboard: leaderboard,
          roster: roster,
          leads: tournament?.leadsFor(id) ?? const [],
          now: clock,
        ),
    ];
  }

  static SeasonSport _one({
    required String sportId,
    required String sportName,
    required List<EventSummary> events,
    required List<Fixture> fixtures,
    required TournamentLeaderboard? leaderboard,
    required List<TournamentOfficial> roster,
    required List<SportLead> leads,
    required DateTime now,
  }) {
    final tally = MatchTally.of(fixtures, now);
    final phases = {for (final f in fixtures) f.id: MatchPhase.of(f, now)};

    final onNow = [
      for (final f in fixtures)
        if (phases[f.id]!.inProgress) f,
    ]..sort(_byStart);

    final ahead = [
      for (final f in fixtures)
        if (phases[f.id]!.isAhead) f,
    ]..sort(_byStart);

    final finished = [
      for (final f in fixtures)
        if (phases[f.id] == MatchPhase.finished) f,
    ]..sort((a, b) {
        final at = a.completedAt ?? a.scheduledAt;
        final bt = b.completedAt ?? b.scheduledAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

    return SeasonSport(
      sportId: sportId,
      sportName: sportName,
      events: events,
      fixtures: fixtures,
      tally: tally,
      stage: _stageOf(tally),
      onNow: onNow,
      upNext: ahead.take(_shortList).toList(),
      latestResults: finished.take(_shortList).toList(),
      leaders: leaderboard?.topFor(sportId, _boardLength) ?? const [],
      tables: [
        for (final e in events) ...SportTable.of(e.competition, fixtures),
      ],
      umpires: _umpiresOf(sportId, fixtures, roster),
      aheadWithoutUmpire: ahead.where((f) => f.officials.isEmpty).length,
      leads: leads,
    );
  }

  static SportStage _stageOf(MatchTally t) {
    if (t.total == 0) return SportStage.notDrawn;
    if (t.played == t.total) return SportStage.complete;
    if (t.played + t.halted == t.total) return SportStage.needsRuling;
    if (t.played == 0 && t.inProgress == 0 && t.halted == 0) {
      return SportStage.notStarted;
    }
    return SportStage.running;
  }

  static List<SportUmpire> _umpiresOf(
    String sportId,
    List<Fixture> fixtures,
    List<TournamentOfficial> roster,
  ) {
    final names = <String, String>{};
    final counts = <String, int>{};
    final onPanel = <String>{};
    for (final o in roster) {
      // An empty sports list is "anything this season runs" — see
      // [TournamentOfficial.coversSport].
      if (!o.coversSport(sportId)) continue;
      onPanel.add(o.uid);
      names[o.uid] = o.name;
      counts.putIfAbsent(o.uid, () => 0);
    }
    for (final f in fixtures) {
      for (final o in f.officials) {
        if (o.uid.isEmpty) continue;
        names.putIfAbsent(o.uid, () => o.name);
        counts[o.uid] = (counts[o.uid] ?? 0) + 1;
      }
    }
    return [
      for (final uid in counts.keys)
        SportUmpire(
          uid: uid,
          name: names[uid] ?? 'Official',
          onPanel: onPanel.contains(uid),
          matches: counts[uid]!,
        ),
    ]..sort((a, b) {
        final byLoad = b.matches.compareTo(a.matches);
        return byLoad != 0 ? byLoad : a.name.compareTo(b.name);
      });
  }

  /// Timed matches by start, untimed last, then draw order.
  static int _byStart(Fixture a, Fixture b) {
    final at = a.scheduledAt;
    final bt = b.scheduledAt;
    if (at != null && bt != null) {
      final c = at.compareTo(bt);
      if (c != 0) return c;
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }
    final byRound = a.round.compareTo(b.round);
    return byRound != 0 ? byRound : a.matchIndex.compareTo(b.matchIndex);
  }
}
