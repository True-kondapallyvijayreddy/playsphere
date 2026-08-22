/// The houses, sections and batches an organizer splits their field into,
/// and the arithmetic of editing that list after people have already entered.
///
/// ## Why the names are the organizer's, not ours
///
/// The app shipped four houses — Red, Blue, Green, Yellow — hard-coded in two
/// wizards and defaulted a third time at the registration dialog. That list is
/// right for exactly one kind of organizer: a school that happens to use
/// colours. A college running an inter-department meet splits by
/// "ECE — 3rd Year" and "CSE — 4th Year"; a school running an intra-class
/// tournament splits by "8-A" and "8-B"; a workplace league splits by floor.
/// Every one of them was being handed Red House and left to work around it,
/// which in practice meant entering everybody into one house and sorting the
/// teams out by hand afterwards.
///
/// So the list is data on the competition ([Competition.presetHouses]) and
/// this file is what lets an organizer author it — from scratch, or from a
/// template that generates the twenty names they would otherwise type.
///
/// ## Why editing is not just "write the new list"
///
/// A student registers by picking a house, and what gets stored on their
/// registration is the house's NAME ([Registration.houseName]) — there is no
/// house id to be stable underneath a rename. So an organizer fixing a typo in
/// "Red Hosue" after thirty students have entered would, with a naive save,
/// leave all thirty pointing at a house that no longer exists. The team
/// builder would show an empty "Red House" and thirty students in the
/// unassigned pool.
///
/// [HouseRosterPlan] is what stops that: the editor keeps each row's original
/// name beside its edited one, and the plan turns that pairing into an explicit
/// rename map the repository replays across the registrations. A house that was
/// renamed takes its members with it; a house that was deleted hands its
/// members back to the pool, which is the only honest thing to do with them.
library;

import '../../core/models/organization.dart';
import '../../core/text/ordinal.dart' as text;

/// One row in the house editor — a name, plus what that row was called when
/// the editor opened.
///
/// [originalName] is the identity that survives editing. Null means the row is
/// new, so there is nobody registered under it and nothing to migrate.
class HouseDraft {
  HouseDraft({required this.name, this.originalName});

  /// A row for a house that already exists on the competition.
  HouseDraft.existing(String existing)
      : name = existing,
        originalName = existing;

  /// A row the organizer just added.
  HouseDraft.fresh([this.name = '']) : originalName = null;

  String name;
  final String? originalName;

  bool get isNew => originalName == null;
  bool get isRenamed =>
      originalName != null && originalName != name.trim() && name.trim().isNotEmpty;
}

/// What saving a set of [HouseDraft]s actually does, worked out before any
/// write is issued so the editor can show it and the repository can replay it.
class HouseRosterPlan {
  const HouseRosterPlan({
    required this.names,
    required this.renames,
    required this.removed,
    this.error,
  });

  /// The final list, in the organizer's order — trimmed, blanks dropped.
  final List<String> names;

  /// old name → new name, for rows the organizer edited. Registrations
  /// carrying the old name are rewritten to the new one.
  final Map<String, String> renames;

  /// Houses that were on the competition and are not any more. Anyone
  /// registered under these is left without a house rather than silently
  /// moved into one they did not choose.
  final List<String> removed;

  /// Why this cannot be saved, or null when it can.
  final String? error;

  bool get isValid => error == null;

  /// Whether saving would touch registrations as well as the competition.
  bool get touchesEntries => renames.isNotEmpty || removed.isNotEmpty;
}

/// Ready-made house lists, because the alternative to a template is an
/// organizer typing sixteen names into sixteen boxes on a phone.
class HouseTemplates {
  const HouseTemplates._();

  /// The classic four, kept as a template rather than a default — a school
  /// that wants them is one tap away, and everyone else is no longer stuck
  /// with them.
  static const List<String> schoolColours = [
    'Red House',
    'Blue House',
    'Green House',
    'Yellow House',
  ];

  /// "1st Year" … "4th Year".
  static List<String> years(int count) =>
      [for (var i = 1; i <= count; i++) '${ordinal(i)} Year'];

  /// Departments crossed with years — "ECE — 3rd Year", "CSE — 4th Year".
  ///
  /// The cross product is the point: a college meet is not ECE against CSE, it
  /// is ECE 3rd Year against CSE 4th Year, and typing that grid by hand is
  /// twenty-odd entries an organizer gets wrong once and lives with all season.
  static List<String> departmentYears({
    required List<String> departments,
    required List<int> years,
  }) =>
      [
        for (final d in departments)
          for (final y in years)
            if (d.trim().isNotEmpty) '${d.trim()} — ${ordinal(y)} Year',
      ];

  /// Class sections — "8-A", "8-B", "8-C".
  static List<String> sections({
    required String grade,
    required int count,
  }) {
    final label = grade.trim().isEmpty ? 'Class' : grade.trim();
    return [
      for (var i = 0; i < count; i++)
        '$label-${String.fromCharCode(65 + (i % 26))}',
    ];
  }

  /// Kept as an entry point here because the templates read better for it;
  /// the implementation is shared with the roster line — see
  /// `lib/core/text/ordinal.dart`.
  static String ordinal(int n) => text.ordinal(n);
}

/// The pure part of house editing — no Firestore, no widgets, so the rename
/// and removal arithmetic can be tested on its own.
class HouseRoster {
  const HouseRoster._();

  /// The smallest field that is a competition rather than an exhibition.
  static const int minHouses = 2;

  /// Works out what saving [drafts] means for a competition whose houses are
  /// currently [current].
  ///
  /// Validation is returned rather than thrown: this runs on every keystroke to
  /// drive the editor's save button, and a blank row half-typed is a normal
  /// intermediate state, not an exception.
  static HouseRosterPlan plan({
    required List<HouseDraft> drafts,
    required List<String> current,
  }) {
    final names = <String>[];
    final renames = <String, String>{};
    final seen = <String>{};
    String? error;

    for (final d in drafts) {
      final name = d.name.trim();
      // A blank row is the organizer having added one and not filled it in.
      // Dropping it silently is kinder than refusing to save over it.
      if (name.isEmpty) continue;

      if (!seen.add(name.toLowerCase())) {
        error ??= 'Two houses are both called "$name". '
            'Names have to differ — a student picks one by reading it.';
        continue;
      }

      names.add(name);
      if (d.originalName != null && d.originalName != name) {
        renames[d.originalName!] = name;
      }
    }

    if (error == null && names.length < minHouses) {
      error = 'Add at least $minHouses houses — a draw needs two sides.';
    }

    final kept = {...names, ...renames.keys};
    final removed = [
      for (final h in current)
        if (!kept.contains(h)) h,
    ];

    return HouseRosterPlan(
      names: names,
      renames: renames,
      removed: removed,
      error: error,
    );
  }

  /// Turns a list of names into editor rows, marking every one as existing.
  static List<HouseDraft> draftsFrom(List<String> current) =>
      [for (final h in current) HouseDraft.existing(h)];
}

/// Works out which of an event's houses a club member belongs in, from what
/// the club already knows about them.
///
/// ## Why candidates rather than matching
///
/// The obvious approach is to compare the member's department against each
/// house name and take the closest. That is fuzzy matching, and fuzzy matching
/// on a school roster puts a child in the wrong team — "ECE — 3rd Year" and
/// "ECE — 4th Year" differ by one character and are two different squads.
///
/// So this goes the other way. The house list was WRITTEN by a template
/// ([HouseTemplates]), so the reliable move is to re-render what that template
/// would have called this particular student and look for that exact string.
/// Every candidate is a name the organizer's own list either contains or does
/// not; nothing is ever approximated. It also means no new field is needed on
/// the competition recording which template produced the list — the candidates
/// cover all of them, and the first one present wins.
///
/// ## Order is specificity, and it matters
///
/// A student with `department: ECE, year: 3` is a candidate for both
/// "ECE — 3rd Year" and "3rd Year". If an event splits by department-and-year,
/// both could plausibly appear; the narrower is the right answer, because an
/// organizer who wrote the narrower list meant it. So candidates run
/// most-specific first and the first hit ends the search.
///
/// ## Who this deliberately cannot place
///
/// Anyone without a membership in the hosting club. An event open to other
/// clubs takes entries from people this club knows nothing about, and there is
/// no honest way to guess their house — see [MemberGrouping] for why the data
/// is club-scoped in the first place. They come back as unplaced, which sends
/// them to the organizer in the Team Builder rather than into a house they
/// were never in.
class HouseAssigner {
  const HouseAssigner._();

  /// Every name this grouping could legitimately be filed under, narrowest
  /// first. Exposed for the editor, which shows an organizer why somebody did
  /// or did not match.
  static List<String> candidates(MemberGrouping g) {
    final year = g.year;
    return [
      if (g.department != null && year != null)
        '${g.department} — ${text.ordinal(year)} Year',
      if (g.grade != null && g.section != null) '${g.grade}-${g.section}',
      if (g.house != null) g.house!,
      if (year != null) '${text.ordinal(year)} Year',
      if (g.department != null) g.department!,
      if (g.grade != null) g.grade!,
    ];
  }

  /// The house from [houses] this member belongs in, or null when the club
  /// does not know enough to say.
  ///
  /// Matching is case- and space-insensitive because the two strings are
  /// typed by two different people at two different times — an organizer
  /// naming houses and an admin filling in a roster — and "ECE" versus "ece"
  /// is not a distinction either of them intended to make.
  static String? assign(MemberGrouping g, List<String> houses) {
    if (g.isEmpty || houses.isEmpty) return null;
    final byKey = {
      for (final h in houses) _key(h): h,
    };
    for (final c in candidates(g)) {
      final hit = byKey[_key(c)];
      if (hit != null) return hit;
    }
    return null;
  }

  static String _key(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// What an auto-placement WOULD do, worked out before anything is written so
/// the organizer sees the outcome and then decides.
///
/// The three buckets are kept apart because they are three different problems
/// with three different fixes: [placements] needs no fix, [unplaced] means the
/// roster is missing details, and [outsiders] means the entrant is not this
/// club's student at all and never will be placeable from here.
class HousePlacementPreview {
  const HousePlacementPreview({
    required this.placements,
    required this.unplaced,
    required this.outsiders,
    required this.alreadyPlaced,
  });

  /// uid → house name, for entries this would set.
  final Map<String, String> placements;

  /// Club members whose grouping matched no house on the list.
  final List<String> unplaced;

  /// Entrants with no membership in the hosting club — an open event's guests.
  final List<String> outsiders;

  /// Entries that already sit in a house on the list, left untouched. An
  /// organizer who hand-placed somebody is not overruled by a bulk action.
  final List<String> alreadyPlaced;

  int get total =>
      placements.length + unplaced.length + outsiders.length + alreadyPlaced.length;

  bool get hasWork => placements.isNotEmpty;
}
