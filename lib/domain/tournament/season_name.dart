import '../../core/models/tournament.dart';

/// What a season or tournament may be called.
///
/// One place for the three rules, because five screens ask for a name (both
/// season forms, both tournament forms and the edit sheet) and the rules are
/// also enforced in `firestore.rules`. A limit the form does not know about is
/// worse than none: season creation is not awaited on the server, so the
/// organizer lands on the new season page and watches it disappear when the
/// commit is refused.
///
/// - At least [minLength] characters.
/// - At most [maxLength] characters. The rules refuse anything longer.
/// - Distinct inside the club. Two live seasons both called "Sports Week
///   2026" are two different registration pages behind one name. People
///   register for the wrong one, and invitations and pushes can't say which
///   is meant. The comparison ignores case and repeated spaces. Cancelled
///   seasons don't count, so a called-off season can be set up again under
///   its own name.
class SeasonName {
  const SeasonName._();

  static const int minLength = 3;

  /// Mirrors `firestore.rules` (`match /tournaments/{tournamentId}`).
  static const int maxLength = 120;

  /// The name as it is stored: trimmed, with runs of whitespace collapsed.
  static String normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// What two names are compared by. Matches `Tournament.nameLower` for any
  /// name saved through [normalize].
  static String key(String raw) => normalize(raw).toLowerCase();

  /// Whether saving [after] over a season called [before] renames it.
  ///
  /// Only a rename is held to these rules. A season from before they
  /// existed — two old seasons both called "Sports Week 2026", or one called
  /// "U9" — must still have its dates, grounds and fees edited without being
  /// made to change a name nobody is changing. `firestore.rules` draws the
  /// same line: its length bound applies only when `name` changes.
  ///
  /// Case and spacing are not a rename: they do not change what the name is
  /// compared by.
  static bool isRename(String before, String after) => key(before) != key(after);

  /// The name to store when [after] is saved over [before]: [before] exactly
  /// when nothing but its spacing would change, so an old name the rules
  /// would now refuse is not rewritten — and re-judged — by an edit that
  /// never touched it.
  static String toStore(String before, String after) =>
      normalize(after) == normalize(before) ? before : normalize(after);

  /// Keys of the names [existing] seasons already hold, leaving out
  /// cancelled ones and [exceptId] (the season being renamed).
  static Set<String> takenKeys(
    Iterable<Tournament> existing, {
    String? exceptId,
  }) =>
      {
        for (final t in existing)
          if (t.id != exceptId && t.status != TournamentStatus.cancelled)
            key(t.name),
      };

  /// Why [raw] cannot be used, or null when it can.
  ///
  /// [noun] is what the organizer is naming ("season", "tournament").
  static String? problem(
    String raw, {
    Set<String> taken = const {},
    String noun = 'season',
  }) {
    final name = normalize(raw);
    if (name.length < minLength) {
      return 'Give the $noun a name of at least $minLength characters.';
    }
    if (name.length > maxLength) {
      return 'Keep the $noun name to $maxLength characters or fewer '
          '(it is ${name.length}).';
    }
    if (taken.contains(key(name))) {
      return 'Your club already has a season or tournament called "$name". '
          'Give this one a different name, such as adding the year or the '
          'place.';
    }
    return null;
  }
}
