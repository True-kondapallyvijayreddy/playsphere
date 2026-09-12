import 'tournament_scheduler.dart';

/// One way a schedule broke a promise.
class ScheduleViolation {
  const ScheduleViolation({
    required this.kind,
    required this.detail,
    required this.matchKeys,
  });

  final ScheduleViolationKind kind;

  /// Written for a human — names the court, the person, or the round, because
  /// "constraint violated" tells an organizer nothing they can act on.
  final String detail;

  /// The matches involved, by [SchedulableMatch.key].
  final List<String> matchKeys;

  @override
  String toString() => '${kind.name}: $detail';
}

enum ScheduleViolationKind {
  courtDoubleBooked,
  playerDoubleBooked,

  /// One team on two grounds at once. Distinct from [playerDoubleBooked]
  /// because a team is not its line-up — see [SchedulableMatch.teamKeys].
  teamDoubleBooked,

  restGapTooShort,
  roundOutOfOrder,

  /// A match placed on a ground its event was never given, or outside the
  /// days or hours that event runs — see [EventAvailability].
  outsideEventAvailability,

  /// A match placed when the venue itself is shut — outside its sessions, or
  /// inside a blackout — or on a court lent to another sport.
  outsideVenueAvailability,

  /// More matches on one playing area in one day than the organizer allowed.
  dailyLimitExceeded,
}

/// Checks a produced schedule against the promises made about it.
///
/// The scheduler is written to satisfy these; this asks whether it did. That
/// is not the same question, and the difference matters because the cost of
/// being wrong is paid by a fourteen-year-old standing on the wrong court at
/// nine on a Saturday. A guarantee nothing checks is a comment.
///
/// Cheap enough to run on every solve — one pass to bucket, then pairwise
/// within each bucket, where a bucket is one court or one person's day.
/// A season of two thousand matches across six courts costs microseconds.
class ScheduleGuarantees {
  const ScheduleGuarantees._();

  /// Every promise, checked. An empty list is the guarantee holding.
  static List<ScheduleViolation> verify({
    required List<SchedulableMatch> matches,
    required TournamentSchedule schedule,
    required Duration minRestBetweenMatches,

    /// The courts as they were offered. Given, the venue's own sessions,
    /// blackouts, sport restriction and daily ceiling are checked too; omitted,
    /// those four checks are skipped and the rest are unchanged.
    List<CourtCalendar> calendars = const [],

    /// Extra gap owed to a person whose next match is at another venue.
    Duration venueTransition = Duration.zero,
  }) {
    final byKey = {for (final m in matches) m.key: m};
    final placed = <({SchedulableMatch match, Placement at})>[
      for (final entry in schedule.placements.entries)
        if (byKey[entry.key] != null)
          (match: byKey[entry.key]!, at: entry.value),
    ];

    return [
      ..._courtClashes(placed),
      ..._peopleClashes(placed, minRestBetweenMatches, venueTransition),
      ..._roundOrder(placed),
      ..._eventAvailability(placed),
      ..._venueAvailability(placed, calendars),
    ];
  }

  /// True when the schedule keeps every promise.
  static bool holds({
    required List<SchedulableMatch> matches,
    required TournamentSchedule schedule,
    required Duration minRestBetweenMatches,
    List<CourtCalendar> calendars = const [],
    Duration venueTransition = Duration.zero,
  }) =>
      verify(
        matches: matches,
        schedule: schedule,
        minRestBetweenMatches: minRestBetweenMatches,
        calendars: calendars,
        venueTransition: venueTransition,
      ).isEmpty;

  /// Two matches on one court at overlapping times.
  static List<ScheduleViolation> _courtClashes(
    List<({SchedulableMatch match, Placement at})> placed,
  ) {
    final byCourt = <String, List<({SchedulableMatch match, Placement at})>>{};
    for (final p in placed) {
      byCourt.putIfAbsent(p.at.court.key, () => []).add(p);
    }

    final out = <ScheduleViolation>[];
    for (final entry in byCourt.entries) {
      final list = [...entry.value]
        ..sort((a, b) => a.at.window.start.compareTo(b.at.window.start));
      for (var i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];
        if (prev.at.window.overlaps(cur.at.window)) {
          out.add(ScheduleViolation(
            kind: ScheduleViolationKind.courtDoubleBooked,
            detail: '${cur.at.court.label} holds two matches at once',
            matchKeys: [prev.match.key, cur.match.key],
          ));
        }
      }
    }
    return out;
  }

  /// One person — or one team — in two places, or given less rest than
  /// promised. Checked across every event, which is the only level at which
  /// any of it is visible.
  ///
  /// Teams are checked alongside people rather than instead of them: sixteen
  /// are registered and eleven play, so two matches of the same team may share
  /// no named player at all at the moment the timetable is built.
  static List<ScheduleViolation> _peopleClashes(
    List<({SchedulableMatch match, Placement at})> placed,
    Duration minRest,
    Duration venueTransition,
  ) {
    final out = <ScheduleViolation>[];

    void check(
      Map<String, List<({SchedulableMatch match, Placement at})>> buckets,
      ScheduleViolationKind clashKind,
      String noun,
    ) {
      for (final entry in buckets.entries) {
        final list = [...entry.value]
          ..sort((a, b) => a.at.window.start.compareTo(b.at.window.start));
        for (var i = 1; i < list.length; i++) {
          final prev = list[i - 1].at;
          final cur = list[i].at;
          final keys = [list[i - 1].match.key, list[i].match.key];

          if (prev.window.overlaps(cur.window)) {
            out.add(ScheduleViolation(
              kind: clashKind,
              detail: '${entry.key} is $noun at once',
              matchKeys: keys,
            ));
            continue;
          }
          // Moving between venues costs travel on top of rest, so the promise
          // owed is larger for the second match of a day spent across town.
          final owed = prev.court.venueId == cur.court.venueId
              ? minRest
              : minRest + venueTransition;
          final gap = cur.window.start.difference(prev.window.end);
          if (gap < owed) {
            out.add(ScheduleViolation(
              kind: ScheduleViolationKind.restGapTooShort,
              detail: '${entry.key} gets ${gap.inMinutes} min between matches, '
                  'owed ${owed.inMinutes}'
                  '${prev.court.venueId == cur.court.venueId ? '' : ' including travel'}',
              matchKeys: keys,
            ));
          }
        }
      }
    }

    final byPlayer = <String, List<({SchedulableMatch match, Placement at})>>{};
    final byTeam = <String, List<({SchedulableMatch match, Placement at})>>{};
    for (final p in placed) {
      for (final uid in p.match.playerUids) {
        byPlayer.putIfAbsent(uid, () => []).add(p);
      }
      for (final key in p.match.teamKeys) {
        byTeam.putIfAbsent(key, () => []).add(p);
      }
    }

    check(byPlayer, ScheduleViolationKind.playerDoubleBooked, 'on two courts');
    check(byTeam, ScheduleViolationKind.teamDoubleBooked, 'in two matches');
    return out;
  }

  /// A match placed when its venue is shut, inside a blackout, on a court lent
  /// to a different sport, or beyond the day's agreed maximum.
  ///
  /// Skipped entirely when no calendars are supplied — the uniform-grid
  /// callers make none of these promises, and inventing a violation for them
  /// would block schedules that were always correct.
  static List<ScheduleViolation> _venueAvailability(
    List<({SchedulableMatch match, Placement at})> placed,
    List<CourtCalendar> calendars,
  ) {
    if (calendars.isEmpty) return const [];
    final byKey = {for (final c in calendars) c.court.key: c};

    final out = <ScheduleViolation>[];
    final dayLoad = <String, int>{};

    for (final p in placed) {
      final calendar = byKey[p.at.court.key];
      if (calendar == null) {
        out.add(ScheduleViolation(
          kind: ScheduleViolationKind.outsideVenueAvailability,
          detail: '${p.at.court.label} was never offered to this season',
          matchKeys: [p.match.key],
        ));
        continue;
      }
      if (!calendar.admits(p.at.window)) {
        out.add(ScheduleViolation(
          kind: ScheduleViolationKind.outsideVenueAvailability,
          detail: '${p.at.court.label} is shut at ${p.at.window.start} — '
              'outside its sessions, or blacked out',
          matchKeys: [p.match.key],
        ));
      }
      if (!calendar.allowsSport(p.match.sportId)) {
        out.add(ScheduleViolation(
          kind: ScheduleViolationKind.outsideVenueAvailability,
          detail: '${p.at.court.label} does not take ${p.match.sportId}',
          matchKeys: [p.match.key],
        ));
      }

      final start = p.at.window.start;
      final key = '${p.at.court.key}|${start.year}-${start.month}-${start.day}';
      dayLoad[key] = (dayLoad[key] ?? 0) + 1;
      if (calendar.maxPerDay > 0 && dayLoad[key]! > calendar.maxPerDay) {
        out.add(ScheduleViolation(
          kind: ScheduleViolationKind.dailyLimitExceeded,
          detail: '${p.at.court.label} holds ${dayLoad[key]} matches on '
              '${start.day}/${start.month}, above the ${calendar.maxPerDay} '
              'a day set for it',
          matchKeys: [p.match.key],
        ));
      }
    }
    return out;
  }

  /// A match sent to a ground its event was never given, or to a day or an
  /// hour that event does not run.
  ///
  /// The check is one line of arithmetic and it guards the failure this whole
  /// feature exists to prevent: a cricket match called to a badminton court,
  /// or a school's football tie scheduled for 7pm at a field whose gate is
  /// locked at 5. Both look like a correct timetable on screen.
  static List<ScheduleViolation> _eventAvailability(
    List<({SchedulableMatch match, Placement at})> placed,
  ) {
    final out = <ScheduleViolation>[];
    for (final p in placed) {
      final availability = p.match.availability;
      if (availability.isUnrestricted) continue;

      if (!availability.allowsCourt(p.at.court)) {
        out.add(ScheduleViolation(
          kind: ScheduleViolationKind.outsideEventAvailability,
          detail: '${p.match.compId} was placed at ${p.at.court.label}, '
              'which is not one of its grounds',
          matchKeys: [p.match.key],
        ));
        continue;
      }
      if (!availability.allowsWindow(p.at.window)) {
        out.add(ScheduleViolation(
          kind: ScheduleViolationKind.outsideEventAvailability,
          detail: '${p.match.compId} was placed at ${p.at.window.start}, '
              'outside the days or hours it runs',
          matchKeys: [p.match.key],
        ));
      }
    }
    return out;
  }

  /// A later round of a draw starting before an earlier one has finished.
  ///
  /// Checked per draw and per phase: group matches and knockout matches both
  /// number their rounds from 1, so comparing round numbers across the two
  /// would report a group match as out of order against a final.
  static List<ScheduleViolation> _roundOrder(
    List<({SchedulableMatch match, Placement at})> placed,
  ) {
    // (compId, phase) -> round -> latest finish seen
    final latestByRound = <String, Map<int, DateTime>>{};
    final anyInRound = <String, Map<int, String>>{};

    for (final p in placed) {
      final phase = '${p.match.compId}#${p.match.isGroupStage ? 'g' : 'k'}';
      final rounds = latestByRound.putIfAbsent(phase, () => {});
      final seen = rounds[p.match.round];
      if (seen == null || p.at.window.end.isAfter(seen)) {
        rounds[p.match.round] = p.at.window.end;
      }
      anyInRound.putIfAbsent(phase, () => {})[p.match.round] = p.match.key;
    }

    final out = <ScheduleViolation>[];
    for (final p in placed) {
      final phase = '${p.match.compId}#${p.match.isGroupStage ? 'g' : 'k'}';
      final rounds = latestByRound[phase]!;
      for (final entry in rounds.entries) {
        if (entry.key >= p.match.round) continue;
        // An earlier round of the same draw still running when this starts.
        if (p.at.window.start.isBefore(entry.value)) {
          out.add(ScheduleViolation(
            kind: ScheduleViolationKind.roundOutOfOrder,
            detail: 'round ${p.match.round} of ${p.match.compId} starts '
                'before round ${entry.key} has finished',
            matchKeys: [p.match.key, anyInRound[phase]![entry.key]!],
          ));
        }
      }
    }
    return out;
  }
}
