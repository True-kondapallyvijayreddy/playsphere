import '../../core/models/fixture.dart';

/// One player's record against one opponent, across every match they have
/// ever played.
class HeadToHeadRecord {
  const HeadToHeadRecord({
    required this.opponentUid,
    required this.opponentName,
    required this.played,
    required this.won,
    required this.lost,
    required this.lastMet,
    required this.sportIds,
  });

  final String opponentUid;
  final String opponentName;
  final int played;
  final int won;
  final int lost;

  /// When they last met. The thing anybody actually wants alongside the
  /// record — "3-2, but you have not played since 2023" is a different fact
  /// from "3-2 this season".
  final DateTime? lastMet;

  /// Sports they have met in. A rivalry can span more than one.
  final Set<String> sportIds;

  int get drawn => played - won - lost;

  /// "3-2" from the subject's point of view.
  String get line => '$won–$lost';

  bool get isAhead => won > lost;
  bool get isLevel => won == lost;
}

/// Who a player has faced, and how they have done.
///
/// ## Why this cannot come from career statistics
///
/// A career profile aggregates *totals* — matches, wins, a rating. It cannot
/// answer the question people actually ask about a rival, which is not "how
/// good is he" but "how do I do against him". Those are different facts, and a
/// player who is 400 points lower rated can still be 4–1 up.
///
/// ## Built from fixtures, not stored
///
/// A head-to-head is a pure function of the matches. Storing it would mean a
/// write per player per result and a number that can silently disagree with
/// the matches behind it.
class HeadToHead {
  const HeadToHead._();

  /// Every opponent [uid] has faced, best-known record first.
  ///
  /// [fixtures] should be the matches this player appeared in. Only decided,
  /// genuinely-played matches count: a walkover says nothing about how two
  /// players match up, which is the only thing this table is for.
  static List<HeadToHeadRecord> forPlayer({
    required String uid,
    required List<Fixture> fixtures,
  }) {
    final records = <String, _Tally>{};

    for (final f in fixtures) {
      if (!f.status.isResulted) continue;
      if (!f.resultType.countsForCareerStats) continue;

      final mine = _sideOf(uid, f);
      if (mine == null) continue;

      // Everyone on the other side. In doubles that is two opponents, and a
      // head-to-head against a *pair* is not a thing anybody asks for — the
      // question is always about a person.
      //
      // An individual event names nobody in a line-up: its entrant id IS the
      // player's uid. Falling back to the entrant is what makes this work for
      // singles, which is the overwhelming majority of what it is read for.
      final lineup = mine == 'a' ? f.lineupB : f.lineupA;
      final opponents = lineup.isNotEmpty
          ? [
              for (final p in lineup)
                if (p.uid != null) (uid: p.uid!, name: p.name),
            ]
          : [
              if (mine == 'a' && f.entrantBId.isNotEmpty)
                (uid: f.entrantBId, name: f.entrantBName)
              else if (mine == 'b' && f.entrantAId.isNotEmpty)
                (uid: f.entrantAId, name: f.entrantAName),
            ];

      final won = mine == 'a'
          ? f.winnerEntrantId == f.entrantAId
          : f.winnerEntrantId == f.entrantBId;

      for (final opponent in opponents) {
        final opponentUid = opponent.uid;
        if (opponentUid == uid) continue;

        final tally = records.putIfAbsent(
          opponentUid,
          () => _Tally(opponentUid, opponent.name),
        );
        tally.name = opponent.name;
        tally.played++;
        if (f.isDraw) {
          // Neither counted as a win or a loss; `drawn` derives from the gap.
        } else if (won) {
          tally.won++;
        } else {
          tally.lost++;
        }
        if (f.sportId != null) tally.sports.add(f.sportId!);

        final at = f.completedAt ?? f.scheduledAt;
        if (at != null && (tally.lastMet == null || at.isAfter(tally.lastMet!))) {
          tally.lastMet = at;
        }
      }
    }

    final rows = [
      for (final t in records.values)
        HeadToHeadRecord(
          opponentUid: t.uid,
          opponentName: t.name,
          played: t.played,
          won: t.won,
          lost: t.lost,
          lastMet: t.lastMet,
          sportIds: t.sports,
        ),
    ];

    // Most-played first — a rivalry is measured in meetings, and an opponent
    // faced once is not a rivalry however the single match went. Ties break on
    // the most recent meeting, then on name so the list is stable.
    rows.sort((a, b) {
      final byPlayed = b.played.compareTo(a.played);
      if (byPlayed != 0) return byPlayed;
      final byRecency = (b.lastMet ?? DateTime(0)).compareTo(
        a.lastMet ?? DateTime(0),
      );
      if (byRecency != 0) return byRecency;
      return a.opponentName.compareTo(b.opponentName);
    });

    return rows;
  }

  /// The record between exactly two players, or null if they have never met.
  static HeadToHeadRecord? between({
    required String uid,
    required String opponentUid,
    required List<Fixture> fixtures,
  }) {
    final all = forPlayer(uid: uid, fixtures: fixtures);
    for (final r in all) {
      if (r.opponentUid == opponentUid) return r;
    }
    return null;
  }

  /// Which side of a fixture a player was on, or null if they were on neither.
  static String? _sideOf(String uid, Fixture f) {
    if (f.lineupA.any((p) => p.uid == uid)) return 'a';
    if (f.lineupB.any((p) => p.uid == uid)) return 'b';
    // An individual event names its competitor on the entrant rather than in a
    // line-up, so the entrant id is the uid.
    if (f.entrantAId == uid) return 'a';
    if (f.entrantBId == uid) return 'b';
    return null;
  }
}

class _Tally {
  _Tally(this.uid, this.name);

  final String uid;
  String name;
  int played = 0;
  int won = 0;
  int lost = 0;
  DateTime? lastMet;
  final Set<String> sports = {};
}
