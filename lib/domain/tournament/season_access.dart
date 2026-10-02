import '../../core/models/tournament_official.dart';
import '../../core/permissions/capability.dart';

/// Who is looking at a season, which decides what the season page is.
///
/// A season page is read by three kinds of people who want three different
/// pages, and it used to be one page with the organizer's controls sprinkled
/// through it behind individual checks — so every new card was one forgotten
/// `if (canManage)` away from showing a member an "Assign" button, and the
/// umpire panel's own screen checked nothing at all.
///
/// This is the one place that decides. Every season surface asks it, and the
/// widget tests pin what each role sees.
enum SeasonRole {
  /// Runs the season: the host club's owner, admins and event managers — the
  /// ranks `firestore.rules` admits through `canManageCompetitions`. Sees and
  /// does everything: drafts, the timetable builder, the umpire panel, the
  /// venue planner, who is in charge, what needs attention.
  organizer,

  /// Officiates in it: on this season's umpire panel, or holding the club's
  /// scorer rank or officials brief. Reads the season like everybody else,
  /// plus their own assignments and the umpires working each sport. Changes
  /// nothing about the season itself.
  official,

  /// Everybody else — members, players, parents, visitors. The plain page:
  /// where the season is, who is winning, what is on and what is next.
  spectator,
}

class SeasonAccess {
  const SeasonAccess(this.role);

  final SeasonRole role;

  static SeasonAccess resolve({
    required Set<Capability> capabilities,
    required String? uid,
    required List<TournamentOfficial> roster,
  }) {
    if (capabilities.contains(Capability.manageCompetitions)) {
      return const SeasonAccess(SeasonRole.organizer);
    }
    final onPanel = uid != null && roster.any((o) => o.uid == uid);
    if (onPanel || capabilities.contains(Capability.scoreMatches)) {
      return const SeasonAccess(SeasonRole.official);
    }
    return const SeasonAccess(SeasonRole.spectator);
  }

  bool get isOrganizer => role == SeasonRole.organizer;
  bool get isOfficial => role == SeasonRole.official;

  /// Every control that changes the season: editing, scheduling, the umpire
  /// panel, venues, leads, entries. Organizers only.
  bool get canManage => isOrganizer;

  /// Draft fixtures are an organizer's preview against placeholder sides —
  /// "Team A v Team B" — and mean nothing to anyone else.
  bool get seesDrafts => isOrganizer;

  /// Who is umpiring each sport. Organizers staff it; officials work
  /// alongside each other. A spectator has no use for a list of umpires.
  bool get seesUmpires => isOrganizer || isOfficial;

  /// Staffing gaps, who is in charge, organizer head-counts — the running of
  /// the season rather than the season.
  bool get seesStaffing => isOrganizer;
}
