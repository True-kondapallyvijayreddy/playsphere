import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../standings/standings_calculator.dart';

/// One event's line in a tournament summary.
class EventSummary {
  const EventSummary({
    required this.competition,
    required this.total,
    required this.played,
    required this.live,
    required this.champion,
  });

  final Competition competition;
  final int total;
  final int played;
  final int live;

  /// Named once the final has a winner. This is the row a medal table is
  /// built from, and it is derived rather than stored so it cannot disagree
  /// with the match that produced it.
  final String? champion;

  int get remaining => total - played;

  double get progress => total == 0 ? 0 : played / total;

  bool get isComplete => total > 0 && played == total;

  bool get hasStarted => played > 0 || live > 0;
}

/// The high-level state of a whole tournament, derived from its events and
/// every fixture across them.
///
/// Everything here is computed, never stored. A tournament's progress is a
/// pure function of its matches, and persisting it would mean a second write
/// on every result, a second thing to keep in step, and a headline number
/// that can silently disagree with the matches it claims to summarise.
class TournamentOverview {
  const TournamentOverview({
    required this.events,
    required this.totalMatches,
    required this.playedMatches,
    required this.liveMatches,
    required this.onCourtNow,
    required this.upNext,
    required this.scheduledThrough,
  });

  final List<EventSummary> events;

  final int totalMatches;
  final int playedMatches;
  final int liveMatches;

  /// Being played right now — the board a spectator walking into the hall
  /// wants, and the one an organizer glances at between matches.
  final List<Fixture> onCourtNow;

  /// The next matches due to start, soonest first.
  final List<Fixture> upNext;

  /// When the last scheduled match is due to begin. Null when nothing has
  /// been scheduled, which is a different thing from "finishes now".
  final DateTime? scheduledThrough;

  int get remainingMatches => totalMatches - playedMatches;

  double get progress => totalMatches == 0 ? 0 : playedMatches / totalMatches;

  bool get isComplete => totalMatches > 0 && playedMatches == totalMatches;

  int get completedEvents => events.where((e) => e.isComplete).length;

  /// Events with a champion, for the honours board. Ordered by name so the
  /// board is stable as results land rather than reshuffling on each one.
  List<EventSummary> get champions => [
        for (final e in events)
          if (e.champion != null) e,
      ]..sort((a, b) => a.competition.name.compareTo(b.competition.name));

  /// Builds the overview from what the screen already has streamed.
  ///
  /// Takes fixtures for the whole tournament in one list rather than per
  /// event, because that is how they arrive — see
  /// `TournamentRepository.watchFixtures` for why that is one query.
  static TournamentOverview from({
    required List<Competition> events,
    required List<Fixture> fixtures,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final byComp = <String, List<Fixture>>{};
    for (final f in fixtures) {
      byComp.putIfAbsent(f.compId, () => []).add(f);
    }

    final summaries = <EventSummary>[];
    var total = 0;
    var played = 0;
    var live = 0;

    for (final event in events) {
      final own = byComp[event.id] ?? const <Fixture>[];
      final ownPlayed = own.where((f) => f.status.isResulted).length;
      final ownLive = own.where((f) => f.isLive).length;

      total += own.length;
      played += ownPlayed;
      live += ownLive;

      summaries.add(EventSummary(
        competition: event,
        total: own.length,
        played: ownPlayed,
        live: ownLive,
        champion: _championOf(event, own),
      ));
    }

    summaries.sort((a, b) => a.competition.name.compareTo(b.competition.name));

    final scheduled = [
      for (final f in fixtures)
        if (f.scheduledAt != null) f.scheduledAt!,
    ];

    return TournamentOverview(
      events: summaries,
      totalMatches: total,
      playedMatches: played,
      liveMatches: live,
      onCourtNow: [
        for (final f in fixtures)
          if (f.isLive) f,
      ],
      upNext: [
        for (final f in fixtures)
          if (f.status == FixtureStatus.scheduled &&
              f.scheduledAt != null &&
              f.scheduledAt!.isAfter(clock.subtract(const Duration(minutes: 15))))
            f,
      ].take(8).toList(),
      scheduledThrough: scheduled.isEmpty
          ? null
          : scheduled.reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  /// Who won an event, by the definition that actually applies to its format.
  ///
  /// A bracket is decided by its last match; a league is decided by its table.
  /// Using one rule for both was wrong and silently so: in a round robin the
  /// deepest resulted round is simply the final round of fixtures, and its
  /// winner is whoever happened to win that one match — which is very often
  /// not the team top of the table.
  ///
  /// For brackets the rule is still "deepest resulted round" rather than
  /// "the fixture labelled Final", because a groups draw numbers two phases
  /// from 1 and a double-elimination reset may never be played.
  ///
  /// Nobody is champion until every match is done: a leader mid-event is not
  /// a winner.
  static String? _championOf(Competition event, List<Fixture> fixtures) {
    if (fixtures.isEmpty) return null;
    if (fixtures.any((f) => !f.status.isResulted)) return null;

    if (_tableFormats.contains(event.format)) {
      final table = const StandingsCalculator()
          .computeFromFixtures(competition: event, fixtures: fixtures);
      return table.isEmpty ? null : table.first.displayName;
    }

    final resulted = [
      for (final f in fixtures)
        if (f.winnerEntrantId != null) f,
    ];
    if (resulted.isEmpty) return null;

    resulted.sort((a, b) {
      final byRound = b.round.compareTo(a.round);
      return byRound != 0 ? byRound : b.matchIndex.compareTo(a.matchIndex);
    });
    final decider = resulted.first;
    return decider.winnerEntrantId == decider.entrantAId
        ? decider.entrantAName
        : decider.entrantBName;
  }

  /// Formats decided by a table rather than by a last match.
  ///
  /// `groupThenKnockout` is deliberately absent: its groups feed a bracket,
  /// and the bracket decides it.
  static const _tableFormats = {
    CompetitionFormat.roundRobin,
    CompetitionFormat.leagueTable,
    CompetitionFormat.swiss,
  };
}
