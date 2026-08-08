import 'package:flutter/foundation.dart';

import '../../core/models/enums.dart';
import 'plugins/athletics_plugin.dart';
import 'plugins/badminton_plugin.dart';
import 'plugins/basketball_plugin.dart';
import 'plugins/carrom_plugin.dart';
import 'plugins/chess_plugin.dart';
import 'plugins/cricket_plugin.dart';
import 'plugins/football_plugin.dart';
import 'plugins/goal_based_plugin.dart';
import 'plugins/hockey_plugin.dart';
import 'plugins/kabaddi_plugin.dart';
import 'plugins/kho_kho_plugin.dart';
import 'plugins/set_based_plugin.dart';
import 'plugins/volleyball_plugin.dart';
import 'plugins/simple_points_plugin.dart';
import 'plugins/table_tennis_plugin.dart';
import 'plugins/tennis_plugin.dart';
import 'rule_config.dart';
import 'scoring_plugin.dart';

/// How many people a side, and what that arrangement is called.
///
/// A sport does not have "a" squad size — badminton is one a side or two a
/// side and the two are different competitions with different ratings;
/// cricket is eleven but a tennis-ball gully game is eight and a school side
/// might be six. Without this the setup screen has to guess, and the guess it
/// made was one player per side for everything. That is not merely
/// inconvenient: a one-man cricket team makes the engine reject the first
/// delivery, because the same person cannot be on strike and at the other
/// end.
///
/// [min] is the floor the engine genuinely needs, not the floor the rulebook
/// prints. Cricket needs two batters to have a striker and a non-striker;
/// football's rulebook says eleven but a five-a-side on a Sunday is still
/// football and must still be scorable. Being stricter than the engine
/// requires would block real matches, which is how a product gets abandoned
/// at the ground.
@immutable
class SideFormat {
  const SideFormat({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    this.configOverrides = const {},
    this.isDefault = false,
  });

  final String id;
  final String name;

  /// Fewest players a side the engine can actually score with.
  final int min;

  /// Most this arrangement admits. A squad, not a starting eleven — cricket
  /// allows more than eleven named so substitutes appear on the scorecard.
  final int max;

  /// Rule values this arrangement implies, layered over the chosen preset.
  /// Doubles is not a different point system, but it is a different serve
  /// rotation, and the engines read that from config.
  final Map<String, dynamic> configOverrides;

  final bool isDefault;
}

/// The arrangements each sport is actually played in.
///
/// Keyed by sport id. Anything absent falls back to [SideFormats.generic],
/// which is deliberately permissive — a sport we have not catalogued must
/// never be a sport that cannot be played.
class SideFormats {
  const SideFormats._();

  /// One against one, and nothing else on offer.
  static const singlesOnly = [
    SideFormat(id: 'singles', name: 'Singles', min: 1, max: 1, isDefault: true),
  ];

  /// Racquet and net sports: singles or doubles, and the engines need to know
  /// which, because service rotation differs.
  static const racquet = [
    SideFormat(id: 'singles', name: 'Singles', min: 1, max: 1, isDefault: true),
    SideFormat(
      id: 'doubles',
      name: 'Doubles',
      min: 2,
      max: 2,
      configOverrides: {'doubles': true},
    ),
  ];

  static const _map = <String, List<SideFormat>>{
    // Two batters are a hard floor — a striker and a non-striker are two
    // different people. Fifteen is a squad with substitutes, not a starting
    // eleven, so the scorecard can name everyone who turned up.
    'cricket': [
      SideFormat(id: 'eleven', name: '11 a side', min: 2, max: 15,
          configOverrides: {'playersPerTeam': 11}, isDefault: true),
      SideFormat(id: 'eight', name: '8 a side (tennis ball)', min: 2, max: 12,
          configOverrides: {'playersPerTeam': 8}),
      SideFormat(id: 'six', name: '6 a side', min: 2, max: 10,
          configOverrides: {'playersPerTeam': 6}),
    ],
    'badminton': racquet,
    'table_tennis': racquet,
    'tennis': racquet,
    'carrom': [
      SideFormat(id: 'singles', name: 'Singles', min: 1, max: 1,
          isDefault: true),
      SideFormat(id: 'doubles', name: 'Doubles', min: 2, max: 2,
          configOverrides: {'doubles': true}),
    ],
    'chess': singlesOnly,
    'football': [
      SideFormat(id: 'eleven', name: '11 a side', min: 1, max: 18,
          configOverrides: {'playersPerTeam': 11}, isDefault: true),
      SideFormat(id: 'seven', name: '7 a side', min: 1, max: 12,
          configOverrides: {'playersPerTeam': 7}),
      SideFormat(id: 'five', name: '5 a side (futsal)', min: 1, max: 10,
          configOverrides: {'playersPerTeam': 5}),
    ],
    'basketball': [
      SideFormat(id: 'five', name: '5 a side', min: 1, max: 12,
          configOverrides: {'playersPerTeam': 5}, isDefault: true),
      SideFormat(id: 'three', name: '3x3', min: 1, max: 6,
          configOverrides: {'playersPerTeam': 3}),
    ],
    'volleyball': [
      SideFormat(id: 'six', name: '6 a side', min: 1, max: 14,
          configOverrides: {'playersPerTeam': 6}, isDefault: true),
      SideFormat(id: 'four', name: '4 a side', min: 1, max: 10,
          configOverrides: {'playersPerTeam': 4}),
    ],
    'throwball': [
      SideFormat(id: 'seven', name: '7 a side', min: 1, max: 14,
          configOverrides: {'playersPerTeam': 7}, isDefault: true),
    ],
    'kabaddi': [
      SideFormat(id: 'seven', name: '7 on court', min: 1, max: 12,
          configOverrides: {'playersPerTeam': 7}, isDefault: true),
    ],
    'kho_kho': [
      SideFormat(id: 'nine', name: '9 a side', min: 1, max: 15,
          configOverrides: {'playersPerTeam': 9}, isDefault: true),
    ],
    'hockey': [
      SideFormat(id: 'eleven', name: '11 a side', min: 1, max: 18,
          configOverrides: {'playersPerTeam': 11}, isDefault: true),
    ],
  };

  /// The escape hatch, and the shape of every performance sport: one entry
  /// per side, up to a squad, with no arrangement worth naming.
  static const generic = [
    SideFormat(id: 'any', name: 'Any number', min: 1, max: 15,
        isDefault: true),
  ];

  static List<SideFormat> forSport(String sportId) =>
      _map[sportId] ?? generic;

  static SideFormat defaultFor(String sportId) {
    final list = forSport(sportId);
    return list.firstWhere((f) => f.isDefault, orElse: () => list.first);
  }

  static SideFormat resolve(String sportId, String? formatId) {
    final list = forSport(sportId);
    return list.firstWhere(
      (f) => f.id == formatId,
      orElse: () => defaultFor(sportId),
    );
  }
}

/// What the side that wins the toss actually gets to choose.
///
/// Every match starts with one, and it is not "bat or field" outside cricket.
/// A badminton umpire asks serve or receive; a football referee asks kick-off
/// or ends; a kabaddi toss picks the raid or the court; chess is decided by
/// colour, not by a toss at all. The dialog offered Bat and Field to all
/// thirteen sports, which meant the record of every non-cricket match said
/// something that had not happened.
///
/// [appliesTo] is what the choice DOES, and it is the reason this is not
/// merely a label. Cricket's choice decides which side bats first and the
/// engine reads it; badminton's decides who serves; football's decides
/// nothing the engine needs. Only the first of those may write
/// `battingFirst`.
@immutable
class TossChoice {
  const TossChoice({
    required this.id,
    required this.label,
    this.givesFirstTurn = true,
  });

  final String id;

  /// As the umpire says it: "Bat", "Serve", "Kick off", "Raid first".
  final String label;

  /// Whether picking this means the winner goes first.
  ///
  /// "Bat" and "Serve" do; "Field", "Receive" and "Ends" hand the first turn
  /// to the other side. It is what lets one piece of code work out who starts
  /// without knowing anything about the sport.
  final bool givesFirstTurn;
}

/// The toss, per sport.
class TossOptions {
  const TossOptions._();

  static const _cricket = [
    TossChoice(id: 'bat', label: 'Bat'),
    TossChoice(id: 'field', label: 'Field', givesFirstTurn: false),
  ];

  static const _serveOrReceive = [
    TossChoice(id: 'serve', label: 'Serve'),
    TossChoice(id: 'receive', label: 'Receive', givesFirstTurn: false),
    // Choosing ends is a real third option in badminton and table tennis, and
    // it concedes the serve — which is exactly what `givesFirstTurn: false`
    // records.
    TossChoice(id: 'ends', label: 'Choose ends', givesFirstTurn: false),
  ];

  static const _kickOff = [
    TossChoice(id: 'kick_off', label: 'Kick off'),
    TossChoice(id: 'ends', label: 'Choose ends', givesFirstTurn: false),
  ];

  static const _map = <String, List<TossChoice>>{
    'cricket': _cricket,
    'badminton': _serveOrReceive,
    'table_tennis': _serveOrReceive,
    'tennis': [
      TossChoice(id: 'serve', label: 'Serve'),
      TossChoice(id: 'receive', label: 'Receive', givesFirstTurn: false),
      TossChoice(id: 'ends', label: 'Choose ends', givesFirstTurn: false),
    ],
    'volleyball': _serveOrReceive,
    'throwball': _serveOrReceive,
    'football': _kickOff,
    'hockey': [
      TossChoice(id: 'push_back', label: 'Push back'),
      TossChoice(id: 'ends', label: 'Choose ends', givesFirstTurn: false),
    ],
    'basketball': [
      TossChoice(id: 'possession', label: 'First possession'),
      TossChoice(id: 'ends', label: 'Choose ends', givesFirstTurn: false),
    ],
    'kabaddi': [
      TossChoice(id: 'raid', label: 'Raid first'),
      TossChoice(id: 'court', label: 'Choose court', givesFirstTurn: false),
    ],
    'kho_kho': [
      TossChoice(id: 'chase', label: 'Chase first'),
      TossChoice(id: 'defend', label: 'Defend first', givesFirstTurn: false),
    ],
    'chess': [
      // Not a toss in the usual sense — the drawing of lots decides colour,
      // and White moves first. Modelling it here rather than hiding it keeps
      // "who started" answerable for every sport.
      TossChoice(id: 'white', label: 'Play White'),
      TossChoice(id: 'black', label: 'Play Black', givesFirstTurn: false),
    ],
    'carrom': [
      TossChoice(id: 'break', label: 'Break'),
      TossChoice(id: 'white', label: 'Take White', givesFirstTurn: false),
    ],
  };

  /// The choices for a sport, or the generic pair for anything uncatalogued.
  /// Never empty — a match must always be able to record who started.
  static List<TossChoice> forSport(String sportId) =>
      _map[sportId] ??
      const [
        TossChoice(id: 'start', label: 'Start'),
        TossChoice(id: 'ends', label: 'Choose ends', givesFirstTurn: false),
      ];

  /// Whether this sport's toss decides who bats, which is the only case where
  /// the choice writes `battingFirst` into the scoring config.
  static bool decidesBatting(String sportId) => sportId == 'cricket';

  static TossChoice resolve(String sportId, String? id) {
    final list = forSport(sportId);
    return list.firstWhere((c) => c.id == id, orElse: () => list.first);
  }
}

/// One thing an organizer has to confirm before a scheduled match is pulled
/// forward and played now.
@immutable
class PreMatchCheck {
  const PreMatchCheck({
    required this.id,
    required this.label,
    this.detail,
  });

  /// Stored as a key on the fixture's `startedEarly.checks` map, so the answer
  /// survives as a record of what was agreed.
  final String id;

  final String label;

  /// The sport-specific nuance behind the question, shown under it.
  final String? detail;
}

/// What to ask before starting a match ahead of its scheduled time.
///
/// ## Why the questions are per sport
///
/// "Shall we play now?" is never the only question. A cricket match moved
/// forward has to settle which ball is being used, because a leather-ball
/// fixture played with a tennis ball is a different match and every bowling
/// figure it produces means something else. A badminton tie moved indoors
/// changes the shuttle. A football match brought forward by three hours is
/// played in daylight on a different surface.
///
/// These are the questions a captain actually asks in the ten minutes before
/// an unscheduled start, and the answers are recorded rather than merely
/// confirmed — an organizer saying "we agreed the same eleven" three weeks
/// later needs the app to be able to say whether they did.
class PreMatchChecks {
  const PreMatchChecks._();

  /// Asked for every sport: the two things that are true of any match.
  static const _universal = [
    PreMatchCheck(
      id: 'lineups_unchanged',
      label: 'Same teams as scheduled',
      detail: 'Tick only if neither side has changed its players.',
    ),
    PreMatchCheck(
      id: 'scorer_ready',
      label: 'A scorer is present and ready',
      detail: 'Nobody is standing at the board is how a match goes unrecorded.',
    ),
  ];

  static const _map = <String, List<PreMatchCheck>>{
    'cricket': [
      PreMatchCheck(
        id: 'same_ball',
        label: 'Same ball type as scheduled',
        detail: 'Leather, tennis or rubber — it changes what the figures mean.',
      ),
      PreMatchCheck(
        id: 'overs_unchanged',
        label: 'Same number of overs',
        detail: 'Shorten it in Rules first if the light will not last.',
      ),
      PreMatchCheck(
        id: 'umpires_present',
        label: 'Umpires in place',
      ),
    ],
    'badminton': [
      PreMatchCheck(
        id: 'same_shuttle',
        label: 'Same shuttle grade',
        detail: 'Feather and nylon do not play the same length.',
      ),
      PreMatchCheck(id: 'court_ready', label: 'Court free and net set'),
    ],
    'table_tennis': [
      PreMatchCheck(id: 'same_ball', label: 'Same ball type'),
      PreMatchCheck(id: 'table_ready', label: 'Table and net set'),
    ],
    'tennis': [
      PreMatchCheck(id: 'same_ball', label: 'Same ball type'),
      PreMatchCheck(id: 'court_ready', label: 'Court free and net set'),
    ],
    'football': [
      PreMatchCheck(id: 'referee_present', label: 'Referee present'),
      PreMatchCheck(
        id: 'surface_same',
        label: 'Same pitch and surface',
        detail: 'Turf and grass are different matches.',
      ),
    ],
    'hockey': [
      PreMatchCheck(id: 'umpires_present', label: 'Umpires in place'),
      PreMatchCheck(id: 'surface_same', label: 'Same pitch and surface'),
    ],
    'volleyball': [
      PreMatchCheck(id: 'net_height', label: 'Net at the agreed height'),
      PreMatchCheck(id: 'court_ready', label: 'Court free'),
    ],
    'kabaddi': [
      PreMatchCheck(id: 'mat_ready', label: 'Mat laid and lines marked'),
      PreMatchCheck(id: 'referee_present', label: 'Referee and umpires present'),
    ],
    'kho_kho': [
      PreMatchCheck(id: 'poles_set', label: 'Poles and lanes marked'),
      PreMatchCheck(id: 'referee_present', label: 'Referee present'),
    ],
    'basketball': [
      PreMatchCheck(id: 'referee_present', label: 'Referees present'),
      PreMatchCheck(id: 'clock_ready', label: 'Clock and shot clock working'),
    ],
    'chess': [
      PreMatchCheck(id: 'clock_ready', label: 'Clock set to the time control'),
    ],
    'carrom': [
      PreMatchCheck(id: 'board_ready', label: 'Board powdered and coins set'),
    ],
  };

  /// Everything to ask for [sportId] — its own questions first, then the two
  /// that apply to every sport.
  static List<PreMatchCheck> forSport(String sportId) => [
        ...?_map[sportId],
        ..._universal,
      ];
}

/// One sport in the platform catalogue.
///
/// A sport is data, not code. It names the plugin that scores it and the
/// default configuration that plugin should run with. That is what makes the
/// claim "an OS for all sports" real: adding kho-kho or throwball is a new
/// [SportSpec] entry, and adding a genuinely new *kind* of scoring is a new
/// plugin — never a change to a screen.
class SportSpec {
  const SportSpec({
    required this.id,
    required this.name,
    required this.pluginKey,
    required this.archetype,
    this.defaultEntrantType = EntrantType.individual,
    this.configOverrides = const {},
    this.icon = '🏅',
    this.unit,
  });

  final String id;
  final String name;
  final String pluginKey;
  final CompetitionArchetype archetype;
  final EntrantType defaultEntrantType;

  /// Values layered on top of the sport's default rule preset. Almost always
  /// empty: the presets in `rule_config.dart` are the single place rule
  /// numbers are written down, and this exists only for the handful of
  /// catalogue entries that reuse another sport's engine with a twist.
  final Map<String, dynamic> configOverrides;

  /// Every ruleset an organizer can pick for this sport, default first.
  List<RulePreset> get presets => RulePresets.forSport(id);

  /// The ruleset a new competition starts from.
  RulePreset? get defaultPreset => RulePresets.defaultFor(id);

  /// Passed to the plugin as [ScoringContext.config]. Copied onto the
  /// competition at creation time and then frozen, so improving a default
  /// here never rewrites a season already in play.
  Map<String, dynamic> get config =>
      RulePresets.resolve(sportId: id, overrides: configOverrides).toMap();

  final String icon;

  /// For performance sports: what is being measured ("seconds", "metres").
  final String? unit;

  bool get isPerformance => archetype == CompetitionArchetype.performance;

  /// The arrangements this sport is played in — singles and doubles, 11 or 8
  /// a side. See [SideFormat] for why a single number will not do.
  List<SideFormat> get sideFormats => SideFormats.forSport(id);

  SideFormat get defaultSideFormat => SideFormats.defaultFor(id);

  /// Every draw format this sport can actually run, default first.
  ///
  /// One list, used by every screen that sets a sport up — standalone event
  /// creation, season creation, and adding a sport to an existing season —
  /// so they cannot drift apart. Before this existed each screen kept its
  /// own copy, and two of the three silently dropped Groups+Knockout and
  /// Double Elimination even though the draw generator has always supported
  /// both; the season screens offered no choice at all and wrote Round
  /// Robin regardless of what the organizer actually needed.
  List<CompetitionFormat> get competitionFormats => isPerformance
      ? const [CompetitionFormat.finalOnly, CompetitionFormat.heatsThenFinal]
      : const [
          CompetitionFormat.roundRobin,
          CompetitionFormat.knockout,
          CompetitionFormat.groupThenKnockout,
          CompetitionFormat.doubleElimination,
          CompetitionFormat.swiss,
          CompetitionFormat.leagueTable,
        ];
}

/// The curated sport catalogue.
///
/// Deliberately weighted towards what Indian schools, colleges, communities
/// and district associations actually run, rather than a generic global list
/// where half the entries are unusable.
class SportCatalog {
  const SportCatalog._();

  static const List<SportSpec> all = [
    // Rule numbers deliberately do not appear here. Each sport's parameters
    // live in `rule_config.dart` as named presets, so a league can pick
    // "Ultimate Kho Kho — Season 2" or "BWF 3x15" rather than inheriting one
    // hard-coded ruleset. `SportSpec.config` resolves the default preset.

    // --- Bat and ball -----------------------------------------------------
    SportSpec(
      id: 'cricket',
      name: 'Cricket',
      pluginKey: CricketPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F3CF}',
    ),

    // --- Racquet / net ----------------------------------------------------
    SportSpec(
      id: 'badminton',
      name: 'Badminton',
      pluginKey: BadmintonPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '\u{1F3F8}',
    ),
    SportSpec(
      id: 'table_tennis',
      name: 'Table Tennis',
      pluginKey: TableTennisPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '\u{1F3D3}',
    ),
    SportSpec(
      id: 'volleyball',
      name: 'Volleyball',
      pluginKey: VolleyballPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F3D0}',
    ),
    SportSpec(
      id: 'tennis',
      name: 'Tennis',
      pluginKey: TennisPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '\u{1F3BE}',
    ),

    // --- Field / court, goal scoring --------------------------------------
    SportSpec(
      id: 'football',
      name: 'Football',
      pluginKey: FootballPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u26BD',
    ),
    SportSpec(
      id: 'basketball',
      name: 'Basketball',
      pluginKey: BasketballPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F3C0}',
    ),
    SportSpec(
      id: 'kabaddi',
      name: 'Kabaddi',
      pluginKey: KabaddiPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F93C}',
    ),
    SportSpec(
      id: 'hockey',
      name: 'Hockey',
      pluginKey: HockeyPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F3D1}',
    ),
    SportSpec(
      id: 'kho_kho',
      name: 'Kho Kho',
      pluginKey: KhoKhoPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F3C3}',
    ),
    SportSpec(
      id: 'throwball',
      name: 'Throwball',
      pluginKey: SetBasedPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '\u{1F93E}',
      // Reuses the generic set engine; throwball ships no preset of its own.
      configOverrides: {'pointsPerSet': 25, 'setsToWin': 2, 'winBy': 2},
    ),

    // --- Mind sports ------------------------------------------------------
    SportSpec(
      id: 'chess',
      name: 'Chess',
      pluginKey: ChessPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '\u265F',
    ),
    SportSpec(
      id: 'carrom',
      name: 'Carrom',
      pluginKey: CarromPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '\u{1F3AF}',
    ),

    // --- Performance sports (no opponent) ---------------------------------
    // These produce measured results rather than fixtures. Modelling them is
    // what allows a school athletics meet to run at all.
    SportSpec(
      id: 'athletics_sprint',
      name: 'Athletics \u2014 Track',
      pluginKey: AthleticsPlugin.pluginKey,
      archetype: CompetitionArchetype.performance,
      icon: '\u{1F3C3}',
      unit: 'seconds',
    ),
    SportSpec(
      id: 'athletics_field',
      name: 'Athletics \u2014 Field',
      pluginKey: AthleticsPlugin.pluginKey,
      archetype: CompetitionArchetype.performance,
      icon: '\u{1F94F}',
      unit: 'metres',
    ),
    SportSpec(
      id: 'swimming',
      name: 'Swimming',
      pluginKey: AthleticsPlugin.pluginKey,
      archetype: CompetitionArchetype.performance,
      icon: '\u{1F3CA}',
      unit: 'seconds',
      configOverrides: {'discipline': 'track', 'lowerIsBetter': true},
    ),

    // --- Escape hatch -----------------------------------------------------
    // An organizer must never be blocked because we have not catalogued
    // their sport yet.
    SportSpec(
      id: 'other',
      name: 'Other sport',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '\u{1F3C5}',
    ),
  ];

  static SportSpec byId(String id) => all.firstWhere(
        (s) => s.id == id,
        orElse: () => all.last,
      );

  static List<SportSpec> get versusSports =>
      all.where((s) => s.archetype == CompetitionArchetype.versus).toList();

  static List<SportSpec> get performanceSports =>
      all.where((s) => s.isPerformance).toList();
}

/// Resolves a plugin key to its implementation.
///
/// Lookup never fails: an unknown key falls back to simple points so that a
/// competition created by a newer build still opens — and still scores — in
/// an older one, rather than showing a permanently broken match screen.
class ScoringRegistry {
  const ScoringRegistry._();

  static const SimplePointsPlugin _fallback = SimplePointsPlugin();

  static const Map<String, ScoringPlugin> _plugins = {
    SimplePointsPlugin.pluginKey: SimplePointsPlugin(),
    SetBasedPlugin.pluginKey: SetBasedPlugin(),
    GoalBasedPlugin.pluginKey: GoalBasedPlugin(),
    CricketPlugin.pluginKey: CricketPlugin(),
    FootballPlugin.pluginKey: FootballPlugin(),
    BasketballPlugin.pluginKey: BasketballPlugin(),
    KabaddiPlugin.pluginKey: KabaddiPlugin(),
    VolleyballPlugin.pluginKey: VolleyballPlugin(),
    KhoKhoPlugin.pluginKey: KhoKhoPlugin(),
    TennisPlugin.pluginKey: TennisPlugin(),
    TableTennisPlugin.pluginKey: TableTennisPlugin(),
    HockeyPlugin.pluginKey: HockeyPlugin(),
    BadmintonPlugin.pluginKey: BadmintonPlugin(),
    ChessPlugin.pluginKey: ChessPlugin(),
    CarromPlugin.pluginKey: CarromPlugin(),
    AthleticsPlugin.pluginKey: AthleticsPlugin(),
  };

  static ScoringPlugin resolve(String? key) => _plugins[key] ?? _fallback;

  static ScoringPlugin forSport(String sportId) =>
      resolve(SportCatalog.byId(sportId).pluginKey);

  static Iterable<ScoringPlugin> get all => _plugins.values;
}
