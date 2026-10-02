/// Where one event's own dates go when its season's dates are edited.
///
/// Pure, so the rules in `TournamentRepository.updateSeasonDetails` can be
/// tested without a Firestore. The decision is made on calendar days: the
/// season's dates are days, and "moved by three days" is a question about
/// days.
///
/// ## Time of day travels with the date
///
/// An event's start is not always midnight. A tournament created from the
/// one-page form stores the start the organizer typed ("Sunday, 09:30"), and
/// that time is what goes on the poster. The day is decided on its own, then
/// the event's own clock time is put back onto the new day, so postponing
/// that tournament by a week gives "next Sunday, 09:30" and not midnight.
/// An event whose start was only ever a day keeps midnight, which is
/// correct for it.
class SeasonDateShift {
  const SeasonDateShift._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _plusDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// [day] at the clock time [original] had. Seconds included, so an
  /// unmoved event compares equal to what is stored and is not rewritten.
  static DateTime _atTimeOf(DateTime day, DateTime? original) => original ==
          null
      ? day
      : DateTime(
          day.year,
          day.month,
          day.day,
          original.hour,
          original.minute,
          original.second,
        );

  /// The event's new `(start, end)`, each keeping its own time of day.
  ///
  /// A null end means "until the season's last day" and stays null unless
  /// it has to be set. See the repository method for the reasoning.
  static ({DateTime? start, DateTime? end}) moveEvent({
    required DateTime? eventStart,
    required DateTime? eventEnd,
    required DateTime oldStart,
    required DateTime oldEnd,
    required DateTime newStart,
    required DateTime newEnd,
  }) {
    final os = _day(oldStart), oe = _day(oldEnd);
    final ns = _day(newStart), ne = _day(newEnd);
    final startDelta = ns.difference(os).inDays;
    final endDelta = ne.difference(oe).inDays;
    var start = eventStart == null ? null : _day(eventStart);
    var end = eventEnd == null ? null : _day(eventEnd);

    if (startDelta == endDelta) {
      // Postponed or brought forward as a whole: every window moves with it.
      if (start != null) start = _plusDays(start, startDelta);
      if (end != null) end = _plusDays(end, startDelta);
    } else {
      // The span changed. Following the old first day means following the
      // new one.
      if (start != null && !start.isAfter(os)) start = ns;
    }

    // Anything now outside the season goes back to following it.
    if (start != null && (start.isBefore(ns) || start.isAfter(ne))) start = ns;
    if (end != null && (end.isBefore(ns) || end.isAfter(ne))) end = null;
    if (start != null && end != null && end.isBefore(start)) end = null;
    return (
      start: start == null ? null : _atTimeOf(start, eventStart),
      end: end == null ? null : _atTimeOf(end, eventEnd),
    );
  }
}
