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

  static Timestamp? ts(DateTime? v) => v == null ? null : Timestamp.fromDate(v);

  /// Strips keys whose value is null so we never write explicit nulls that
  /// would clobber a field another writer just set.
  static Map<String, Object?> prune(Map<String, Object?> data) {
    return Map<String, Object?>.fromEntries(
      data.entries.where((e) => e.value != null),
    );
  }
}

/// Age is computed from date of birth against a fixed reference date, never
/// against "now". Age-category eligibility must be stable for the whole
/// season: a player who is U-17 on the cut-off date stays U-17 even if they
/// have a birthday mid-tournament. Every sports body in the world works this
/// way, and computing against `DateTime.now()` silently disqualifies people
/// halfway through a competition.
int ageOnDate(DateTime dateOfBirth, DateTime referenceDate) {
  var age = referenceDate.year - dateOfBirth.year;
  final hadBirthday = referenceDate.month > dateOfBirth.month ||
      (referenceDate.month == dateOfBirth.month &&
          referenceDate.day >= dateOfBirth.day);
  if (!hadBirthday) age -= 1;
  return age;
}
