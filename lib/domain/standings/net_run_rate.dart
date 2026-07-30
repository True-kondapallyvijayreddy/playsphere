import '../scoring/plugins/cricket_plugin.dart';
import '../scoring/scoring_plugin.dart';

/// One team's batting or bowling record in a single completed innings, in the
/// form net run rate needs it.
class InningsRecord {
  const InningsRecord({
    required this.battingSide,
    required this.runs,
    required this.legalBalls,
    required this.wickets,
    required this.allOut,
    required this.allottedBalls,
  });

  /// 'a' or 'b'.
  final String battingSide;
  final int runs;
  final int legalBalls;
  final int wickets;

  /// Whether the side lost all its wickets.
  final bool allOut;

  /// The full quota this innings was entitled to, in balls.
  final int allottedBalls;

  /// The balls this innings counts as having faced, for net run rate.
  ///
  /// **This is the rule everyone gets wrong.** A side bowled out is charged
  /// its FULL allotted overs, not the overs it actually survived. Without it,
  /// a team dismissed for 60 in 12 overs would show a run rate of 5.00 — the
  /// same as a side that scored 100 in 20 — and the table would reward
  /// collapsing quickly.
  ///
  /// A side that was chasing and won does not get this treatment: it stopped
  /// because it had won, not because it ran out of resources.
  int get ballsForRate => allOut ? allottedBalls : legalBalls;

  /// Overs as a decimal: balls / 6, never the "47.2 means 47.2" mistake that
  /// makes every rate in the table wrong.
  double oversForRate(int ballsPerOver) =>
      ballsPerOver <= 0 ? 0 : ballsForRate / ballsPerOver;
}

/// Running net-run-rate totals for one entrant across a competition.
class NrrTally {
  double runsScored = 0;
  double oversFaced = 0;
  double runsConceded = 0;
  double oversBowled = 0;

  void addBatting(double runs, double overs) {
    runsScored += runs;
    oversFaced += overs;
  }

  void addBowling(double runs, double overs) {
    runsConceded += runs;
    oversBowled += overs;
  }

  bool get hasData => oversFaced > 0 || oversBowled > 0;

  /// Net run rate: runs scored per over faced, less runs conceded per over
  /// bowled. Reported to three decimals, which is the precision every league
  /// table in the sport publishes.
  double? get value {
    if (oversFaced <= 0 || oversBowled <= 0) return null;
    final forRate = runsScored / oversFaced;
    final againstRate = runsConceded / oversBowled;
    return double.parse((forRate - againstRate).toStringAsFixed(3));
  }
}

/// Reads completed innings out of a cricket match's projected state.
///
/// Lives here rather than on the plugin because net run rate is a
/// *competition* concern: the engine's job ends at the scorecard.
class NetRunRate {
  const NetRunRate._();

  /// Formats a net run rate the way a table prints it: three decimals, with
  /// an explicit sign, and a dash when there is nothing to report.
  static String format(double? nrr) {
    if (nrr == null) return '—';
    final s = nrr.abs().toStringAsFixed(3);
    if (nrr > 0) return '+$s';
    if (nrr < 0) return '-$s';
    return '0.000';
  }

  /// Extracts both innings from a cricket fixture's score state.
  ///
  /// Returns an empty list for any sport that is not cricket, or for a match
  /// whose innings never started — a table must not be moved by a fixture
  /// that has no runs in it.
  static List<InningsRecord> inningsOf({
    required Map<String, dynamic> scoreState,
    required ScoringContext ctx,
    required String pluginKey,
  }) {
    if (pluginKey != CricketPlugin.pluginKey) return const [];

    final raw = scoreState['innings'];
    if (raw is! List) return const [];

    final ballsPerOver = ctx.intConfig('ballsPerOver', 6);
    final oversPerInnings = ctx.intConfig('oversPerInnings', 20);
    final wicketsAllowed = ctx.intConfig('playersPerTeam', 11) - 1;
    final allottedBalls = oversPerInnings * ballsPerOver;

    final out = <InningsRecord>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final legalBalls = ((entry['legalBalls'] as num?) ?? 0).toInt();
      final runs = ((entry['runs'] as num?) ?? 0).toInt();
      final wickets = ((entry['wickets'] as num?) ?? 0).toInt();
      // An innings nobody batted in contributes nothing.
      if (legalBalls == 0 && runs == 0) continue;

      out.add(InningsRecord(
        battingSide: (entry['battingSide'] as String?) ?? 'a',
        runs: runs,
        legalBalls: legalBalls,
        wickets: wickets,
        allOut: wicketsAllowed > 0 && wickets >= wicketsAllowed,
        allottedBalls: allottedBalls,
      ));
    }
    return out;
  }
}
