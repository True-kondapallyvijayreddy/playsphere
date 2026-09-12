/// One physical playing area, resolved from a venue document.
///
/// Carries the venue it belongs to so a schedule can say "Gachibowli Stadium ·
/// Court 3" rather than "Court 3", which matters the moment a tournament runs
/// across two buildings.
class CourtRef {
  const CourtRef({
    required this.venueId,
    required this.venueName,
    required this.courtId,
    required this.courtName,
  });

  final String venueId;
  final String venueName;
  final String courtId;
  final String courtName;

  /// Unique across the whole tournament. Two venues may each have a "Court 1"
  /// and they are not the same court — the bug that a bare court name cannot
  /// avoid.
  String get key => '$venueId/$courtId';

  String get label => '$venueName · $courtName';
}

class ScheduleWindow {
  const ScheduleWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool overlaps(ScheduleWindow other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  /// Gap between two non-overlapping windows. Callers must check [overlaps]
  /// first — the result is meaningless for windows that intersect.
  Duration gapTo(ScheduleWindow other) {
    if (start.isAfter(other.end)) return start.difference(other.end);
    return other.start.difference(end);
  }
}

/// Where and when one event is allowed to be played.
///
/// ## Why an event, not a tournament, owns this
///
/// A multi-sport season is not one competition on one ground. The badminton
/// runs in the indoor hall, the cricket needs the main field, and the football
/// is on the far pitch — and each of those grounds is free at different hours
/// and on different days. Scheduling all of it against one shared pool of
/// courts and one shared day window is arithmetic that cannot be wrong on
/// paper and is always wrong in the hall: it will happily call a cricket match
/// to badminton court 3.
///
/// So the pool stays shared — that is what makes cross-event clash detection
/// possible at all, see [TournamentScheduler] — and each match carries what
/// its own event may use. Everything here is a *restriction*: the empty /
/// null state means "no opinion, use the tournament's", which is exactly what
/// every single-sport event and every season created before this existed
/// wants.
class EventAvailability {
  const EventAvailability({
    this.venueIds = const {},
    this.firstDay,
    this.lastDay,
    this.dayStartHour,
    this.dayEndHour,
  });

  /// No restriction at all — any court in the pool, any slot on the grid.
  static const EventAvailability anywhere = EventAvailability();

  /// The venues this event may be played at. Empty means every venue in the
  /// tournament's pool.
  ///
  /// Venue ids rather than court keys deliberately: an organizer picks a
  /// ground, not a court. Which court inside it is the scheduler's job, and
  /// the whole point of letting it choose is that it can spread a draw across
  /// all of them.
  final Set<String> venueIds;

  /// The first and last day this event runs, inclusive. Only the date part is
  /// read; the time of day is [dayStartHour]/[dayEndHour]'s business.
  ///
  /// This is what "the cricket is on the 12th and 13th, the badminton on the
  /// 14th" means to the scheduler. Null on either end falls back to the
  /// tournament's own span.
  final DateTime? firstDay;
  final DateTime? lastDay;

  /// The hours of the day this event's ground is actually available. Null
  /// falls back to the grid the tournament was built with.
  final int? dayStartHour;
  final int? dayEndHour;

  bool get isUnrestricted =>
      venueIds.isEmpty &&
      firstDay == null &&
      lastDay == null &&
      dayStartHour == null &&
      dayEndHour == null;

  bool allowsCourt(CourtRef court) =>
      venueIds.isEmpty || venueIds.contains(court.venueId);

  /// Whether a match occupying [window] fits inside this event's days and
  /// hours.
  ///
  /// The end of the window is checked, not just the start, and that is the
  /// difference between a rule and a suggestion: a 45-minute match starting at
  /// 17:30 against a ground that locks at 18:00 is a match that does not
  /// finish, and starting it is the failure.
  bool allowsWindow(ScheduleWindow window) {
    final first = firstDay;
    if (first != null && _dateOf(window.start).isBefore(_dateOf(first))) {
      return false;
    }
    final last = lastDay;
    if (last != null && _dateOf(window.start).isAfter(_dateOf(last))) {
      return false;
    }

    final open = dayStartHour;
    if (open != null && window.start.hour < open) return false;

    final close = dayEndHour;
    if (close != null) {
      // A match must both start and end inside the day. Spilling past
      // midnight is caught by the same check: the closing instant is built on
      // the START's date, so a window that runs into tomorrow is after it.
      final closesAt = DateTime(
        window.start.year,
        window.start.month,
        window.start.day,
        close,
      );
      if (window.end.isAfter(closesAt)) return false;
    }
    return true;
  }

  static DateTime _dateOf(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// One playing area, plus exactly when it may be used and how hard it may be
/// worked.
///
/// ## Why the grid cannot be one shared list of slots
///
/// The scheduler was built against a single uniform slot grid, which encodes
/// the assumption that every court is free at the same hours on the same days.
/// A real season breaks that on day one: the cricket ground is lent 08:00–20:00
/// but not on the 13th, the TT hall runs a morning and an evening session with
/// a two-hour break between them, and one ground closes at 18:00 while another
/// goes on to 20:00. Handed the union of all of it, the solver puts a match on
/// a ground that is locked.
///
/// So availability is a property of the *court*, and the timetable is solved
/// against a list of these rather than against one grid.
class CourtCalendar {
  const CourtCalendar({
    required this.court,
    required this.slotStarts,
    this.openPeriods = const [],
    this.maxPerDay = 0,
    this.sportIds = const {},
  });

  final CourtRef court;

  /// The times a match may be *started* on this court, earliest first.
  final List<DateTime> slotStarts;

  /// The stretches this court is actually usable — sessions, minus blackouts.
  /// A match must fit entirely inside one of them.
  ///
  /// Empty means no boundary check at all, which is what the uniform-grid
  /// callers get: every season created before venue planning existed is
  /// scheduled exactly as it was.
  final List<ScheduleWindow> openPeriods;

  /// The organizer's ceiling on matches per day on this court, already
  /// reconciled against what the day physically holds. Zero means no ceiling.
  final int maxPerDay;

  /// The sports this court will take. Empty means any — the normal state for
  /// a club with one ground, and the restriction that stops a cricket match
  /// being called to a table-tennis table.
  final Set<String> sportIds;

  bool get isUnbounded => openPeriods.isEmpty;

  /// Whether a match occupying [window] fits entirely inside one usable
  /// stretch of this court.
  ///
  /// The whole window, not the start: a three-hour match beginning at 17:00
  /// on a ground that locks at 18:00 is a match that does not finish, and
  /// starting it is the failure.
  bool admits(ScheduleWindow window) {
    if (openPeriods.isEmpty) return true;
    for (final p in openPeriods) {
      if (!window.start.isBefore(p.start) && !window.end.isAfter(p.end)) {
        return true;
      }
    }
    return false;
  }

  bool allowsSport(String sportId) =>
      sportIds.isEmpty || sportId.isEmpty || sportIds.contains(sportId);

  /// Matches this court can hold in total, given its own periods, a match of
  /// [matchMinutes] plus [turnaroundMinutes] between them, and [maxPerDay].
  ///
  /// The arithmetic behind "you asked for 4 a day and 3 fit": one match needs
  /// its own length, every match after it needs the turnaround too, so a
  /// window of `w` minutes holds `(w + turnaround) ~/ (match + turnaround)`.
  int capacity({required int matchMinutes, required int turnaroundMinutes}) {
    if (matchMinutes <= 0) return 0;
    if (openPeriods.isEmpty) return slotStarts.length;

    final slot = matchMinutes + turnaroundMinutes;
    final perDay = <String, int>{};
    for (final p in openPeriods) {
      final minutes = p.end.difference(p.start).inMinutes;
      if (minutes < matchMinutes) continue;
      final fits = (minutes + turnaroundMinutes) ~/ slot;
      final key = _dayKey(p.start);
      perDay[key] = (perDay[key] ?? 0) + fits;
    }

    var total = 0;
    for (final fits in perDay.values) {
      total += maxPerDay > 0 && maxPerDay < fits ? maxPerDay : fits;
    }
    return total;
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// One match awaiting a court and a time.
///
/// Deliberately not a `Fixture`: the scheduler needs a handful of facts about
/// a match and nothing else, and taking the whole document would tie a pure,
/// testable algorithm to Firestore. The caller projects fixtures into these.
class SchedulableMatch {
  const SchedulableMatch({
    required this.compId,
    required this.matchIndex,
    required this.round,
    required this.playerUids,
    this.teamKeys = const {},
    this.sportId = '',
    this.isGroupStage = false,
    this.priority = 0,
    this.matchMinutes = 30,
    this.availability = EventAvailability.anywhere,
  });

  final String compId;
  final int matchIndex;
  final int round;

  /// **The humans playing, not the entrant ids.**
  ///
  /// This is the whole reason a tournament scheduler exists separately from
  /// the per-draw one. `MatchScheduler` checks clashes by `Entrant.id`, which
  /// is correct within one draw and useless across several: the same person is
  /// a different entrant in the singles, the doubles and the mixed. Keyed on
  /// entrant id, a scheduler will happily put one player on two courts at the
  /// same minute and see no conflict at all.
  ///
  /// Empty for a placeholder whose entrants are not yet known — such a match
  /// cannot be safely placed and is reported as waiting, not failed.
  final Set<String> playerUids;

  /// The sides, by an identity that survives leaving one event — a team id, or
  /// the club id for an inter-club fixture.
  ///
  /// ## Why this is not covered by [playerUids]
  ///
  /// A team is not its squad. Sixteen names are registered, eleven play, and
  /// the eleven are not chosen until the morning — so two matches of the same
  /// team may share no line-up at all at the moment the timetable is built,
  /// and a player-keyed check sees two unrelated fixtures. Team A cannot be on
  /// two grounds at once whichever eleven it fields, and that is a constraint
  /// of its own.
  final Set<String> teamKeys;

  /// What is being played, so a court lent to one sport is not handed to
  /// another. Empty means unstated, which every pre-existing caller is.
  final String sportId;

  /// Group matches must all finish before the knockout phase they feed can
  /// begin, whatever their round numbers say — both phases number from 1.
  final bool isGroupStage;

  /// Lower goes first. The home for "finish the U-13 events before lunch so
  /// the children can go home", which is a real constraint every organizer
  /// has and which has nowhere else to live.
  final int priority;

  /// Per-match, because a U-13 singles and a men's doubles final are not the
  /// same length and a schedule that pretends otherwise drifts all day.
  final int matchMinutes;

  /// The grounds, days and hours this match's EVENT is confined to — see
  /// [EventAvailability]. Every match of one event carries the same one.
  final EventAvailability availability;

  String get key => '$compId#$matchIndex';
}

class Placement {
  const Placement({required this.court, required this.window});

  final CourtRef court;
  final ScheduleWindow window;
}

class UnplacedMatch {
  const UnplacedMatch({required this.match, required this.reason});

  final SchedulableMatch match;

  /// Written for an organizer deciding what to change, so it names the thing
  /// that would actually help — another court, another day, a shorter rest
  /// gap — rather than saying "could not schedule".
  final String reason;
}

class TournamentSchedule {
  const TournamentSchedule({
    required this.placements,
    required this.unplaced,
  });

  /// Keyed by [SchedulableMatch.key].
  final Map<String, Placement> placements;
  final List<UnplacedMatch> unplaced;

  bool get isComplete => unplaced.isEmpty;

  /// When the last scheduled match finishes — what an organizer is really
  /// asking when they ask whether the day fits.
  DateTime? get finishesAt {
    DateTime? latest;
    for (final p in placements.values) {
      if (latest == null || p.window.end.isAfter(latest)) {
        latest = p.window.end;
      }
    }
    return latest;
  }
}

/// Schedules every match of every event in a tournament against one shared
/// pool of courts.
///
/// ## Why this cannot be done one event at a time
///
/// A tournament is a resource-allocation problem — fifteen events, six courts,
/// one weekend — and each of its three constraints spans events:
///
/// 1. **Courts are shared.** Scheduling the U-13 draw and the senior draw
///    independently produces two timetables that each believe they own the
///    hall, and two matches called to court 3 at 11:00.
/// 2. **Players are shared.** Somebody entered in singles, doubles and mixed
///    plays in three draws. They cannot be on two courts at once, and they are
///    entitled to a rest between their own matches *whichever draws those
///    matches belong to*.
/// 3. **The day is shared.** Finishing on time is a property of the whole
///    tournament, not of any one event within it.
///
/// ## Algorithm
///
/// Greedy, over a deterministic ordering: priority, then group-stage before
/// knockout, then round, then draw position. For each match, walk the slots in
/// time order and take the first where a court is free and every player is
/// free — including the rest gap, and including a match in a different event.
///
/// Greedy is not optimal; a smarter search would occasionally fit more. It is
/// chosen because an organizer has to be able to explain the timetable to a
/// parent asking why their child plays at 4pm, and "matches are filled into
/// the earliest slot that works for everyone in them" is an explanation.
/// A globally-optimised timetable that nobody can account for gets overridden
/// by hand, which is worse than a slightly looser one that is trusted.
class TournamentScheduler {
  const TournamentScheduler();

  /// Lays out [matches] against the playing areas offered.
  ///
  /// Pass [calendars] for the real thing — a court whose usable hours, days
  /// and daily ceiling are its own. [courts] plus [slots] is the older uniform
  /// grid, kept because every caller that has no venue plan still wants it and
  /// because the shape is what most of the tests are written against; it is
  /// turned into calendars with no boundaries and no daily cap.
  TournamentSchedule schedule({
    required List<SchedulableMatch> matches,
    List<CourtRef> courts = const [],
    List<ScheduleWindow> slots = const [],
    List<CourtCalendar> calendars = const [],
    Duration minRestBetweenMatches = const Duration(minutes: 20),

    /// Extra time a person needs on top of their rest when their next match is
    /// at a *different* venue. Zero for a one-ground event, and the difference
    /// between a timetable and a fiction for a season across town.
    Duration venueTransition = Duration.zero,
  }) {
    final placements = <String, Placement>{};
    final unplaced = <UnplacedMatch>[];

    final resources = calendars.isNotEmpty
        ? calendars
        : [
            for (final c in courts)
              CourtCalendar(
                court: c,
                slotStarts: [for (final s in slots) s.start],
              ),
          ];

    final hasSlots = resources.any((c) => c.slotStarts.isNotEmpty);
    if (resources.isEmpty || !hasSlots) {
      return TournamentSchedule(
        placements: placements,
        unplaced: [
          for (final m in matches)
            UnplacedMatch(
              match: m,
              reason: resources.isEmpty
                  ? 'No courts were offered. Add a venue with at least one '
                      'court before generating a schedule.'
                  : 'No time slots were offered to schedule into. Check the '
                      'venue availability — every session may be blacked out.',
            ),
        ],
      );
    }

    // Every (time, court) the season offers, in the order the greedy pass
    // walks them: earliest first, and within one minute the courts in the
    // order they were given. Built once — a season of two thousand matches
    // would otherwise re-sort the grid two thousand times.
    final candidates = <_Candidate>[];
    for (var i = 0; i < resources.length; i++) {
      for (final start in resources[i].slotStarts) {
        candidates.add(_Candidate(start: start, order: i, court: resources[i]));
      }
    }
    candidates.sort((a, b) {
      final byTime = a.start.compareTo(b.start);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });

    // courtKey -> the windows already taken on it.
    final courtBookings = <String, List<ScheduleWindow>>{};
    // "courtKey|yyyy-mm-dd" -> how many matches that court already holds that
    // day, so an organizer's "three a day on Ground A" is a rule and not a
    // hope.
    final dayLoad = <String, int>{};
    // playerUid -> every window that person is already committed to, ACROSS
    // every event, with the venue it is at. The cross-event constraint, in one
    // map; the venue is what makes the transition gap checkable.
    final playerBookings = <String, List<_Booking>>{};
    // The same, for team identities — see [SchedulableMatch.teamKeys].
    final teamBookings = <String, List<_Booking>>{};
    // compId -> when the earliest-finishing later round may start, so a
    // semi-final can never be placed before the quarter-final feeding it.
    final roundBarrier = <String, DateTime>{};
    // compId -> the candidates that event's own grounds and sport resolve to.
    final eligibleFor = <String, List<_Candidate>>{};

    for (final match in _ordered(matches)) {
      // Nobody named yet — a knockout placeholder waiting on a feeder. It
      // cannot be safely placed (there is no one to check a clash against)
      // and that is not a scheduling failure.
      if (match.playerUids.isEmpty && match.teamKeys.isEmpty) {
        unplaced.add(UnplacedMatch(
          match: match,
          reason: 'Waiting on an earlier result — both sides are still '
              'undecided, so nobody can be checked for a clash.',
        ));
        continue;
      }

      // The (time, court) pairs this event is allowed on. Computed once per
      // draw rather than per match — every match of an event carries the same
      // availability and the same sport.
      final eligible = eligibleFor.putIfAbsent(
        match.compId,
        () => [
          for (final c in candidates)
            if (match.availability.allowsCourt(c.court.court) &&
                c.court.allowsSport(match.sportId))
              c,
        ],
      );

      if (eligible.isEmpty) {
        unplaced.add(UnplacedMatch(
          match: match,
          reason: 'This event is restricted to grounds that have no usable '
              'courts for it. Add a court to one of them, let one of them '
              'take this sport, or widen the event to another ground.',
        ));
        continue;
      }

      final barrier = roundBarrier[match.compId];
      var sawFreeCourt = false;
      var sawFreePlayers = false;
      var sawAllowedSlot = false;
      var sawOpenCourt = false;
      var sawCourtUnderCap = false;
      Placement? placed;

      for (final candidate in eligible) {
        // A match of this length starting here. Slots are uniform within one
        // court, but a longer match consumes the time regardless, so the
        // window is built from the match rather than taken from the slot.
        final window = ScheduleWindow(
          start: candidate.start,
          end: candidate.start.add(Duration(minutes: match.matchMinutes)),
        );

        // Outside this event's own days or its ground's own hours. Checked
        // before anything expensive: it rejects whole days at a time for an
        // event that runs on one afternoon of a fortnight-long season.
        if (!match.availability.allowsWindow(window)) continue;
        sawAllowedSlot = true;

        // The venue is shut, on a break, or blacked out for part of it.
        if (!candidate.court.admits(window)) continue;
        sawOpenCourt = true;

        // The round that feeds this one has not finished by then.
        if (barrier != null && window.start.isBefore(barrier)) continue;

        final cap = candidate.court.maxPerDay;
        final loadKey = '${candidate.court.court.key}|${_dayKey(window.start)}';
        if (cap > 0 && (dayLoad[loadKey] ?? 0) >= cap) continue;
        sawCourtUnderCap = true;

        final taken =
            courtBookings[candidate.court.court.key] ?? const <ScheduleWindow>[];
        if (taken.any((w) => w.overlaps(window))) continue;
        sawFreeCourt = true;

        final venueId = candidate.court.court.venueId;
        final peopleFree = match.playerUids.every(
              (uid) => _isFree(
                playerBookings[uid] ?? const [],
                window,
                venueId,
                minRestBetweenMatches,
                venueTransition,
              ),
            ) &&
            match.teamKeys.every(
              (key) => _isFree(
                teamBookings[key] ?? const [],
                window,
                venueId,
                minRestBetweenMatches,
                venueTransition,
              ),
            );
        if (!peopleFree) continue;
        sawFreePlayers = true;

        placed = Placement(court: candidate.court.court, window: window);
        dayLoad[loadKey] = (dayLoad[loadKey] ?? 0) + 1;
        break;
      }

      if (placed == null) {
        unplaced.add(UnplacedMatch(
          match: match,
          reason: _reasonFor(
            sawAllowedSlot: sawAllowedSlot,
            sawOpenCourt: sawOpenCourt,
            sawCourtUnderCap: sawCourtUnderCap,
            sawFreeCourt: sawFreeCourt,
            sawFreePlayers: sawFreePlayers,
            restricted: !match.availability.isUnrestricted,
          ),
        ));
        continue;
      }

      placements[match.key] = placed;
      courtBookings.putIfAbsent(placed.court.key, () => []).add(placed.window);
      final booking =
          _Booking(window: placed.window, venueId: placed.court.venueId);
      for (final uid in match.playerUids) {
        playerBookings.putIfAbsent(uid, () => []).add(booking);
      }
      for (final key in match.teamKeys) {
        teamBookings.putIfAbsent(key, () => []).add(booking);
      }

      // Everything after this round in the same draw must start later.
      final existing = roundBarrier[match.compId];
      if (existing == null || placed.window.end.isAfter(existing)) {
        roundBarrier[match.compId] = placed.window.end;
      }
    }

    return TournamentSchedule(placements: placements, unplaced: unplaced);
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Deterministic, so regenerating a schedule produces the same one and an
  /// organizer can be told why a match moved.
  List<SchedulableMatch> _ordered(List<SchedulableMatch> matches) {
    // Priority is applied per DRAW, not per match, and that is a correctness
    // requirement rather than a preference.
    //
    // `roundBarrier` below records one "everything so far has finished by"
    // time per draw, which is only sound if that draw's rounds are visited in
    // ascending order. Sorting on each match's own priority breaks exactly
    // that: give round 3 a lower priority number than round 2 and round 3 is
    // placed first, against a barrier that has only seen round 1 — a
    // semi-final scheduled before the quarter-final feeding it, which is the
    // one thing the barrier exists to prevent.
    //
    // Every production caller already sets priority from the event
    // (`_priorityFor`), so collapsing to the draw's minimum changes nothing
    // there and closes the hole for any caller that does not. Found by the
    // randomised season in `schedule_guarantees_test.dart`, not by reading.
    final drawPriority = <String, int>{};
    for (final m in matches) {
      final seen = drawPriority[m.compId];
      if (seen == null || m.priority < seen) drawPriority[m.compId] = m.priority;
    }
    int priorityOf(SchedulableMatch m) => drawPriority[m.compId] ?? m.priority;

    return [...matches]..sort((a, b) {
        final byPriority = priorityOf(a).compareTo(priorityOf(b));
        if (byPriority != 0) return byPriority;
        // Group stages before knockouts: a knockout cannot start until the
        // groups feeding it are done, and both number their rounds from 1.
        final byPhase = (a.isGroupStage ? 0 : 1).compareTo(b.isGroupStage ? 0 : 1);
        if (byPhase != 0) return byPhase;
        final byRound = a.round.compareTo(b.round);
        if (byRound != 0) return byRound;
        final byComp = a.compId.compareTo(b.compId);
        if (byComp != 0) return byComp;
        return a.matchIndex.compareTo(b.matchIndex);
      });
  }

  /// Whether a person or a team is free for [candidate].
  ///
  /// The required gap grows when the previous match was somewhere else: rest
  /// is what a body needs after playing, transition is the time it takes to
  /// get across town, and someone finishing at the ground at 17:00 with a
  /// 30-minute rest and a 20-minute journey cannot be on the hall's court
  /// before 17:50.
  bool _isFree(
    List<_Booking> booked,
    ScheduleWindow candidate,
    String venueId,
    Duration minRest,
    Duration venueTransition,
  ) {
    for (final b in booked) {
      if (b.window.overlaps(candidate)) return false;
      final needed =
          b.venueId == venueId ? minRest : minRest + venueTransition;
      if (b.window.gapTo(candidate) < needed) return false;
    }
    return true;
  }

  String _reasonFor({
    required bool sawAllowedSlot,
    required bool sawOpenCourt,
    required bool sawCourtUnderCap,
    required bool sawFreeCourt,
    required bool sawFreePlayers,
    required bool restricted,
  }) {
    // Ordered by how early the constraint bites, so the reason names the first
    // thing that actually blocked the match rather than the last thing that
    // was checked. Each one is written as something an organizer can change.
    if (!sawAllowedSlot) {
      return restricted
          ? 'None of this season\'s slots fall inside the days and hours this '
              'event was given. Widen its dates or its playing hours.'
          : 'No time slots were offered to schedule into.';
    }
    if (!sawOpenCourt) {
      return 'Every slot this event could use falls outside its venue\'s '
          'playing sessions, or inside a blackout. Add a session, shorten the '
          'match, or clear a blackout.';
    }
    if (!sawCourtUnderCap) {
      return 'Every day at this event\'s grounds has already hit the maximum '
          'matches you set for it. Raise the daily maximum, add a ground, or '
          'add a day.';
    }
    if (!sawFreeCourt) {
      return restricted
          ? 'Every court at this event\'s own grounds was already booked in '
              'the slots it may use. Give it another ground, or more days.'
          : 'Every court was already booked in those slots. Add a court, or '
              'extend the day.';
    }
    if (!sawFreePlayers) {
      return 'Every remaining slot clashes with another match one of these '
          'players or teams is already in, or falls inside their rest or '
          'travel gap. Add a day, or shorten the rest gap.';
    }
    return 'No court and slot were free at the same time with every player '
        'available.';
  }

  /// Builds the uniform slot grid a tournament is scheduled into.
  ///
  /// Per day rather than one continuous run, because a tournament stops
  /// overnight and a match must not be scheduled at 3am simply because the
  /// arithmetic allowed it.
  static List<ScheduleWindow> buildSlots({
    required DateTime firstDay,
    required int dayCount,
    required int openHour,
    required int closeHour,
    required int slotMinutes,
  }) {
    if (slotMinutes <= 0 || closeHour <= openHour) return const [];
    final slots = <ScheduleWindow>[];
    final perDay = ((closeHour - openHour) * 60) ~/ slotMinutes;

    for (var day = 0; day < dayCount; day++) {
      var cursor = DateTime(
        firstDay.year,
        firstDay.month,
        firstDay.day + day,
        openHour,
      );
      for (var i = 0; i < perDay; i++) {
        slots.add(ScheduleWindow(
          start: cursor,
          end: cursor.add(Duration(minutes: slotMinutes)),
        ));
        cursor = cursor.add(Duration(minutes: slotMinutes));
      }
    }
    return slots;
  }
}

/// One offer of "this court, starting then".
class _Candidate {
  const _Candidate({
    required this.start,
    required this.order,
    required this.court,
  });

  final DateTime start;

  /// The court's position in the pool the caller gave, so ties break the same
  /// way on every run and a regenerated schedule is the same schedule.
  final int order;

  final CourtCalendar court;
}

/// A commitment already made, and where it is.
class _Booking {
  const _Booking({required this.window, required this.venueId});

  final ScheduleWindow window;
  final String venueId;
}
