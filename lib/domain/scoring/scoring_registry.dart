import '../../core/models/enums.dart';
import 'plugins/basketball_plugin.dart';
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
import 'scoring_plugin.dart';

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
    this.config = const {},
    this.icon = '🏅',
    this.unit,
  });

  final String id;
  final String name;
  final String pluginKey;
  final CompetitionArchetype archetype;
  final EntrantType defaultEntrantType;

  /// Passed to the plugin as [ScoringContext.config]. Copied onto the
  /// competition at creation time and then frozen, so improving a default
  /// here never rewrites a season already in play.
  final Map<String, dynamic> config;

  final String icon;

  /// For performance sports: what is being measured ("seconds", "metres").
  final String? unit;

  bool get isPerformance => archetype == CompetitionArchetype.performance;
}

/// The curated sport catalogue.
///
/// Deliberately weighted towards what Indian schools, colleges, communities
/// and district associations actually run, rather than a generic global list
/// where half the entries are unusable.
class SportCatalog {
  const SportCatalog._();

  static const List<SportSpec> all = [
    // --- Bat and ball -----------------------------------------------------
    SportSpec(
      id: 'cricket',
      name: 'Cricket',
      pluginKey: CricketPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🏏',
      config: {
        'oversPerInnings': 20,
        'ballsPerOver': 6,
        'playersPerTeam': 11,
      },
    ),

    // --- Racquet / net ----------------------------------------------------
    SportSpec(
      id: 'badminton',
      name: 'Badminton',
      pluginKey: SetBasedPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '🏸',
      // 21 a game, best of three, win by two, hard cap at 30.
      config: {
        'pointsPerSet': 21,
        'setsToWin': 2,
        'winBy': 2,
        'hardCap': 30,
      },
    ),
    SportSpec(
      id: 'table_tennis',
      name: 'Table Tennis',
      pluginKey: TableTennisPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '🏓',
      // 11 a game, best of five, win by two, no cap.
      config: {
        'pointsPerSet': 11,
        'setsToWin': 3,
        'winBy': 2,
      },
    ),
    SportSpec(
      id: 'volleyball',
      name: 'Volleyball',
      pluginKey: VolleyballPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🏐',
      // 25 a set, best of five, but the deciding fifth set is only to 15.
      config: {
        'pointsPerSet': 25,
        'decidingSetPoints': 15,
        'setsToWin': 3,
        'winBy': 2,
      },
    ),
    SportSpec(
      id: 'tennis',
      name: 'Tennis',
      pluginKey: TennisPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '🎾',
      config: {
        'setsToWin': 2,
        'gamesPerSet': 6,
        'tiebreakTo': 7,
        'noAd': false,
        'decidingSetTiebreak': false,
      },
    ),

    // --- Field / court, goal scoring --------------------------------------
    SportSpec(
      id: 'football',
      name: 'Football',
      pluginKey: FootballPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '⚽',
      config: {'periods': 2, 'periodLabel': 'Half', 'allowDraw': true},
    ),
    SportSpec(
      id: 'basketball',
      name: 'Basketball',
      pluginKey: BasketballPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🏀',
      config: {
        'periods': 4,
        'periodLabel': 'Quarter',
        'foulOutAt': 5,
      },
    ),
    SportSpec(
      id: 'kabaddi',
      name: 'Kabaddi',
      pluginKey: KabaddiPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🤼',
      config: {
        'periods': 2,
        'periodLabel': 'Half',
        'playersOnCourt': 7,
        'bonusMinDefenders': 6,
        'superTackleMaxDefenders': 3,
        'superRaidPoints': 3,
      },
    ),
    SportSpec(
      id: 'hockey',
      name: 'Hockey',
      pluginKey: HockeyPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🏑',
      config: {'periods': 4, 'periodLabel': 'Quarter', 'allowDraw': true},
    ),
    SportSpec(
      id: 'kho_kho',
      name: 'Kho Kho',
      pluginKey: KhoKhoPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🏃',
      // Ultimate Kho Kho season-2 style values. Every one is overridable —
      // they differ between UKK seasons and KKFI-aligned rulesets, and an
      // engine that hard-coded them would be wrong for whichever league it
      // was not written against.
      config: {
        'tagPoints': 2,
        'poleDivePoints': 2,
        'skyDivePoints': 2,
        'allOutBonus': 4,
        'batchSize': 3,
        'turnsPerInnings': 2,
        'dreamRunAfterSeconds': 180,
        'dreamRunEverySeconds': 30,
      },
    ),
    SportSpec(
      id: 'throwball',
      name: 'Throwball',
      pluginKey: SetBasedPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      defaultEntrantType: EntrantType.team,
      icon: '🤾',
      config: {'pointsPerSet': 25, 'setsToWin': 2, 'winBy': 2},
    ),

    // --- Mind sports ------------------------------------------------------
    SportSpec(
      id: 'chess',
      name: 'Chess',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '♟️',
      config: {'target': 1, 'winBy': 1, 'allowDraw': true},
    ),
    SportSpec(
      id: 'carrom',
      name: 'Carrom',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '🎯',
      config: {'target': 25, 'winBy': 1, 'allowDraw': false},
    ),

    // --- Performance sports (no opponent) ---------------------------------
    // These produce measured results rather than fixtures. Modelling them is
    // what allows a school athletics meet to run at all.
    SportSpec(
      id: 'athletics_sprint',
      name: 'Athletics — Track',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.performance,
      icon: '🏃',
      unit: 'seconds',
    ),
    SportSpec(
      id: 'athletics_field',
      name: 'Athletics — Field',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.performance,
      icon: '🥏',
      unit: 'metres',
    ),
    SportSpec(
      id: 'swimming',
      name: 'Swimming',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.performance,
      icon: '🏊',
      unit: 'seconds',
    ),

    // --- Escape hatch -----------------------------------------------------
    // An organizer must never be blocked because we have not catalogued
    // their sport yet.
    SportSpec(
      id: 'other',
      name: 'Other sport',
      pluginKey: SimplePointsPlugin.pluginKey,
      archetype: CompetitionArchetype.versus,
      icon: '🏅',
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
  };

  static ScoringPlugin resolve(String? key) => _plugins[key] ?? _fallback;

  static ScoringPlugin forSport(String sportId) =>
      resolve(SportCatalog.byId(sportId).pluginKey);

  static Iterable<ScoringPlugin> get all => _plugins.values;
}
