import 'package:intl/intl.dart';

/// "Member since Mar 2024 · 2 yrs 6 mos" — how long somebody has belonged to
/// a club, for the roster.
///
/// Both halves on purpose. The date answers "when did they come in", the
/// length answers the question a roster is actually scanned for — who has
/// been here for years and who arrived last week — without the reader doing
/// arithmetic on four hundred dates.
String memberSinceLabel(DateTime since, {DateTime? now}) =>
    'Member since ${DateFormat('MMM y').format(since)} · '
    '${clubTenure(since, now: now)}';

/// The length alone: "Joined today", "5 days", "3 mos", "1 yr", "2 yrs 6 mos".
///
/// Counted in calendar months, not 30-day blocks, so somebody who joined on
/// 31 January is not "1 mo" on 2 March and "0 mos" a day earlier by accident
/// of February.
String clubTenure(DateTime since, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (!since.isBefore(today)) return 'Joined today';

  var months = (today.year - since.year) * 12 + today.month - since.month;
  if (today.day < since.day) months -= 1;

  if (months < 1) {
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(since.year, since.month, since.day))
        .inDays;
    if (days < 1) return 'Joined today';
    return days == 1 ? '1 day' : '$days days';
  }

  final years = months ~/ 12;
  final rest = months % 12;
  String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

  if (years == 0) return plural(rest, 'mo', 'mos');
  if (rest == 0) return plural(years, 'yr', 'yrs');
  return '${plural(years, 'yr', 'yrs')} ${plural(rest, 'mo', 'mos')}';
}
