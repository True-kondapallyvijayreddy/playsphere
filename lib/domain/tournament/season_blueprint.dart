import '../../core/models/competition.dart';
import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../draw/match_duration.dart';
import '../scoring/rule_config.dart';
import '../scoring/scoring_registry.dart';
import 'house_roster.dart';
import 'season_name.dart';

/// One category of a season as the organizer finished describing it: a sport,
/// in one arrangement, for one age/gender band, optionally with one kind of
/// ball — and where and when it plays, where that differs from the season.
///
/// Immutable, and deliberately free of Flutter. Both season forms hold their
/// own editable drafts (text controllers, expansion state) and hand this over
/// at the moment they measure or save, so the rules below are written once.
class SeasonCategorySpec {
  const SeasonCategorySpec({
    required this.sportId,
    required this.sideFormat,
    required this.category,
    required this.format,
    this.equipment,
    this.draw = const DrawConfig(),
    this.maxEntrants,
    this.entryFeeRupees = 0,
    this.venueIds = const {},
    this.startDate,
    this.endDate,
    this.dayStartHour,
    this.dayEndHour,
    this.matchMinutes,
  });

  final String sportId;
  final SideFormat sideFormat;
  final CompetitionCategory category;
  final CompetitionFormat format;

  /// The ball or shuttle this category is played with, when the organizer
  /// chose one — "Hard Tennis Ball" and "Red Leather Ball" cricket are
  /// different tournaments with different entrants, not one tournament.
  final String? equipment;

  /// Already normalised for [format] by the form that built it.
  final DrawConfig draw;

  /// Null means no limit.
  final int? maxEntrants;
  final int entryFeeRupees;

  /// Grounds this category is confined to. Empty means every ground the
  /// season has.
  final Set<String> venueIds;

  final DateTime? startDate;
  final DateTime? endDate;
  final int? dayStartHour;
  final int? dayEndHour;

  /// This category's own match length. Null means the season's, or the
  /// sport's ruleset when the season did not set one.
  final int? matchMinutes;

  SportSpec get sport => SportCatalog.byId(sportId);

  /// Two specs describing the same draw — which, created twice, would give a
  /// season two identical events with split entry lists.
  String get identity =>
      '$sportId|${sideFormat.id}|${category.label}|${equipment ?? ''}';

  /// A human label for this category, without the season name.
  String get label {
    final parts = <String>[
      sport.name,
      if (sport.sideFormats.length > 1) '(${sideFormat.name})',
    ];
    final tail = <String>[
      if (!category.isOpen) category.label,
      if (equipment != null && equipment!.trim().isNotEmpty) equipment!.trim(),
    ];
    return tail.isEmpty ? parts.join(' ') : '${parts.join(' ')} — ${tail.join(' · ')}';
  }
}

/// A whole season as typed, before anything is written.
///
/// ## Why one builder for two screens
///
/// `CreateSeasonScreen` and `GuidedSeasonScreen` each carried their own copy
/// of "turn the form into a Tournament and its Competitions", and the copies
/// drifted: one stored the season as open while its events were drafts, one
/// never saved the rest gap, one left the age category out of event names so
/// U-14 and U-17 cricket were both called "Cricket". The screens now describe
/// the season; this decides what is stored, and [problems] decides whether it
/// may be stored at all. What the Review step shows and what Create writes
/// are the same object.
class SeasonBlueprint {
  const SeasonBlueprint({
    required this.orgId,
    required this.name,
    required this.createdBy,
    required this.startDate,
    required this.categories,
    required this.groundIds,
    this.endDate,
    this.entriesCloseOn,
    this.shortName,
    this.organizerName,
    this.venueLabel,
    this.seasonMatchMinutes,
    this.changeoverMinutes = 5,
    this.restGapMinutes = 20,
    this.dayStartHour = 9,
    this.dayEndHour = 19,
    this.externalEntries = false,
    this.feeMode = SeasonFeeMode.wholeSeason,
    this.seasonFeeRupees = 0,
    this.presetHouses = HouseTemplates.schoolColours,
    this.takenNames = const {},
  });

  final String orgId;
  final String name;
  final String createdBy;
  final DateTime? startDate;
  final DateTime? endDate;

  /// The last day entries are taken, inclusive — every district and school
  /// meet publishes one, because the draw needs a settled field and the
  /// organiser needs time to print it. Null means entries stay open until
  /// the organiser closes them. Stored as the end of that day on the season
  /// and on every event, where `Competition.registrationIsOpen` and the
  /// registration transaction already enforce it.
  final DateTime? entriesCloseOn;

  final String? shortName;
  final String? organizerName;

  /// The free-text place shown on each event ("School grounds"). Scheduling
  /// never reads it — [groundIds] is what matches are placed on.
  final String? venueLabel;

  final List<String> groundIds;
  final List<SeasonCategorySpec> categories;

  /// The organizer's season-wide match length. Null means each sport takes
  /// its own from its ruleset.
  final int? seasonMatchMinutes;
  final int changeoverMinutes;
  final int restGapMinutes;
  final int dayStartHour;
  final int dayEndHour;

  /// Other clubs may enter, and every entry waits for approval.
  final bool externalEntries;

  final SeasonFeeMode feeMode;
  final int seasonFeeRupees;

  /// What an internal season's team events are entered by.
  final List<String> presetHouses;

  /// [SeasonName.key]s of the names the club's other live seasons hold, so
  /// [problems] can refuse a duplicate before anything is written.
  final Set<String> takenNames;

  /// Firestore commits at most 500 writes atomically. A season is written in
  /// one commit so it can never exist half-made; this leaves room for the
  /// season document, its grounds, their plans and the officiating panel.
  static const int maxCategories = 300;

  /// The earliest a season may start, given what day it is: tomorrow.
  static DateTime earliestStart(DateTime now) =>
      DateTime(now.year, now.month, now.day + 1);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The last moment of the entries-close day.
  DateTime? get entriesCloseAt => entriesCloseOn == null
      ? null
      : DateTime(entriesCloseOn!.year, entriesCloseOn!.month,
          entriesCloseOn!.day, 23, 59, 59);

  /// The name as it is stored — see [SeasonName.normalize].
  String get trimmedName => SeasonName.normalize(name);

  DateTime? get _start => startDate == null ? null : _day(startDate!);

  /// The last day, which is the first day for a one-day season.
  DateTime? get _end {
    final start = _start;
    if (start == null) return null;
    return endDate == null ? start : _day(endDate!);
  }

  /// Minutes one match of [spec] takes: its own, then the season's, then the
  /// sport's ruleset for the arrangement actually chosen — six-a-side
  /// tennis-ball cricket is not a T20.
  int minutesFor(SeasonCategorySpec spec) =>
      spec.matchMinutes ??
      seasonMatchMinutes ??
      MatchDuration.estimate(
        sportId: spec.sportId,
        rules: spec.sideFormat.configOverrides.isEmpty
            ? null
            : RulePresets.resolve(
                sportId: spec.sportId,
                overrides: spec.sideFormat.configOverrides,
              ).toMap(),
      );

  /// Everything that stops this season from being created, in the order an
  /// organizer should fix them. Empty means it may be saved.
  ///
  /// [now] is injected so the "at least tomorrow" rule is testable.
  List<String> problems({DateTime? now}) {
    final out = <String>[];
    final today = now ?? DateTime.now();

    final nameProblem = SeasonName.problem(name, taken: takenNames);
    if (nameProblem != null) out.add(nameProblem);
    if (categories.isEmpty) {
      out.add('Add at least one sport category.');
    }
    if (categories.length > maxCategories) {
      out.add('A season can be created with at most $maxCategories '
          'categories at once. Create it with fewer and add the rest from the '
          'season page.');
    }

    final start = _start;
    final end = _end;
    if (start == null) {
      out.add('Pick the date the season starts.');
    } else if (start.isBefore(earliestStart(today))) {
      out.add('The season must start tomorrow or later, so people have '
          'time to enter.');
    }
    if (start != null && endDate != null && _day(endDate!).isBefore(start)) {
      out.add('The season cannot end before it starts.');
    }
    final closes = entriesCloseOn == null ? null : _day(entriesCloseOn!);
    if (closes != null) {
      if (closes.isBefore(_day(today))) {
        out.add('The last day for entries has already passed.');
      } else if (start != null && closes.isAfter(start)) {
        out.add('Entries must close on or before the day the season starts.');
      }
    }
    if (groundIds.isEmpty) {
      out.add('Pick at least one ground. Matches are scheduled onto its '
          'courts.');
    }
    if (dayStartHour >= dayEndHour) {
      out.add('The season’s daily hours must end after they start.');
    }

    final seen = <String, String>{};
    final grounds = groundIds.toSet();
    for (final spec in categories) {
      final label = spec.label;
      final twin = seen[spec.identity];
      if (twin != null) {
        out.add('$label is in the season twice. Remove one, or change its '
            'category or ball.');
      } else {
        seen[spec.identity] = label;
      }

      if (spec.maxEntrants != null && spec.maxEntrants! < 2) {
        out.add('$label needs room for at least 2 entries, or no limit.');
      }
      if (spec.venueIds.isNotEmpty && !grounds.containsAll(spec.venueIds)) {
        out.add('$label is pinned to a ground this season no longer uses. '
            'Pick its grounds again.');
      }

      final ownStart = spec.startDate == null ? null : _day(spec.startDate!);
      final ownEnd = spec.endDate == null ? null : _day(spec.endDate!);
      if (start != null && end != null) {
        if (ownStart != null && (ownStart.isBefore(start) || ownStart.isAfter(end))) {
          out.add('$label starts outside the season’s dates.');
        }
        if (ownEnd != null && (ownEnd.isBefore(start) || ownEnd.isAfter(end))) {
          out.add('$label ends outside the season’s dates.');
        }
      }
      if (ownStart != null && ownEnd != null && ownEnd.isBefore(ownStart)) {
        out.add('$label ends before it starts.');
      }

      final from = spec.dayStartHour ?? dayStartHour;
      final to = spec.dayEndHour ?? dayEndHour;
      if (from >= to) {
        out.add('$label’s daily hours must end after they start.');
      }
    }
    return out;
  }

  /// The season document, published: entries are open from the moment it is
  /// created.
  ///
  /// It used to be a draft that waited on an "Open entries" press, and that
  /// second step was where seasons stalled — organizers shared the link to a
  /// season nobody could enter. [problems] is the review; once it passes, the
  /// season is live. The events are written open in the same commit
  /// (`Competition.toCreate(openForEntries: true)`), so the header and the
  /// draws beneath it can never disagree about whether entries are taken.
  Tournament tournament() {
    final start = _start!;
    final timetabled = [
      for (final c in categories)
        if (!c.sport.isPerformance) minutesFor(c),
    ];
    return Tournament(
      id: '',
      orgId: orgId,
      name: trimmedName,
      shortName: _blankToNull(shortName),
      organizerName: _blankToNull(organizerName),
      status: TournamentStatus.entriesOpen,
      startDate: start,
      endDate: _end,
      entryDeadline: entriesCloseAt,
      venueIds: List.unmodifiable(groundIds),
      eventCount: categories.length,
      feeMode: feeMode,
      // Zero under per-sport pricing, always: a season fee typed before the
      // mode was switched must not be quoted beside a different event fee.
      entryFeeRupees:
          feeMode == SeasonFeeMode.wholeSeason ? _floor0(seasonFeeRupees) : 0,
      // The court grid is laid at this spacing. The shortest match anybody
      // plays is the right grain: a coarser grid strands the badminton
      // between cricket-length slots, and a longer match still occupies as
      // many slots as it needs.
      matchMinutesDefault: seasonMatchMinutes ??
          (timetabled.isEmpty
              ? 30
              : timetabled.reduce((a, b) => a < b ? a : b)),
      changeoverMinutes: changeoverMinutes,
      restGapMinutes: restGapMinutes,
      createdBy: createdBy,
    );
  }

  /// One event per category, each pointing at [seasonId].
  List<Competition> events(String seasonId) {
    final start = _start;
    final grounds = groundIds.toSet();
    final label = _blankToNull(venueLabel);

    return [
      for (final spec in categories)
        _event(
          spec: spec,
          seasonId: seasonId,
          start: start,
          grounds: grounds,
          venueLabel: label,
        ),
    ];
  }

  Competition _event({
    required SeasonCategorySpec spec,
    required String seasonId,
    required DateTime? start,
    required Set<String> grounds,
    required String? venueLabel,
  }) {
    final sport = spec.sport;
    final individual = sport.defaultEntrantType == EntrantType.individual;
    final pinned = spec.venueIds.where(grounds.contains).toList();
    final houses = presetHouses
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toList();
    final equipment = _blankToNull(spec.equipment);

    return Competition(
      id: '',
      orgId: orgId,
      tournamentId: seasonId,
      name: '$trimmedName — ${spec.label}',
      sportId: sport.id,
      sportName: sport.name,
      archetype: sport.archetype,
      entrantType: sport.defaultEntrantType,
      // How the field is assembled. A team sport inside one school is entered
      // house by house; opened to other clubs it is entered as whole teams.
      teamEntryMode: individual
          ? TeamEntryMode.individual
          : (externalEntries
              ? TeamEntryMode.preformedTeam
              : TeamEntryMode.houseBatch),
      presetHouses: individual || externalEntries
          ? const []
          : (houses.isEmpty ? HouseTemplates.schoolColours : houses),
      format: spec.format,
      status: CompetitionStatus.registrationOpen,
      // Ages measured on the season's first day, whatever date was on screen
      // when the chip was tapped.
      category:
          start == null ? spec.category : spec.category.withAgeCutOff(start),
      scoringPluginKey: sport.pluginKey,
      scoringConfig: spec.sideFormat.configOverrides,
      drawConfig: spec.draw,
      scheduleConfig: ScheduleConfig(
        venueIds: pinned.isEmpty ? List.of(groundIds) : pinned,
        matchMinutes: minutesFor(spec),
        changeoverMinutes: changeoverMinutes,
        restGapMinutes: restGapMinutes,
        dayStartHour: spec.dayStartHour ?? dayStartHour,
        dayEndHour: spec.dayEndHour ?? dayEndHour,
      ),
      venue: venueLabel,
      startDate: spec.startDate == null ? start : _day(spec.startDate!),
      // Null while the category runs to the season's last day.
      endDate: spec.endDate == null ? null : _day(spec.endDate!),
      registrationClosesAt: entriesCloseAt,
      // Shown to entrants before they register — the one place the product
      // already says "leather ball" to them.
      rulesNote: equipment == null ? null : 'Played with: $equipment',
      entryFeeRupees:
          feeMode == SeasonFeeMode.perEvent ? _floor0(spec.entryFeeRupees) : 0,
      maxEntrants: spec.maxEntrants,
      participationModel: externalEntries
          ? ParticipationModel.approval
          : ParticipationModel.open,
      waitlistEnabled: true,
      openToNonMembers: externalEntries,
      createdBy: createdBy,
    );
  }

  static int _floor0(int n) => n < 0 ? 0 : n;

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
