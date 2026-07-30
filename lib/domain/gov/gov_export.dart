import 'gov_aggregate.dart';

/// One row of the stable export shape §6 Module D requires for SATS
/// (Sports Authority of Telangana State), SGFI (School Games Federation of
/// India), Khelo India/MyBharat and Fit India.
///
/// None of those integrations exist yet, and each will eventually want its
/// own field names and transport (CSV upload, REST push, whatever SATS
/// settles on). This type is deliberately the *one* stable shape all of them
/// are built from — a pure `GovAggregate → GovExportRecord` transform with
/// no HTTP, no per-target quirks. When a real SATS/SGFI/Khelo India schema
/// arrives, it gets its own thin mapper from this record, so the aggregation
/// and suppression logic upstream never has to change or be re-verified per
/// destination — only the last-mile field mapping does.
///
/// Field names below are intentionally generic (not copied from any single
/// government schema, none of which is publicly finalised at the time of
/// writing) but every field is documented with what it means so a future
/// per-target mapper has an unambiguous source.
class GovExportRecord {
  const GovExportRecord({
    required this.schemaVersion,
    required this.period,
    required this.geoLevel,
    required this.area,
    required this.sportId,
    required this.ageGroup,
    required this.gender,
    required this.isPara,
    required this.participants,
    required this.matches,
    required this.events,
    required this.clubs,
    required this.venueUtilizationPct,
    required this.talentIdentified,
    required this.talentTrialed,
    required this.talentSelected,
    required this.suppressed,
  });

  /// Bump whenever a field is added, renamed or reinterpreted below. Every
  /// consumer of an export file should refuse to parse a schema version it
  /// does not recognise rather than guess at a changed shape.
  final int schemaVersion;

  /// Reporting period identifier, e.g. `"2026-Q2"` or `"2026-07"` — whatever
  /// granularity [GovAggregator.aggregate] was called with. Opaque to this
  /// type; it round-trips whatever the caller passed as `period`.
  final String period;

  /// One of `state` | `district` | `mandal` | `village`.
  final String geoLevel;

  /// The area's name at [geoLevel] (e.g. `"Warangal"` for a district-level
  /// row). Never a full path — [geoLevel] plus [area] is the coordinate;
  /// reconstructing the full state→...→area path is the export consumer's
  /// job if it needs one, using its own gazetteer.
  final String area;

  /// PlaySphere's internal sport identifier (e.g. `"kabaddi"`, `"cricket"`).
  final String sportId;

  /// Khelo India age band label (`"U-14"`, `"U-17"`, `"U-19"`, `"U-21"`,
  /// `"Senior"`) — see [AgeGroup.label].
  final String ageGroup;

  /// Wire value of the participants' [Gender] in this cell (see
  /// `Gender.wire` in `lib/core/models/enums.dart`).
  final String gender;

  final bool isPara;

  /// Null means "suppressed for k-anonymity", never "zero". See
  /// [GovAggregate.suppressed] and `GovAggregator.applyKAnonymity`. An export
  /// consumer MUST treat a null count as "not reported this period", not as
  /// a real zero — collapsing the two would make Telangana's participation
  /// numbers look artificially lower than they are in every district small
  /// enough to trigger suppression, which for a state-wide dataset is most
  /// of them at village granularity.
  final int? participants;
  final int? matches;
  final int? events;
  final int? clubs;

  /// 0–100, or null if venue booking data was not available for this
  /// area/sport/period. Unlike the count fields, a null here really does
  /// mean "unknown", not "suppressed" — venue utilization is never subject
  /// to k-anonymity (see [GovAggregate.venueUtilization]).
  final double? venueUtilizationPct;

  final int? talentIdentified;
  final int? talentTrialed;
  final int? talentSelected;

  /// True if any count field above was redacted by k-anonymity. Carried
  /// through explicitly rather than left for the consumer to infer from
  /// nulls, because a null [venueUtilizationPct] does *not* imply
  /// suppression and a consumer guessing from field shape alone would get
  /// that case wrong.
  final bool suppressed;

  factory GovExportRecord.fromAggregate(GovAggregate a,
      {int schemaVersion = 1}) {
    return GovExportRecord(
      schemaVersion: schemaVersion,
      period: a.period,
      geoLevel: a.geoLevel.name,
      area: a.area,
      sportId: a.sportId,
      ageGroup: a.ageGroup.label,
      gender: a.gender.wire,
      isPara: a.isPara,
      participants: a.participants,
      matches: a.matches,
      events: a.events,
      clubs: a.clubs,
      venueUtilizationPct:
          a.venueUtilization == null ? null : a.venueUtilization! * 100,
      talentIdentified: a.talentIdentified,
      talentTrialed: a.talentTrialed,
      talentSelected: a.talentSelected,
      suppressed: a.suppressed,
    );
  }

  /// Plain-map form for JSON/CSV serialisation. Key set and ordering are
  /// part of the documented contract for [schemaVersion] — do not reorder or
  /// rename without bumping it.
  Map<String, Object?> toMap() => {
        'schemaVersion': schemaVersion,
        'period': period,
        'geoLevel': geoLevel,
        'area': area,
        'sportId': sportId,
        'ageGroup': ageGroup,
        'gender': gender,
        'isPara': isPara,
        'participants': participants,
        'matches': matches,
        'events': events,
        'clubs': clubs,
        'venueUtilizationPct': venueUtilizationPct,
        'talentIdentified': talentIdentified,
        'talentTrialed': talentTrialed,
        'talentSelected': talentSelected,
        'suppressed': suppressed,
      };
}

/// Bulk convenience: [GovAggregate] rows → export-ready records, one to one.
///
/// Deliberately does **not** call `applyKAnonymity` itself — suppression is
/// applied once, upstream, to the row list every consumer shares (dashboard
/// and export alike), so there is exactly one place a caller can forget to
/// suppress rather than one per export target. Callers must pass already-
/// suppressed rows; see `GovAggregator.applyKAnonymity`.
List<GovExportRecord> toExportRecords(
  List<GovAggregate> suppressedRows, {
  int schemaVersion = 1,
}) =>
    [
      for (final row in suppressedRows)
        GovExportRecord.fromAggregate(row, schemaVersion: schemaVersion),
    ];
