import 'fixture_generator.dart';

/// A place matches can be played, with how many can run at once.
///
/// [capacity] models multiple concurrent playing areas at one physical
/// venue — several badminton courts in one hall, several pitches on one
/// ground — not multiple time slots (that is what [TimeSlot] is for).
class Venue {
  const Venue({
    required this.id,
    required this.name,
    this.capacity = 1,
  });

  final String id;
  final String name;

  /// How many matches this venue can host simultaneously.
  final int capacity;
}

/// A candidate window a match could be played in.
class TimeSlot {
  const TimeSlot({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// Whether this slot shares any real time with [other]. Half-open on
  /// purpose (`start < other.end && other.start < end`) so a slot that ends
  /// exactly when another begins does not count as a clash — back-to-back
  /// slots are the normal way a day is scheduled.
  bool overlaps(TimeSlot other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  /// Gap between this slot and [other] when they do not overlap. Negative
  /// (and meaningless as a "gap") if they do — callers must check
  /// [overlaps] first.
  Duration gapTo(TimeSlot other) {
    if (start.isAfter(other.end)) return start.difference(other.end);
    return other.start.difference(end);
  }
}

class ScheduledFixture {
  const ScheduledFixture({
    required this.fixture,
    required this.venue,
    required this.slot,
  });

  final PlannedFixture fixture;
  final Venue venue;
  final TimeSlot slot;
}

class UnscheduledFixture {
  const UnscheduledFixture({required this.fixture, required this.reason});

  final PlannedFixture fixture;

  /// Human-readable — this is shown to an organizer deciding whether to add
  /// venues, add slots, or relax the rest gap, so it says which of those
  /// would actually help rather than just "could not schedule".
  final String reason;
}

class ScheduleResult {
  const ScheduleResult({required this.scheduled, required this.unscheduled});

  final List<ScheduledFixture> scheduled;
  final List<UnscheduledFixture> unscheduled;

  bool get isFullyScheduled => unscheduled.isEmpty;
}

/// Assigns generated fixtures to (venue, time slot) pairs.
///
/// ## Why this reports instead of throwing
///
/// A real tournament routinely does not have enough courts and daylight to
/// fit every match with a comfortable rest gap — that is an organizing
/// problem to be surfaced (add a venue, add a slot, shrink the rest gap),
/// not a programming error. Throwing on infeasibility would force every
/// caller into a try/catch just to discover *which* matches did not fit and
/// why; returning a [ScheduleResult] with both the placements that worked
/// and the ones that did not (with a reason) lets the organizer's screen
/// show "12 of 15 scheduled, 3 need attention" instead of a crash.
///
/// ## Algorithm
///
/// Greedy, in the order [fixtures] is given (callers control priority —
/// typically round order, so earlier rounds are not left unscheduled while
/// a later round's matches grab the earliest slots). For each fixture, try
/// slots in the order given, and within each slot try venues in the order
/// given, taking the first (venue, slot) that satisfies every constraint.
/// Greedy is not globally optimal — a different placement order can
/// occasionally fit more fixtures overall — but it is fast, deterministic,
/// and gives an organizer a schedule they can reason about ("matches are
/// filled into the earliest available slot"), which matters more here than
/// a marginally denser packing.
class MatchScheduler {
  const MatchScheduler();

  ScheduleResult schedule({
    required List<PlannedFixture> fixtures,
    required List<Venue> venues,
    required List<TimeSlot> slots,
    Duration minRestBetweenMatches = Duration.zero,
  }) {
    final scheduled = <ScheduledFixture>[];
    final unscheduled = <UnscheduledFixture>[];

    // venueId -> slot -> count of matches already placed there, to enforce
    // capacity without rescanning `scheduled` on every attempt.
    final venueSlotUsage = <String, Map<TimeSlot, int>>{};
    // entrantId -> every slot that entrant is already booked into, to check
    // clashes and rest gaps in one pass per candidate slot.
    final entrantSlots = <String, List<TimeSlot>>{};

    for (final fixture in fixtures) {
      // Nothing to place: a bye has no opponent to play, and a deeper
      // knockout/losers-bracket/qualifier placeholder with neither entrant
      // known yet cannot be scheduled before it has two real sides. Neither
      // is a scheduling failure — there is no fixture standing here.
      if (fixture.entrantA == null || fixture.entrantB == null) continue;

      final entrantIds = [fixture.entrantA!.id, fixture.entrantB!.id];

      TimeSlot? placedSlot;
      Venue? placedVenue;
      var anyVenueHadCapacity = false;
      var anySlotWasEntrantFree = false;

      for (final slot in slots) {
        final entrantFree = entrantIds.every((id) => _isFree(
              entrantSlots[id] ?? const [],
              slot,
              minRestBetweenMatches,
            ));
        if (entrantFree) anySlotWasEntrantFree = true;
        if (!entrantFree) continue;

        for (final venue in venues) {
          final used = venueSlotUsage[venue.id]?[slot] ?? 0;
          if (used < venue.capacity) {
            anyVenueHadCapacity = true;
          } else {
            continue;
          }

          placedSlot = slot;
          placedVenue = venue;
          break;
        }
        if (placedSlot != null) break;
      }

      if (placedSlot != null && placedVenue != null) {
        scheduled.add(ScheduledFixture(
          fixture: fixture,
          venue: placedVenue,
          slot: placedSlot,
        ));
        venueSlotUsage
            .putIfAbsent(placedVenue.id, () => {})
            .update(placedSlot, (v) => v + 1, ifAbsent: () => 1);
        for (final id in entrantIds) {
          entrantSlots.putIfAbsent(id, () => []).add(placedSlot);
        }
      } else {
        unscheduled.add(UnscheduledFixture(
          fixture: fixture,
          reason: _reasonFor(
            anySlotWasEntrantFree: anySlotWasEntrantFree,
            anyVenueHadCapacity: anyVenueHadCapacity,
            venuesGiven: venues.isNotEmpty,
            slotsGiven: slots.isNotEmpty,
          ),
        ));
      }
    }

    return ScheduleResult(scheduled: scheduled, unscheduled: unscheduled);
  }

  bool _isFree(
    List<TimeSlot> booked,
    TimeSlot candidate,
    Duration minRest,
  ) {
    for (final b in booked) {
      if (b.overlaps(candidate)) return false;
      if (b.gapTo(candidate) < minRest) return false;
    }
    return true;
  }

  String _reasonFor({
    required bool anySlotWasEntrantFree,
    required bool anyVenueHadCapacity,
    required bool venuesGiven,
    required bool slotsGiven,
  }) {
    if (!slotsGiven) return 'No time slots were offered to schedule into.';
    if (!venuesGiven) return 'No venues were offered to schedule into.';
    if (!anySlotWasEntrantFree) {
      return 'Both entrants are already booked, clashing, or within the '
          'minimum rest gap in every candidate slot.';
    }
    if (!anyVenueHadCapacity) {
      return 'Every venue was at capacity in the slots where both entrants '
          'were free — add a venue or another slot.';
    }
    return 'No (venue, slot) combination satisfied every constraint '
        'simultaneously.';
  }
}
