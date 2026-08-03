import '../../core/models/competition.dart';
import '../../core/models/draw_slot.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/tournament.dart';

/// How far a competitor got in one event.
///
/// The unit every federation's ranking table is built from: what you win is
/// grade × how far you went, and nothing else about the matches matters.
enum FinishingRound {
  winner('winner', 'Winner', 100),
  runnerUp('runner_up', 'Runner-up', 60),
  semiFinal('semi_final', 'Semi-finalist', 36),
  quarterFinal('quarter_final', 'Quarter-finalist', 20),
  lastSixteen('last_16', 'Last 16', 11),
  lastThirtyTwo('last_32', 'Last 32', 6),
  groupStage('group_stage', 'Group stage', 3),
  participated('participated', 'Participated', 1);

  const FinishingRound(this.wire, this.label, this.share);

  final String wire;
  final String label;

  /// Relative worth of this finish, before the tournament's grade is applied.
  ///
  /// Roughly halving each round out, which is the shape every federation
  /// table uses — the gap between winning and losing the final is meant to be
  /// large, and the gap between the last 32 and the last 16 small. The exact
  /// figures are arbitrary until a real ranking list calibrates them, which is
  /// why they live here as one readable table rather than scattered as
  /// constants.
  final int share;

  static FinishingRound fromWire(String? w) => FinishingRound.values.firstWhere(
        (e) => e.wire == w,
        orElse: () => FinishingRound.participated,
      );
}

/// What one competitor earned from one event.
class RankingAward {
  const RankingAward({
    required this.entrantId,
    required this.displayName,
    required this.round,
    required this.points,
  });

  final String entrantId;
  final String displayName;
  final FinishingRound round;
  final int points;
}

/// Turns results into ranking points.
///
/// ## Why this exists alongside Glicko-2
///
/// They answer different questions and a sports body needs both. Glicko says
/// **how good you are** — a live estimate of strength that moves on every
/// match and can fall. Ranking points say **what you have won** — an
/// accumulated record of achievement over a rolling window, which is what
/// actually decides seeding, selection and funding everywhere in the world.
///
/// A player can be strong and unranked (they entered nothing) or ranked and
/// past their best (they won a lot last season). Collapsing the two into one
/// number loses the distinction that every selection meeting turns on.
///
/// Without this, winning a district championship changes nothing anybody can
/// see, which is exactly the complaint that started this work: results get
/// announced on a Telegram channel and then vanish.
class RankingPoints {
  const RankingPoints._();

  /// Points for one finish at one tournament grade.
  ///
  /// Grade multiplies rather than adds, because a national title should be
  /// worth more than several club ones and an additive scheme cannot express
  /// that without absurd numbers at the bottom.
  static int pointsFor({
    required TournamentGrade grade,
    required FinishingRound round,
  }) =>
      grade.weight * round.share;

  /// Works out how far everyone got in one event.
  ///
  /// ## Why the field size matters
  ///
  /// "Semi-finalist" means something different in a draw of 8 and a draw of
  /// 128, and a scheme that ignored that would let someone farm points from
  /// tiny events. So the round is derived from **how many were still in when
  /// the competitor went out**, not from a round label — which also handles
  /// byes, groups and double elimination without special-casing any of them.
  static List<RankingAward> award({
    required Tournament tournament,
    required Competition event,
    required List<Fixture> fixtures,
  }) {
    final decided = [
      for (final f in fixtures)
        if (f.status.isResulted && f.winnerEntrantId != null) f,
    ];
    if (decided.isEmpty) return const [];

    // Everyone who appeared, and the deepest round they were beaten in.
    final names = <String, String>{};
    final lastRound = <String, int>{};
    final everWon = <String>{};
    var deepestRound = 0;

    for (final f in decided) {
      for (final side in [
        (id: f.entrantAId, name: f.entrantAName),
        (id: f.entrantBId, name: f.entrantBName),
      ]) {
        if (side.id.isEmpty) continue;
        names[side.id] = side.name;
        final r = f.bracket == Bracket.group ? 0 : f.round;
        if (r > (lastRound[side.id] ?? -1)) lastRound[side.id] = r;
        if (r > deepestRound) deepestRound = r;
      }
      if (f.winnerEntrantId != null) everWon.add(f.winnerEntrantId!);
    }
    if (names.isEmpty) return const [];

    final champion = _championOf(event, decided);
    final finalist = _finalistOf(event, decided);

    final awards = <RankingAward>[];
    for (final entry in names.entries) {
      final reached = lastRound[entry.key] ?? 0;
      final round = _roundFor(
        entrantId: entry.key,
        champion: champion,
        finalist: finalist,
        lastRound: reached,
        deepestRound: deepestRound,
        playedGroupOnly: reached == 0,
        wonAnything: everWon.contains(entry.key),
      );
      awards.add(RankingAward(
        entrantId: entry.key,
        displayName: entry.value,
        round: round,
        points: pointsFor(grade: tournament.grade, round: round),
      ));
    }

    return awards
      ..sort((a, b) {
        final byPoints = b.points.compareTo(a.points);
        return byPoints != 0
            ? byPoints
            : a.displayName.compareTo(b.displayName);
      });
  }

  /// How far out from the final somebody went, expressed as a round.
  static FinishingRound _roundFor({
    required String entrantId,
    required String? champion,
    required String? finalist,
    required int lastRound,
    required int deepestRound,
    required bool playedGroupOnly,
    required bool wonAnything,
  }) {
    if (entrantId == champion) return FinishingRound.winner;
    if (entrantId == finalist) return FinishingRound.runnerUp;
    if (playedGroupOnly) {
      return wonAnything
          ? FinishingRound.groupStage
          : FinishingRound.participated;
    }

    // Rounds from the end: 1 = lost the semi-final, 2 = lost the quarter,
    // and so on. Derived from the bracket's actual depth rather than a
    // label, so a draw of 8 and a draw of 128 are scored differently.
    final fromEnd = deepestRound - lastRound;
    return switch (fromEnd) {
      <= 1 => FinishingRound.semiFinal,
      2 => FinishingRound.quarterFinal,
      3 => FinishingRound.lastSixteen,
      4 => FinishingRound.lastThirtyTwo,
      _ => FinishingRound.participated,
    };
  }

  static String? _championOf(Competition event, List<Fixture> decided) {
    final decider = _deciderOf(event, decided);
    return decider?.winnerEntrantId;
  }

  static String? _finalistOf(Competition event, List<Fixture> decided) {
    final decider = _deciderOf(event, decided);
    if (decider == null) return null;
    return decider.winnerEntrantId == decider.entrantAId
        ? decider.entrantBId
        : decider.entrantAId;
  }

  /// The match that settled the event. Null for a league, which has no
  /// deciding match — its title comes from the table, and nobody is a
  /// "runner-up" of a round robin in the sense a ranking table means.
  static Fixture? _deciderOf(Competition event, List<Fixture> decided) {
    if (event.format == CompetitionFormat.roundRobin ||
        event.format == CompetitionFormat.leagueTable ||
        event.format == CompetitionFormat.swiss) {
      return null;
    }
    final bracketMatches = [
      for (final f in decided)
        if (f.bracket != Bracket.group) f,
    ];
    if (bracketMatches.isEmpty) return null;
    bracketMatches.sort((a, b) {
      final byRound = b.round.compareTo(a.round);
      return byRound != 0 ? byRound : b.matchIndex.compareTo(a.matchIndex);
    });
    return bracketMatches.first;
  }
}
