import 'package:flutter/foundation.dart';

/// Typed, immutable view over a sport's rule parameters.
///
/// CLAUDE.md §2.3 makes this non-negotiable: point values, targets, formats
/// and timers vary by league and by season — kho-kho point values differ
/// between Ultimate Kho Kho seasons, badminton is mid-transition from 21-point
/// games to the BWF 3×15 system — so an engine that hard-codes a number is
/// wrong for whichever ruleset it was not written against.
///
/// This is deliberately a wrapper over `Map<String, dynamic>` rather than a
/// sealed per-sport class. Configs are persisted to Firestore, frozen onto a
/// fixture at toss time, and must survive being read back by an older or newer
/// build than the one that wrote them. A map degrades gracefully; a sealed
/// class throws on an unknown key.
@immutable
class RuleConfig {
  const RuleConfig(this.values);

  const RuleConfig.empty() : values = const {};

  factory RuleConfig.fromMap(Map<String, dynamic>? map) =>
      RuleConfig(Map<String, dynamic>.unmodifiable(map ?? const {}));

  final Map<String, dynamic> values;

  bool has(String key) => values.containsKey(key);

  int getInt(String key, int fallback) {
    final v = values[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  double getDouble(String key, double fallback) {
    final v = values[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  bool getBool(String key, bool fallback) {
    final v = values[key];
    if (v is bool) return v;
    // Firestore round-trips and CSV imports both produce these.
    if (v is num) return v != 0;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return fallback;
  }

  String getString(String key, String fallback) {
    final v = values[key];
    return v is String ? v : fallback;
  }

  List<int> getIntList(String key, List<int> fallback) {
    final v = values[key];
    if (v is! List) return fallback;
    final out = <int>[];
    for (final e in v) {
      if (e is int) {
        out.add(e);
      } else if (e is num) {
        out.add(e.toInt());
      }
    }
    return out.isEmpty ? fallback : out;
  }

  List<String> getStringList(String key, List<String> fallback) {
    final v = values[key];
    if (v is! List) return fallback;
    final out = v.whereType<String>().toList();
    return out.isEmpty ? fallback : out;
  }

  /// Returns a new config with [overrides] layered on top. Used to apply a
  /// league's amendments over a season preset without mutating either.
  RuleConfig merge(Map<String, dynamic>? overrides) {
    if (overrides == null || overrides.isEmpty) return this;
    return RuleConfig(Map<String, dynamic>.unmodifiable({
      ...values,
      ...overrides,
    }));
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(values);

  @override
  bool operator ==(Object other) =>
      other is RuleConfig && mapEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(
        values.entries.map((e) => Object.hash(e.key, e.value)),
      );

  @override
  String toString() => 'RuleConfig(${values.length} keys)';
}

/// A named, citable bundle of rule values.
///
/// Presets exist so an organizer picks "Ultimate Kho Kho — Season 2" rather
/// than typing eight numbers, and so a scorecard can say which ruleset it was
/// scored under years later. [source] is shown in the rules sheet in-app: a
/// disputed result is settled by pointing at the ruleset, so the ruleset has
/// to be attributable.
@immutable
class RulePreset {
  const RulePreset({
    required this.id,
    required this.name,
    required this.sportId,
    required this.values,
    this.description = '',
    this.source = '',
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String sportId;
  final Map<String, dynamic> values;
  final String description;

  /// Where these numbers come from — a federation rulebook, a league season.
  final String source;

  /// Whether this is the preset a new competition gets unless told otherwise.
  final bool isDefault;

  RuleConfig get config => RuleConfig.fromMap(values);
}

/// Every ruleset the platform ships with, grouped by sport.
///
/// Adding a league's variant is an entry here, never an engine change. The
/// engines read keys; this file decides what those keys are worth.
class RulePresets {
  const RulePresets._();

  static const List<RulePreset> all = [
    // --- Cricket ----------------------------------------------------------
    RulePreset(
      id: 'cricket_t20',
      sportId: 'cricket',
      name: 'T20',
      isDefault: true,
      description: '20 overs a side, free hit after a no-ball.',
      source: 'ICC limited-overs playing conditions',
      values: {
        'oversPerInnings': 20,
        'ballsPerOver': 6,
        'playersPerTeam': 11,
        'freeHitOnNoBall': true,
        'wideRuns': 1,
        'noBallRuns': 1,
        'powerplayOvers': 6,
        'maxOversPerBowler': 4,
        'boundaryFour': 4,
        'boundarySix': 6,
      },
    ),
    RulePreset(
      id: 'cricket_t10',
      sportId: 'cricket',
      name: 'T10',
      description: '10 overs a side — the standard community-tournament format.',
      values: {
        'oversPerInnings': 10,
        'ballsPerOver': 6,
        'playersPerTeam': 11,
        'freeHitOnNoBall': true,
        'wideRuns': 1,
        'noBallRuns': 1,
        'powerplayOvers': 3,
        'maxOversPerBowler': 2,
        'boundaryFour': 4,
        'boundarySix': 6,
      },
    ),
    RulePreset(
      id: 'cricket_odi',
      sportId: 'cricket',
      name: 'One Day (50 over)',
      values: {
        'oversPerInnings': 50,
        'ballsPerOver': 6,
        'playersPerTeam': 11,
        'freeHitOnNoBall': true,
        'wideRuns': 1,
        'noBallRuns': 1,
        'powerplayOvers': 10,
        'maxOversPerBowler': 10,
        'boundaryFour': 4,
        'boundarySix': 6,
      },
    ),
    RulePreset(
      id: 'cricket_tennis_ball',
      sportId: 'cricket',
      name: 'Tennis-ball (8 over, no free hit)',
      description:
          'Gully and community tennis-ball rules: shorter, no free hit, '
          'and a wide costs two.',
      values: {
        'oversPerInnings': 8,
        'ballsPerOver': 6,
        'playersPerTeam': 8,
        'freeHitOnNoBall': false,
        'wideRuns': 2,
        'noBallRuns': 2,
        'powerplayOvers': 0,
        'maxOversPerBowler': 2,
        'boundaryFour': 4,
        'boundarySix': 6,
      },
    ),

    // --- Badminton --------------------------------------------------------
    RulePreset(
      id: 'badminton_21',
      sportId: 'badminton',
      name: '21 point (best of 3)',
      isDefault: true,
      description: 'Rally scoring to 21, win by 2, hard cap 30. Interval at 11.',
      source: 'BWF Laws of Badminton, rally-point era',
      values: {
        'pointsPerSet': 21,
        'setsToWin': 2,
        'maxSets': 3,
        'winBy': 2,
        'hardCap': 30,
        'intervalAt': 11,
        'changeEndsInDecidingAt': 11,
      },
    ),
    RulePreset(
      id: 'badminton_3x15',
      sportId: 'badminton',
      name: 'BWF 3×15 (2026 system)',
      description:
          'Best of five games to 15, win by 2, cap 21, interval at 8. '
          'Selectable now so a league can pilot it before it is mandatory.',
      source: 'BWF-approved scoring change expected 2026',
      values: {
        'pointsPerSet': 15,
        'setsToWin': 3,
        'maxSets': 5,
        'winBy': 2,
        'hardCap': 21,
        'intervalAt': 8,
        'changeEndsInDecidingAt': 8,
      },
    ),

    // --- Table tennis -----------------------------------------------------
    RulePreset(
      id: 'tt_best_of_5',
      sportId: 'table_tennis',
      name: '11 point, best of 5',
      isDefault: true,
      values: {
        'pointsPerSet': 11,
        'setsToWin': 3,
        'winBy': 2,
        'servesPerTurn': 2,
        'servesPerTurnAtDeuce': 1,
        'decidingGameSwitchAt': 5,
        'expediteAfterMinutes': 10,
      },
    ),
    RulePreset(
      id: 'tt_best_of_7',
      sportId: 'table_tennis',
      name: '11 point, best of 7',
      values: {
        'pointsPerSet': 11,
        'setsToWin': 4,
        'winBy': 2,
        'servesPerTurn': 2,
        'servesPerTurnAtDeuce': 1,
        'decidingGameSwitchAt': 5,
        'expediteAfterMinutes': 10,
      },
    ),

    // --- Pickleball -------------------------------------------------------
    RulePreset(
      id: 'pickleball_11_sideout',
      sportId: 'pickleball',
      name: '11 point, side-out (best of 3)',
      isDefault: true,
      description:
          'Traditional scoring: only the serving side can score. Two servers '
          'a side, one for whoever opens the game. Ends change at 6.',
      source: 'USA Pickleball Official Rulebook',
      values: {
        'pointsPerSet': 11,
        'setsToWin': 2,
        'maxSets': 3,
        'winBy': 2,
        'hardCap': 0,
        'rallyScoring': false,
        'serversPerSide': 2,
        'firstServerException': true,
        'changeEndsAt': 6,
      },
    ),
    RulePreset(
      id: 'pickleball_15_sideout',
      sportId: 'pickleball',
      name: '15 point, side-out',
      description: 'Longer tournament games to 15, ends changing at 8.',
      values: {
        'pointsPerSet': 15,
        'setsToWin': 2,
        'maxSets': 3,
        'winBy': 2,
        'hardCap': 0,
        'rallyScoring': false,
        'serversPerSide': 2,
        'firstServerException': true,
        'changeEndsAt': 8,
      },
    ),
    RulePreset(
      id: 'pickleball_21_rally',
      sportId: 'pickleball',
      name: '21 point, rally scoring',
      description:
          'Every rally scores, the way badminton does. Used by MLP-style '
          'league play where the match has to fit a clock.',
      values: {
        'pointsPerSet': 21,
        'setsToWin': 2,
        'maxSets': 3,
        'winBy': 2,
        'hardCap': 0,
        'rallyScoring': true,
        'serversPerSide': 2,
        'firstServerException': false,
        'changeEndsAt': 11,
      },
    ),

    // --- Padel ------------------------------------------------------------
    RulePreset(
      id: 'padel_best_of_3',
      sportId: 'padel',
      name: 'Best of 3 sets',
      isDefault: true,
      description:
          'Tennis scoring on a padel court: 15/30/40, advantage at deuce, '
          'tiebreak at 6-6.',
      source: 'International Padel Federation rules of play',
      values: {
        'setsToWin': 2,
        'gamesPerSet': 6,
        'gamesWinBy': 2,
        'tiebreakTo': 7,
        'tiebreakWinBy': 2,
        'pointsToWinGame': 4,
        'gameWinBy': 2,
        'noAd': false,
        'decidingSetTiebreak': false,
        'matchTiebreakTo': 10,
        'tiebreakChangeEndsEvery': 6,
        'doubles': true,
      },
    ),
    RulePreset(
      id: 'padel_golden_point',
      sportId: 'padel',
      name: 'Golden point (no advantage)',
      description:
          'Deuce is settled by a single point — the format used on the '
          'professional tour and by most clubs running a timetable.',
      values: {
        'setsToWin': 2,
        'gamesPerSet': 6,
        'gamesWinBy': 2,
        'tiebreakTo': 7,
        'tiebreakWinBy': 2,
        'pointsToWinGame': 4,
        'gameWinBy': 1,
        'noAd': true,
        'decidingSetTiebreak': false,
        'matchTiebreakTo': 10,
        'tiebreakChangeEndsEvery': 6,
        'doubles': true,
      },
    ),

    // --- Squash -----------------------------------------------------------
    RulePreset(
      id: 'squash_par11',
      sportId: 'squash',
      name: 'PAR 11, best of 5',
      isDefault: true,
      description:
          'Point-a-rally to 11, win by 2, best of five games. The modern '
          'scoring system — every rally scores whoever served it.',
      source: 'World Squash Federation rules',
      values: {
        'pointsPerSet': 11,
        'setsToWin': 3,
        'maxSets': 5,
        'winBy': 2,
        'hardCap': 0,
      },
    ),
    RulePreset(
      id: 'squash_par15',
      sportId: 'squash',
      name: 'PAR 15, best of 3',
      description: 'Shorter format for club nights and box leagues.',
      values: {
        'pointsPerSet': 15,
        'setsToWin': 2,
        'maxSets': 3,
        'winBy': 2,
        'hardCap': 0,
      },
    ),

    // --- Volleyball -------------------------------------------------------
    RulePreset(
      id: 'volleyball_5_set',
      sportId: 'volleyball',
      name: '25 point, best of 5',
      isDefault: true,
      values: {
        'pointsPerSet': 25,
        'decidingSetPoints': 15,
        'setsToWin': 3,
        'winBy': 2,
        'switchEndsInDecidingAt': 8,
        'timeoutsPerSet': 2,
        'squadSize': 6,
        'maxSubstitutions': 6,
        'allowReturn': true,
      },
    ),
    RulePreset(
      id: 'volleyball_3_set',
      sportId: 'volleyball',
      name: '25 point, best of 3 (school)',
      values: {
        'pointsPerSet': 25,
        'decidingSetPoints': 15,
        'setsToWin': 2,
        'winBy': 2,
        'switchEndsInDecidingAt': 8,
        'timeoutsPerSet': 2,
        'squadSize': 6,
        'maxSubstitutions': 6,
        'allowReturn': true,
      },
    ),

    // --- Kabaddi ----------------------------------------------------------
    RulePreset(
      id: 'kabaddi_pkl',
      sportId: 'kabaddi',
      name: 'Pro Kabaddi style',
      isDefault: true,
      source: 'Pro Kabaddi League playing conditions',
      values: {
        'periods': 2,
        'periodLabel': 'Half',
        'halfLengthMinutes': 20,
        'raidClockSeconds': 30,
        'playersOnCourt': 7,
        'bonusMinDefenders': 6,
        'bonusPoints': 1,
        'touchPointsPerDefender': 1,
        'tacklePoints': 1,
        'superTacklePoints': 2,
        'superTackleMaxDefenders': 3,
        'superRaidPoints': 3,
        'allOutBonus': 2,
        'doOrDieAfterEmptyRaids': 2,
        'superTenAt': 10,
        'highFiveAt': 5,
        'timeoutsPerPeriod': 2,
        'reviewsPerSide': 1,
      },
    ),
    RulePreset(
      id: 'kabaddi_amateur',
      sportId: 'kabaddi',
      name: 'Circle / amateur (no super tackle)',
      description:
          'Village and school kabaddi as commonly played: no super-tackle '
          'bonus, shorter halves.',
      values: {
        'periods': 2,
        'periodLabel': 'Half',
        'halfLengthMinutes': 15,
        'raidClockSeconds': 30,
        'playersOnCourt': 7,
        'bonusMinDefenders': 6,
        'bonusPoints': 1,
        'touchPointsPerDefender': 1,
        'tacklePoints': 1,
        'superTacklePoints': 1,
        'superTackleMaxDefenders': 0,
        'superRaidPoints': 3,
        'allOutBonus': 2,
        'doOrDieAfterEmptyRaids': 2,
        'superTenAt': 10,
        'highFiveAt': 5,
      },
    ),

    // --- Kho-kho ----------------------------------------------------------
    // §13 calls this out explicitly: point values differ across UKK seasons
    // and KKFI-aligned rulesets, so both ship as presets.
    RulePreset(
      id: 'kho_kho_ukk_s2',
      sportId: 'kho_kho',
      name: 'Ultimate Kho Kho — Season 2',
      isDefault: true,
      source: 'Ultimate Kho Kho season-2 playing conditions',
      values: {
        'tagPoints': 2,
        'poleDivePoints': 2,
        'skyDivePoints': 2,
        'allOutBonus': 4,
        'batchSize': 3,
        'turnsPerInnings': 2,
        'turnLengthSeconds': 420,
        'dreamRunAfterSeconds': 180,
        'dreamRunEverySeconds': 30,
        'dreamRunPoints': 1,
      },
    ),
    RulePreset(
      id: 'kho_kho_kkfi',
      sportId: 'kho_kho',
      name: 'KKFI / traditional (9 min turns)',
      description:
          'Federation-aligned ruleset: dives are worth three, turns run nine '
          'minutes, dream run starts at 2:30.',
      source: 'Kho Kho Federation of India aligned rulesets',
      values: {
        'tagPoints': 1,
        'poleDivePoints': 3,
        'skyDivePoints': 3,
        'allOutBonus': 2,
        'batchSize': 3,
        'turnsPerInnings': 2,
        'turnLengthSeconds': 540,
        'dreamRunAfterSeconds': 150,
        'dreamRunEverySeconds': 30,
        'dreamRunPoints': 1,
      },
    ),

    // --- Tennis -----------------------------------------------------------
    RulePreset(
      id: 'tennis_best_of_3',
      sportId: 'tennis',
      name: 'Best of 3 sets',
      isDefault: true,
      values: {
        'setsToWin': 2,
        'gamesPerSet': 6,
        'gamesWinBy': 2,
        'tiebreakTo': 7,
        'tiebreakWinBy': 2,
        'pointsToWinGame': 4,
        'gameWinBy': 2,
        'noAd': false,
        'decidingSetTiebreak': false,
        'matchTiebreakTo': 10,
        'tiebreakChangeEndsEvery': 6,
      },
    ),
    RulePreset(
      id: 'tennis_fast4',
      sportId: 'tennis',
      name: 'Fast4 / no-ad (club)',
      description:
          'Four-game sets, no advantage, match tiebreak to 10. Fits a club '
          'night where courts turn over every 40 minutes.',
      values: {
        'setsToWin': 2,
        'gamesPerSet': 4,
        'gamesWinBy': 1,
        'tiebreakTo': 5,
        'tiebreakWinBy': 2,
        'pointsToWinGame': 4,
        'gameWinBy': 1,
        'noAd': true,
        'decidingSetTiebreak': true,
        'matchTiebreakTo': 10,
        'tiebreakChangeEndsEvery': 6,
      },
    ),

    // --- Basketball -------------------------------------------------------
    RulePreset(
      id: 'basketball_full',
      sportId: 'basketball',
      name: '5-a-side, 4 quarters',
      isDefault: true,
      values: {
        'periods': 4,
        'periodLabel': 'Quarter',
        'periodMinutes': 10,
        'shotClockSeconds': 24,
        'foulOutAt': 5,
        'bonusFoulsPerPeriod': 5,
        'freeThrowPoints': 1,
        'fieldGoalPoints': 2,
        'threePointPoints': 3,
        'threeMode': false,
        'squadSize': 5,
        'maxSubstitutions': 0,
        'allowReturn': true,
        'timeoutsPerPeriod': 2,
      },
    ),
    RulePreset(
      id: 'basketball_3x3',
      sportId: 'basketball',
      name: '3×3 (to 21 or 10 minutes)',
      description:
          'FIBA 3×3: baskets are worth 1 and 2, first to 21 or 10 minutes.',
      source: 'FIBA 3×3 official rules',
      values: {
        'periods': 1,
        'periodLabel': 'Period',
        'periodMinutes': 10,
        'shotClockSeconds': 12,
        'foulOutAt': 4,
        'bonusFoulsPerPeriod': 6,
        'freeThrowPoints': 1,
        'fieldGoalPoints': 1,
        'threePointPoints': 2,
        'threeMode': true,
        'targetScore': 21,
        'squadSize': 3,
        'maxSubstitutions': 0,
        'allowReturn': true,
        'timeoutsPerSide': 1,
      },
    ),

    // --- Football ---------------------------------------------------------
    RulePreset(
      id: 'football_11',
      sportId: 'football',
      name: '11-a-side, 2 × 45',
      isDefault: true,
      values: {
        'periods': 2,
        'periodLabel': 'Half',
        'periodMinutes': 45,
        'squadSize': 11,
        'maxSubstitutions': 5,
        'allowReturn': false,
        'allowDraw': true,
        'extraTime': false,
        'shootoutBestOf': 5,
      },
    ),
    RulePreset(
      id: 'football_7',
      sportId: 'football',
      name: '7-a-side, 2 × 25',
      values: {
        'periods': 2,
        'periodLabel': 'Half',
        'periodMinutes': 25,
        'squadSize': 7,
        'maxSubstitutions': 5,
        'allowReturn': false,
        'allowDraw': true,
        'extraTime': false,
        'shootoutBestOf': 3,
      },
    ),
    RulePreset(
      id: 'football_futsal',
      sportId: 'football',
      name: '5-a-side / futsal',
      values: {
        'periods': 2,
        'periodLabel': 'Half',
        'periodMinutes': 20,
        'squadSize': 5,
        'maxSubstitutions': 5,
        'allowReturn': false,
        'allowDraw': true,
        'extraTime': false,
        'shootoutBestOf': 3,
      },
    ),

    // --- Hockey -----------------------------------------------------------
    RulePreset(
      id: 'hockey_quarters',
      sportId: 'hockey',
      name: '4 × 15 minute quarters',
      isDefault: true,
      values: {
        'periods': 4,
        'periodLabel': 'Quarter',
        'periodMinutes': 15,
        'allowDraw': true,
        'shootoutBestOf': 5,
        // Rolling substitution: unlimited, and a player who comes off goes
        // back on. Both differ from football, which is exactly why they are
        // configuration rather than engine code.
        'squadSize': 11,
        'maxSubstitutions': 0,
        'allowReturn': true,
        'reviewsPerSide': 1,
      },
    ),

    // --- Chess ------------------------------------------------------------
    RulePreset(
      id: 'chess_classical',
      sportId: 'chess',
      name: 'Classical (90+30)',
      isDefault: true,
      values: {
        'timeControl': 'classical',
        'baseMinutes': 90,
        'incrementSeconds': 30,
        'winPoints': 1.0,
        'drawPoints': 0.5,
        'lossPoints': 0.0,
        'recordMoves': true,
      },
    ),
    RulePreset(
      id: 'chess_rapid',
      sportId: 'chess',
      name: 'Rapid (15+10)',
      values: {
        'timeControl': 'rapid',
        'baseMinutes': 15,
        'incrementSeconds': 10,
        'winPoints': 1.0,
        'drawPoints': 0.5,
        'lossPoints': 0.0,
        'recordMoves': true,
      },
    ),
    RulePreset(
      id: 'chess_blitz',
      sportId: 'chess',
      name: 'Blitz (5+3)',
      values: {
        'timeControl': 'blitz',
        'baseMinutes': 5,
        'incrementSeconds': 3,
        'winPoints': 1.0,
        'drawPoints': 0.5,
        'lossPoints': 0.0,
        'recordMoves': false,
      },
    ),
    RulePreset(
      id: 'chess_bullet',
      sportId: 'chess',
      name: 'Bullet (1+0)',
      values: {
        'timeControl': 'bullet',
        'baseMinutes': 1,
        'incrementSeconds': 0,
        'winPoints': 1.0,
        'drawPoints': 0.5,
        'lossPoints': 0.0,
        'recordMoves': false,
      },
    ),

    // --- Carrom -----------------------------------------------------------
    RulePreset(
      id: 'carrom_icf',
      sportId: 'carrom',
      name: 'ICF singles (29 points)',
      isDefault: true,
      description:
          'A board is won by the player who pockets all their coins; the '
          'board is worth the count of the loser\'s remaining coins, capped '
          'at 25, plus 3 for the queen. Match is to 29 points or 8 boards.',
      source: 'International Carrom Federation laws',
      values: {
        'matchTarget': 29,
        'maxBoards': 8,
        'queenPoints': 3,
        'queenMustBeCovered': true,
        'coinPoints': 1,
        'coinsPerSide': 9,
        'maxBoardPoints': 25,
        'queenCountsOnlyBelowPoints': 22,
        'foulPenalty': 1,
      },
    ),
    RulePreset(
      id: 'carrom_club',
      sportId: 'carrom',
      name: 'Club (best of 3 boards)',
      values: {
        'matchTarget': 0,
        'maxBoards': 3,
        'queenPoints': 3,
        'queenMustBeCovered': true,
        'coinPoints': 1,
        'coinsPerSide': 9,
        'maxBoardPoints': 25,
        'queenCountsOnlyBelowPoints': 22,
        'foulPenalty': 1,
      },
    ),

    // --- Athletics --------------------------------------------------------
    RulePreset(
      id: 'athletics_track',
      sportId: 'athletics_sprint',
      name: 'Track event (heats → final)',
      isDefault: true,
      values: {
        'discipline': 'track',
        'lanes': 8,
        'precisionDecimals': 2,
        'lowerIsBetter': true,
        'falseStartDisqualifies': true,
        'recordWind': true,
        'qualifiersPerHeat': 2,
        'fastestLosers': 2,
      },
    ),
    RulePreset(
      id: 'athletics_field',
      sportId: 'athletics_field',
      name: 'Field event (best of attempts)',
      isDefault: true,
      values: {
        'discipline': 'field',
        'attempts': 6,
        'precisionDecimals': 2,
        'lowerIsBetter': false,
        'recordWind': true,
        'finalistsAfterAttempt': 3,
        'finalists': 8,
      },
    ),
  ];

  /// Presets available for a sport, default first.
  static List<RulePreset> forSport(String sportId) {
    final list = all.where((p) => p.sportId == sportId).toList()
      ..sort((a, b) {
        if (a.isDefault == b.isDefault) return a.name.compareTo(b.name);
        return a.isDefault ? -1 : 1;
      });
    return list;
  }

  static RulePreset? byId(String? id) {
    if (id == null) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The preset a new competition in [sportId] starts from, or null when the
  /// sport ships no presets (the generic archetypes).
  static RulePreset? defaultFor(String sportId) {
    for (final p in all) {
      if (p.sportId == sportId && p.isDefault) return p;
    }
    final any = forSport(sportId);
    return any.isEmpty ? null : any.first;
  }

  /// Resolves the config a fixture should be scored under: the named preset
  /// with any per-competition amendments layered on top.
  static RuleConfig resolve({
    String? presetId,
    String? sportId,
    Map<String, dynamic>? overrides,
  }) {
    final preset = byId(presetId) ??
        (sportId == null ? null : defaultFor(sportId));
    final base = preset?.config ?? const RuleConfig.empty();
    return base.merge(overrides);
  }
}

/// Turns a rule key into something a scorer can be shown and can edit.
///
/// CLAUDE.md §2.3 says rules are configuration, not code — but a config only
/// a developer can change is code with extra steps. An organizer running an
/// eight-over tennis-ball match, or a school playing 15-point badminton
/// because the hall is booked at seven, has to be able to say so at the point
/// the match is set up, without waiting for a preset to be added here.
///
/// This deliberately describes keys rather than enumerating them. Everything
/// in a preset is editable; [labelFor] falls back to un-camel-casing an
/// unknown key, so adding a value to a preset makes it editable in the same
/// commit, with no screen to update. [order] only decides what a scorer sees
/// FIRST — the things that change most often, per sport.
///
/// ## Enforced and advisory settings
///
/// "Everything in a preset is editable" was true and hid something: some of
/// those settings were read by no engine at all. The review found
/// twenty-four of them — most sharply `maxOversPerBowler`, offered as the
/// fourth field in the cricket sheet and enforced nowhere, so a T20 innings
/// could legally be bowled by two bowlers and still feed Glicko and the
/// bowling leaderboards. Three more (`pointsWin`, `pointsDraw`,
/// `pointsLoss`) duplicated `Competition.pointsForWin`, which is the field
/// `StandingsCalculator` actually reads — so a league that set two points a
/// win here silently kept scoring three.
///
/// The quota is now enforced and the duplicates are gone. The ten that remain
/// genuinely are not enforced, because enforcing them needs data the pad does
/// not capture — a running shot clock, per-ball fielding positions, an
/// extra-time phase the engines have no concept of. Pretending otherwise is
/// what the old state did; deleting them would throw away a real record of
/// what a competition agreed to play under.
///
/// So they are declared [advisory] instead, with the reason each one is,
/// [isAdvisory] lets the Rules sheet label them honestly, and
/// `test/rule_config_coverage_test.dart` fails when a preset gains a key that
/// is neither read by an engine nor listed here. A new unenforced setting can
/// no longer arrive silently.
class RuleFields {
  const RuleFields._();

  /// Settings recorded as part of what a competition agreed, and enforced by
  /// no engine — mapped to why not.
  ///
  /// Each is a real rule of its sport that the app cannot police with the
  /// information a scorer gives it. Recording an organizer's answer is still
  /// worth doing: "we agreed 24-second shot clock" settles an argument three
  /// weeks later even though nothing counted the seconds.
  static const advisory = <String, String>{
    'powerplayOvers':
        'Needs per-ball fielding positions, which the pad does not collect. '
            'The over count is recorded; the fielding restriction is the '
            "umpire's to apply.",
    'shotClockSeconds':
        'Needs a running clock. The pad records events, not elapsed time, so '
            'nothing here can know when 24 seconds have passed.',
    'bonusFoulsPerPeriod':
        'Needs team fouls tracked per period. Individual fouls are recorded '
            'and `foulOutAt` is enforced; the team total is not.',
    'extraTime':
        'The engines have no extra-time phase — a drawn knockout is resolved '
            'by the organizer recording the outcome, not by the pad playing '
            'on.',
    'shootoutBestOf':
        'A shootout is recorded as an outcome rather than scored kick by '
            'kick — the engines have no shootout phase, so the number of '
            'kicks agreed is a note on the fixture and not a thing that '
            'counts down.',
    'qualifiersPerHeat':
        'Heat-to-final progression is not computed from marks. The draw '
            'generator builds heats and a final; who advances is the '
            "organizer's entry.",
    'fastestLosers':
        'The non-automatic qualifiers — the quickest athletes who did not win '
            'a heat. Working them out means ranking marks across heats, which '
            'is the progression the athletics engine does not compute.',
    'finalists':
        'How many reach the final. Recorded so the programme is right; who '
            'they are is the organizer\'s entry, for the same reason '
            'qualifiersPerHeat is.',
    'finalistsAfterAttempt':
        'Field-event cut-downs need per-attempt progression the athletics '
            'engine does not model.',
    'threeMode':
        '3x3 basketball scores 1s and 2s rather than 2s and 3s. The engine '
            'takes the point value from the action, so the variant is scored '
            'correctly by pressing the right button; this flag would only '
            'relabel them.',
  };

  /// Whether [key] is recorded but not enforced.
  ///
  /// The Rules sheet asks this so it can say so beside the field. An
  /// organizer who sets a shot clock the app will not count should know that
  /// before the match, not discover it during one.
  static bool isAdvisory(String key) => advisory.containsKey(key);

  /// Why [key] is not enforced, or null when it is.
  static String? advisoryReason(String key) => advisory[key];

  /// Hand-written labels for the keys worth phrasing properly. Anything
  /// missing is derived from the key itself.
  static const _labels = <String, String>{
    'oversPerInnings': 'Overs per innings',
    'ballsPerOver': 'Balls per over',
    'playersPerTeam': 'Players per team',
    'maxOversPerBowler': 'Max overs per bowler',
    'powerplayOvers': 'Powerplay overs',
    'freeHitOnNoBall': 'Free hit after a no-ball',
    'wideRuns': 'Runs for a wide',
    'noBallRuns': 'Runs for a no-ball',
    'boundaryFour': 'Runs for a four',
    'boundarySix': 'Runs for a six',
    'pointsPerSet': 'Points per game',
    'setsToWin': 'Games to win the match',
    'maxSets': 'Maximum games',
    'winBy': 'Must win by',
    'hardCap': 'Hard cap',
    'intervalAt': 'Interval at',
    'decidingSetPoints': 'Points in the deciding set',
    'servesPerTurn': 'Serves per turn',
    'servesPerTurnAtDeuce': 'Serves per turn at deuce',
    'periodMinutes': 'Minutes per period',
    'periods': 'Number of periods',
    'periodLabel': 'What a period is called',
    'halfLengthMinutes': 'Minutes per half',
    'raidClockSeconds': 'Raid clock (seconds)',
    'timeControl': 'Time control',
    'baseMinutes': 'Base minutes',
    'incrementSeconds': 'Increment (seconds)',
    'matchTarget': 'Points to win',
    'targetScore': 'Target score',
    'allowDraw': 'Draws allowed',
    'squadSize': 'Players on the field',
    'maxSubstitutions': 'Substitutions allowed (0 = unlimited)',
    'allowReturn': 'A substituted player may return',
    'timeoutsPerSide': 'Timeouts per side (whole match)',
    'timeoutsPerPeriod': 'Timeouts per side, per period',
    'timeoutsPerSet': 'Timeouts per side, per set',
    'reviewsPerSide': 'Reviews per side',
    'retainReviewOnSuccess': 'A successful review is not spent',
  };

  /// What a scorer is most likely to want to change, per sport, in the order
  /// they should meet it. Everything else follows alphabetically.
  static const _order = <String, List<String>>{
    'cricket': [
      'oversPerInnings',
      'ballsPerOver',
      'playersPerTeam',
      'maxOversPerBowler',
      'freeHitOnNoBall',
      'wideRuns',
      'noBallRuns',
    ],
    'badminton': ['pointsPerSet', 'setsToWin', 'winBy', 'hardCap', 'intervalAt'],
    'table_tennis': ['pointsPerSet', 'setsToWin', 'winBy', 'servesPerTurn'],
    'tennis': ['gamesPerSet', 'setsToWin', 'noAd', 'tiebreakTo'],
    'padel': ['gamesPerSet', 'setsToWin', 'noAd', 'tiebreakTo'],
    'pickleball': [
      'pointsPerSet',
      'setsToWin',
      'winBy',
      'rallyScoring',
      'changeEndsAt',
    ],
    'squash': ['pointsPerSet', 'setsToWin', 'winBy'],
    'volleyball': [
      'pointsPerSet',
      'setsToWin',
      'decidingSetPoints',
      'winBy',
      'maxSubstitutions',
      'timeoutsPerSet',
    ],
    'football': [
      'periodMinutes',
      'periods',
      'squadSize',
      'maxSubstitutions',
      'allowReturn',
      'extraTime',
    ],
    'basketball': [
      'periodMinutes',
      'periods',
      'shotClockSeconds',
      'foulOutAt',
      'timeoutsPerPeriod',
    ],
    'kabaddi': [
      'halfLengthMinutes',
      'raidClockSeconds',
      'playersOnCourt',
      'timeoutsPerPeriod',
    ],
    'hockey': ['periodMinutes', 'periods', 'squadSize', 'maxSubstitutions'],
    'chess': ['timeControl', 'baseMinutes', 'incrementSeconds'],
    'carrom': ['matchTarget', 'maxBoardPoints', 'queenPoints'],
  };

  static String labelFor(String key) => _labels[key] ?? _humanize(key);

  /// `oversPerInnings` → `Overs per innings`. Not clever, and does not need to
  /// be: it exists so an uncatalogued key is still legible rather than hidden.
  static String _humanize(String key) {
    final spaced = key.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
      (_) => ' ',
    );
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }

  /// Every key in [config], most-edited first for [sportId].
  static List<String> orderedKeys(String sportId, Map<String, dynamic> config) {
    final priority = _order[sportId] ?? const <String>[];
    final keys = config.keys.toList()..sort();
    final head = [for (final k in priority) if (config.containsKey(k)) k];
    final tail = [for (final k in keys) if (!head.contains(k)) k];
    return [...head, ...tail];
  }
}
