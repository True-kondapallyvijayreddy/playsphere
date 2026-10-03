import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';

/// "Court 2 is running half an hour late" — which matches move, and to when.
///
/// ## Why one court and not the whole season
///
/// The season-wide shift (`TournamentRepository.shiftSchedule`) is for rain:
/// everything moves together. A single court overrunning is the everyday
/// case — a five-set badminton final, a cricket innings that went long — and
/// moving the whole season for it pushes back forty matches that were on time
/// and tells hundreds of people something that is not true for them
/// (TC-ADM-024). So this moves [target] and every later match on the SAME
/// court on the SAME day, and nothing else.
///
/// Only matches still to be played move: one under way or finished keeps its
/// time, because that time is what happened.
///
/// Pure. Returns fixture id → new start.
Map<String, DateTime> courtDelayMoves({
  required Fixture target,
  required Iterable<Fixture> fixtures,
  required Duration by,
}) {
  final start = target.scheduledAt;
  if (start == null || by == Duration.zero) return const {};
  final court = courtKeyOf(target);
  if (court == null) return const {};

  return {
    for (final f in fixtures)
      if (_unplayed(f) &&
          f.scheduledAt != null &&
          courtKeyOf(f) == court &&
          _sameDay(f.scheduledAt!, start) &&
          !f.scheduledAt!.isBefore(start))
        f.id: f.scheduledAt!.add(by),
  };
}

/// Which court a match is on, or null when it was never given one. The
/// stored ids where they exist, the names a hand-placed match carries where
/// they do not — the same two shapes the timetable reads.
String? courtKeyOf(Fixture f) {
  final venue = f.venueId ?? f.venue;
  final court = f.courtRefId ?? f.courtId;
  if (venue == null || court == null) return null;
  return '$venue/$court';
}

bool _unplayed(Fixture f) =>
    f.status == FixtureStatus.scheduled && f.lastSeq == 0;

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}
