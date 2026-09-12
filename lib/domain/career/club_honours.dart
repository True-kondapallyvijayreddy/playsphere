import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../tournament/tournament_overview.dart';

/// One title in a club's cabinet.
class ClubTitle {
  const ClubTitle({
    required this.competition,
    required this.championName,
    required this.championEntrantId,
    required this.wonByTheClub,
    required this.when,
  });

  final Competition competition;

  /// Who lifted it, as they were named on the day. Rule 31: the record
  /// survives the team renaming itself afterwards, so this is the snapshot,
  /// not a live lookup.
  final String championName;

  final String championEntrantId;

  /// True when the club ITSELF was the winning entrant — an accepted
  /// challenge or an inter-club event, where `entrantAId`/`entrantBId` are org
  /// ids. False for a title one of the club's own sides won at an event the
  /// club ran, which is still an honour but a different sentence.
  final bool wonByTheClub;

  final DateTime? when;

  String get sportId => competition.sportId;

  /// Whether this title was contested against somebody outside the club.
  ///
  /// A house championship is a real trophy and belongs on the board; it is
  /// not evidence the club beats other clubs, and an honours list that does
  /// not distinguish the two is the sort of thing a rival spots in a second.
  bool get isOpenTitle => competition.isInterClub || wonByTheClub;
}

/// A club's honours: what it has won, and what its people have won for it.
///
/// ## Why these are derived and not stored
///
/// Nothing in the schema records "champion". It does not need to: a bracket
/// is decided by its last match and a league by its table, and both are in
/// the fixtures already — [TournamentOverview.championOf] is the one
/// definition, shared with the tournament page so a trophy cabinet and a
/// tournament summary can never name two different winners of one event.
///
/// ## The guard that stops a half-played event minting a trophy
///
/// `championOf` refuses to name anybody while an unresulted fixture remains.
/// That check is only as good as the fixture list it is given, and the club
/// fixture stream deliberately carries finished matches ONLY — see
/// `CareerRepository.watchOrgFixtures` — so an event with three of five
/// matches played would look, from here, like a completed one.
///
/// Two conditions close that. The competition must say it is
/// [CompetitionStatus.completed], and the number of fixtures held for it must
/// match its own `fixtureCount`. Either alone is not enough: a status can be
/// set early by an organizer tidying up, and a `fixtureCount` can be stale on
/// an event nobody finished. Together they mean the event says it is over and
/// every match it claims to have is on the sheet.
class ClubHonours {
  const ClubHonours({required this.titles});

  static const empty = ClubHonours(titles: []);

  /// Most recent first.
  final List<ClubTitle> titles;

  bool get isEmpty => titles.isEmpty;

  /// Titles the club won as the club — the ones that say something about it
  /// against other clubs.
  List<ClubTitle> get openTitles => [
        for (final t in titles)
          if (t.isOpenTitle) t,
      ];

  /// Titles decided inside the club: its own sides winning its own events.
  List<ClubTitle> get internalTitles => [
        for (final t in titles)
          if (!t.isOpenTitle) t,
      ];

  List<ClubTitle> forSport(String sportId) {
    final base = sportId.split(':').first;
    return [
      for (final t in titles)
        if (t.sportId.split(':').first == base) t,
    ];
  }

  /// The sports this club has ever won something in.
  Set<String> get sportsWon => {
        for (final t in titles) t.sportId.split(':').first,
      };

  static ClubHonours forClub({
    required List<Competition> competitions,
    required List<Fixture> fixtures,
    required String orgId,
  }) {
    final byComp = <String, List<Fixture>>{};
    for (final f in fixtures) {
      // A draft placeholder is not a match anybody played, and counting one
      // towards `fixtureCount` would let an undrawn slot complete an event.
      if (f.isDraft) continue;
      byComp.putIfAbsent(f.compId, () => <Fixture>[]).add(f);
    }

    final titles = <ClubTitle>[];
    for (final c in competitions) {
      if (c.status != CompetitionStatus.completed) continue;
      final own = byComp[c.id];
      if (own == null || own.isEmpty) continue;
      // See the class doc: the fixture stream is finished-matches-only, so
      // the count is what proves nothing is still to be played.
      if (c.fixtureCount > 0 && own.length < c.fixtureCount) continue;

      final champion = TournamentOverview.championOf(c, own);
      if (champion == null) continue;

      DateTime? when;
      for (final f in own) {
        final at = f.completedAt ?? f.startedAt ?? f.scheduledAt;
        if (at != null && (when == null || at.isAfter(when))) when = at;
      }

      titles.add(ClubTitle(
        competition: c,
        championName: champion.displayName,
        championEntrantId: champion.entrantId,
        wonByTheClub: champion.entrantId == orgId,
        when: when ?? c.startDate,
      ));
    }

    titles.sort((a, b) {
      final at = a.when;
      final bt = b.when;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return ClubHonours(titles: titles);
  }
}
