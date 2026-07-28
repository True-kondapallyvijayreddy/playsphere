import '../scoring_plugin.dart';

/// One batter's line on the scorecard.
class BattingLine {
  const BattingLine({
    required this.playerId,
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.isOut,
    required this.battedYet,
    this.dismissal,
  });

  final String playerId;
  final String name;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final bool isOut;

  /// False for a batter who has not come to the crease. They appear on the
  /// card as "did not bat" rather than as 0 (0), which reads as a duck.
  final bool battedYet;

  /// "b Kumar", "c Reddy b Sharma", "run out (Rao)".
  final String? dismissal;

  /// Runs per hundred balls. Zero balls faced is 0, not a division by zero —
  /// a batter who came in and was run out without facing has no strike rate.
  double get strikeRate => balls == 0 ? 0 : (runs * 100) / balls;

  bool get isNotOut => battedYet && !isOut;
}

/// One bowler's line on the scorecard.
class BowlingLine {
  const BowlingLine({
    required this.playerId,
    required this.name,
    required this.legalBalls,
    required this.runsConceded,
    required this.wickets,
    required this.maidens,
    required this.wides,
    required this.noBalls,
    required this.ballsPerOver,
  });

  final String playerId;
  final String name;
  final int legalBalls;

  /// Runs off the bat plus wides plus no-balls. Byes and leg-byes are NOT
  /// charged to the bowler — they went past the bat, not off it, and charging
  /// them is the most common error in amateur bowling figures.
  final int runsConceded;

  /// Excludes run-outs: a bowler is not credited for a batter run out off
  /// their bowling.
  final int wickets;

  final int maidens;
  final int wides;
  final int noBalls;
  final int ballsPerOver;

  /// Overs as cricket writes them: completed overs, dot, balls into the
  /// current one. 47.2 means 47 overs and 2 balls.
  String get oversText => '${legalBalls ~/ ballsPerOver}.'
      '${legalBalls % ballsPerOver}';

  /// Overs as a NUMBER, for economy and net run rate. 47.2 overs is 47.333
  /// overs, never 47.4 — getting this wrong is what makes an NRR table wrong.
  double get oversDecimal => legalBalls / ballsPerOver;

  double get economy =>
      legalBalls == 0 ? 0 : runsConceded / (legalBalls / ballsPerOver);

  /// Runs per wicket. Null rather than infinity when wicketless, so the UI
  /// can print a dash.
  double? get average => wickets == 0 ? null : runsConceded / wickets;

  /// Balls per wicket.
  double? get strikeRate => wickets == 0 ? null : legalBalls / wickets;
}

/// A fall of wicket: "3-47 (Sharma, 12.4)".
class FallOfWicket {
  const FallOfWicket({
    required this.wicketNumber,
    required this.runs,
    required this.legalBalls,
    required this.playerId,
    required this.name,
    required this.ballsPerOver,
  });

  final int wicketNumber;
  final int runs;
  final int legalBalls;
  final String playerId;
  final String name;
  final int ballsPerOver;

  String get oversText =>
      '${legalBalls ~/ ballsPerOver}.${legalBalls % ballsPerOver}';
}

/// A full innings card — what a player screenshots and shares.
class InningsCard {
  const InningsCard({
    required this.battingSide,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
    required this.ballsPerOver,
    required this.extras,
    required this.batting,
    required this.bowling,
    required this.fallOfWickets,
    required this.isClosed,
  });

  final Side battingSide;
  final int runs;
  final int wickets;
  final int legalBalls;
  final int ballsPerOver;

  /// wide / noBall / bye / legBye → runs.
  final Map<String, int> extras;

  final List<BattingLine> batting;
  final List<BowlingLine> bowling;
  final List<FallOfWicket> fallOfWickets;
  final bool isClosed;

  int get extrasTotal => extras.values.fold(0, (a, b) => a + b);

  String get oversText =>
      '${legalBalls ~/ ballsPerOver}.${legalBalls % ballsPerOver}';

  double get oversDecimal => legalBalls / ballsPerOver;

  double get runRate => legalBalls == 0 ? 0 : runs / (legalBalls / ballsPerOver);

  /// The line every scoreboard shows: "142/6 (18.3)".
  String get headline => '$runs/$wickets ($oversText)';
}
