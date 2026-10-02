import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared conversion helpers between Firestore documents and Dart models.
///
/// Firestore hands back `dynamic` for everything and returns `null` for any
/// field a document happens not to have — including documents written by an
/// older or newer version of the app. Every read therefore goes through a
/// total function with an explicit fallback, so a partially-written document
/// degrades gracefully instead of throwing inside a StreamBuilder where the
/// user would only see a spinner that never resolves.
class Fs {
  const Fs._();

  static String str(Object? v, [String fallback = '']) =>
      v is String ? v : fallback;

  static String? strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

  static int integer(Object? v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  /// For settings where "not set" and "set to zero" are different answers —
  /// a draw with `numGroups: null` derives its group count, one with
  /// `numGroups: 0` is a mistake worth seeing rather than silently treating
  /// as absent.
  static int? intOrNull(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static double decimal(Object? v, [double fallback = 0]) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return fallback;
  }

  static bool boolean(Object? v, [bool fallback = false]) =>
      v is bool ? v : fallback;

  static List<String> strList(Object? v) =>
      v is List ? v.whereType<String>().toList(growable: false) : const [];

  static Map<String, dynamic> map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Firestore stores instants as [Timestamp]. A document read back from the
  /// local cache immediately after a write with [FieldValue.serverTimestamp]
  /// carries `null` here until the server round-trips, so callers must
  /// tolerate a null return rather than assuming a value.
  static DateTime? dateOrNull(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static DateTime date(Object? v, DateTime fallback) =>
      dateOrNull(v) ?? fallback;

  static List<DateTime> dateList(Object? v) {
    if (v is! List) return const [];
    return v.map(dateOrNull).whereType<DateTime>().toList(growable: false);
  }

  static Timestamp? ts(DateTime? v) => v == null ? null : Timestamp.fromDate(v);

  /// Strips keys whose value is null so we never write explicit nulls that
  /// would clobber a field another writer just set.
  static Map<String, Object?> prune(Map<String, Object?> data) {
    return Map<String, Object?>.fromEntries(
      data.entries.where((e) => e.value != null),
    );
  }
}

/// The instant a deadline picked as a DAY actually expires: the end of that
/// day, not its beginning.
///
/// ## Why this exists
///
/// Every deadline in the product is chosen from a date picker, which returns
/// midnight. Midnight is the *start* of the chosen day, so a season whose
/// entries closed "19 Sep" stopped taking entries at 00:00 on the 19th — and
/// on the first morning of the season the home screen said "Active seasons 0"
/// while both seasons were still openly advertising Register buttons. The day
/// before, it had correctly said 2.
///
/// Read-side rather than write-side, deliberately, and for the same reason
/// `Competition.displayStatus` is: it repairs every season already in the
/// database, including the ones running right now, with no migration and no
/// scheduled job. The creation path already stores 23:59:59 (see
/// `SeasonBlueprint.entriesCloseAt`), and a value with a real time on it is
/// passed through untouched — an organizer who says "entries close at 6pm"
/// means 6pm.
DateTime? endOfDeadlineDay(DateTime? deadline) {
  if (deadline == null) return null;
  final atMidnight = deadline.hour == 0 &&
      deadline.minute == 0 &&
      deadline.second == 0 &&
      deadline.millisecond == 0 &&
      deadline.microsecond == 0;
  if (!atMidnight) return deadline;
  return DateTime(
    deadline.year,
    deadline.month,
    deadline.day,
    23,
    59,
    59,
    999,
  );
}

/// Age is computed from date of birth against a fixed reference date, never
/// against "now". Age-category eligibility must be stable for the whole
/// season: a player who is U-17 on the cut-off date stays U-17 even if they
/// have a birthday mid-tournament. Every sports body in the world works this
/// way, and computing against `DateTime.now()` silently disqualifies people
/// halfway through a competition.
///
/// Both dates are read as India Standard Time calendar days before the
/// year/month/day comparison, regardless of the device's own timezone. A
/// birth or cut-off instant stored near midnight would otherwise land on the
/// wrong calendar day for a device (or a UTC-clocked server) not set to IST —
/// this product's whole userbase reads age bounds against the Indian date.
int ageOnDate(DateTime dateOfBirth, DateTime referenceDate) {
  final dob = _istCalendarDay(dateOfBirth);
  final ref = _istCalendarDay(referenceDate);
  var age = ref.year - dob.year;
  final hadBirthday =
      ref.month > dob.month || (ref.month == dob.month && ref.day >= dob.day);
  if (!hadBirthday) age -= 1;
  return age;
}

/// India observes no daylight-saving time, so a constant UTC+5:30 offset is
/// correct year-round without needing a full timezone database.
const _istOffset = Duration(hours: 5, minutes: 30);

DateTime _istCalendarDay(DateTime dt) {
  final ist = dt.toUtc().add(_istOffset);
  return DateTime(ist.year, ist.month, ist.day);
}
