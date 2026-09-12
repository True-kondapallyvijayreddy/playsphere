import 'package:intl/intl.dart';

import '../../core/models/tournament_official.dart';
import '../scoring/scoring_registry.dart';
import 'draft_season_plan.dart';

/// The prefix on a roster id belonging to somebody with no PlaySphere account.
///
/// A roster entry is keyed by uid, because that is what makes an assignment
/// land on the right person's record. The club treasurer's uncle umpiring the
/// final has no uid, and refusing to let him on the panel for that reason
/// would be the app failing at the most ordinary case in Indian club sport.
/// So a guest gets a generated id, and this prefix is what tells every screen
/// afterwards that there is no account behind it: no profile to open, no
/// notification to send, and — because `Fixture.officials` carries the same
/// id — a name on the team sheet that is honest about being just a name.
const String guestOfficialPrefix = 'guest_';

/// Mints one. Microseconds rather than milliseconds, because two officials
/// added in the same breath must not collide onto one roster row.
String newGuestOfficialId() =>
    '$guestOfficialPrefix${DateTime.now().microsecondsSinceEpoch}';

/// Whether [uid] belongs to a guest rather than an account.
bool isGuestOfficial(String uid) => uid.startsWith(guestOfficialPrefix);

/// What the officiating panel can cover, against what the season needs.
///
/// ## Why capacity is two numbers and a list, not one number
///
/// A panel is not short of people in the way a season is short of courts. It
/// can have plenty of capacity and still fail, because officiating is not
/// fungible: the two people who know the kabaddi rules are not the ones who
/// can call a badminton service fault. So "enough hands" and "somebody for
/// every sport" are checked separately, and the second is the one that reads
/// as a complete panel right up until Saturday morning.
class OfficialsCoverage {
  const OfficialsCoverage({
    required this.matches,
    required this.capacity,
    required this.uncoveredSports,
  });

  /// Matches that will need somebody standing at them.
  final int matches;

  /// Match-slots the panel can take across the season — every official's
  /// daily limit, counted only on the days they said they can come.
  final int capacity;

  /// Sports in this season that nobody on the panel covers.
  final List<String> uncoveredSports;

  bool get isEmpty => matches == 0;
  bool get fits => capacity >= matches && uncoveredSports.isEmpty;
  int get shortfall => capacity >= matches ? 0 : matches - capacity;

  /// Works the numbers out from a panel and the season it is for.
  static OfficialsCoverage of({
    required List<TournamentOfficial> panel,
    required List<SeasonEventPlan> events,
    required List<SeasonDayLoad> days,
  }) {
    var matches = 0;
    final sports = <String>{};
    for (final e in events) {
      final required = e.matchesRequired;
      if (required == 0) continue;
      matches += required;
      sports.add(e.sportId);
    }

    // Days the season actually plays on. An official free every day of a
    // ten-day window that finishes in three has three days of capacity, not
    // ten — counting the window would promise cover that never turns up.
    final dayKeys = [
      for (final d in days)
        if (!d.isEmpty) DateFormat('yyyy-MM-dd').format(d.day),
    ];

    var capacity = 0;
    for (final official in panel) {
      final limit =
          official.maxMatchesPerDay < 1 ? 1 : official.maxMatchesPerDay;
      if (dayKeys.isEmpty) {
        capacity += limit;
        continue;
      }
      for (final key in dayKeys) {
        if (official.isFreeOn(key)) capacity += limit;
      }
    }

    final uncovered = <String>[];
    for (final sportId in sports) {
      if (!panel.any((o) => o.coversSport(sportId))) {
        uncovered.add(SportCatalog.byId(sportId).name);
      }
    }

    return OfficialsCoverage(
      matches: matches,
      capacity: capacity,
      uncoveredSports: uncovered,
    );
  }
}
