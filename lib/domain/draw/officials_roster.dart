import 'tournament_scheduler.dart';

/// Somebody available to officiate.
class AvailableOfficial {
  const AvailableOfficial({
    required this.uid,
    required this.name,
    this.clubId,
    this.role = 'main_umpire',
    this.maxMatches = 8,
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
  final int maxMatches;
}

/// A match that needs an official, already placed in time and space.
class OfficiatingSlot {
  const OfficiatingSlot({
    required this.fixtureId,
    required this.window,
    required this.courtKey,
    required this.contestingClubIds,
    this.label = '',
  });

  final String fixtureId;
  final ScheduleWindow window;
  final String courtKey;

  /// The clubs playing. An official from either may not take this match.
  final Set<String> contestingClubIds;

  final String label;
}

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
  });

  final List<OfficialAssignment> assignments;
  final List<UnstaffedSlot> unstaffed;

  /// How many matches each official ended up with — the number an organizer
  /// checks before agreeing to the roster.
  final Map<String, int> loadByUid;

  bool get isComplete => unstaffed.isEmpty;
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
/// their own limit. Both are the same class of constraint as the player rest
/// gap in [TournamentScheduler] and are checked the same way.
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

      var sawNeutral = false;
      var sawFree = false;
      AvailableOfficial? chosen;

      // Least-loaded first, so the work spreads rather than landing on
      // whoever happens to be first in the list.
      final candidates = [...officials]
        ..sort((a, b) => (load[a.uid] ?? 0).compareTo(load[b.uid] ?? 0));

      for (final official in candidates) {
        final club = official.clubId;
        if (club != null && slot.contestingClubIds.contains(club)) continue;
        sawNeutral = true;

        if ((load[official.uid] ?? 0) >= official.maxMatches) continue;
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
          reason: _reasonFor(sawNeutral: sawNeutral, sawFree: sawFree),
        ));
        continue;
      }

      assignments.add(
        OfficialAssignment(fixtureId: slot.fixtureId, official: chosen),
      );
      booked.putIfAbsent(chosen.uid, () => []).add(slot.window);
      load[chosen.uid] = (load[chosen.uid] ?? 0) + 1;
    }

    return OfficialsRoster(
      assignments: assignments,
      unstaffed: unstaffed,
      loadByUid: load,
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

  String _reasonFor({required bool sawNeutral, required bool sawFree}) {
    if (!sawNeutral) {
      return 'Every available official belongs to one of the two clubs '
          'playing. Add a neutral official, or assign one by hand and record '
          'that both sides agreed.';
    }
    if (!sawFree) {
      return 'Every neutral official is already on another court at this time '
          'or has reached their match limit for the day.';
    }
    return 'No official could be placed on this match.';
  }
}
