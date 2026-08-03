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
    this.isGroupStage = false,
    this.priority = 0,
    this.matchMinutes = 30,
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

  TournamentSchedule schedule({
    required List<SchedulableMatch> matches,
    required List<CourtRef> courts,
    required List<ScheduleWindow> slots,
    Duration minRestBetweenMatches = const Duration(minutes: 20),
  }) {
    final placements = <String, Placement>{};
    final unplaced = <UnplacedMatch>[];

    if (courts.isEmpty || slots.isEmpty) {
      return TournamentSchedule(
        placements: placements,
        unplaced: [
          for (final m in matches)
            UnplacedMatch(
              match: m,
              reason: courts.isEmpty
                  ? 'No courts were offered. Add a venue with at least one '
                      'court before generating a schedule.'
                  : 'No time slots were offered to schedule into.',
            ),
        ],
      );
    }

    // courtKey -> the windows already taken on it.
    final courtBookings = <String, List<ScheduleWindow>>{};
    // playerUid -> every window that person is already committed to, ACROSS
    // every event. The cross-event constraint, in one map.
    final playerBookings = <String, List<ScheduleWindow>>{};
    // compId -> when the earliest-finishing later round may start, so a
    // semi-final can never be placed before the quarter-final feeding it.
    final roundBarrier = <String, DateTime>{};

    for (final match in _ordered(matches)) {
      // Nobody named yet — a knockout placeholder waiting on a feeder. It
      // cannot be safely placed (there is no one to check a clash against)
      // and that is not a scheduling failure.
      if (match.playerUids.isEmpty) {
        unplaced.add(UnplacedMatch(
          match: match,
          reason: 'Waiting on an earlier result — both sides are still '
              'undecided, so nobody can be checked for a clash.',
        ));
        continue;
      }

      final barrier = roundBarrier[match.compId];
      var sawFreeCourt = false;
      var sawFreePlayers = false;
      Placement? placed;

      for (final slot in slots) {
        // A match of this length starting here. Slots are uniform, but a
        // longer match consumes the time regardless, so the window is built
        // from the match rather than taken from the slot.
        final window = ScheduleWindow(
          start: slot.start,
          end: slot.start.add(Duration(minutes: match.matchMinutes)),
        );

        // The round that feeds this one has not finished by then.
        if (barrier != null && window.start.isBefore(barrier)) continue;

        final playersFree = match.playerUids.every(
          (uid) => _isFree(
            playerBookings[uid] ?? const [],
            window,
            minRestBetweenMatches,
          ),
        );
        if (!playersFree) continue;
        sawFreePlayers = true;

        for (final court in courts) {
          final taken = courtBookings[court.key] ?? const <ScheduleWindow>[];
          if (taken.any((w) => w.overlaps(window))) continue;
          sawFreeCourt = true;
          placed = Placement(court: court, window: window);
          break;
        }
        if (placed != null) break;
      }

      if (placed == null) {
        unplaced.add(UnplacedMatch(
          match: match,
          reason: _reasonFor(
            sawFreePlayers: sawFreePlayers,
            sawFreeCourt: sawFreeCourt,
          ),
        ));
        continue;
      }

      placements[match.key] = placed;
      courtBookings.putIfAbsent(placed.court.key, () => []).add(placed.window);
      for (final uid in match.playerUids) {
        playerBookings.putIfAbsent(uid, () => []).add(placed.window);
      }

      // Everything after this round in the same draw must start later.
      final existing = roundBarrier[match.compId];
      if (existing == null || placed.window.end.isAfter(existing)) {
        roundBarrier[match.compId] = placed.window.end;
      }
    }

    return TournamentSchedule(placements: placements, unplaced: unplaced);
  }

  /// Deterministic, so regenerating a schedule produces the same one and an
  /// organizer can be told why a match moved.
  List<SchedulableMatch> _ordered(List<SchedulableMatch> matches) {
    return [...matches]..sort((a, b) {
        final byPriority = a.priority.compareTo(b.priority);
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

  bool _isFree(
    List<ScheduleWindow> booked,
    ScheduleWindow candidate,
    Duration minRest,
  ) {
    for (final w in booked) {
      if (w.overlaps(candidate)) return false;
      if (w.gapTo(candidate) < minRest) return false;
    }
    return true;
  }

  String _reasonFor({
    required bool sawFreePlayers,
    required bool sawFreeCourt,
  }) {
    if (!sawFreePlayers) {
      return 'Every slot clashes with another match one of these players is '
          'already in, or falls inside their rest gap. They are entered in '
          'too many events for the days available — add a day, or shorten '
          'the rest gap.';
    }
    if (!sawFreeCourt) {
      return 'Players were free but every court was already booked in those '
          'slots. Add a court, or extend the day.';
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
