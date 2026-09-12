import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import '../../core/models/venue.dart';
import '../../core/models/venue_plan.dart';
import 'match_count.dart';
import 'season_capacity.dart';
import 'tournament_scheduler.dart';

/// One ground as a season being created holds it: the place, and the terms
/// this season has it on.
///
/// A pair rather than one object because that is the split the product
/// already makes and depends on — [Venue] is the building and outlives the
/// season, [VenuePlan] is what this season has it for. Keeping them together
/// here lets a create form hand exactly the same two things to
/// [SeasonCapacity] that the saved season will later hand it, so the answer
/// the organizer gets before pressing Create is the answer the scheduler
/// gives afterwards.
class SeasonGround {
  const SeasonGround({
    required this.venue,
    required this.plan,
    this.hourlyRatePaise,
    this.marketGroundId,
    this.isNew = false,
  });

  final Venue venue;
  final VenuePlan plan;

  /// What the owner charges, when this came from the rentals marketplace.
  /// Null for a club's own ground, which costs the club nothing.
  final int? hourlyRatePaise;

  /// The `grounds/{id}` listing this was taken from, if any. Kept so the
  /// season can point back at the listing it was booked from.
  final String? marketGroundId;

  /// True while the venue document does not exist yet — a ground picked from
  /// the marketplace, or typed in by hand on the form. Saving the season
  /// creates it.
  final bool isNew;

  String get id => venue.id;
  String get name => venue.name;

  /// Playing areas this season may actually use here.
  int get courts => [
        for (final c in venue.courts)
          if (plan.allowsCourt(c)) c,
      ].length;

  SeasonGround copyWith({Venue? venue, VenuePlan? plan}) => SeasonGround(
        venue: venue ?? this.venue,
        plan: plan ?? this.plan,
        hourlyRatePaise: hourlyRatePaise,
        marketGroundId: marketGroundId,
        isNew: isNew,
      );
}

/// One event as a season being created holds it, in the terms capacity is
/// measured in.
class SeasonEventPlan {
  const SeasonEventPlan({
    required this.key,
    required this.label,
    required this.sportId,
    required this.entrants,
    required this.format,
    required this.matchMinutes,
    this.drawConfig = const DrawConfig(),
    this.groundIds = const {},
    this.turnaroundMinutes = 5,
    this.isTimetabled = true,
  });

  final String key;
  final String label;
  final String sportId;

  /// How big the field is expected to be. An organizer who has not said gets
  /// the form's own assumption — see `_CategoryDraft.plannedEntrants`.
  final int entrants;

  final CompetitionFormat format;
  final DrawConfig drawConfig;

  /// The grounds this event is pinned to. Empty means every ground the season
  /// has, which is the normal case.
  final Set<String> groundIds;

  final int matchMinutes;
  final int turnaroundMinutes;

  /// False for a performance event — a long jump is recorded, not drawn onto
  /// a court, so it takes no ground time and must not inflate the demand.
  final bool isTimetabled;

  /// Matches this event's draw will produce.
  int get matchesRequired => !isTimetabled
      ? 0
      : MatchCount.forDraw(
          format: format,
          config: drawConfig,
          entrants: entrants,
        );
}

/// One day of the season, and how much of it is spoken for.
class SeasonDayLoad {
  const SeasonDayLoad({
    required this.day,
    required this.slots,
    required this.matches,
  });

  final DateTime day;

  /// Match slots the grounds offer on this day, across every court.
  final int slots;

  /// Matches this projection puts on it.
  final int matches;

  bool get isFull => matches >= slots && slots > 0;
  bool get isEmpty => matches == 0;
}

/// The answer to "will this season actually run?", computed from a form that
/// has not been submitted.
class SeasonPlanPreview {
  const SeasonPlanPreview({
    required this.report,
    required this.days,
    required this.matchesRequired,
    required this.unplacedMatches,
    required this.courts,
    required this.groundCount,
  });

  /// The full feasibility verdict, from the same engine a saved season is
  /// checked with.
  final CapacityReport report;

  /// Day by day, what the grounds hold and what would land on them.
  final List<SeasonDayLoad> days;

  final int matchesRequired;

  /// Matches with nowhere to go — the number that makes "add a fifth ground"
  /// a concrete instruction rather than a guess.
  final int unplacedMatches;

  final int courts;
  final int groundCount;

  bool get fits => report.isFeasible && unplacedMatches == 0;

  /// Spare capacity once every match is placed. Zero when it does not fit.
  int get spareSlots {
    final spare = report.totalCapacity - matchesRequired;
    return spare > 0 ? spare : 0;
  }

  /// Days that would actually be used. A season booked over ten days that
  /// finishes in three has told the organizer something worth knowing.
  int get daysUsed => [for (final d in days) if (!d.isEmpty) d].length;

  static const SeasonPlanPreview empty = SeasonPlanPreview(
    report: CapacityReport(
      totalRequired: 0,
      totalCapacity: 0,
      courts: 0,
      perEvent: [],
      pools: [],
    ),
    days: [],
    matchesRequired: 0,
    unplacedMatches: 0,
    courts: 0,
    groundCount: 0,
  );
}

/// Works out whether a season that is still being typed will fit on the
/// grounds it has been given, and what its days would look like if it did.
///
/// ## Why this is answered before the season exists
///
/// The complaint this was built for: an organizer adds four grounds for
/// twelve cricket matches, creates the season, generates the schedule, finds
/// it does not fit, goes back, adds a fifth ground, and regenerates. Every
/// number needed to answer that was available on the form — twelve matches,
/// four grounds, three hours a match, the hours each ground is open — and the
/// organizer was made to find out by trying.
///
/// So this runs the real capacity engine over the draft. [SeasonCapacity] is
/// not reimplemented here and must not be: the whole value of the answer is
/// that it is the same arithmetic the scheduler will do, so ticking a fifth
/// ground flips the verdict for the same reason the schedule will then
/// succeed.
class DraftSeasonPlan {
  const DraftSeasonPlan._();

  static SeasonPlanPreview build({
    required DateTime? start,
    required DateTime? end,
    required List<SeasonGround> grounds,
    required List<SeasonEventPlan> events,

    /// Forces the slot grid's granularity. Null — the normal case — sizes it
    /// from the events themselves; see [_gridMinutes].
    int? defaultMatchMinutes,
    int defaultTurnaroundMinutes = 5,
  }) {
    if (start == null || grounds.isEmpty || events.isEmpty) {
      return SeasonPlanPreview.empty;
    }

    final firstDay = DateTime(start.year, start.month, start.day);
    final dayCount = _dayCount(firstDay, end);
    final gridMinutes = defaultMatchMinutes ?? _gridMinutes(events);

    final calendars = SeasonCapacity.buildCalendars(
      seasonStart: firstDay,
      dayCount: dayCount,
      venues: [for (final g in grounds) g.venue],
      plans: {for (final g in grounds) g.venue.id: g.plan},
      defaultMatchMinutes: gridMinutes,
      defaultTurnaroundMinutes: defaultTurnaroundMinutes,
    );

    final byVenue = <String, List<CourtCalendar>>{};
    for (final c in calendars) {
      (byVenue[c.court.venueId] ??= []).add(c);
    }

    final demands = <EventDemand>[];
    for (final e in events) {
      final required = e.matchesRequired;
      if (required == 0) continue;

      final allowed = e.groundIds.isEmpty
          ? {for (final g in grounds) g.venue.id}
          : e.groundIds;
      final eligible = <String>{
        for (final c in calendars)
          if (allowed.contains(c.court.venueId) && c.allowsSport(e.sportId))
            c.court.key,
      };

      demands.add(EventDemand(
        compId: e.key,
        label: e.label,
        sportId: e.sportId,
        matchesRequired: required,
        eligibleCourtKeys: eligible,
        matchMinutes: e.matchMinutes,
        turnaroundMinutes: e.turnaroundMinutes,
      ));
    }

    final report = SeasonCapacity.assess(calendars: calendars, demands: demands);
    final projection = _project(
      firstDay: firstDay,
      dayCount: dayCount,
      calendars: calendars,
      demands: demands,
    );

    var required = 0;
    for (final d in demands) {
      required += d.matchesRequired;
    }

    return SeasonPlanPreview(
      report: report,
      days: projection.days,
      matchesRequired: required,
      unplacedMatches: projection.unplaced,
      courts: calendars.length,
      groundCount: byVenue.length,
    );
  }

  /// Lays the required matches across the season's days, longest match first.
  ///
  /// Deliberately a projection and not a schedule: it respects how many
  /// matches each day physically holds and which grounds an event may use,
  /// and it ignores everything the real scheduler exists for — a player in
  /// three draws, rest gaps, a final that cannot precede its semi. It answers
  /// "which days will be busy", which is the question an organizer asks while
  /// deciding how many days to book, and it does not pretend to answer more.
  ///
  /// Longest first because that is the packing order that fails honestly: fit
  /// the three-hour cricket ties first and the short draws fill the gaps, and
  /// what will not fit is what genuinely will not fit.
  static ({List<SeasonDayLoad> days, int unplaced}) _project({
    required DateTime firstDay,
    required int dayCount,
    required List<CourtCalendar> calendars,
    required List<EventDemand> demands,
  }) {
    // Slots remaining per court per day, keyed by court and day index.
    final remaining = <String, List<int>>{};
    for (final cal in calendars) {
      final perDay = List<int>.filled(dayCount, 0);
      for (final startAt in cal.slotStarts) {
        final index = DateTime(startAt.year, startAt.month, startAt.day)
            .difference(firstDay)
            .inDays;
        if (index < 0 || index >= dayCount) continue;
        perDay[index]++;
      }
      if (cal.maxPerDay > 0) {
        for (var i = 0; i < dayCount; i++) {
          if (perDay[i] > cal.maxPerDay) perDay[i] = cal.maxPerDay;
        }
      }
      remaining[cal.court.key] = perDay;
    }

    final capacityPerDay = List<int>.filled(dayCount, 0);
    for (final perDay in remaining.values) {
      for (var i = 0; i < dayCount; i++) {
        capacityPerDay[i] += perDay[i];
      }
    }

    final placedPerDay = List<int>.filled(dayCount, 0);
    var unplaced = 0;

    final ordered = [...demands]
      ..sort((a, b) => b.matchMinutes.compareTo(a.matchMinutes));

    for (final demand in ordered) {
      var left = demand.matchesRequired;
      for (var day = 0; day < dayCount && left > 0; day++) {
        for (final key in demand.eligibleCourtKeys) {
          if (left == 0) break;
          final perDay = remaining[key];
          if (perDay == null || perDay[day] == 0) continue;
          final take = perDay[day] < left ? perDay[day] : left;
          perDay[day] -= take;
          placedPerDay[day] += take;
          left -= take;
        }
      }
      unplaced += left;
    }

    return (
      days: [
        for (var i = 0; i < dayCount; i++)
          SeasonDayLoad(
            day: DateTime(firstDay.year, firstDay.month, firstDay.day + i),
            slots: capacityPerDay[i],
            matches: placedPerDay[i],
          ),
      ],
      unplaced: unplaced,
    );
  }

  /// How long one slot of the grid is, when no ground states its own length.
  ///
  /// The events' own lengths, weighted by how many matches each brings. This
  /// is load-bearing and was the bug the tests caught: left at a flat thirty
  /// minutes, a ground open 09:00–18:00 offered eighteen slots, and twelve
  /// three-hour cricket matches "fitted" on four grounds in a day. The
  /// verdict has to be built on the grid the season will actually be played
  /// on, or it is a reassurance rather than an answer.
  ///
  /// A venue that names its own match length in its plan overrides this for
  /// itself — the cricket square runs three-hour matches whatever else is on.
  static int _gridMinutes(List<SeasonEventPlan> events) {
    var matches = 0;
    var minutes = 0;
    for (final e in events) {
      final n = e.matchesRequired;
      if (n == 0) continue;
      matches += n;
      minutes += e.matchMinutes * n;
    }
    if (matches == 0) return 30;
    final average = (minutes / matches).round();
    return average < 5 ? 5 : average;
  }

  /// Days the season spans, inclusive. One when there is no end date, which
  /// is what a one-day meet stores.
  static int _dayCount(DateTime firstDay, DateTime? end) {
    if (end == null) return 1;
    final last = DateTime(end.year, end.month, end.day);
    final days = last.difference(firstDay).inDays + 1;
    return days < 1 ? 1 : days;
  }
}
