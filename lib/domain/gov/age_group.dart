import '../../core/models/firestore_codec.dart' show ageOnDate;

/// Khelo India's age bands, in ascending order. [Senior] is the open
/// category — anyone too old for U-21 lands there, not "unclassified".
///
/// Bands are inclusive-upper: a competitor is placed in the youngest band
/// their age still fits, exactly the way junior sport eligibility has always
/// worked (a 14-year-old plays U-14, not U-17, even though U-17 would also
/// technically admit them).
enum AgeGroup {
  u14('U-14', 14),
  u17('U-17', 17),
  u19('U-19', 19),
  u21('U-21', 21),
  senior('Senior', null);

  const AgeGroup(this.label, this.maxAge);

  final String label;

  /// Oldest age this band admits, inclusive. Null for [senior] — there is no
  /// upper bound on the open category.
  final int? maxAge;

  /// Places a birth date into a band **as of [referenceDate]**, never as of
  /// "now".
  ///
  /// This is the rule §12.8 exists to protect: age-category eligibility must
  /// be stable for a whole reporting period. A gov dashboard rebuilt on
  /// every visitor's "today" would reclassify a player mid-season the day
  /// after their birthday, so every caller must supply the same cut-off date
  /// used for the rest of that period's aggregation — computing against
  /// `DateTime.now()` here would make an U-17 participation count silently
  /// drift depending on which day someone happened to run the report.
  ///
  /// No stored age is ever read; this is the only place an age group is
  /// produced, and it is produced fresh from date of birth every time.
  factory AgeGroup.fromDateOfBirth(
    DateTime dateOfBirth, {
    required DateTime referenceDate,
  }) {
    final age = ageOnDate(dateOfBirth, referenceDate);
    for (final band in AgeGroup.values) {
      final max = band.maxAge;
      if (max == null || age <= max) return band;
    }
    return AgeGroup.senior; // unreachable: senior's null max always matches
  }
}
