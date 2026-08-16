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
  restGapTooShort,
  roundOutOfOrder,
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
  }) {
    final byKey = {for (final m in matches) m.key: m};
    final placed = <({SchedulableMatch match, Placement at})>[
      for (final entry in schedule.placements.entries)
        if (byKey[entry.key] != null)
          (match: byKey[entry.key]!, at: entry.value),
    ];

    return [
      ..._courtClashes(placed),
      ..._playerClashes(placed, minRestBetweenMatches),
      ..._roundOrder(placed),
    ];
  }

  /// True when the schedule keeps every promise.
  static bool holds({
    required List<SchedulableMatch> matches,
    required TournamentSchedule schedule,
    required Duration minRestBetweenMatches,
  }) =>
      verify(
        matches: matches,
        schedule: schedule,
        minRestBetweenMatches: minRestBetweenMatches,
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

  /// One person in two places, or given less rest than promised — checked
  /// across every event, which is the only level at which either is visible.
  static List<ScheduleViolation> _playerClashes(
    List<({SchedulableMatch match, Placement at})> placed,
    Duration minRest,
  ) {
    final byPlayer = <String, List<({SchedulableMatch match, Placement at})>>{};
    for (final p in placed) {
      for (final uid in p.match.playerUids) {
        byPlayer.putIfAbsent(uid, () => []).add(p);
      }
    }

    final out = <ScheduleViolation>[];
    for (final entry in byPlayer.entries) {
      final list = [...entry.value]
        ..sort((a, b) => a.at.window.start.compareTo(b.at.window.start));
      for (var i = 1; i < list.length; i++) {
        final prev = list[i - 1].at.window;
        final cur = list[i].at.window;
        final keys = [list[i - 1].match.key, list[i].match.key];

        if (prev.overlaps(cur)) {
          out.add(ScheduleViolation(
            kind: ScheduleViolationKind.playerDoubleBooked,
            detail: '${entry.key} is on two courts at once',
            matchKeys: keys,
          ));
          continue;
        }
        final gap = cur.start.difference(prev.end);
        if (gap < minRest) {
          out.add(ScheduleViolation(
            kind: ScheduleViolationKind.restGapTooShort,
            detail: '${entry.key} gets ${gap.inMinutes} min rest, '
                'promised ${minRest.inMinutes}',
            matchKeys: keys,
          ));
        }
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
