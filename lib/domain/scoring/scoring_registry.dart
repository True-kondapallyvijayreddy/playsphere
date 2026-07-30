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
