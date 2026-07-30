import '../../core/models/enums.dart' show Gender;
import '../../core/models/geo.dart';

/// How far one person has progressed through the talent pipeline the gov
/// dashboards track (§6 Module D: "identified → trialed → selected").
///
/// Deliberately a single ordered stage rather than three independent booleans
/// — a selected trialist is by definition also identified and trialed, and
/// modelling that as three separate flags would let upstream data produce a
/// nonsensical state (selected but never trialed) that the funnel math would
/// then have to silently paper over.
enum TalentStage {
  none,
  identified,
  trialed,
  selected;

  bool reached(TalentStage stage) => index >= stage.index;
}

/// One person's participation in one sport, for one reporting period — the
/// raw input the gov aggregator folds into [GovAggregate] rows.
///
/// This is deliberately *not* a Firestore model. §5's `gov_aggregates` table
/// is a rollup computed from other tables (memberships, matches, events,
/// talent-pipeline records), and the whole point of keeping the aggregator
/// pure (see `gov_aggregator.dart`) is that it never reaches into Firestore
/// itself — a caller (Cloud Function, batch job, or a test) assembles this
/// list from whatever sources it has and hands it in. That is what makes the
/// rollup logic testable without a Firestore emulator and reusable for a
/// one-off SATS export as easily as for a live dashboard.
class ParticipationEntry {
  const ParticipationEntry({
    required this.uid,
    required this.dateOfBirth,
    required this.gender,
    required this.geo,
    required this.sportId,
    this.isPara = false,
    this.clubId,
    this.matchId,
    this.eventId,
    this.talentStage = TalentStage.none,
  });

  /// Never surfaced past aggregation — see the k-anonymity suppression in
  /// `gov_aggregator.dart`, which exists precisely so this identity never
  /// reaches an exported cell.
  final String uid;

  final DateTime dateOfBirth;
  final Gender gender;
  final GeoLocation geo;
  final String sportId;

  /// Para-sport participation, a first-class KPI per §6 Module D (called out
  /// explicitly alongside women's participation) rather than something a
  /// consumer has to infer from a free-text disability field.
  final bool isPara;

  final String? clubId;

  /// Non-null when this entry represents having played in a specific match —
  /// lets the aggregator count *distinct* matches per cell instead of one
  /// match being counted once per participant.
  final String? matchId;

  /// Non-null when this entry represents attending a specific event, for the
  /// same distinct-count reason as [matchId].
  final String? eventId;

  final TalentStage talentStage;
}
