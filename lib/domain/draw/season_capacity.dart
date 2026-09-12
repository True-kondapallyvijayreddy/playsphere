import '../../core/models/venue.dart';
import '../../core/models/venue_plan.dart';
import 'tournament_scheduler.dart';

/// Turns venues and the season's plans for them into the resources a schedule
/// is solved against, and answers the question an organizer should be asked
/// *before* they press Generate: does this fit?
///
/// ## Why capacity is computed and not typed in
///
/// An organizer asked "how many matches a day?" answers with an intention —
/// four — and the ground answers with arithmetic. A window of 08:00–20:00, a
/// three-hour match and a thirty-minute turnaround holds three. Both numbers
/// are real and they are not the same number: the first is a ceiling the
/// organizer wants, the second is what the day physically has. Asking only the
/// first produces a timetable that overruns; computing only the second ignores
/// a constraint the organizer meant. So both are kept, the stricter one is
/// used, and the difference is shown rather than silently resolved.
class SeasonCapacity {
  const SeasonCapacity._();

  /// Builds one [CourtCalendar] per usable playing area.
  ///
  /// Every venue without a plan behaves as it always did — its own opening
  /// hours, every day of the season, no ceiling — so this is invisible to a
  /// season whose organizer never opened the venue planner.
  static List<CourtCalendar> buildCalendars({
    required DateTime seasonStart,
    required int dayCount,
    required List<Venue> venues,
    Map<String, VenuePlan> plans = const {},
    int defaultMatchMinutes = 30,
    int defaultTurnaroundMinutes = 5,
  }) {
    final out = <CourtCalendar>[];
    final firstDay =
        DateTime(seasonStart.year, seasonStart.month, seasonStart.day);

    for (final venue in venues) {
      if (venue.isArchived) continue;
      final plan = plans[venue.id] ?? VenuePlan(venueId: venue.id);
      final matchMinutes = plan.matchMinutes ?? defaultMatchMinutes;
      final turnaround = plan.turnaroundMinutes ?? defaultTurnaroundMinutes;
      final slotMinutes = matchMinutes + turnaround;
      if (slotMinutes <= 0) continue;

      // The usable stretches of every day this venue is lent to the season,
      // computed once and shared by all of its courts: sessions minus
      // blackouts is a fact about the building, not about court 3.
      final periods = <ScheduleWindow>[];
      for (var i = 0; i < dayCount; i++) {
        final day = DateTime(firstDay.year, firstDay.month, firstDay.day + i);
        if (!plan.servesDay(day)) continue;
        for (final session in plan.sessionsFor(venue)) {
          final span = session.on(day);
          periods.addAll(
            _subtractBlackouts(
              ScheduleWindow(start: span.start, end: span.end),
              plan.blackouts,
              day,
            ),
          );
        }
      }
      if (periods.isEmpty) continue;
      periods.sort((a, b) => a.start.compareTo(b.start));

      final starts = <DateTime>[];
      for (final p in periods) {
        var cursor = p.start;
        while (!cursor.add(Duration(minutes: matchMinutes)).isAfter(p.end)) {
          starts.add(cursor);
          cursor = cursor.add(Duration(minutes: slotMinutes));
        }
      }
      if (starts.isEmpty) continue;

      for (final court in venue.courts) {
        if (!plan.allowsCourt(court)) continue;
        out.add(CourtCalendar(
          court: CourtRef(
            venueId: venue.id,
            venueName: venue.name,
            courtId: court.id,
            courtName: court.name,
          ),
          slotStarts: starts,
          openPeriods: periods,
          maxPerDay: plan.maxMatchesPerCourtPerDay,
          sportIds: plan.sportIds,
        ));
      }
    }

    return out;
  }

  /// What one venue offers the season, in the two numbers §5 of the plan
  /// insists on keeping apart.
  static VenueCapacityLine lineFor({
    required Venue venue,
    required VenuePlan plan,
    required DateTime seasonStart,
    required int dayCount,
    int defaultMatchMinutes = 30,
    int defaultTurnaroundMinutes = 5,
  }) {
    final matchMinutes = plan.matchMinutes ?? defaultMatchMinutes;
    final turnaround = plan.turnaroundMinutes ?? defaultTurnaroundMinutes;
    final calendars = buildCalendars(
      seasonStart: seasonStart,
      dayCount: dayCount,
      venues: [venue],
      plans: {venue.id: plan},
      defaultMatchMinutes: defaultMatchMinutes,
      defaultTurnaroundMinutes: defaultTurnaroundMinutes,
    );

    // The best single day, which is what "matches per day" means to the
    // person who typed the ceiling in.
    var computedPerDay = 0;
    var playableDays = 0;
    if (calendars.isNotEmpty) {
      final byDay = <String, int>{};
      for (final p in calendars.first.openPeriods) {
        final minutes = p.end.difference(p.start).inMinutes;
        if (minutes < matchMinutes) continue;
        final fits = (minutes + turnaround) ~/ (matchMinutes + turnaround);
        final key = _dayKey(p.start);
        byDay[key] = (byDay[key] ?? 0) + fits;
      }
      playableDays = byDay.length;
      for (final fits in byDay.values) {
        if (fits > computedPerDay) computedPerDay = fits;
      }
    }

    var total = 0;
    for (final c in calendars) {
      total += c.capacity(
        matchMinutes: matchMinutes,
        turnaroundMinutes: turnaround,
      );
    }

    return VenueCapacityLine(
      venueId: venue.id,
      venueName: venue.name,
      courts: calendars.length,
      playableDays: playableDays,
      matchMinutes: matchMinutes,
      turnaroundMinutes: turnaround,
      organiserLimitPerCourtPerDay: plan.maxMatchesPerCourtPerDay,
      computedPerCourtPerDay: computedPerDay,
      totalMatchSlots: total,
    );
  }

  /// The feasibility check that belongs in front of the Generate button.
  ///
  /// Three questions, because one number cannot answer them: does the season
  /// as a whole fit, does each event fit on the grounds it is allowed, and
  /// does any *shared* pool of grounds hold everything competing for it. The
  /// last is the one that catches the real failure — cricket alone fits and
  /// football alone fits and they are on the same field.
  static CapacityReport assess({
    required List<CourtCalendar> calendars,
    required List<EventDemand> demands,
  }) {
    final byKey = {for (final c in calendars) c.court.key: c};

    int capacityOf(Set<String> keys, int matchMinutes, int turnaround) {
      var total = 0;
      for (final key in keys) {
        final cal = byKey[key];
        if (cal == null) continue;
        total += cal.capacity(
          matchMinutes: matchMinutes,
          turnaroundMinutes: turnaround,
        );
      }
      return total;
    }

    final perEvent = [
      for (final d in demands)
        EventFeasibility(
          compId: d.compId,
          label: d.label,
          required: d.matchesRequired,
          capacity: capacityOf(
            d.eligibleCourtKeys,
            d.matchMinutes,
            d.turnaroundMinutes,
          ),
        ),
    ];

    // Hall's condition over the pools that actually occur. For every distinct
    // set of grounds some event is confined to, everything confined to a
    // subset of it must fit inside it. Necessary rather than sufficient — a
    // full check is exponential and an organizer does not need one — but it
    // is the check that finds two sports sharing a field.
    final pools = <PoolFeasibility>[];
    final seen = <String>{};
    for (final d in demands) {
      final keys = d.eligibleCourtKeys;
      final id = (keys.toList()..sort()).join('|');
      if (!seen.add(id)) continue;

      var required = 0;
      final members = <String>[];
      final competing = <EventDemand>[];
      for (final other in demands) {
        if (!keys.containsAll(other.eligibleCourtKeys)) continue;
        required += other.matchesRequired;
        members.add(other.label);
        competing.add(other);
      }

      // The shared grounds are counted once, at the average match length of
      // what competes for them — a pool holding a three-hour cricket tie and
      // a 45-minute singles has no single slot size, and weighting by how
      // many matches each event brings is the honest compromise. Counting
      // each event's own capacity and adding them would count the same court
      // once per event.
      final avg = _weightedAverage(competing);
      final capacity = capacityOf(keys, avg.match, avg.turnaround);

      pools.add(PoolFeasibility(
        label: members.length == 1 ? members.first : '${members.length} events',
        events: members,
        required: required,
        capacity: capacity,
      ));
    }

    var totalRequired = 0;
    for (final d in demands) {
      totalRequired += d.matchesRequired;
    }
    final avgAll = _weightedAverage(demands);
    final totalCapacity = capacityOf(
      byKey.keys.toSet(),
      avgAll.match,
      avgAll.turnaround,
    );

    return CapacityReport(
      totalRequired: totalRequired,
      totalCapacity: totalCapacity,
      courts: calendars.length,
      perEvent: perEvent,
      pools: pools,
    );
  }

  /// The average match length across [demands], weighted by how many matches
  /// each one contributes — the right figure for a pool holding a few long
  /// finals and many short group games.
  static ({int match, int turnaround}) _weightedAverage(
    List<EventDemand> demands,
  ) {
    var matches = 0;
    var matchMinutes = 0;
    var turnaround = 0;
    for (final d in demands) {
      final n = d.matchesRequired < 1 ? 1 : d.matchesRequired;
      matches += n;
      matchMinutes += d.matchMinutes * n;
      turnaround += d.turnaroundMinutes * n;
    }
    if (matches == 0) return (match: 30, turnaround: 5);
    return (
      match: (matchMinutes / matches).round(),
      turnaround: (turnaround / matches).round(),
    );
  }

  /// [window] with every blackout on [day] cut out of it.
  static List<ScheduleWindow> _subtractBlackouts(
    ScheduleWindow window,
    List<VenueBlackout> blackouts,
    DateTime day,
  ) {
    var pieces = <ScheduleWindow>[window];
    for (final b in blackouts) {
      if (!b.coversDay(day)) continue;
      final cut = b.window;
      final next = <ScheduleWindow>[];
      for (final piece in pieces) {
        if (!piece.start.isBefore(cut.end) || !cut.start.isBefore(piece.end)) {
          next.add(piece); // No overlap at all.
          continue;
        }
        if (piece.start.isBefore(cut.start)) {
          next.add(ScheduleWindow(start: piece.start, end: cut.start));
        }
        if (cut.end.isBefore(piece.end)) {
          next.add(ScheduleWindow(start: cut.end, end: piece.end));
        }
      }
      pieces = next;
    }
    return [
      for (final p in pieces)
        if (p.end.isAfter(p.start)) p,
    ];
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// What one event needs, in the terms capacity is measured in.
class EventDemand {
  const EventDemand({
    required this.compId,
    required this.label,
    required this.matchesRequired,
    required this.eligibleCourtKeys,
    this.sportId = '',
    this.matchMinutes = 30,
    this.turnaroundMinutes = 5,
  });

  final String compId;
  final String label;
  final String sportId;

  /// How many matches its draw produces. The number an organizer never has to
  /// work out by hand.
  final int matchesRequired;

  /// [CourtRef.key]s this event may actually be played on, after both its own
  /// ground list and the venues' sport restrictions are applied.
  final Set<String> eligibleCourtKeys;

  final int matchMinutes;
  final int turnaroundMinutes;
}

/// One venue's contribution, with the organizer's ceiling and the arithmetic
/// kept visibly apart.
class VenueCapacityLine {
  const VenueCapacityLine({
    required this.venueId,
    required this.venueName,
    required this.courts,
    required this.playableDays,
    required this.matchMinutes,
    required this.turnaroundMinutes,
    required this.organiserLimitPerCourtPerDay,
    required this.computedPerCourtPerDay,
    required this.totalMatchSlots,
  });

  final String venueId;
  final String venueName;

  /// Playing areas this season may use here.
  final int courts;

  /// Days it is actually open to the season, after blackouts.
  final int playableDays;

  final int matchMinutes;
  final int turnaroundMinutes;

  /// What the organizer typed. Zero when they named no ceiling.
  final int organiserLimitPerCourtPerDay;

  /// What the sessions physically hold on the busiest day.
  final int computedPerCourtPerDay;

  /// The one the scheduler uses.
  int get effectivePerCourtPerDay =>
      organiserLimitPerCourtPerDay > 0 &&
              organiserLimitPerCourtPerDay < computedPerCourtPerDay
          ? organiserLimitPerCourtPerDay
          : computedPerCourtPerDay;

  /// True when the organizer asked for more than the day holds — the case
  /// worth telling them about rather than quietly overruling.
  bool get limitExceedsReality =>
      organiserLimitPerCourtPerDay > computedPerCourtPerDay;

  final int totalMatchSlots;
}

/// One event measured against the grounds it is allowed to use.
class EventFeasibility {
  const EventFeasibility({
    required this.compId,
    required this.label,
    required this.required,
    required this.capacity,
  });

  final String compId;
  final String label;
  final int required;
  final int capacity;

  int get shortfall => required > capacity ? required - capacity : 0;
  bool get fits => shortfall == 0;
}

/// A set of grounds, and everything competing for it.
class PoolFeasibility {
  const PoolFeasibility({
    required this.label,
    required this.events,
    required this.required,
    required this.capacity,
  });

  final String label;
  final List<String> events;
  final int required;
  final int capacity;

  int get shortfall => required > capacity ? required - capacity : 0;
  bool get fits => shortfall == 0;
}

/// The answer to "will this schedule?", before anything is generated.
class CapacityReport {
  const CapacityReport({
    required this.totalRequired,
    required this.totalCapacity,
    required this.courts,
    required this.perEvent,
    required this.pools,
  });

  final int totalRequired;
  final int totalCapacity;
  final int courts;
  final List<EventFeasibility> perEvent;
  final List<PoolFeasibility> pools;

  bool get isFeasible =>
      totalRequired <= totalCapacity &&
      perEvent.every((e) => e.fits) &&
      pools.every((p) => p.fits);

  /// The largest number of extra match slots any single check is short of —
  /// what "you need 15 more slots" should actually say.
  int get shortfall {
    var worst = totalRequired > totalCapacity ? totalRequired - totalCapacity : 0;
    for (final e in perEvent) {
      if (e.shortfall > worst) worst = e.shortfall;
    }
    for (final p in pools) {
      if (p.shortfall > worst) worst = p.shortfall;
    }
    return worst;
  }

  /// Named in the order an organizer can actually act on them, cheapest first.
  /// A red verdict with no next step is a dead end, and this feature exists so
  /// that the answer to "it does not fit" is a list of things that would make
  /// it fit.
  List<String> get suggestions {
    if (isFeasible) return const [];
    return [
      'Add another day to the season',
      'Extend a venue\'s playing hours, or add an evening session',
      'Shorten the match duration or the turnaround',
      'Raise a venue\'s maximum matches per day',
      'Add another ground, or another playing area at an existing one',
    ];
  }

  /// The blocking checks, worst first, phrased for a human.
  List<String> get problems {
    final out = <String>[];
    if (totalRequired > totalCapacity) {
      out.add('The season needs $totalRequired matches and the venues hold '
          '$totalCapacity.');
    }
    for (final e in perEvent) {
      if (!e.fits) {
        out.add('${e.label} needs ${e.required} matches and its grounds hold '
            '${e.capacity}.');
      }
    }
    for (final p in pools) {
      if (!p.fits && p.events.length > 1) {
        out.add('${p.events.join(', ')} share the same grounds and need '
            '${p.required} matches between them, against ${p.capacity}.');
      }
    }
    return out;
  }
}
