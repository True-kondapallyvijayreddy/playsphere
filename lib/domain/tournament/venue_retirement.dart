import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';

/// Why a venue cannot come off a season yet, or null when it can.
///
/// ## Why removing a venue is refused rather than allowed
///
/// Unticking a ground in the season's venue list used to save at once, even
/// with a match still booked on one of its courts (TC-ADM-040). The match kept
/// pointing at a court the season no longer had: the timetable could not
/// verify it, the scheduler would not protect it, and the players were still
/// told to turn up there. Nothing said so.
///
/// So the venue stays until every unplayed match on it has been moved — which
/// the organizer can do from the timetable — and this names the matches, so
/// they know exactly which ones.
///
/// A match only counts when the venue is gone for its event as a whole: an
/// event that names the ground in its own settings still has it after the
/// season drops it (see `_venuesOf` in `TournamentRepository`), so its matches
/// are not stranded.
///
/// [eventVenueIds] maps each event id to the venues it names itself.
/// [venueNames] is used only for the message.
String? venueRetirementBlock({
  required Set<String> removedVenueIds,
  required Iterable<Fixture> fixtures,
  required Map<String, Set<String>> eventVenueIds,
  required Map<String, String> venueNames,
  int listed = 3,
}) {
  if (removedVenueIds.isEmpty) return null;
  final stranded = [
    for (final f in fixtures)
      if (_unplayed(f) &&
          f.venueId != null &&
          removedVenueIds.contains(f.venueId) &&
          !(eventVenueIds[f.compId]?.contains(f.venueId) ?? false))
        f,
  ]..sort((a, b) {
      final at = a.scheduledAt, bt = b.scheduledAt;
      if (at == null || bt == null) return at == null ? 1 : -1;
      return at.compareTo(bt);
    });
  if (stranded.isEmpty) return null;

  final byVenue = <String, int>{};
  for (final f in stranded) {
    byVenue.update(f.venueId!, (n) => n + 1, ifAbsent: () => 1);
  }
  final where = byVenue.entries
      .map((e) => '${venueNames[e.key] ?? 'That venue'} still has '
          '${e.value} ${e.value == 1 ? 'match' : 'matches'} booked')
      .join('; ');
  final names = stranded.take(listed).map(_describe).join(', ');
  final more =
      stranded.length > listed ? ' and ${stranded.length - listed} more' : '';
  return '$where — $names$more. Move '
      '${stranded.length == 1 ? 'it' : 'them'} to another venue on the '
      'timetable first, then remove the venue.';
}

bool _unplayed(Fixture f) =>
    f.status == FixtureStatus.scheduled || f.status == FixtureStatus.live;

String _describe(Fixture f) {
  final a = f.displayNameA().trim();
  final b = f.displayNameB().trim();
  final sides = (a.isEmpty || b.isEmpty) ? '' : '$a v $b';
  final round = f.roundLabel?.trim() ?? '';
  final label = [
    if (round.isNotEmpty) round,
    if (sides.isNotEmpty) sides,
  ].join(' ');
  return label.isEmpty ? 'match ${f.matchIndex + 1}' : label;
}
