import '../../core/models/fixture.dart';
import '../../core/models/match_player.dart';
import '../scoring/player_stats.dart';
import '../scoring/scoring_registry.dart';

/// One person's contribution to a club, summed across every match they played
/// under it.
///
/// [id] is the line-up id — equal to the account uid for a registered player
/// and a generated local id for a guest, exactly as [MatchPlayer.id] defines
/// it. Both appear here: a village side that borrows a neighbour every Sunday
/// would otherwise show a top-scorer list with its top scorer missing. Only
/// the registered ones carry a [uid] and are therefore linkable to a profile.
class ClubPlayerLine {
  const ClubPlayerLine({
    required this.id,
    required this.name,
    required this.uid,
    required this.matches,
    required this.won,
    required this.mvps,
    required this.tally,
  });

  final String id;
  final String name;

  /// The PlaySphere account, when this player has one. Null for a guest.
  final String? uid;

  final int matches;
  final int won;

  /// Player-of-the-match awards — `Fixture.mvp`, which the engine computes
  /// from what the scorer recorded rather than from a vote. This is the
  /// number a club actually brags about, and it is the one honour a player
  /// can win in a losing side.
  final int mvps;

  /// Counters keyed exactly as the sport's engine keys them.
  final Map<String, num> tally;

  bool get isRegistered => uid != null;

  num operator [](String key) => tally[key] ?? 0;
}

/// A club's record in one sport.
///
/// ## What "won" means here, and why it is not simply [matches]
///
/// The aggregator this replaced refused a won/lost record outright, and its
/// reasoning was sound as far as it went: a fixture lives under exactly one
/// club's `orgId`,
/// and a school's house match is that club playing itself, where "the club
/// won" means nothing. What it missed is that some matches under a club's
/// `orgId` DO name the club itself as one of the two sides — every accepted
/// challenge does, because `CommunityRepository.acceptChallenge` writes the
/// two org ids straight into `entrantAId`/`entrantBId`. Those are club-vs-club
/// results and there is nothing ambiguous about them.
///
/// So the record is split rather than refused. [decided] counts the matches
/// where this club was a named side and a result exists; [won]/[lost]/[drawn]
/// partition it. [internal] counts the rest — the club's own sides playing
/// each other, and the events it hosted for other people — which are real
/// matches played and are counted in [matches], but contribute no result to
/// anybody's win rate. A screen that shows one number without the other is
/// how a club with forty house matches ends up looking like it has never won
/// anything.
class ClubSportRecord {
  const ClubSportRecord({
    required this.sportId,
    required this.matches,
    required this.won,
    required this.lost,
    required this.drawn,
    required this.internal,
    required this.tally,
    required this.players,
  });

  final String sportId;

  /// Every finished match — see [Fixture.countsTowardsRecords].
  final int matches;

  final int won;
  final int lost;
  final int drawn;

  /// Matches played under this club where the club was not itself a side:
  /// its own teams against each other, and events it hosted for others.
  final int internal;

  /// Every counter from every player who represented this club, summed.
  final Map<String, num> tally;

  /// Everyone who played for the club in this sport, best first — see
  /// [topPlayers] for what "best" means.
  final List<ClubPlayerLine> players;

  bool get isEmpty => matches == 0;

  /// Matches with a club-level result on them.
  int get decided => won + lost + drawn;

  /// Wins as a share of the matches that were actually decided.
  ///
  /// Draws sit outside the denominator, the same choice [ScopedStats.winRate]
  /// makes and for the same reason: a 60% record over ten matches means one
  /// thing with no draws in it and another with four.
  double? get winRate {
    final settled = won + lost;
    if (settled == 0) return null;
    return won / settled;
  }

  /// The tally keys this sport ranks its players on — cricket's runs and
  /// wickets, kabaddi's raid and tackle points. Empty for a sport that
  /// publishes none, which is a real answer rather than a fallback.
  List<String> get headlineStats =>
      ScoringRegistry.forSport(sportId).headlineStats;

  /// Player-of-the-match awards handed to this club's players in this sport.
  int get mvps {
    var total = 0;
    for (final p in players) {
      total += p.mvps;
    }
    return total;
  }

  /// The club's most-decorated players, by awards won.
  ///
  /// A separate list from [topPlayers] because it answers a different
  /// question. A top-scorer board rewards volume; this rewards being the best
  /// player on the day, which is what a club's own people argue about. Only
  /// players with at least one award appear — a list of nobodies with zero
  /// awards is not an honours board.
  List<ClubPlayerLine> mvpLeaders([int limit = 5]) {
    final ranked = [
      for (final p in players)
        if (p.mvps > 0) p,
    ]..sort((a, b) {
        final byAwards = b.mvps.compareTo(a.mvps);
        if (byAwards != 0) return byAwards;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return ranked.take(limit).toList(growable: false);
  }

  /// The club's leading players, by this sport's first headline stat.
  ///
  /// A sport with no headline stat falls back to appearances, which is the
  /// only ranking left that is honestly derivable — it says "these are the
  /// club's regulars", which is a true and useful thing to say, rather than
  /// picking an arbitrary counter and calling it form.
  List<ClubPlayerLine> topPlayers([int limit = 5]) {
    final key = headlineStats.isEmpty ? null : headlineStats.first;
    final ranked = [...players];
    ranked.sort((a, b) {
      if (key != null) {
        final byStat = b[key].compareTo(a[key]);
        if (byStat != 0) return byStat;
      }
      final byMatches = b.matches.compareTo(a.matches);
      if (byMatches != 0) return byMatches;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    // A row of zeroes under a "Top scorers" heading is not a leaderboard.
    // Where the sport has a stat to rank on, only players who registered
    // something on it qualify; where it has none, an appearance is the stat.
    final qualified = key == null
        ? ranked
        : [
            for (final p in ranked)
              if (p[key] != 0) p,
          ];
    return qualified.take(limit).toList(growable: false);
  }
}

/// Everything a club's match history says about it, in one pass.
///
/// Computed on the client from the same fixtures every other club screen
/// reads, the same choice `ScopedStats` makes for a player: a stored
/// aggregate is one more number that can drift away from the matches it
/// claims to summarize, and nobody can tell which of the two is wrong once
/// they disagree.
class ClubRecord {
  const ClubRecord({required this.sports});

  /// One row per sport the club has played, most-played first.
  final List<ClubSportRecord> sports;

  static const empty = ClubRecord(sports: []);

  bool get isEmpty => sports.isEmpty;

  int get matches => _sum((s) => s.matches);
  int get won => _sum((s) => s.won);
  int get lost => _sum((s) => s.lost);
  int get drawn => _sum((s) => s.drawn);
  int get internal => _sum((s) => s.internal);
  int get mvps => _sum((s) => s.mvps);
  int get decided => won + lost + drawn;

  double? get winRate {
    final settled = won + lost;
    if (settled == 0) return null;
    return won / settled;
  }

  /// How many different people have represented the club, across every sport.
  /// Counted once each: a player who plays both cricket and badminton for the
  /// club is one member of its playing strength, not two.
  int get playerCount => {
        for (final sport in sports)
          for (final p in sport.players) p.id,
      }.length;

  ClubSportRecord? forSport(String sportId) {
    final base = sportId.split(':').first;
    for (final s in sports) {
      if (s.sportId == base) return s;
    }
    return null;
  }

  int _sum(int Function(ClubSportRecord) of) {
    var total = 0;
    for (final s in sports) {
      total += of(s);
    }
    return total;
  }

  /// Builds the whole record in one pass over [fixtures].
  ///
  /// [fixtures] must already be scoped to [orgId] — `orgFixturesProvider`
  /// does that at the query — this does no org filtering of its own, exactly
  /// like `ClubSportStats.forFixtures` before it.
  static ClubRecord forFixtures({
    required List<Fixture> fixtures,
    required String orgId,
  }) {
    final matches = <String, int>{};
    final won = <String, int>{};
    final lost = <String, int>{};
    final drawn = <String, int>{};
    final internal = <String, int>{};
    final tally = <String, Map<String, num>>{};
    final players = <String, Map<String, _PlayerAcc>>{};

    for (final fixture in fixtures) {
      if (!fixture.countsTowardsRecords) continue;

      // Chess is rated per time control (`chess:blitz`); a club's record is
      // kept per sport, the same split every other career reader applies.
      final sportId = fixture.sport.split(':').first;
      matches[sportId] = (matches[sportId] ?? 0) + 1;

      final side = _clubSide(fixture, orgId);
      if (side == null) {
        internal[sportId] = (internal[sportId] ?? 0) + 1;
      } else {
        switch (_outcomeForSide(fixture, side)) {
          case _Outcome.won:
            won[sportId] = (won[sportId] ?? 0) + 1;
          case _Outcome.lost:
            lost[sportId] = (lost[sportId] ?? 0) + 1;
          case _Outcome.drawn:
            drawn[sportId] = (drawn[sportId] ?? 0) + 1;
          case null:
            // A named side with no winner recorded. Played, but nothing to
            // claim about it either way.
            break;
        }
      }

      final bucket = tally.putIfAbsent(sportId, () => <String, num>{});
      final roster = players.putIfAbsent(sportId, () => <String, _PlayerAcc>{});

      // Only the club's own players when the club is one of two sides;
      // everybody when the match is the club playing itself, where both
      // team sheets are its members.
      for (final entry in _representing(fixture, side)) {
        final acc = roster.putIfAbsent(
          entry.player.id,
          () => _PlayerAcc(entry.player),
        );
        acc.name = entry.player.name;
        acc.matches += 1;
        if (_outcomeForSide(fixture, entry.side) == _Outcome.won) {
          acc.won += 1;
        }
        if (fixture.mvp?.playerId == entry.player.id) acc.mvps += 1;
        for (final stat in PlayerTally.of(fixture.scoreState, entry.player.id)
            .entries) {
          acc.tally[stat.key] = (acc.tally[stat.key] ?? 0) + stat.value;
          bucket[stat.key] = (bucket[stat.key] ?? 0) + stat.value;
        }
      }
    }

    final sportIds = matches.keys.toList()
      ..sort((a, b) => (matches[b] ?? 0).compareTo(matches[a] ?? 0));

    return ClubRecord(
      sports: [
        for (final id in sportIds)
          ClubSportRecord(
            sportId: id,
            matches: matches[id] ?? 0,
            won: won[id] ?? 0,
            lost: lost[id] ?? 0,
            drawn: drawn[id] ?? 0,
            internal: internal[id] ?? 0,
            tally: tally[id] ?? const <String, num>{},
            players: [
              for (final acc in (players[id] ?? const <String, _PlayerAcc>{})
                  .values)
                acc.freeze(),
            ],
          ),
      ],
    );
  }

  /// Which side of this fixture the club itself is, or null when the club is
  /// not a named side.
  ///
  /// Deliberately looser than [Fixture.sideForOrg], which additionally
  /// insists on `participantOrgIds`. That field is the *authorization* record
  /// — the rules read it to widen a visiting club's access — and requiring it
  /// here would silently drop any club-vs-club fixture written before it
  /// existed, turning a real result into an unattributed one. Matching the
  /// entrant ids is the evidence; `participantOrgIds` is the permission.
  static String? _clubSide(Fixture fixture, String orgId) {
    if (fixture.entrantAId == orgId) return 'a';
    if (fixture.entrantBId == orgId) return 'b';
    return null;
  }

  static _Outcome? _outcomeForSide(Fixture fixture, String side) {
    if (fixture.isDraw) return _Outcome.drawn;
    final winner = fixture.winnerEntrantId;
    if (winner == null) return null;
    final theirs = side == 'a' ? fixture.entrantAId : fixture.entrantBId;
    return winner == theirs ? _Outcome.won : _Outcome.lost;
  }

  /// Everyone who played for this club in this fixture, with the side they
  /// played on.
  ///
  /// An individual event never fills a line-up — its competitors are named on
  /// the entrant document, which is why [Fixture.entrantAUid] exists — so a
  /// club's chess and badminton players would be absent from its own top-player
  /// list if only the line-ups were read. The entrant name is used for them
  /// because it is the only name the fixture carries for a side that is one
  /// person.
  static List<({MatchPlayer player, String side})> _representing(
    Fixture fixture,
    String? clubSide,
  ) {
    final out = <({MatchPlayer player, String side})>[];

    void addSide(String side) {
      final lineup = side == 'a' ? fixture.lineupA : fixture.lineupB;
      if (lineup.isNotEmpty) {
        for (final p in lineup) {
          out.add((player: p, side: side));
        }
        return;
      }
      final uid = side == 'a' ? fixture.entrantAUid : fixture.entrantBUid;
      if (uid == null || uid.isEmpty) return;
      out.add((
        player: MatchPlayer(
          id: uid,
          name: side == 'a' ? fixture.entrantAName : fixture.entrantBName,
          uid: uid,
        ),
        side: side,
      ));
    }

    if (clubSide == null) {
      addSide('a');
      addSide('b');
    } else {
      addSide(clubSide);
    }
    return out;
  }
}

enum _Outcome { won, lost, drawn }

class _PlayerAcc {
  _PlayerAcc(MatchPlayer player)
      : id = player.id,
        name = player.name,
        uid = player.uid;

  final String id;
  String name;
  final String? uid;
  int matches = 0;
  int won = 0;
  int mvps = 0;
  final Map<String, num> tally = <String, num>{};

  ClubPlayerLine freeze() => ClubPlayerLine(
        id: id,
        name: name,
        uid: uid,
        matches: matches,
        won: won,
        mvps: mvps,
        tally: Map.unmodifiable(tally),
      );
}
