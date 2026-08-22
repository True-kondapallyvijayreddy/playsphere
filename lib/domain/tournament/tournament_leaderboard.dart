import '../../core/models/competition.dart';
import '../../core/models/draw_slot.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../standings/standings_calculator.dart';

/// One competitor's record across the whole tournament.
class PlayerRecord {
  const PlayerRecord({
    required this.entrantId,
    required this.displayName,
    required this.played,
    required this.won,
    required this.lost,
    required this.eventIds,
    required this.titles,
    required this.finals,
    this.sportIds = const {},
  });

  final String entrantId;
  final String displayName;
  final int played;
  final int won;
  final int lost;

  /// Which events they appeared in — a player entered in singles, doubles and
  /// mixed has three.
  final Set<String> eventIds;

  /// Which sports those events were. A multi-sport season's board is filtered
  /// on this; a single-sport one has one entry here and never shows the
  /// filter at all.
  final Set<String> sportIds;

  /// Events won outright.
  final int titles;

  /// Events where they reached the deciding match, won or lost.
  final int finals;

  int get eventsEntered => eventIds.length;

  /// Wins as a share of matches played. Null below three matches: a player who
  /// won their only match is not on 100% in any sense worth printing, and a
  /// leaderboard that says so is worse than one that stays quiet.
  double? get winRate => played < 3 ? null : won / played;
}

/// One group's state, compact enough to show without opening the event.
class GroupSummary {
  const GroupSummary({
    required this.eventId,
    required this.eventName,
    required this.groupId,
    required this.leader,
    required this.leaderPoints,
    required this.played,
    required this.total,
    required this.qualifiers,
    required this.table,
  });

  final String eventId;
  final String eventName;
  final String groupId;

  /// Top of the table right now. Null before anyone has played.
  final String? leader;
  final int leaderPoints;

  final int played;
  final int total;

  /// How many go through, so the summary can say what is at stake.
  final int qualifiers;

  /// The full ordered table, for the expanded view.
  final List<Standing> table;

  int get remaining => total - played;

  bool get isComplete => total > 0 && played == total;

  /// Whether the qualifying places are already settled — nobody outside them
  /// can still catch the last qualifying position.
  ///
  /// Uses the crude but honest bound of three points per remaining match. It
  /// answers "is this group still live?" and deliberately never claims
  /// certainty it does not have: a group it calls live may in fact be decided
  /// on a tiebreak, and that is the safe direction to be wrong in.
  bool get isDecided {
    if (isComplete) return true;
    if (table.length <= qualifiers) return true;
    final cutoff = table[qualifiers - 1].points;
    final chaser = table[qualifiers];
    final maxGain = (total ~/ table.length + 1) * 3;
    return chaser.points + maxGain < cutoff;
  }
}

/// Tournament-wide boards derived from every match in it.
///
/// ## Why this is separate from the per-event tables
///
/// A points table answers "who is winning this draw". Neither of the two
/// questions people actually ask at a tournament is answerable from it: *how
/// are the groups doing overall* — which otherwise means opening fifteen
/// events one at a time — and *who has had the best tournament*, which spans
/// every event and no single table can see.
class TournamentLeaderboard {
  const TournamentLeaderboard({
    required this.players,
    required this.groups,
    this.bySport = const {},
    this.sportNames = const {},
  });

  /// Best record first.
  final List<PlayerRecord> players;

  /// Every group across every event, ordered by event then group.
  final List<GroupSummary> groups;

  /// The same board computed WITHIN each sport, keyed by sport id.
  ///
  /// ## Why this is not the combined board filtered
  ///
  /// A filter would keep whole rows, and a row's numbers are cross-sport:
  /// somebody who played six badminton matches and two cricket ones has
  /// `played: 8` on the combined board, and showing that row under "Badminton"
  /// prints 8 for a player who played 6. The win rate is wrong by the same
  /// amount, and the ordering is wrong in a way nobody can see.
  ///
  /// So each sport's board is accumulated separately over that sport's matches
  /// only. A five-sport season computes six boards in one pass over the
  /// fixtures, which is what makes the dropdown free.
  final Map<String, List<PlayerRecord>> bySport;

  /// Sport id to its display name, for labelling the filter.
  final Map<String, String> sportNames;

  /// Sport ids present, in display-name order.
  List<String> get sportIds {
    final ids = bySport.keys.toList();
    ids.sort((a, b) =>
        (sportNames[a] ?? a).compareTo(sportNames[b] ?? b));
    return ids;
  }

  /// Whether a sport filter is worth showing. One sport is not a choice.
  bool get isMultiSport => bySport.length > 1;

  /// The board for one sport, or the combined board when [sportId] is null.
  List<PlayerRecord> playersFor(String? sportId) =>
      sportId == null ? players : (bySport[sportId] ?? const []);

  /// The headline board — most titles, then most wins.
  List<PlayerRecord> top([int limit = 10]) => players.take(limit).toList();

  /// The same, within one sport.
  List<PlayerRecord> topFor(String? sportId, [int limit = 10]) =>
      playersFor(sportId).take(limit).toList();

  bool get hasGroups => groups.isNotEmpty;

  /// Groups still capable of changing who goes through.
  List<GroupSummary> get liveGroups => [
        for (final g in groups)
          if (!g.isDecided) g,
      ];

  static TournamentLeaderboard from({
    required List<Competition> events,
    required List<Fixture> fixtures,
  }) {
    final byComp = <String, List<Fixture>>{};
    for (final f in fixtures) {
      byComp.putIfAbsent(f.compId, () => []).add(f);
    }

    final records = <String, _Record>{};

    // The same accumulation again, once per sport, keyed `sportId|entrantId`.
    // Not a filter over [records] — see [TournamentLeaderboard.bySport] for
    // why a filtered row prints the wrong numbers.
    final perSport = <String, Map<String, _Record>>{};
    final sportNames = <String, String>{};

    final groups = <GroupSummary>[];
    const calc = StandingsCalculator();

    for (final event in events) {
      final own = byComp[event.id] ?? const <Fixture>[];
      final sportId = event.sportId;
      sportNames[sportId] = event.sportName;
      final sportRecords = perSport.putIfAbsent(sportId, () => {});

      // ---- Per-player record ----
      for (final f in own) {
        // A walkover awards the match but nobody played it, so counting it as
        // a win on a "best tournament" board would rank turning up above
        // playing well. The result still stands in the draw; it just is not
        // evidence of a good tournament.
        if (!f.status.isResulted ||
            f.resultType == MatchResultType.walkover ||
            f.resultType == MatchResultType.noShow ||
            f.resultType == MatchResultType.conceded) {
          continue;
        }
        if (f.entrantAId.isEmpty || f.entrantBId.isEmpty) continue;

        for (final side in [
          (id: f.entrantAId, name: f.entrantAName),
          (id: f.entrantBId, name: f.entrantBName),
        ]) {
          for (final r in [
            records.putIfAbsent(side.id, () => _Record(side.id, side.name)),
            sportRecords.putIfAbsent(
              side.id,
              () => _Record(side.id, side.name),
            ),
          ]) {
            r.played++;
            r.eventIds.add(event.id);
            r.sportIds.add(sportId);
            if (f.winnerEntrantId == side.id) {
              r.won++;
            } else if (f.winnerEntrantId != null) {
              r.lost++;
            }
          }
        }
      }

      // ---- Titles and finals ----
      final decider = _deciderOf(event, own);
      if (decider != null) {
        final winnerId = decider.winnerEntrantId;
        for (final id in [decider.entrantAId, decider.entrantBId]) {
          if (id.isEmpty) continue;
          for (final r in [records[id], sportRecords[id]]) {
            if (r == null) continue;
            r.finals++;
            if (id == winnerId) r.titles++;
          }
        }
      }

      // ---- Group summaries ----
      final tables = calc.computeGroups(
        competition: event,
        entrants: _entrantsFrom(own, event),
        fixtures: own,
      );
      final ids = tables.keys.toList()..sort();
      for (final groupId in ids) {
        final table = tables[groupId]!;
        final inGroup = [
          for (final f in own)
            if (f.bracket == Bracket.group && f.groupId == groupId) f,
        ];
        groups.add(GroupSummary(
          eventId: event.id,
          eventName: event.name,
          groupId: groupId,
          leader: table.isEmpty ? null : table.first.displayName,
          leaderPoints: table.isEmpty ? 0 : table.first.points,
          played: inGroup.where((f) => f.status.isResulted).length,
          total: inGroup.length,
          qualifiers: event.drawConfig.qualifiersPerGroup,
          table: table,
        ));
      }
    }

    final players = _rank(records.values);
    final bySport = <String, List<PlayerRecord>>{};
    for (final entry in perSport.entries) {
      // A sport nobody has finished a match in yet has no board to show, and
      // an empty option in the filter is worse than no option.
      if (entry.value.isEmpty) continue;
      bySport[entry.key] = _rank(entry.value.values);
    }

    groups.sort((a, b) {
      final byEvent = a.eventName.compareTo(b.eventName);
      return byEvent != 0 ? byEvent : a.groupId.compareTo(b.groupId);
    });

    return TournamentLeaderboard(
      players: players,
      groups: groups,
      bySport: bySport,
      sportNames: sportNames,
    );
  }

  /// Turns raw tallies into the ordered board.
  ///
  /// Titles first — a tournament is won, not accumulated — then finals
  /// reached, then matches won, then fewest played (a player who won six from
  /// six had a better tournament than one who won six from ten), and finally
  /// name so the board is stable rather than arbitrary.
  static List<PlayerRecord> _rank(Iterable<_Record> records) => records
      .map((r) => PlayerRecord(
            entrantId: r.id,
            displayName: r.name,
            played: r.played,
            won: r.won,
            lost: r.lost,
            eventIds: r.eventIds,
            sportIds: r.sportIds,
            titles: r.titles,
            finals: r.finals,
          ))
      .toList()
    ..sort((a, b) {
      final byTitles = b.titles.compareTo(a.titles);
      if (byTitles != 0) return byTitles;
      final byFinals = b.finals.compareTo(a.finals);
      if (byFinals != 0) return byFinals;
      final byWon = b.won.compareTo(a.won);
      if (byWon != 0) return byWon;
      final byPlayed = a.played.compareTo(b.played);
      if (byPlayed != 0) return byPlayed;
      return a.displayName.compareTo(b.displayName);
    });

  /// The match that decided an event, for titles and finals.
  ///
  /// Only for bracket formats. A league has no deciding match — its title is
  /// settled by the table, and crediting "a final" to whoever happened to play
  /// in the last round of fixtures would be meaningless.
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
  /// tournament-wide board costs no extra reads. See
  /// `StandingsCalculator.computeFromFixtures` for the same trade.
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

class _Record {
  _Record(this.id, this.name);

  final String id;
  final String name;
  int played = 0;
  int won = 0;
  int lost = 0;
  int titles = 0;
  int finals = 0;
  final Set<String> eventIds = {};
  final Set<String> sportIds = {};
}
