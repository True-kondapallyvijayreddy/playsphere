/// How many groups a field of a given size is allowed to be split into.
///
/// A group stage has two hard edges and organizers hit both. Too few groups
/// and each one is a nine- or ten-team round robin — 36 or 45 matches for a
/// phase whose only job is to seed a knockout, which is how a two-day event
/// becomes a four-day one. Too many and a "group" is a single pair, or worse
/// a lone entrant who advances without playing anybody.
///
/// This lives in the domain layer rather than in the setup sheet because the
/// rule is a property of a draw, not of a screen. It was written down twice
/// before — once as constants in a generator nothing called, once as a
/// stepper bound that allowed groups of ten — and the two disagreed.
class GroupBounds {
  const GroupBounds._();

  /// A group of one is not a group: its occupant qualifies unbeaten and
  /// unplayed.
  static const int minPerGroup = 2;

  /// Above this a group stage costs more matches than the knockout it feeds.
  static const int maxPerGroup = 8;

  /// Fewest groups that keeps every group at or under [maxPerGroup].
  static int minGroups(int entrants) {
    if (entrants <= 0) return 1;
    final needed = (entrants / maxPerGroup).ceil();
    return needed < 1 ? 1 : needed;
  }

  /// Most groups that keeps every group at or above [minPerGroup] and still
  /// leaves each one able to supply its qualifiers — a group of two that
  /// advances three is not a draw.
  ///
  /// When a field is too small to satisfy both edges at once (five entrants
  /// with three qualifying, say) the [minGroups] floor wins, because a
  /// schedule that exists and is slightly over-sized beats no schedule.
  static int maxGroups(int entrants, {int qualifiersPerGroup = 2}) {
    if (entrants <= 0) return 1;
    final qualifiers = qualifiersPerGroup < 1 ? 1 : qualifiersPerGroup;
    final bySize = entrants ~/ minPerGroup;
    final byQualifiers = entrants ~/ qualifiers;
    final upper = bySize < byQualifiers ? bySize : byQualifiers;
    final floor = minGroups(entrants);
    return upper < floor ? floor : upper;
  }

  /// The group count a draw will actually use.
  ///
  /// [requested] is the organizer's choice when they have made one. Null
  /// means "you decide", which aims at five a group — comfortably inside both
  /// edges, and the size most federations run.
  static int resolve({
    required int entrants,
    int? requested,
    int qualifiersPerGroup = 2,
  }) {
    if (entrants <= 0) return 1;
    final want = requested ?? (entrants / 5).ceil();
    final lower = minGroups(entrants);
    final upper = maxGroups(entrants, qualifiersPerGroup: qualifiersPerGroup);
    return want.clamp(lower, upper);
  }

  /// Size of the largest group once [entrants] are dealt into [groups].
  static int largestGroupSize(int entrants, int groups) {
    if (groups <= 0) return entrants;
    return (entrants / groups).ceil();
  }

  /// Size of the smallest group once [entrants] are dealt into [groups].
  static int smallestGroupSize(int entrants, int groups) {
    if (groups <= 0) return entrants;
    return entrants ~/ groups;
  }
}
