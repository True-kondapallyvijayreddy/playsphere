import '../scoring/rule_config.dart';

/// How long one match of a sport actually takes, worked out from the ruleset
/// rather than asked for as a number.
///
/// ## Why this exists
///
/// Every screen that builds a season asked the organizer "minutes per match?"
/// and defaulted it to 30. Thirty minutes is right for a badminton game and
/// absurd for a T20 innings, so a cricket season built on the default packed
/// twelve three-hour matches into a day that holds four — and nothing said so
/// until the timetable came out with matches at 2am, or the generator gave up.
///
/// The organizer already told us the answer: they picked cricket, and the
/// ruleset says twenty overs a side. Twenty overs a side is three and a bit
/// hours in every ground in the country. Deriving the number from the rules
/// means the default is right for the sport being played, and the organizer
/// still overrides it when their ground turns matches around faster.
///
/// ## What the numbers are
///
/// Playing time plus the breaks that are part of the fixture — an innings
/// interval, half time, a knock-up — because a court is occupied for all of
/// it. They are deliberately *generous* rather than optimistic: a season
/// planned on optimistic durations overruns, and overrunning is the failure
/// this is meant to prevent. Turnaround between two different matches is a
/// separate number and belongs to the venue, not here.
///
/// Every figure is rounded to five minutes. Nobody schedules a 187-minute
/// match, and a slot grid built on round numbers is one an organizer can read.
class MatchDuration {
  const MatchDuration._();

  /// The floor and ceiling any estimate is clamped into. Ten minutes is
  /// shorter than any real fixture including its knock-up; eight hours is
  /// longer than anything this product schedules, a two-innings red-ball day
  /// included.
  static const int minMinutes = 10;
  static const int maxMinutes = 8 * 60;

  /// A whole day, for the venue that is booked out and lit.
  static const int fallbackMinutes = 45;

  /// Minutes one match of [sportId] takes under [rules].
  ///
  /// [rules] is the sport's resolved rule map — `SportSpec.config`, or the
  /// event's own `scoringConfig` once it has one. Passing null uses the
  /// sport's default preset, which is what a season being created has.
  static int estimate({required String sportId, Map<String, dynamic>? rules}) {
    final config = RuleConfig.fromMap(
      rules ?? RulePresets.resolve(sportId: sportId).toMap(),
    );

    final raw = _rawMinutes(sportId: sportId, config: config);
    return _round5(raw.clamp(minMinutes, maxMinutes));
  }

  /// The same figure with the reasoning attached — "20 overs a side · about
  /// 3h 15m" — so the organizer can see WHY the season is asking for that
  /// much ground time instead of being handed a number to argue with.
  static String explain({
    required String sportId,
    Map<String, dynamic>? rules,
  }) {
    final config = RuleConfig.fromMap(
      rules ?? RulePresets.resolve(sportId: sportId).toMap(),
    );
    final minutes = estimate(sportId: sportId, rules: rules);
    final shape = _shapeLabel(sportId: sportId, config: config);
    return shape == null ? format(minutes) : '$shape · ${format(minutes)}';
  }

  /// "3h 15m", "45m". The one place match lengths are written for a human.
  static String format(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static int _rawMinutes({
    required String sportId,
    required RuleConfig config,
  }) {
    // --- Innings sports: cricket ------------------------------------------
    //
    // Two innings at roughly four and a half minutes an over — the figure
    // club cricket actually runs at once drinks, wickets and fetching the
    // ball out of the maize are counted — plus the interval between them.
    if (config.has('oversPerInnings')) {
      final overs = config.getInt('oversPerInnings', 20);
      if (overs > 0) {
        final interval = overs >= 20 ? 15 : 10;
        return (overs * 2 * 4.5).round() + interval;
      }
    }

    // --- Turn sports: kho kho ---------------------------------------------
    //
    // Two innings of however many turns, each turn a fixed clock, with a
    // break between innings.
    if (config.has('turnLengthSeconds')) {
      final turns = config.getInt('turnsPerInnings', 2);
      final seconds = config.getInt('turnLengthSeconds', 420);
      if (turns > 0 && seconds > 0) {
        return ((2 * turns * seconds) / 60).round() + 10;
      }
    }

    // --- Clock sports: football, hockey, basketball, kabaddi ---------------
    //
    // Periods times their length, plus a break at each interval and ten
    // minutes for the toss, the warm-up and getting both sides on.
    final periods = config.getInt('periods', 0);
    if (periods > 0) {
      final length = config.has('periodMinutes')
          ? config.getInt('periodMinutes', 0)
          : config.getInt('halfLengthMinutes', 0);
      if (length > 0) {
        // A half-time is longer than a quarter break, and the difference
        // matters over four quarters.
        final breakEach = periods <= 2 ? 10 : 3;
        return periods * length + (periods - 1) * breakEach + 10;
      }
    }

    // --- Clock sports: chess ----------------------------------------------
    //
    // Both clocks in full, plus the increment over a game of about forty
    // moves. A classical game genuinely can take the whole session, and a
    // tournament that assumes otherwise runs out of hall.
    if (config.has('baseMinutes')) {
      final base = config.getInt('baseMinutes', 15);
      final increment = config.getInt('incrementSeconds', 0);
      if (base > 0) return (2 * (base + (40 * increment / 60))).round() + 5;
    }

    // --- Rally sports: badminton, table tennis, volleyball, pickleball -----
    //
    // Sets actually played, at about a minute a point. The average match goes
    // to the minimum plus half the remaining sets — a best-of-three averages
    // two and a half — which is the honest figure for a whole draw even
    // though no single match is 2.5 sets long.
    final setsToWin = config.getInt('setsToWin', 0);
    if (setsToWin > 0) {
      final maxSets = config.getInt('maxSets', setsToWin * 2 - 1);
      final expectedSets = setsToWin + (maxSets - setsToWin) / 2;
      final perSet = _minutesPerSet(sportId: sportId, config: config);
      return (expectedSets * perSet).round() + 10;
    }

    // --- Board sports: carrom ---------------------------------------------
    if (config.has('maxBoards')) {
      final boards = config.getInt('maxBoards', 8);
      if (boards > 0) return boards * 6 + 5;
    }

    return fallbackMinutes;
  }

  /// Minutes one set takes.
  ///
  /// The point target sets the scale — a game to 21 is longer than a game to
  /// 11 — and the sport sets the pace. A badminton rally and a table-tennis
  /// rally are not the same length of time, so a flat minute-per-point reads
  /// a best-of-five table-tennis match as an hour when it is nearer half of
  /// one, and halves the hall's apparent capacity for the whole season.
  ///
  /// Tennis is the exception these factors cannot express: it counts games,
  /// not points, so its set length comes from the games instead.
  static int _minutesPerSet({
    required String sportId,
    required RuleConfig config,
  }) {
    if (config.has('pointsPerSet')) {
      final points = config.getInt('pointsPerSet', 21);
      final scaled = (points * _paceFactor(sportId)).round();
      return scaled < 5 ? 5 : scaled;
    }
    if (sportId == 'tennis' || sportId == 'padel') {
      final games = config.getInt('gamesPerSet', 6);
      return games * 6;
    }
    return 20;
  }

  /// Minutes per point of the target, by sport.
  ///
  /// One is the reference — badminton, where a game to 21 runs about twenty
  /// minutes. Table tennis is played at well under half that per point, and
  /// nothing else in the catalogue departs far enough from the reference to
  /// need an entry of its own.
  static double _paceFactor(String sportId) => switch (sportId) {
        'table_tennis' => 0.6,
        'pickleball' => 0.9,
        'volleyball' => 0.9,
        _ => 1.0,
      };

  /// The half of [explain] that names the ruleset in the organizer's own
  /// vocabulary. Null when the sport has no shape worth restating.
  static String? _shapeLabel({
    required String sportId,
    required RuleConfig config,
  }) {
    if (config.has('oversPerInnings')) {
      final overs = config.getInt('oversPerInnings', 20);
      return '$overs overs a side';
    }
    if (config.has('turnLengthSeconds')) {
      final turns = config.getInt('turnsPerInnings', 2);
      final minutes = config.getInt('turnLengthSeconds', 420) ~/ 60;
      if (turns > 0 && minutes > 0) return '$turns × $minutes min turns a side';
    }
    final periods = config.getInt('periods', 0);
    if (periods > 0) {
      final length = config.has('periodMinutes')
          ? config.getInt('periodMinutes', 0)
          : config.getInt('halfLengthMinutes', 0);
      if (length > 0) {
        final label = config.getString('periodLabel', 'period').toLowerCase();
        return '$periods × $length min ${_plural(label)}';
      }
    }
    if (config.has('baseMinutes')) {
      final base = config.getInt('baseMinutes', 15);
      final inc = config.getInt('incrementSeconds', 0);
      return inc > 0 ? '$base+$inc each' : '$base min each';
    }
    final setsToWin = config.getInt('setsToWin', 0);
    if (setsToWin > 0 && config.has('pointsPerSet')) {
      final maxSets = config.getInt('maxSets', setsToWin * 2 - 1);
      return 'best of $maxSets to ${config.getInt('pointsPerSet', 21)}';
    }
    return null;
  }

  /// "half" → "halves", "quarter" → "quarters". Only ever handed the handful
  /// of period labels the rule presets actually use.
  static String _plural(String word) => word.endsWith('f')
      ? '${word.substring(0, word.length - 1)}ves'
      : '${word}s';

  static int _round5(int minutes) {
    final rounded = ((minutes + 2) ~/ 5) * 5;
    return rounded < minMinutes ? minMinutes : rounded;
  }
}
