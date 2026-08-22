import 'tournament_scheduler.dart';

/// Somebody available to officiate.
class AvailableOfficial {
  const AvailableOfficial({
    required this.uid,
    required this.name,
    this.clubId,
    this.role = 'main_umpire',
    this.maxMatches = 8,
    this.sports = const [],
    this.availableDays = const {},
  });

  final String uid;
  final String name;

  /// The club they belong to. Drives neutrality — an official from a club may
  /// not be put on that club's match. Null means unaffiliated, which is the
  /// most useful kind of official to have and is never blocked.
  final String? clubId;

  final String role;

  /// How many matches they will take in a day. An umpire who stands for
  /// fourteen matches is not officiating the last four of them, and a roster
  /// that quietly does that to a volunteer is how a club loses its volunteers.
  ///
  /// Counted per calendar day, so a three-day season does not silently turn a
  /// daily limit into a weekend one.
  final int maxMatches;

  /// Sports this person will officiate, by sport id. Empty means any — see
  /// [TournamentOfficial.coversSport].
  ///
  /// ## Why this is a hard constraint and not a preference
  ///
  /// A multi-sport season is the case this exists for. Five sports run in one
  /// hall over one weekend, and the panel is not one panel: the two people who
  /// know the kabaddi rules are not the ones who can call a badminton service
  /// fault. An assigner that ignores this spreads the work evenly and staffs
  /// every match with somebody who cannot officiate it — which reads as a
  /// complete roster right up until Saturday morning.
  final List<String> sports;

  /// Calendar days (`yyyy-MM-dd`) this person can attend. Empty means every
  /// day, which is the common case for a one-day meet.
  final Set<String> availableDays;

  bool coversSport(String? sportId) =>
      sports.isEmpty || sportId == null || sports.contains(sportId);

  bool isFreeOn(String dayKey) =>
      availableDays.isEmpty || availableDays.contains(dayKey);
}

/// A match that needs an official, already placed in time and space.
class OfficiatingSlot {
  const OfficiatingSlot({
    required this.fixtureId,
    required this.window,
    required this.courtKey,
    required this.contestingClubIds,
    this.sportId,
    this.eventId,
    this.eventName = '',
    this.groupId,
    this.label = '',
  });

  final String fixtureId;
  final ScheduleWindow window;
  final String courtKey;

  /// The clubs playing. An official from either may not take this match.
  final Set<String> contestingClubIds;

  /// Which sport this match is, so only officials who cover it are offered.
  /// Null for a match whose event never recorded one, and treated as "any
  /// official will do" rather than "nobody may take it".
  final String? sportId;

  /// The draw this match belongs to, and its name. Carried through so an
  /// unstaffed match can be reported as "U-13 Boys Singles, quarter-final"
  /// rather than as a fixture id, and so the caller can total the work per
  /// event without joining back to the fixtures.
  final String? eventId;
  final String eventName;

  /// The group, for a group-stage match. A season's groups are where most of
  /// the volume is — a five-group event is thirty matches to the knockout's
  /// seven — and an organizer staffing a day wants them counted as groups.
  final String? groupId;

  final String label;

  /// The calendar day this match is on, as the same `yyyy-MM-dd` key an
  /// official's availability is recorded in.
  String get dayKey => _dayKeyOf(window.start);
}

/// `yyyy-MM-dd` for a local instant.
///
/// Deliberately not `DateFormat` — this file is pure domain logic with no
/// package dependencies, and the format is three padded numbers.
String _dayKeyOf(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

class OfficialAssignment {
  const OfficialAssignment({
    required this.fixtureId,
    required this.official,
  });

  final String fixtureId;
  final AvailableOfficial official;
}

class UnstaffedSlot {
  const UnstaffedSlot({required this.slot, required this.reason});

  final OfficiatingSlot slot;

  /// Written for an organizer deciding what to do about it, so it names the
  /// thing that would help — find a neutral official, raise a cap, accept a
  /// non-neutral one — rather than "no official available".
  final String reason;
}

class OfficialsRoster {
  const OfficialsRoster({
    required this.assignments,
    required this.unstaffed,
    required this.loadByUid,
    this.loadByUidByDay = const {},
  });

  final List<OfficialAssignment> assignments;
  final List<UnstaffedSlot> unstaffed;

  /// How many matches each official ended up with — the number an organizer
  /// checks before agreeing to the roster.
  final Map<String, int> loadByUid;

  /// The same totals split by calendar day, `uid -> dayKey -> count`.
  ///
  /// The tournament total is the wrong number to check on a three-day season:
  /// twelve matches spread over three days is a normal weekend, and twelve on
  /// the Saturday is somebody going home. The per-day cap is enforced against
  /// this, and the panel screen shows it for the same reason.
  final Map<String, Map<String, int>> loadByUidByDay;

  bool get isComplete => unstaffed.isEmpty;

  /// Unstaffed matches grouped by sport, so an organizer is told "kabaddi has
  /// nobody" rather than handed a list of forty match names to notice it in.
  Map<String, List<UnstaffedSlot>> get unstaffedBySport {
    final out = <String, List<UnstaffedSlot>>{};
    for (final u in unstaffed) {
      out.putIfAbsent(u.slot.sportId ?? 'unknown', () => []).add(u);
    }
    return out;
  }

  /// Unstaffed matches grouped by the event they belong to.
  Map<String, List<UnstaffedSlot>> get unstaffedByEvent {
    final out = <String, List<UnstaffedSlot>>{};
    for (final u in unstaffed) {
      out.putIfAbsent(u.slot.eventName.isEmpty ? 'Event' : u.slot.eventName,
          () => []).add(u);
    }
    return out;
  }
}

/// Puts officials on matches.
///
/// ## Why neutrality is the point
///
/// An umpire from Kompally Sports Academy standing in a Kompally match is the
/// single most common complaint at a grassroots tournament, and it is almost
/// never actual bias — it is that nobody checked, and the losing side has no
/// way to know nobody checked. A roster that can *state* every official was
/// neutral is worth more than one that merely was.
///
/// So neutrality is a hard constraint, and where it cannot be met the slot is
/// reported as unstaffed with the reason rather than quietly filled by
/// somebody from one of the two clubs. The organizer can still assign by hand
/// — they are allowed to decide "both captains are happy with Ravi" — but the
/// system will not make that decision for them silently.
///
/// ## What else it enforces
///
/// An official cannot be in two places at once, and cannot be booked past
/// their own limit for that day. Both are the same class of constraint as the
/// player rest gap in [TournamentScheduler] and are checked the same way.
///
/// Two more, added because a multi-sport season made them the difference
/// between a roster and a list:
///
/// - **Sport.** Somebody on the panel for kabaddi is not offered a badminton
///   court. See [AvailableOfficial.sports].
/// - **The day they said they could come.** An official who is free on the
///   Saturday is not put on a Sunday match, however light their load looks.
///   See [AvailableOfficial.availableDays].
///
/// Both default open — an official with no sports and no dates recorded is
/// treated as available for everything — so a panel built in two minutes
/// still works, and one built carefully is honoured exactly.
class OfficialsAssigner {
  const OfficialsAssigner();

  OfficialsRoster assign({
    required List<OfficiatingSlot> slots,
    required List<AvailableOfficial> officials,

    /// Minimum gap between an official's own matches — they have to walk
    /// across the hall and read the next team sheet.
    Duration turnaround = const Duration(minutes: 10),
  }) {
    final assignments = <OfficialAssignment>[];
    final unstaffed = <UnstaffedSlot>[];
    final booked = <String, List<ScheduleWindow>>{};
    final load = <String, int>{for (final o in officials) o.uid: 0};
    final loadByDay = <String, Map<String, int>>{
      for (final o in officials) o.uid: <String, int>{},
    };

    // Earliest first, so the day fills forwards and an official's load
    // accumulates in the order they will actually work.
    final ordered = [...slots]
      ..sort((a, b) => a.window.start.compareTo(b.window.start));

    for (final slot in ordered) {
      if (officials.isEmpty) {
        unstaffed.add(UnstaffedSlot(
          slot: slot,
          reason: 'No officials have been added to this tournament.',
        ));
        continue;
      }

      final day = slot.dayKey;

      // Each of these records how far down the funnel any candidate reached,
      // so the reason given for an unstaffed match names the constraint that
      // actually stopped it. "No official available" is true of every failure
      // and useful for none of them: the organizer's next action is different
      // for "nobody covers kabaddi" than for "everybody is on another court".
      var sawSport = false;
      var sawDay = false;
      var sawNeutral = false;
      var sawUnderCap = false;
      var sawFree = false;
      AvailableOfficial? chosen;

      // Least-loaded ON THIS DAY first, so the work spreads across the people
      // who are actually present rather than being levelled against a total
      // that includes days they were not there for.
      int dayLoad(AvailableOfficial o) => loadByDay[o.uid]?[day] ?? 0;
      final candidates = [...officials]
        ..sort((a, b) {
          final byDay = dayLoad(a).compareTo(dayLoad(b));
          if (byDay != 0) return byDay;
          return (load[a.uid] ?? 0).compareTo(load[b.uid] ?? 0);
        });

      for (final official in candidates) {
        // Sport first: it is the constraint that cannot be argued away. An
        // organizer can accept a non-neutral umpire or raise a cap; they
        // cannot make somebody know the kho-kho rules on Saturday morning.
        if (!official.coversSport(slot.sportId)) continue;
        sawSport = true;

        if (!official.isFreeOn(day)) continue;
        sawDay = true;

        final club = official.clubId;
        if (club != null && slot.contestingClubIds.contains(club)) continue;
        sawNeutral = true;

        if (dayLoad(official) >= official.maxMatches) continue;
        sawUnderCap = true;

        if (!_isFree(booked[official.uid] ?? const [], slot.window, turnaround)) {
          continue;
        }
        sawFree = true;
        chosen = official;
        break;
      }

      if (chosen == null) {
        unstaffed.add(UnstaffedSlot(
          slot: slot,
          reason: _reasonFor(
            slot: slot,
            sawSport: sawSport,
            sawDay: sawDay,
            sawNeutral: sawNeutral,
            sawUnderCap: sawUnderCap,
            sawFree: sawFree,
          ),
        ));
        continue;
      }

      assignments.add(
        OfficialAssignment(fixtureId: slot.fixtureId, official: chosen),
      );
      booked.putIfAbsent(chosen.uid, () => []).add(slot.window);
      load[chosen.uid] = (load[chosen.uid] ?? 0) + 1;
      final perDay = loadByDay.putIfAbsent(chosen.uid, () => <String, int>{});
      perDay[day] = (perDay[day] ?? 0) + 1;
    }

    return OfficialsRoster(
      assignments: assignments,
      unstaffed: unstaffed,
      loadByUid: load,
      loadByUidByDay: loadByDay,
    );
  }

  bool _isFree(
    List<ScheduleWindow> booked,
    ScheduleWindow candidate,
    Duration turnaround,
  ) {
    for (final w in booked) {
      if (w.overlaps(candidate)) return false;
      if (w.gapTo(candidate) < turnaround) return false;
    }
    return true;
  }

  /// Names the constraint that actually stopped this match being staffed.
  ///
  /// Ordered the way the funnel is, so the reason is the FIRST wall every
  /// candidate hit rather than the last. Getting this backwards produces the
  /// most misleading message the screen can show — telling an organizer their
  /// umpires are all busy when in fact none of them covers the sport, which
  /// sends them off to shuffle a timetable that was never the problem.
  String _reasonFor({
    required OfficiatingSlot slot,
    required bool sawSport,
    required bool sawDay,
    required bool sawNeutral,
    required bool sawUnderCap,
    required bool sawFree,
  }) {
    if (!sawSport) {
      final sport = slot.sportId;
      return 'Nobody on the panel officiates '
          '${sport == null || sport.isEmpty ? 'this sport' : sport}. Add '
          'someone for it, or widen an existing panel member to cover it.';
    }
    if (!sawDay) {
      return 'Everybody who officiates this sport said they are unavailable '
          'on this date. Move the match, or add someone who can come.';
    }
    if (!sawNeutral) {
      return 'Every official free on this date belongs to one of the two '
          'clubs playing. Add a neutral official, or assign one by hand and '
          'record that both sides agreed.';
    }
    if (!sawUnderCap) {
      return 'Every neutral official has already reached their match limit '
          'for this day. Raise a limit, or add someone to the panel.';
    }
    if (!sawFree) {
      return 'Every neutral official is on another court at this time, or is '
          'inside their turnaround gap from their last match.';
    }
    return 'No official could be placed on this match.';
  }
}
