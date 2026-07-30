import '../../core/models/enums.dart' show Gender;
import '../../core/models/geo.dart';
import 'age_group.dart';
import 'gov_aggregate.dart';
import 'participation_entry.dart';

/// Turns raw participation into the gov-dashboard cube described in §5
/// (`gov_aggregates`) and §6 Module D.
///
/// Pure Dart, no I/O — deliberately mirrors `CareerAggregator` in
/// `lib/domain/career/career_stats.dart`: the same rollup code runs inside a
/// scheduled Cloud Function against production data and inside a unit test
/// against a handful of fixture rows, with identical answers either way.
/// That is what makes a published gov figure defensible — it can always be
/// recomputed from the underlying participation records, never trusted
/// because "the dashboard says so".
class GovAggregator {
  const GovAggregator();

  /// Folds [entries] into one [GovAggregate] per (area at [level], sport,
  /// age group, gender, disability) cell for [period].
  ///
  /// [referenceDate] is the single date every entry's age is evaluated
  /// against — see [AgeGroup.fromDateOfBirth] for why that must be a fixed
  /// date (the period's cut-off), never "now".
  ///
  /// An entry that has no value at [level] (e.g. a user who only ever
  /// recorded a district, asked to roll up to mandal) is **excluded** from
  /// the result rather than bucketed under a fabricated "Unknown" area —
  /// silently inventing a placeholder area would make an aggregate look
  /// complete when it is actually missing data, which is worse for a policy
  /// dashboard than an honestly smaller, correctly-labelled sample.
  ///
  /// [venueUtilizationByAreaSport] is an optional side channel: venue
  /// utilization is a property of venues/time-slots, not of participants, so
  /// it cannot be derived from [entries] the way participant/match/event/club
  /// counts can. Keyed by `(area, sportId)` and applied uniformly across
  /// every age/gender/disability cell in that area+sport, because venue
  /// booking data is not broken down by who used the slot.
  List<GovAggregate> aggregate(
    List<ParticipationEntry> entries, {
    required String period,
    required GeoLevel level,
    required DateTime referenceDate,
    Map<(String area, String sportId), double>? venueUtilizationByAreaSport,
  }) {
    final participants = <GovCubeKey, Set<String>>{};
    final matches = <GovCubeKey, Set<String>>{};
    final events = <GovCubeKey, Set<String>>{};
    final clubs = <GovCubeKey, Set<String>>{};
    final identified = <GovCubeKey, Set<String>>{};
    final trialed = <GovCubeKey, Set<String>>{};
    final selected = <GovCubeKey, Set<String>>{};
    final keysInOrder = <GovCubeKey>[];

    for (final e in entries) {
      final area = e.geo.rollUpTo(level);
      if (area == null) continue; // no data this granular — see doc above

      final key = (
        period: period,
        geoLevel: level,
        area: area,
        sportId: e.sportId,
        ageGroup: AgeGroup.fromDateOfBirth(e.dateOfBirth,
            referenceDate: referenceDate),
        gender: e.gender,
        isPara: e.isPara,
      );

      if (!participants.containsKey(key)) keysInOrder.add(key);
      participants.putIfAbsent(key, () => {}).add(e.uid);
      if (e.matchId != null) matches.putIfAbsent(key, () => {}).add(e.matchId!);
      if (e.eventId != null) events.putIfAbsent(key, () => {}).add(e.eventId!);
      if (e.clubId != null) clubs.putIfAbsent(key, () => {}).add(e.clubId!);

      if (e.talentStage.reached(TalentStage.identified)) {
        identified.putIfAbsent(key, () => {}).add(e.uid);
      }
      if (e.talentStage.reached(TalentStage.trialed)) {
        trialed.putIfAbsent(key, () => {}).add(e.uid);
      }
      if (e.talentStage.reached(TalentStage.selected)) {
        selected.putIfAbsent(key, () => {}).add(e.uid);
      }
    }

    return [
      for (final key in keysInOrder)
        GovAggregate(
          key: key,
          participants: participants[key]!.length,
          matches: matches[key]?.length ?? 0,
          events: events[key]?.length ?? 0,
          clubs: clubs[key]?.length ?? 0,
          venueUtilization:
              venueUtilizationByAreaSport?[(key.area, key.sportId)],
          talentIdentified: identified[key]?.length ?? 0,
          talentTrialed: trialed[key]?.length ?? 0,
          talentSelected: selected[key]?.length ?? 0,
        ),
    ];
  }

  /// Enforces the k-anonymity rule DPDP compliance (§2.7, a MUST) requires:
  /// no published cell may let a reader infer a specific minor's
  /// participation. A cell that says "2 U-14 girls played kabaddi in
  /// Bhupalpally mandal this month" is not a statistic, it is a
  /// near-complete roster — in a village-level cell the two children are
  /// very likely locally identifiable even without names attached.
  ///
  /// Any metric whose true count is strictly between 0 and [threshold]
  /// (default 5, matching common official small-cell-suppression practice)
  /// is redacted to null and the row is marked [GovAggregate.suppressed]. A
  /// count of exactly 0 is left alone — "nobody" carries no privacy risk and
  /// suppressing it would make an empty cell indistinguishable from a
  /// merely-small one, defeating transparency for no safety benefit.
  ///
  /// Each metric is checked **independently**, not just [participants] as a
  /// whole: a district might have 200 total kabaddi participants (safe to
  /// publish) but only 2 of them [GovAggregate.talentSelected] for a state
  /// trial — publishing that "2" would still de-anonymise those two minors
  /// even though the district total is large. Talent-selection is exactly
  /// the sensitive case a naive "suppress the row if participants < 5" rule
  /// would miss.
  ///
  /// [venueUtilization] is exempt — it describes venues, not people, and
  /// carries no individual-identifying information at any magnitude.
  List<GovAggregate> applyKAnonymity(
    List<GovAggregate> rows, {
    int threshold = 5,
  }) {
    bool small(int? v) => v != null && v > 0 && v < threshold;

    // Only counts OF PEOPLE are suppressed.
    //
    // k-anonymity exists to stop a published cell identifying an individual,
    // and matches, events and clubs are not individuals — a fixture is a
    // fixture and a club is an organisation. Suppressing "1 match" protects
    // nobody and guts the dashboard: a mandal that ran one tournament would
    // report no tournaments, which is the opposite of what the participation
    // backbone in §6 Module D is for.
    //
    // The exception is a row whose participant count is itself too small.
    // There the whole cell is unpublishable — leaving the structural counts
    // visible would let a reader infer the group's size from the fact that a
    // single club in a single village fielded a suppressed handful of
    // children.
    final participantsUnsafe = <GovAggregate, bool>{
      for (final row in rows) row: small(row.participants),
    };

    return [
      for (final row in rows)
        if (participantsUnsafe[row] == true)
          // Too small to publish at all.
          row.redactMetrics(
            participants: true,
            matches: true,
            events: true,
            clubs: true,
            talentIdentified: true,
            talentTrialed: true,
            talentSelected: true,
          )
        else if (small(row.talentIdentified) ||
            small(row.talentTrialed) ||
            small(row.talentSelected))
          // The cell as a whole is safe, but a stage of the talent pipeline
          // is not. Those are counts of named minors being put forward for
          // trials, so they are redacted independently of the total.
          row.redactMetrics(
            talentIdentified: small(row.talentIdentified),
            talentTrialed: small(row.talentTrialed),
            talentSelected: small(row.talentSelected),
          )
        else
          row,
    ];
  }

  /// Women's participation as a first-class KPI (§6 Module D calls it out by
  /// name rather than leaving it to be found by filtering gender in a
  /// generic dashboard query) — the rows where [GovAggregate.gender] is
  /// [Gender.female], summed to a single headline count.
  ///
  /// Sums whatever is left *after* suppression, matching how every other
  /// published figure in this module behaves: a caller passes the
  /// already-[applyKAnonymity]'d list, and a suppressed cell (null
  /// participants) contributes 0 to the total rather than throwing — the
  /// headline number silently undercounts by the same small amounts the
  /// per-cell view already declined to publish, which is the correct
  /// trade-off for a public transparency figure.
  int womensParticipation(List<GovAggregate> rows) => rows
      .where((r) => r.gender == Gender.female)
      .fold(0, (sum, r) => sum + (r.participants ?? 0));

  /// Para-sport participation as a first-class KPI (§6 Module D), summed the
  /// same way as [womensParticipation].
  int paraParticipation(List<GovAggregate> rows) => rows
      .where((r) => r.isPara)
      .fold(0, (sum, r) => sum + (r.participants ?? 0));

  /// The talent-pipeline funnel (§6 Module D: identified → trialed →
  /// selected) totalled across [rows], typically already suppressed.
  TalentFunnelTotals talentFunnel(List<GovAggregate> rows) => TalentFunnelTotals(
        identified: rows.fold(0, (s, r) => s + (r.talentIdentified ?? 0)),
        trialed: rows.fold(0, (s, r) => s + (r.talentTrialed ?? 0)),
        selected: rows.fold(0, (s, r) => s + (r.talentSelected ?? 0)),
      );
}

/// Headline funnel counts, cumulative in the same sense as the per-cell
/// fields on [GovAggregate]: [selected] is a subset of [trialed], which is a
/// subset of [identified].
class TalentFunnelTotals {
  const TalentFunnelTotals({
    required this.identified,
    required this.trialed,
    required this.selected,
  });

  final int identified;
  final int trialed;
  final int selected;

  /// trialed / identified, or 0 when nobody has been identified yet — a
  /// conversion rate over an empty pipeline is undefined, not infinite or
  /// crashing.
  double get identifiedToTrialedRate =>
      identified == 0 ? 0 : trialed / identified;

  double get trialedToSelectedRate => trialed == 0 ? 0 : selected / trialed;
}
