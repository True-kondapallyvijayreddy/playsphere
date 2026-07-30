import '../../core/models/enums.dart' show Gender;
import '../../core/models/geo.dart';
import 'age_group.dart';

/// The cube coordinate for one [GovAggregate] row: everything the Telangana
/// Sports Policy dashboards slice by, per §5's `gov_aggregates` table
/// (`period × state/district/mandal/village × sport × age_group × gender ×
/// disability`).
///
/// A Dart record, not a class — records get structural `==`/`hashCode` for
/// free, which is what lets [GovAggregator.aggregate] use one directly as a
/// `Map` key while folding thousands of [ParticipationEntry] rows without
/// hand-writing equality.
typedef GovCubeKey = ({
  String period,
  GeoLevel geoLevel,
  String area,
  String sportId,
  AgeGroup ageGroup,
  Gender gender,
  bool isPara,
});

/// One cell of the gov-dashboard cube: a single (period, area, sport,
/// age group, gender, disability) combination and its counts.
///
/// Metrics are nullable **on purpose** — a null metric is not "zero", it is
/// "not reported", which is what [GovAggregator.applyKAnonymity] produces
/// for any cell too small to publish safely. Treating null and zero as the
/// same thing anywhere downstream (a dashboard, an export) would defeat the
/// whole point of suppression, so every consumer must render a null metric
/// as "—" or "suppressed", never as 0.
class GovAggregate {
  const GovAggregate({
    required this.key,
    required this.participants,
    required this.matches,
    required this.events,
    required this.clubs,
    this.venueUtilization,
    this.talentIdentified,
    this.talentTrialed,
    this.talentSelected,
    this.suppressed = false,
  });

  final GovCubeKey key;

  String get period => key.period;
  GeoLevel get geoLevel => key.geoLevel;
  String get area => key.area;
  String get sportId => key.sportId;
  AgeGroup get ageGroup => key.ageGroup;
  Gender get gender => key.gender;
  bool get isPara => key.isPara;

  /// Distinct participants in this cell.
  final int? participants;

  /// Distinct matches with at least one participant in this cell.
  final int? matches;

  /// Distinct events with at least one participant in this cell.
  final int? events;

  /// Distinct clubs with at least one participant in this cell.
  final int? clubs;

  /// Fraction of available venue-slots used in [area]/[sportId]/[period],
  /// 0.0–1.0. Not personally identifying (it is a property of venues, not
  /// people), so it is never subject to k-anonymity suppression — see
  /// [GovAggregator.applyKAnonymity].
  final double? venueUtilization;

  /// Talent-pipeline funnel counts (§6 Module D: identified → trialed →
  /// selected), cumulative — [talentSelected] participants are a subset of
  /// [talentTrialed], which are a subset of [talentIdentified].
  final int? talentIdentified;
  final int? talentTrialed;
  final int? talentSelected;

  /// True once [GovAggregator.applyKAnonymity] has redacted this row's
  /// metrics for being below the reporting threshold. The row itself is kept
  /// (area/sport/age/gender stay visible) so a dashboard can still show
  /// "data suppressed" rather than the cell disappearing without
  /// explanation — but every numeric field it redacted is null, not a small
  /// true number.
  final bool suppressed;

  /// Redacts a metric to null (leaving the others untouched) and marks the
  /// row [suppressed]. Called only from the k-anonymity pass in
  /// `gov_aggregator.dart` — never a general-purpose "update this field"
  /// helper, because redaction only ever moves one direction (visible →
  /// hidden), and a normal `copyWith` that let a caller pass `null` to
  /// "leave unchanged" could never be used to redact anything.
  GovAggregate redactMetrics({
    bool participants = false,
    bool matches = false,
    bool events = false,
    bool clubs = false,
    bool talentIdentified = false,
    bool talentTrialed = false,
    bool talentSelected = false,
  }) =>
      GovAggregate(
        key: key,
        participants: participants ? null : this.participants,
        matches: matches ? null : this.matches,
        events: events ? null : this.events,
        clubs: clubs ? null : this.clubs,
        venueUtilization: venueUtilization,
        talentIdentified: talentIdentified ? null : this.talentIdentified,
        talentTrialed: talentTrialed ? null : this.talentTrialed,
        talentSelected: talentSelected ? null : this.talentSelected,
        suppressed: true,
      );
}
