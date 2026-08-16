import 'firestore_codec.dart';

/// The organizer's choices about the *shape* of a draw.
///
/// These are all parameters `FixtureGenerator.generate` has always accepted
/// and that `CompetitionRepository.generateDraw` never passed — so a
/// groups+knockout competition always took the fallback of roughly four per
/// group with two qualifiers each, whatever the organizer intended, and there
/// was nowhere to record otherwise. Grouping them into one object keeps the
/// call site honest: adding a knob to the generator now means adding it here,
/// where it is persisted, rather than quietly defaulting it.
///
/// Stored as a nested map on the competition so the whole set round-trips
/// together. A draw that cannot say how it was built cannot be regenerated
/// identically after a withdrawal, and explaining a bracket to an organizer
/// who is challenging it is most of what a tournament referee does.
class DrawConfig {
  const DrawConfig({
    this.useGroups = false,
    this.numGroups,
    this.groupSize,
    this.qualifiersPerGroup = 2,
    this.doubleRoundRobin = false,
    this.bracketReset = true,
    this.shuffleSeed,
    this.method = 'ranked',
    this.seedFromRatings = false,
  });

  /// Split the field into groups, whatever the format.
  ///
  /// Groups used to be welded to [CompetitionFormat.groupThenKnockout], which
  /// made "put them in pools" a decision about the *knockout* stage. An
  /// organizer with thirty entrants who wants six groups of five and no
  /// knockout had nowhere to say so, and one round robin of thirty is 435
  /// matches nobody will play. With this set:
  ///
  /// - a round robin or league becomes **pools** — a round robin inside each
  ///   group, standings per group, no knockout;
  /// - a knockout gains a group stage in front of it, exactly as
  ///   Groups+Knockout has always done.
  ///
  /// Implied (and therefore ignored) for [CompetitionFormat.groupThenKnockout],
  /// which is the same thing said in the format.
  final bool useGroups;

  /// How many groups. Takes priority over [groupSize].
  final int? numGroups;

  /// Groups+knockout: entrants per group. Used only when [numGroups] is null.
  final int? groupSize;

  /// Groups+knockout: how many from each group reach the knockout phase.
  final int qualifiersPerGroup;

  /// Round robin / league: play a second leg with sides swapped.
  final bool doubleRoundRobin;

  /// Double elimination: carry a decider for the case where the
  /// losers-bracket champion beats the undefeated winners-bracket champion.
  final bool bracketReset;

  /// Fixes the shuffle so regenerating a draw produces the same bracket.
  ///
  /// Recorded rather than left to the generator's internal default because
  /// "why did the draw change when you re-ran it?" is a question an organizer
  /// will be asked, and the answer has to be checkable.
  final int? shuffleSeed;

  /// `DrawMethod.wire` — how the field is arranged into the bracket.
  ///
  /// Stored as the raw token rather than the enum so this model stays free of
  /// a domain import; the generator parses it. Defaults to a ranked ladder,
  /// which is what every draw made before this field existed was.
  final String method;

  /// Whether seeds are computed from Glicko-2 at draw time.
  ///
  /// Off by default, because turning it on retroactively would reseed events
  /// whose organizer chose their seeds by hand. When on, `generateDraw` ranks
  /// the field by rating and refuses to seed anyone whose rating is not yet
  /// evidence — see `SeedingPolicy`.
  final bool seedFromRatings;

  static DrawConfig fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DrawConfig();
    return DrawConfig(
      useGroups: Fs.boolean(m['useGroups']),
      numGroups: Fs.intOrNull(m['numGroups']),
      groupSize: Fs.intOrNull(m['groupSize']),
      qualifiersPerGroup: Fs.integer(m['qualifiersPerGroup'], 2),
      doubleRoundRobin: Fs.boolean(m['doubleRoundRobin']),
      // Defaults true, so a missing key must not read as false.
      bracketReset: m['bracketReset'] is bool
          ? m['bracketReset'] as bool
          : true,
      shuffleSeed: Fs.intOrNull(m['shuffleSeed']),
      method: Fs.str(m['method'], 'ranked'),
      seedFromRatings: Fs.boolean(m['seedFromRatings']),
    );
  }

  Map<String, Object?> toMap() => {
        'useGroups': useGroups,
        'numGroups': numGroups,
        'groupSize': groupSize,
        'qualifiersPerGroup': qualifiersPerGroup,
        'doubleRoundRobin': doubleRoundRobin,
        'bracketReset': bracketReset,
        'shuffleSeed': shuffleSeed,
        'method': method,
        'seedFromRatings': seedFromRatings,
      };

  DrawConfig copyWith({
    bool? useGroups,
    int? numGroups,
    int? groupSize,
    int? qualifiersPerGroup,
    bool? doubleRoundRobin,
    bool? bracketReset,
    int? shuffleSeed,
    String? method,
    bool? seedFromRatings,
  }) =>
      DrawConfig(
        useGroups: useGroups ?? this.useGroups,
        numGroups: numGroups ?? this.numGroups,
        groupSize: groupSize ?? this.groupSize,
        qualifiersPerGroup: qualifiersPerGroup ?? this.qualifiersPerGroup,
        doubleRoundRobin: doubleRoundRobin ?? this.doubleRoundRobin,
        bracketReset: bracketReset ?? this.bracketReset,
        shuffleSeed: shuffleSeed ?? this.shuffleSeed,
        method: method ?? this.method,
        seedFromRatings: seedFromRatings ?? this.seedFromRatings,
      );
}

/// The organizer's choices about *when and where* a draw's matches are played.
///
/// Absent this, every fixture in a draw was stamped with the competition's
/// single `startDate` and its single `venue` string — so a 38-entrant
/// tournament told all 38 entrants to arrive at 10:00, which is how a day that
/// was planned to finish at six finishes at eleven.
class ScheduleConfig {
  const ScheduleConfig({
    this.courts = const [],
    this.venueIds = const [],
    this.matchMinutes = 30,
    this.changeoverMinutes = 5,
    this.restGapMinutes = 20,
    this.dayStartHour = 9,
    this.dayEndHour = 19,
  });

  /// Venues this draw may be played at — ids into `orgs/{orgId}/venues`.
  ///
  /// This is the field that makes cross-event scheduling possible, and
  /// [courts] is why it had to be added. A typed court name is a fact local
  /// to one draw: the U-13 event's "Court 1" and the senior event's "Court 1"
  /// are unrelated strings, so nothing could tell that two draws were
  /// competing for the same physical court — which is exactly the contention
  /// that overruns a tournament day. A venue id resolves to the same [Court]
  /// objects for every event that names it.
  ///
  /// Empty means fall back to [courts], so a standalone club event that just
  /// wants to type "Court 1, Court 2" still can.
  final List<String> venueIds;

  /// Ad-hoc playing-area names, for a draw that is not part of a tournament
  /// and whose organizer has not set up a venue.
  ///
  /// Retained rather than removed because most club events are exactly this:
  /// one afternoon, two courts, nobody wants to fill in a venue form first.
  /// [venueIds] takes precedence whenever it is set.
  final List<String> courts;

  /// Planned duration of one match, before changeover. The single biggest
  /// lever on whether a day finishes on time, and deliberately per-competition
  /// rather than global: a U13 singles and a men's doubles final are not the
  /// same match.
  final int matchMinutes;

  /// Time between matches on the same court — players off, players on.
  final int changeoverMinutes;

  /// Minimum rest an entrant gets between two of their own matches.
  ///
  /// The reason a schedule is not simply "fill the courts": the same player
  /// reaching a quarter-final and a semi-final on one day must not be called
  /// straight from one to the other.
  final int restGapMinutes;

  final int dayStartHour;
  final int dayEndHour;

  /// One match plus its changeover — the true spacing between successive
  /// matches on a court.
  int get slotMinutes => matchMinutes + changeoverMinutes;

  /// Whether this draw has anywhere at all to be scheduled into.
  bool get hasCourts => courts.isNotEmpty || venueIds.isNotEmpty;

  /// Whether courts come from real venue documents rather than typed text.
  bool get usesVenues => venueIds.isNotEmpty;

  static ScheduleConfig fromMap(Map<String, dynamic>? m) {
    if (m == null) return const ScheduleConfig();
    return ScheduleConfig(
      courts: Fs.strList(m['courts']),
      venueIds: Fs.strList(m['venueIds']),
      matchMinutes: Fs.integer(m['matchMinutes'], 30),
      changeoverMinutes: Fs.integer(m['changeoverMinutes'], 5),
      restGapMinutes: Fs.integer(m['restGapMinutes'], 20),
      dayStartHour: Fs.integer(m['dayStartHour'], 9),
      dayEndHour: Fs.integer(m['dayEndHour'], 19),
    );
  }

  Map<String, Object?> toMap() => {
        'courts': courts,
        'venueIds': venueIds,
        'matchMinutes': matchMinutes,
        'changeoverMinutes': changeoverMinutes,
        'restGapMinutes': restGapMinutes,
        'dayStartHour': dayStartHour,
        'dayEndHour': dayEndHour,
      };

  ScheduleConfig copyWith({
    List<String>? courts,
    List<String>? venueIds,
    int? matchMinutes,
    int? changeoverMinutes,
    int? restGapMinutes,
    int? dayStartHour,
    int? dayEndHour,
  }) =>
      ScheduleConfig(
        courts: courts ?? this.courts,
        venueIds: venueIds ?? this.venueIds,
        matchMinutes: matchMinutes ?? this.matchMinutes,
        changeoverMinutes: changeoverMinutes ?? this.changeoverMinutes,
        restGapMinutes: restGapMinutes ?? this.restGapMinutes,
        dayStartHour: dayStartHour ?? this.dayStartHour,
        dayEndHour: dayEndHour ?? this.dayEndHour,
      );
}


/// How a league awards match points.
///
/// ## Why 3/1/0 is not enough
///
/// The product has always had `pointsForWin` / `pointsForDraw` /
/// `pointsForLoss`, which covers football and most club leagues and is simply
/// wrong for two sports it already supports:
///
/// - **Volleyball (FIVB).** A 3-0 or 3-1 win is worth 3 and the loser nothing;
///   a 3-2 win is worth 2 and the loser 1. A five-set match is a different
///   result from a straight-sets one and the table is supposed to say so.
/// - **Kabaddi and rugby-shaped leagues.** A team beaten by less than a set
///   margin takes a losing bonus point.
///
/// Both are "the margin changes the points", which a flat win/draw/loss triple
/// cannot express at all. Off by default, so every existing league keeps
/// exactly the points it has been awarding.
class MatchPointsModel {
  const MatchPointsModel({
    this.enabled = false,
    this.closeWin = 2,
    this.closeLoss = 1,
    this.closeMarginAtMost = 1,
    this.losingBonusWithin = 0,
    this.losingBonusPoints = 1,
  });

  /// When false, the plain `pointsForWin/Draw/Loss` triple is used and nothing
  /// here applies.
  final bool enabled;

  /// Points to the winner of a match decided by a narrow margin.
  final int closeWin;

  /// Points to the loser of one.
  final int closeLoss;

  /// What counts as narrow, measured in the sport's own score unit — sets for
  /// volleyball, so 1 means a 3-2. Zero disables the close-match split.
  final int closeMarginAtMost;

  /// A losing team within this margin takes [losingBonusPoints]. Zero
  /// disables the bonus entirely, which is the default.
  final int losingBonusWithin;

  final int losingBonusPoints;

  /// Points for one result, given the margin the winner won by.
  ///
  /// [margin] is always non-negative — the winner's score minus the loser's.
  ({int winner, int loser}) award({
    required int margin,
    required int pointsForWin,
    required int pointsForLoss,
  }) {
    if (!enabled) return (winner: pointsForWin, loser: pointsForLoss);

    if (closeMarginAtMost > 0 && margin <= closeMarginAtMost) {
      return (winner: closeWin, loser: closeLoss);
    }
    if (losingBonusWithin > 0 && margin <= losingBonusWithin) {
      return (winner: pointsForWin, loser: pointsForLoss + losingBonusPoints);
    }
    return (winner: pointsForWin, loser: pointsForLoss);
  }

  static MatchPointsModel fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MatchPointsModel();
    return MatchPointsModel(
      enabled: Fs.boolean(m['enabled']),
      closeWin: Fs.integer(m['closeWin'], 2),
      closeLoss: Fs.integer(m['closeLoss'], 1),
      closeMarginAtMost: Fs.integer(m['closeMarginAtMost'], 1),
      losingBonusWithin: Fs.integer(m['losingBonusWithin']),
      losingBonusPoints: Fs.integer(m['losingBonusPoints'], 1),
    );
  }

  Map<String, Object?> toMap() => {
        'enabled': enabled,
        'closeWin': closeWin,
        'closeLoss': closeLoss,
        'closeMarginAtMost': closeMarginAtMost,
        'losingBonusWithin': losingBonusWithin,
        'losingBonusPoints': losingBonusPoints,
      };

  /// FIVB: 3 for a 3-0 or 3-1, 2/1 for a 3-2.
  static const volleyball = MatchPointsModel(
    enabled: true,
    closeWin: 2,
    closeLoss: 1,
    closeMarginAtMost: 1,
  );
}
