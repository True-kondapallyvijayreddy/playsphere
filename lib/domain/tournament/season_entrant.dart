import '../../core/models/competition.dart';
import '../../core/models/draw_slot.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../standings/standings_calculator.dart';

/// How one team or player is doing in one event of a season.
class SeasonEventRun {
  const SeasonEventRun({
    required this.eventId,
    required this.eventName,
    required this.sportName,
    required this.format,
    required this.played,
    required this.won,
    required this.lost,
    required this.remaining,
    this.groupId,
    this.groupRank,
    this.groupSize,
    this.groupPoints,
    this.isChampion = false,
    this.isRunnerUp = false,
    this.isOut = false,
  });

  final String eventId;
  final String eventName;
  final String sportName;
  final CompetitionFormat format;

  final int played;
  final int won;
  final int lost;

  /// Matches in this event still to play. What decides whether the run is
  /// history or something to turn up for.
  final int remaining;

  /// Where they sit in their group, when the event has groups. A team in a
  /// season wants their position in THIS group, not the event-wide table they
  /// are not actually competing in.
  final String? groupId;
  final int? groupRank;
  final int? groupSize;
  final int? groupPoints;

  final bool isChampion;
  final bool isRunnerUp;

  /// Knocked out — the last bracket match they played, they lost, and there
  /// is nothing of theirs left in the draw.
  final bool isOut;

  bool get isLive => remaining > 0;

  /// The one-line verdict on this run, for the row under the event's name.
  String get outcome {
    if (isChampion) return 'Champion';
    if (isRunnerUp) return 'Runner-up';
    if (groupRank != null) {
      final where = groupSize == null
          ? 'Group $groupId'
          : 'Group $groupId, $groupRank of $groupSize';
      return isLive ? '$where · still playing' : where;
    }
    if (isOut) return 'Knocked out';
    if (isLive) return '$remaining still to play';
    return 'Finished';
  }
}

/// Everything one entrant did in one season, and nothing they did outside it.
///
/// ## Why this is scoped to the season rather than to a career
///
/// Tapping a name on a season's leaderboard asks a specific question — *how is
/// this team doing in THIS season* — and the two pages that already existed
/// answer different ones. A player's career page spans every club and year and
/// buries the season in it. `EntrantDetailScreen` is scoped to one draw, so a
/// team entered in three events of a season is three unrelated pages.
///
/// A season is the unit an organizer, a parent and a captain all think in, and
/// it is the only scope where "every match they play, and the score" is a
/// finite, readable list. So this collects exactly that: their events, their
/// record, their group positions and every one of their matches — with
/// everything from other seasons deliberately absent.
class SeasonEntrantRecord {
  const SeasonEntrantRecord({
    required this.entrantId,
    required this.displayName,
    required this.runs,
    required this.upcoming,
    required this.played,
    required this.won,
    required this.lost,
    required this.drawn,
    required this.titles,
    required this.eventNames,
  });

  final String entrantId;
  final String displayName;

  /// One per event they entered, best result first.
  final List<SeasonEventRun> runs;

  /// Their matches still to come, earliest first. The first of these is the
  /// one anybody opening this page is looking for.
  final List<Fixture> upcoming;

  /// Their finished matches, most recent first.
  final List<Fixture> played;

  final int won;
  final int lost;
  final int drawn;
  final int titles;

  /// Event id to name, for labelling a match with the draw it belongs to.
  final Map<String, String> eventNames;

  int get matchesPlayed => played.length;

  Fixture? get nextMatch => upcoming.isEmpty ? null : upcoming.first;

  /// Wins as a share of matches played. Null below three, the same bar
  /// `PlayerRecord.winRate` sets and for the same reason: one win from one is
  /// not 100% in any sense worth printing.
  double? get winRate => matchesPlayed < 3 ? null : won / matchesPlayed;

  bool get isEmpty => runs.isEmpty && upcoming.isEmpty && played.isEmpty;

  /// Builds the record from the season's events and every match in it.
  ///
  /// Pure, and driven by the streams the season screens already hold, so
  /// opening one of these costs no read.
  static SeasonEntrantRecord from({
    required String entrantId,
    required List<Competition> events,
    required List<Fixture> fixtures,
  }) {
    final eventById = {for (final e in events) e.id: e};
    final eventNames = {for (final e in events) e.id: e.name};

    // Their matches, and only theirs. A season's fixture list is every match
    // of every event; this page is one row of it.
    final theirs = [
      for (final f in fixtures)
        if (f.entrantAId == entrantId || f.entrantBId == entrantId) f,
    ];

    var displayName = '';
    for (final f in theirs) {
      displayName =
          f.entrantAId == entrantId ? f.entrantAName : f.entrantBName;
      if (displayName.isNotEmpty) break;
    }

    final upcoming = [
      for (final f in theirs)
        if (!f.status.isResulted && f.status != FixtureStatus.abandoned) f,
    ]..sort((a, b) {
        final at = a.scheduledAt;
        final bt = b.scheduledAt;
        // Untimed matches sort last rather than first: a match with no time
        // is not "next", it is not yet arranged.
        if (at == null && bt == null) return a.matchIndex.compareTo(b.matchIndex);
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });

    final played = [
      for (final f in theirs)
        if (f.status.isResulted) f,
    ]..sort((a, b) {
        final at = a.scheduledAt;
        final bt = b.scheduledAt;
        if (at == null && bt == null) return b.matchIndex.compareTo(a.matchIndex);
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

    var won = 0;
    var lost = 0;
    var drawn = 0;
    for (final f in played) {
      if (f.isDraw) {
        drawn++;
      } else if (f.winnerEntrantId == entrantId) {
        won++;
      } else if (f.winnerEntrantId != null) {
        lost++;
      }
    }

    // ---- Per-event runs ----
    final byComp = <String, List<Fixture>>{};
    for (final f in theirs) {
      byComp.putIfAbsent(f.compId, () => []).add(f);
    }

    const calc = StandingsCalculator();
    final runs = <SeasonEventRun>[];
    var titles = 0;

    for (final entry in byComp.entries) {
      final event = eventById[entry.key];
      if (event == null) continue;
      final mine = entry.value;

      // The whole event's matches, not just theirs — a group position cannot
      // be worked out from one team's results.
      final all = [
        for (final f in fixtures)
          if (f.compId == event.id) f,
      ];

      var eWon = 0;
      var eLost = 0;
      var ePlayed = 0;
      for (final f in mine) {
        if (!f.status.isResulted) continue;
        ePlayed++;
        if (f.winnerEntrantId == entrantId) {
          eWon++;
        } else if (f.winnerEntrantId != null) {
          eLost++;
        }
      }

      final groupId = mine
          .where((f) => f.bracket == Bracket.group && f.groupId != null)
          .map((f) => f.groupId!)
          .firstOrNull;

      int? rank;
      int? size;
      int? points;
      if (groupId != null) {
        final tables = calc.computeGroups(
          competition: event,
          entrants: _entrantsFrom(all, event),
          fixtures: all,
        );
        final table = tables[groupId];
        if (table != null) {
          size = table.length;
          for (var i = 0; i < table.length; i++) {
            if (table[i].entrantId == entrantId) {
              rank = i + 1;
              points = table[i].points;
              break;
            }
          }
        }
      }

      final decider = _deciderOf(event, all);
      final isChampion = decider != null && decider.winnerEntrantId == entrantId;
      final isRunnerUp = decider != null &&
          !isChampion &&
          (decider.entrantAId == entrantId || decider.entrantBId == entrantId);
      if (isChampion) titles++;

      final remaining = mine.where((f) => !f.status.isResulted).length;

      runs.add(SeasonEventRun(
        eventId: event.id,
        eventName: event.name,
        sportName: event.sportName,
        format: event.format,
        played: ePlayed,
        won: eWon,
        lost: eLost,
        remaining: remaining,
        groupId: groupId,
        groupRank: rank,
        groupSize: size,
        groupPoints: points,
        isChampion: isChampion,
        isRunnerUp: isRunnerUp,
        // Out, not merely finished: they have no matches left AND the event
        // does. An event that has finished entirely leaves everybody with
        // nothing left, and calling the champion "knocked out" would be a
        // remarkable way to report a title.
        isOut: remaining == 0 &&
            !isChampion &&
            all.any((f) => !f.status.isResulted),
      ));
    }

    runs.sort((a, b) {
      if (a.isChampion != b.isChampion) return a.isChampion ? -1 : 1;
      if (a.isRunnerUp != b.isRunnerUp) return a.isRunnerUp ? -1 : 1;
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return a.eventName.compareTo(b.eventName);
    });

    return SeasonEntrantRecord(
      entrantId: entrantId,
      displayName: displayName.isEmpty ? 'Entrant' : displayName,
      runs: runs,
      upcoming: upcoming,
      played: played,
      won: won,
      lost: lost,
      drawn: drawn,
      titles: titles,
      eventNames: eventNames,
    );
  }

  /// The match that decided an event. Mirrors the same rule
  /// `TournamentLeaderboard` uses: a league has no deciding match, because its
  /// title is settled by the table.
  static Fixture? _deciderOf(Competition event, List<Fixture> fixtures) {
    if (event.format == CompetitionFormat.roundRobin ||
        event.format == CompetitionFormat.leagueTable ||
        event.format == CompetitionFormat.swiss) {
      return null;
    }
    if (fixtures.isEmpty || fixtures.any((f) => !f.status.isResulted)) {
      return null;
    }
    final resulted = [
      for (final f in fixtures)
        if (f.winnerEntrantId != null && f.bracket != Bracket.group) f,
    ];
    if (resulted.isEmpty) return null;
    resulted.sort((a, b) {
      final byRound = b.round.compareTo(a.round);
      return byRound != 0 ? byRound : b.matchIndex.compareTo(a.matchIndex);
    });
    return resulted.first;
  }

  /// Entrant rows synthesized from the names the fixtures already carry, so a
  /// group position costs no extra reads. Same trade as
  /// `TournamentLeaderboard._entrantsFrom`.
  static List<Entrant> _entrantsFrom(
    List<Fixture> fixtures,
    Competition event,
  ) {
    final names = <String, String>{};
    for (final f in fixtures) {
      if (f.entrantAId.isNotEmpty) names[f.entrantAId] = f.entrantAName;
      if (f.entrantBId.isNotEmpty) names[f.entrantBId] = f.entrantBName;
    }
    return [
      for (final e in names.entries)
        Entrant(
          id: e.key,
          displayName: e.value,
          entrantType: event.entrantType,
        ),
    ];
  }
}
