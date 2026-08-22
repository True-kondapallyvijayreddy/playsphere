import '../../core/models/competition.dart';
import '../../core/models/draw_slot.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/models/tournament_official.dart';

/// What each sport in a season needs officiating, and who on the panel can
/// actually do it.
///
/// ## Why the panel screen needed this
///
/// A season is not one officiating problem, it is one per sport. Five sports
/// share a hall over a weekend and the panel is five panels: the two people
/// who know the kabaddi rules are not the ones who can call a badminton
/// service fault. A flat "Panel (9)" heading over a flat list of forty
/// unstaffed matches hides the only fact that decides whether Saturday works
/// — that eight of the nine are badminton umpires and the kabaddi has nobody.
///
/// So this is the same arithmetic an organizer does on paper before a season:
/// per sport, how many matches need somebody, how many already have somebody,
/// and how many people on the panel could take one. Where a sport's draws
/// have groups it breaks down again, because a five-group event is thirty
/// matches to the knockout's seven and "the groups" is how the day is
/// actually staffed.
class SportDemand {
  const SportDemand({
    required this.sportId,
    required this.sportName,
    required this.events,
    required this.total,
    required this.staffed,
    required this.unscheduled,
    required this.panelCount,
    required this.dayKeys,
    required this.groups,
  });

  final String sportId;
  final String sportName;

  /// The draws of this sport — a season's badminton is usually three or four
  /// events, not one.
  final List<String> events;

  /// Matches that need an official: everything not yet played. A completed
  /// match needed one at the time and is not work an organizer can still do
  /// anything about.
  final int total;

  /// How many of [total] already carry an official.
  final int staffed;

  /// Matches with no time yet. Counted apart from [total] rather than folded
  /// into "still needs somebody", because they are a different job: the bulk
  /// assigner cannot place a match with no window to check clashes against,
  /// and the fix is to schedule them, not to find more umpires.
  final int unscheduled;

  /// Panel members who cover this sport — including the ones who named no
  /// sport at all, who are available for anything. See
  /// [TournamentOfficial.coversSport].
  final int panelCount;

  /// The calendar days (`yyyy-MM-dd`) this sport actually plays on. What an
  /// organizer checks an official's availability against.
  final List<String> dayKeys;

  /// Per group, where the sport's draws have groups: `'Event · Group A'` to
  /// how many of its matches still need somebody.
  final Map<String, int> groups;

  int get needed => total - staffed;

  bool get isCovered => needed == 0 && unscheduled == 0;

  /// Whether the panel physically cannot staff this sport, however the
  /// timetable is arranged. The one problem on this screen that no amount of
  /// rescheduling fixes.
  bool get hasNobody => panelCount == 0 && needed > 0;
}

/// Builds the per-sport picture from what the season already has.
///
/// Pure and synchronous: it takes the events, fixtures and roster the screen
/// is already streaming, so the breakdown costs no extra reads.
List<SportDemand> officiatingDemand({
  required List<Competition> events,
  required List<Fixture> fixtures,
  required List<TournamentOfficial> roster,
}) {
  final eventById = {for (final e in events) e.id: e};

  // Bucketed by sport rather than by event, because the panel is chosen by
  // sport. Two badminton draws are one staffing question.
  final bySport = <String, _Bucket>{};

  for (final f in fixtures) {
    // A played match is not work — `isResulted` covers completed and
    // walkovers, and an abandoned one was somebody's Saturday but is not
    // still on the list of matches to staff.
    if (f.status.isResulted || f.status == FixtureStatus.abandoned) continue;
    if (f.isDraft) continue;

    final event = eventById[f.compId];
    final sportId = event?.sportId ?? f.sportId ?? 'unknown';
    final bucket = bySport.putIfAbsent(
      sportId,
      () => _Bucket(sportId, event?.sportName ?? f.sport),
    );

    if (event != null) bucket.events.add(event.name);

    final at = f.scheduledAt;
    if (at == null) {
      bucket.unscheduled++;
      continue;
    }

    bucket.total++;
    bucket.dayKeys.add(_dayKey(at));
    if (f.officials.isNotEmpty) {
      bucket.staffed++;
    } else if (f.bracket == Bracket.group && f.groupId != null) {
      final label = '${event?.name ?? 'Event'} · Group ${f.groupId}';
      bucket.groups[label] = (bucket.groups[label] ?? 0) + 1;
    }
  }

  final out = [
    for (final b in bySport.values)
      SportDemand(
        sportId: b.sportId,
        sportName: b.sportName,
        events: b.events.toList()..sort(),
        total: b.total,
        staffed: b.staffed,
        unscheduled: b.unscheduled,
        panelCount: roster.where((o) => o.coversSport(b.sportId)).length,
        dayKeys: b.dayKeys.toList()..sort(),
        groups: b.groups,
      ),
  ];

  // The sport in most trouble first — nobody on the panel, then the biggest
  // gap, then alphabetically so the list is stable between refreshes rather
  // than reshuffling as matches finish.
  out.sort((a, b) {
    if (a.hasNobody != b.hasNobody) return a.hasNobody ? -1 : 1;
    final byNeed = b.needed.compareTo(a.needed);
    if (byNeed != 0) return byNeed;
    return a.sportName.compareTo(b.sportName);
  });
  return out;
}

/// Every calendar day the season's matches fall on, earliest first.
///
/// What the availability editor offers as checkboxes. Derived from the
/// fixtures rather than from the tournament's start/end dates because those
/// two are often wrong in opposite directions — a season with no end date set
/// would offer one day, and one that overran would not offer the day it
/// actually finished on.
List<String> seasonDayKeys(List<Fixture> fixtures) {
  final days = <String>{};
  for (final f in fixtures) {
    final at = f.scheduledAt;
    if (at != null) days.add(_dayKey(at));
  }
  return days.toList()..sort();
}

String _dayKey(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

class _Bucket {
  _Bucket(this.sportId, this.sportName);

  final String sportId;
  final String sportName;
  final Set<String> events = {};
  final Set<String> dayKeys = {};
  final Map<String, int> groups = {};
  int total = 0;
  int staffed = 0;
  int unscheduled = 0;
}
