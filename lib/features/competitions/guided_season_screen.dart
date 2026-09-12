import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/competition.dart';
import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../../core/models/venue.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/draw/draft_season_plan.dart';
import '../../domain/draw/match_duration.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart' show showError;
import '../../shared/club_context_banner.dart';
import '../../shared/offline_fee_notice.dart';
import '../../shared/season_branding_field.dart';
import '../../shared/ui_kit.dart';
import '../../shared/wizard.dart';
import 'widgets/daily_hours_field.dart';
import 'widgets/bulk_category_selector_sheet.dart';
import 'widgets/season_officials_field.dart';
import 'widgets/season_plan_field.dart';
import 'widgets/group_stage_fields.dart';
import '../../domain/tournament/house_roster.dart';
import 'widgets/house_list_editor.dart';

/// One sport category in a season, in a specific arrangement and age/gender band.
class _SeasonSport {
  _SeasonSport({
    required this.sportId,
    SideFormat? sideFormat,
    CompetitionCategory? category,
    CompetitionFormat? format,
  })  : sideFormat = sideFormat ?? SportCatalog.byId(sportId).defaultSideFormat,
        category = category ?? CompetitionCategory.presets().first,
        format =
            format ?? SportCatalog.byId(sportId).defaultCompetitionFormat;

  final String sportId;
  SideFormat sideFormat;
  CompetitionCategory category;
  CompetitionFormat format;
  int maxEntrants = 16;

  // --- Where and when THIS sport plays -------------------------------------
  //
  // Every field below is an override of the season's own answer, and null or
  // empty means "whatever the season said". That is deliberate: the common
  // season is one ground and one set of hours, and an organizer who has not
  // asked for anything different must not have to fill six sports' worth of
  // identical forms to get it.
  //
  // The reason they exist at all is that the *other* common season is a
  // school sports week: badminton in the indoor hall from four to seven,
  // cricket on the main field all day Saturday, football on the far pitch on
  // Sunday. One ground list and one day window cannot describe that, and
  // scheduling it as though they could is how a cricket match gets called to
  // a badminton court.

  /// Grounds this sport is played at. Empty means every ground the season
  /// picked. Always a subset of the season's list — the picker only offers
  /// those, so a sport can never point at a ground the season does not hold.
  Set<String> venueIds = {};

  /// The days this sport runs, inside the season's own span. Null on either
  /// end means the season's own date.
  DateTime? startDate;
  DateTime? endDate;

  /// The hours this sport's ground is available. Null means the season's.
  int? dayStartHour;
  int? dayEndHour;

  /// How long one match of this sport takes. Null means the season's default
  /// — and this is the field that most often should not be: a T20 innings and
  /// a badminton singles are not both 30 minutes, and a season that pretends
  /// they are produces a timetable that drifts by lunchtime.
  int? matchMinutes;

  /// Whether anything at all has been said about this sport specifically.
  /// Drives the summary line on the card, so an organizer can see at a glance
  /// which sports they have customised without opening each one.
  bool get hasScheduleOverride =>
      venueIds.isNotEmpty ||
      startDate != null ||
      endDate != null ||
      dayStartHour != null ||
      dayEndHour != null ||
      matchMinutes != null;

  /// This event's entry fee in whole rupees. Zero is free, and is the
  /// default because most of them are.
  ///
  /// Held as an int rather than a controller for the same reason
  /// [maxEntrants] is: a `_SeasonSport` is added and removed freely from a
  /// plain list with no lifecycle hook to dispose a controller in, and a
  /// leaked controller per removed category is a worse trade than parsing
  /// the field on change.
  int entryFeeRupees = 0;

  /// How this category's field is split up — groups, how many, and how many
  /// of each go through.
  ///
  /// Set here rather than at "Make the draw", because a season is drawn by
  /// `setUpWholeSeason` in one pass over every event and never opens that
  /// sheet at all. A category created without this took the empty default —
  /// no groups — whatever its format said.
  DrawConfig draw = const DrawConfig();

  /// The draw config as it will be stored, clamped to what this format and
  /// this expected field size allow.
  ///
  /// [maxEntrants] is a plan, not a roll: `GroupBounds` re-clamps against the
  /// real field when the draw is finally generated.
  DrawConfig get drawToSubmit => GroupStageFields.normalize(
        format: format,
        entrantCount: maxEntrants,
        config: draw,
      );

  SportSpec get sport => SportCatalog.byId(sportId);

  String get displayName {
    final hasArrangement = sport.sideFormats.length > 1;
    final catLabel = category.isOpen ? '' : ' · ${category.label}';
    if (hasArrangement) {
      return '${sport.name} (${sideFormat.name})$catLabel';
    }
    return '${sport.name}$catLabel';
  }
}

/// A multi-sport season, created one step at a time.
///
/// The guided counterpart to [CreateSeasonScreen], built on the same shell as
/// the tournament flow and writing through the same repositories, so a season
/// created either way is indistinguishable afterwards.
///
/// ## Where this stops short of the sample design
///
/// The reference flow has eight steps, two of which the data model cannot
/// honestly support yet:
///
/// - **Venues & Locations** offers photographs per venue and assigns each
///   venue to particular sports. Venues themselves are here — the season
///   picks any number of them, and the scheduler spreads matches across every
///   court they hold — but a [Competition] carries a single `venue` string, so
///   pinning one *sport* to one *ground* would be a schema change, not a
///   screen. The photographs are part of the same gap.
/// - **Logo and banner upload** needs Firebase Storage, which is not
///   configured on this project. The controls are present and say so rather
///   than failing on tap.
class GuidedSeasonScreen extends ConsumerStatefulWidget {
  const GuidedSeasonScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<GuidedSeasonScreen> createState() => _GuidedSeasonScreenState();
}

class _GuidedSeasonScreenState extends ConsumerState<GuidedSeasonScreen> {
  final _name = TextEditingController();
  final _shortName = TextEditingController();
  final _organizer = TextEditingController();
  final _venue = TextEditingController();

  /// The season's crest and header art, staged until the season has an id —
  /// see [SeasonBranding]. The same block the one-page form uses, so a season
  /// built through the wizard and a season built on `CreateSeasonScreen` come
  /// out looking the same.
  final _branding = SeasonBranding();

  final List<_SeasonSport> _sports = [];

  /// The grounds the season runs across and the hours it has each of them
  /// for — the pair [SeasonPlanField] needs to answer "does this fit?".
  ///
  /// This is what makes the schedule generatable. `generateSchedule` resolves
  /// courts from these documents and refuses outright when there are none, so
  /// a season created without them produced a tournament whose only
  /// scheduling button failed — the organizer had to find a different screen
  /// to fix something they were never told was missing.
  final _grounds = SeasonGroundsDraft();

  /// The officiating panel, staged like the grounds — see
  /// [SeasonOfficialsDraft] for why it is asked for here.
  final _officials = SeasonOfficialsDraft();

  Set<String> get _venueIds => {..._grounds.venueIds};

  DateTime? _startDate;
  DateTime? _endDate;

  /// The season-wide match length, and whether the organizer set it.
  ///
  /// Untouched, each category takes its length from its own ruleset — see
  /// [MatchDuration] and the identical note in `create_season_screen.dart`.
  int _matchMinutes = 30;
  bool _matchMinutesSet = false;

  int _changeoverMinutes = 5;
  int _restGapMinutes = 20;
  /// When play may start and when it must stop, per day.
  ///
  /// Editable, which they were not: the two fields existed, were written into
  /// every event's `ScheduleConfig`, and were shown on this screen as plain
  /// text with no way to change them. Every season in the product was
  /// therefore scheduled 09:00–19:00 whatever its organizer actually had the
  /// ground for, and a school with the field until 4pm got a timetable that
  /// ran three hours past the gate being locked.
  int _dayStartHour = 9;
  int _dayEndHour = 19;

  bool _externalEntries = false;

  /// The houses/departments/sections an internal season's team events split
  /// into. Only reaches the created competitions when the season stays inside
  /// the club — an open season takes pre-formed teams from other clubs, and
  /// house names would mean nothing to them. Seeded from the school-colours
  /// template because a list has to open with something; see [HouseRoster]
  /// for why four colours are no longer the only option.
  List<String> _presetHouses = [...HouseTemplates.schoolColours];
  bool _liveScoring = true;
  bool _leaderboard = true;
  bool _playerStats = true;
  bool _resultsApproval = false;
  bool _allowProtests = false;

  /// One fee for the season, or one per sport — see [SeasonFeeMode]. Asked
  /// before any amount, because it decides which fields exist.
  SeasonFeeMode _feeMode = SeasonFeeMode.wholeSeason;

  /// The whole-season fee. Only read under [SeasonFeeMode.wholeSeason].
  final _seasonFee = TextEditingController();

  /// The declared whole-season fee in whole rupees, floored at zero.
  int get _seasonFeeRupees {
    final n = int.tryParse(_seasonFee.text.trim());
    return (n == null || n < 0) ? 0 : n;
  }

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    _organizer.dispose();
    _venue.dispose();
    _seasonFee.dispose();
    _grounds.dispose();
    _officials.dispose();
    super.dispose();
  }

  /// The earliest a season may start: tomorrow.
  ///
  /// Same rule `CreateSeasonScreen` enforces, and for the same reason — a
  /// season starting today gives entrants no notice, and a start date in the
  /// past is a mistake rather than a smaller season.
  static DateTime get _earliestStart {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day + 1);
  }

  /// Entries from outside the club must be approved, never auto-confirmed.
  ///
  /// The point of opening a season to other clubs is that the host decides
  /// who is in; an open model would let anyone with the link confirm
  /// themselves a place in a school's meet.
  ParticipationModel get _participation => _externalEntries
      ? ParticipationModel.approval
      : ParticipationModel.open;

  Future<void> _addCategoriesForSport({String? sportId}) async {
    final drafts = await showModalBottomSheet<List<CategoryDraftItem>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BulkCategorySelectorSheet(
        initialSportId: sportId,
        cutOff: _startDate,
      ),
    );
    if (drafts == null || drafts.isEmpty) return;

    int addedCount = 0;
    for (final draft in drafts) {
      if (_sports.any((s) =>
          s.sportId == draft.sportId &&
          s.sideFormat.id == draft.sideFormat.id &&
          s.category.label == draft.category.label)) {
        continue;
      }
      _sports.add(
        _SeasonSport(
          sportId: draft.sportId,
          sideFormat: draft.sideFormat,
          category: draft.category,
          format: draft.format,
        ),
      );
      addedCount++;
    }

    if (mounted) {
      setState(() {});
      if (addedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $addedCount categories to season!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    final uid = ref.read(currentUidProvider);
    final start = _startDate;
    if (uid == null || start == null || _sports.isEmpty) return;

    setState(() => _busy = true);
    try {
      final tournaments = ref.read(tournamentRepositoryProvider);
      final competitions = ref.read(competitionRepositoryProvider);
      final end = _endDate ?? start;

      // Grounds before the season, because the season document carries their
      // ids — and any sport pinned to a ground added on this form is
      // re-pointed at the real id, or its draw would be confined to a ground
      // key nothing has. Same order and same reason as
      // `create_season_screen.dart`.
      final remap = await _grounds.ensureVenues(
        repo: tournaments,
        orgId: widget.orgId,
      );
      if (remap.isNotEmpty) {
        for (final sport in _sports) {
          final moved = {for (final id in sport.venueIds) remap[id] ?? id};
          sport.venueIds
            ..clear()
            ..addAll(moved);
        }
      }
      final venueIds = _grounds.venueIds;

      // The container first: every event below carries its id, and an event
      // pointing at a season that does not exist yet is a dangling reference
      // for however long the writes take.
      final seasonId = await tournaments.createTournament(
        Tournament(
          id: '',
          orgId: widget.orgId,
          name: _name.text.trim(),
          status: TournamentStatus.draft,
          startDate: start,
          endDate: end,
          venueIds: venueIds,
          eventCount: _sports.length,
          matchMinutesDefault: _matchMinutes,
          changeoverMinutes: _changeoverMinutes,
          restGapMinutes: _restGapMinutes,
          feeMode: _feeMode,
          // Zero under per-sport pricing — see the same guard in
          // `create_season_screen.dart` for why a stale season fee must not
          // survive a mode switch.
          entryFeeRupees:
              _feeMode == SeasonFeeMode.wholeSeason ? _seasonFeeRupees : 0,
          createdBy: uid,
        ),
      );

      for (final entry in _sports) {
        final sport = entry.sport;
        final showsArrangement = sport.sideFormats.length > 1;
        final catSuffix =
            entry.category.isOpen ? '' : ' — ${entry.category.label}';
        final compName = showsArrangement
            ? '${_name.text.trim()} — ${sport.name} (${entry.sideFormat.name})$catSuffix'
            : '${_name.text.trim()} — ${sport.name}$catSuffix';

        await competitions.createCompetition(
          Competition(
            id: '',
            orgId: widget.orgId,
            tournamentId: seasonId,
            name: compName,
            sportId: sport.id,
            sportName: sport.name,
            archetype: sport.archetype,
            entrantType: sport.defaultEntrantType,
            format: entry.format,
            status: CompetitionStatus.registrationOpen,
            category: entry.category,
            scoringPluginKey: sport.pluginKey,
            scoringConfig: entry.sideFormat.configOverrides,
            drawConfig: entry.drawToSubmit,
            // The season's answers, with this sport's own where it gave any
            // — see `_SeasonSport` for why the override is per sport and why
            // it is stored resolved rather than as "same as the season".
            // `generateSchedule` reads exactly these fields back, so what an
            // organizer set on this card is what the timetable obeys.
            scheduleConfig: ScheduleConfig(
              venueIds: entry.venueIds.isEmpty
                  ? venueIds
                  : entry.venueIds.toList(),
              // The sport's own length unless it was overridden — the number
              // the plan on the Schedule step was computed from, so the
              // timetable this season generates is the one it promised.
              matchMinutes: _minutesFor(entry),
              changeoverMinutes: _changeoverMinutes,
              restGapMinutes: _restGapMinutes,
              dayStartHour: entry.dayStartHour ?? _dayStartHour,
              dayEndHour: entry.dayEndHour ?? _dayEndHour,
            ),
            teamEntryMode: sport.defaultEntrantType == EntrantType.individual
                ? TeamEntryMode.individual
                : (_externalEntries ? TeamEntryMode.preformedTeam : TeamEntryMode.houseBatch),
            presetHouses: _externalEntries ? const [] : _presetHouses,
            venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
            // The sport's own days where it has them. Written onto the event
            // rather than only into the schedule config because this is the
            // date the event page already shows: an event that reads
            // "12 September" and is then scheduled on the 15th is wrong
            // whichever of the two the organizer believes.
            startDate: entry.startDate ?? start,
            // Left null when the sport runs the whole season, which is what
            // every event carried before this and what the season page
            // already says on their behalf. Set only when this sport stops
            // earlier than the season does.
            endDate: entry.endDate,
            entryFeeRupees: _feeMode == SeasonFeeMode.perEvent
                ? entry.entryFeeRupees
                : 0,
            maxEntrants: entry.maxEntrants,
            participationModel: _participation,
            waitlistEnabled: true,
            openToNonMembers: _externalEntries,
            createdBy: uid,
          ),
        );
      }

      // The events above were created already attached, which is the one path
      // that bypasses `addEvent` and its increment. Without this the season
      // reports no events, and the rule refusing to delete a tournament with
      // events in it stops protecting the ones it has.
      tournaments.noteEventsCreated(
        orgId: widget.orgId,
        tournamentId: seasonId,
        count: _sports.length,
      );

      // Everything that needs the season's id and may fail without taking
      // the season with it: the per-ground hours, the officiating panel, the
      // artwork — see [SeasonBranding.uploadTo].
      await _grounds.savePlans(
        repo: tournaments,
        orgId: widget.orgId,
        tournamentId: seasonId,
      );

      final panelProblem = await _officials.commit(
        repo: tournaments,
        orgId: widget.orgId,
        tournamentId: seasonId,
        addedByUid: uid,
      );

      final brandingProblem = await _branding.uploadTo(
        repo: tournaments,
        orgId: widget.orgId,
        tournamentId: seasonId,
        uid: uid,
      );

      if (!mounted) return;
      context.pushReplacement(Routes.tournament(widget.orgId, seasonId));
      final problem = panelProblem ?? brandingProblem;
      if (problem != null) showError(context, problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WizardScaffold(
      title: 'Create Season',
      submitLabel: 'Publish Season',
      submitting: _busy,
      onSubmit: _submit,
      steps: [
        WizardStep(
          title: 'Season Details',
          canAdvance: () => _name.text.trim().isNotEmpty,
          builder: _detailsStep,
        ),
        WizardStep(
          title: 'Select Sports',
          subtitle: 'Choose the sports and categories this season runs',
          canAdvance: () => _sports.isNotEmpty,
          builder: _sportsStep,
        ),
        WizardStep(
          title: 'Competition Structure',
          subtitle: 'Set the draw shape and entry limit for each category',
          builder: _structureStep,
        ),
        WizardStep(
          title: 'Schedule',
          // Grounds are as much a prerequisite as a start date, and until now
          // only the date was treated as one. `generateSchedule` resolves its
          // courts from these venue documents and refuses outright when there
          // are none, so a season published without them had exactly one
          // scheduling button and it always failed — with nothing on the
          // creation flow having ever said a ground was needed.
          canAdvance: () => _startDate != null && _venueIds.isNotEmpty,
          builder: _scheduleStep,
        ),
        WizardStep(
          title: 'Rules & Settings',
          builder: _settingsStep,
        ),
        WizardStep(
          title: 'Registration',
          builder: _registrationStep,
        ),
        WizardStep(title: 'Review & Publish', builder: _reviewStep),
      ],
    );
  }

  // --- Steps ---------------------------------------------------------------

  Widget _detailsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClubContextBanner(orgId: widget.orgId),
              WizardField(
                label: 'Season Name',
                required: true,
                child: TextField(
                  controller: _name,
                  decoration: _input('Hyderabad Sports Season 2026'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              WizardField(
                label: 'Short Name',
                child: TextField(
                  controller: _shortName,
                  decoration: _input('HSS 2026'),
                ),
              ),
              WizardField(
                label: 'Organizer',
                child: TextField(
                  controller: _organizer,
                  decoration: _input('Hyderabad Sports Association'),
                ),
              ),
              const SizedBox(height: 8),
              SeasonBrandingField(
                branding: _branding,
                name: _name.text,
                onChanged: () => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _StorageNotice(),
      ],
    );
  }

  Widget _sportsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsCard(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Multi-Category Matrix',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Ps.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Add multiple arrangements (Singles/Doubles) & Age groups per sport at once.',
                      style: TextStyle(fontSize: 12, color: Ps.muted),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Categories (+)'),
                onPressed: () => _addCategoriesForSport(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PsCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final spec in SportCatalog.versusSports)
                _SportCheckRow(
                  spec: spec,
                  selected: _sports.any((s) => s.sportId == spec.id),
                  categoryCount:
                      _sports.where((s) => s.sportId == spec.id).length,
                  onChanged: (on) => setState(() {
                    if (on) {
                      _sports.add(_SeasonSport(sportId: spec.id));
                    } else {
                      _sports.removeWhere((s) => s.sportId == spec.id);
                    }
                  }),
                  onAddCustomCategories: () =>
                      _addCategoriesForSport(sportId: spec.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whether entrants pay once for the season or once per sport, and the
  /// whole-season amount when it is the former.
  ///
  /// Asked before any amount, because the answer decides whether the number
  /// belongs here or on each sport card below — see [SeasonFeeMode]. Neither
  /// mode collects anything; see [FeeSettlement].
  Widget _feeCard(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Entry fee',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Either option is free if you leave the amount blank.',
            style: TextStyle(fontSize: 12, color: Ps.muted),
          ),
          for (final mode in SeasonFeeMode.values)
            RadioListTile<SeasonFeeMode>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: mode,
              groupValue: _feeMode,
              title: Text(mode.label, style: const TextStyle(fontSize: 14)),
              // Spelled out rather than left to the two labels. "A separate
              // fee for each sport" does not tell an organizer that the
              // amounts are typed on the cards below, and one who does not
              // scroll concludes the feature is missing.
              subtitle: Text(
                mode == SeasonFeeMode.wholeSeason
                    ? 'One payment lets an entrant play every event in this '
                        'season.'
                    : 'Badminton ₹500, cricket ₹2000 — set each amount on its '
                        'own sport card below.',
                style: const TextStyle(fontSize: 12, color: Ps.muted),
              ),
              onChanged: (v) => setState(() => _feeMode = v ?? _feeMode),
            ),
          if (_feeMode == SeasonFeeMode.wholeSeason)
            WizardField(
              label: 'Fee for the whole season',
              child: TextFormField(
                controller: _seasonFee,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Free',
                  prefixText: '₹ ',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            )
          else if (_sports.isEmpty)
            const Text(
              'Add a sport below to set its fee.',
              style: TextStyle(fontSize: 12, color: Ps.muted),
            ),
          const SizedBox(height: 8),
          const OfflineFeeNotice(message: FeeSettlement.organiserHelper),
        ],
      ),
    );
  }

  Widget _structureStep(BuildContext context) {
    final presets = CompetitionCategory.presets(cutOff: _startDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Named the moment they are in the season, not weeks later when the
        // timetable is built and one event is missing from it.
        _PerformanceSportNotice(sports: _sports),
        // ABOVE the sport cards, and that ordering is the whole point.
        //
        // This card decides whether each sport card below shows an entry-fee
        // field at all. Sitting underneath them, it asked the organizer to
        // choose per-sport pricing and then left the fields it had just
        // revealed off the top of the screen — so the honest report was that
        // per-sport entry fees "were not in the app". They were; nobody was
        // ever shown them.
        _feeCard(context),
        const SizedBox(height: 12),
        for (int i = 0; i < _sports.length; i++) ...[
          Builder(builder: (context) {
            final entry = _sports[i];
            return PsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SportBadge(sportId: entry.sportId, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Ps.ink,
                              ),
                            ),
                            Text(
                              entry.sport.name,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Ps.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.close, size: 20, color: Ps.muted),
                        tooltip: 'Remove category',
                        onPressed: () => setState(() => _sports.removeAt(i)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (entry.sport.sideFormats.length > 1)
                    WizardField(
                      label: 'Arrangement',
                      child: _dropdown<String>(
                        value: entry.sideFormat.id,
                        items: [
                          for (final f in entry.sport.sideFormats)
                            DropdownMenuItem(value: f.id, child: Text(f.name)),
                        ],
                        onChanged: (v) => setState(() {
                          entry.sideFormat = entry.sport.sideFormats
                              .firstWhere((f) => f.id == v);
                        }),
                      ),
                    ),
                  WizardField(
                    label: 'Category (Age / Gender)',
                    child: _dropdown<String>(
                      value: entry.category.label,
                      items: [
                        for (final cat in presets)
                          DropdownMenuItem(
                              value: cat.label, child: Text(cat.label)),
                      ],
                      onChanged: (label) => setState(() {
                        if (label != null) {
                          entry.category =
                              presets.firstWhere((c) => c.label == label);
                        }
                      }),
                    ),
                  ),
                  WizardField(
                    label: 'Format',
                    child: _dropdown<CompetitionFormat>(
                      value: entry.format,
                      items: [
                        for (final f in entry.sport.competitionFormats)
                          DropdownMenuItem(value: f, child: Text(f.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => entry.format = v ?? entry.format),
                    ),
                  ),
                  // Asked here because a season never opens the draw sheet:
                  // `setUpWholeSeason` draws every event from the config
                  // stored on it, so this is the only place the shape of the
                  // group stage can be chosen.
                  GroupStageFields(
                    format: entry.format,
                    entrantCount: entry.maxEntrants,
                    config: entry.draw,
                    onChanged: (v) => setState(() => entry.draw = v),
                  ),
                  WizardField(
                    label: entry.sport.defaultEntrantType == EntrantType.team
                        ? 'Maximum teams'
                        : 'Maximum entries',
                    child: _dropdown<int>(
                      value: entry.maxEntrants,
                      items: [
                        for (final n in const [4, 8, 16, 32, 64, 128])
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: (v) =>
                          setState(() => entry.maxEntrants = v ?? 16),
                    ),
                  ),
                  // Declared per sport, up front, and collected by the
                  // organizer at the venue — see `FeeSettlement`. Absent
                  // under a whole-season fee: the event is covered, not
                  // separately priced.
                  if (_feeMode == SeasonFeeMode.perEvent)
                  WizardField(
                    label: 'Entry fee — ${entry.sport.name}',
                    child: TextFormField(
                      key: ObjectKey(entry),
                      initialValue: entry.entryFeeRupees == 0
                          ? ''
                          : '${entry.entryFeeRupees}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Free',
                        prefixText: '₹ ',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      // No setState: the value is read back at submit time
                      // and nothing else on this card renders from it, so
                      // rebuilding the whole step on every keystroke would
                      // only cost the field its cursor position.
                      onChanged: (v) {
                        final n = int.tryParse(v.trim());
                        entry.entryFeeRupees = (n == null || n < 0) ? 0 : n;
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => _addCategoriesForSport(),
          icon: const Icon(Icons.add_circle_outline, size: 18),
          label: const Text('Add More Sport Categories (+)'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _scheduleStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WizardField(
                label: 'Start Date',
                required: true,
                child: _DateBox(
                  value: _startDate,
                  hint: 'Pick a start date',
                  // Bounded here rather than validated on submit, so the
                  // wrong date is never offered in the first place.
                  firstDate: _earliestStart,
                  onPick: (d) => setState(() {
                    _startDate = d;
                    if (_endDate != null && _endDate!.isBefore(d)) {
                      _endDate = d;
                    }
                  }),
                ),
              ),
              WizardField(
                label: 'End Date',
                child: _DateBox(
                  value: _endDate,
                  hint: 'Pick an end date',
                  firstDate: _startDate ?? _earliestStart,
                  onPick: (d) => setState(() => _endDate = d),
                ),
              ),
              WizardField(
                label: 'Venue shown on each event',
                child: TextField(
                  controller: _venue,
                  decoration: _input('Green Field Ground'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SeasonPlanField(
          orgId: widget.orgId,
          draft: _grounds,
          events: _eventPlans,
          start: _startDate,
          end: _endDate,
          defaultTurnaroundMinutes: _changeoverMinutes,
          onChanged: () => setState(() {}),
          onAddDay: _addADay,
        ),
        const SizedBox(height: 12),
        SeasonOfficialsField(
          orgId: widget.orgId,
          draft: _officials,
          events: _eventPlans,
          days: _preview.days,
          seasonStart: _startDate,
          seasonEnd: _endDate,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Match Timings & Operating Hours',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Configure standard match durations, court changeover gaps, and venue daily operating hours.',
                style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: WizardField(
                      label: 'Match Duration',
                      child: _TimingStepper(
                        value: _matchMinutes,
                        unit: 'min',
                        min: 5,
                        max: 240,
                        step: 5,
                        onChanged: (v) => setState(() {
                          _matchMinutes = v;
                          _matchMinutesSet = true;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Changeover',
                      child: _TimingStepper(
                        value: _changeoverMinutes,
                        unit: 'min',
                        min: 0,
                        max: 30,
                        step: 5,
                        onChanged: (v) => setState(() => _changeoverMinutes = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: WizardField(
                      label: 'Min Rest Gap',
                      child: _TimingStepper(
                        value: _restGapMinutes,
                        unit: 'min',
                        min: 0,
                        max: 120,
                        step: 5,
                        onChanged: (v) => setState(() => _restGapMinutes = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Daily Hours',
                      child: DailyHoursField(
                        startHour: _dayStartHour,
                        endHour: _dayEndHour,
                        onChanged: (start, end) => setState(() {
                          _dayStartHour = start;
                          _dayEndHour = end;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _perSportSchedule(context),
      ],
    );
  }

  /// Per-sport grounds, days and hours.
  ///
  /// ## Why this is a second, optional layer rather than the only one
  ///
  /// The season-wide answers above are right for most seasons and are the
  /// only thing a club running one badminton weekend should have to fill in.
  /// But a school sports week is the other half of the product: badminton in
  /// the hall from four to seven, cricket on the main field all Saturday,
  /// football on the far pitch on Sunday. Scheduling that against one ground
  /// list and one day window is not an approximation, it is wrong — the
  /// timetable will call a cricket match to a badminton court and print it as
  /// though it were fact.
  ///
  /// Everything here is an override, and an untouched sport stores exactly
  /// what it stored before. That is the difference between offering this and
  /// imposing it: nobody is asked six times for an answer they gave once.
  ///
  /// Only the season's own grounds are offered. A sport pointing at a ground
  /// the season does not hold would be unschedulable in a way whose cause is
  /// two screens away from its symptom.
  Widget _perSportSchedule(BuildContext context) {
    if (_sports.isEmpty) {
      return const PsCard(
        child: Text(
          'Add a sport first — per-sport grounds and timings are set here '
          'once there is something to set them on.',
          style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
        ),
      );
    }

    // Straight off the grounds panel: a ground added on this form is not a
    // saved venue yet, so filtering the saved list by the season's ids would
    // hide exactly the ground the organizer had just typed in.
    final seasonVenues = [for (final g in _grounds.grounds) g.venue];
    final nameById = {for (final v in seasonVenues) v.id: v.name};

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Each sport’s own ground & timing',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Optional. Badminton in the hall, cricket on the main field, '
            'football on Sunday — set it here and the timetable keeps each '
            'sport where and when you put it. Anything left alone follows the '
            'season above.',
            style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final entry in _sports)
            _SportScheduleTile(
              entry: entry,
              seasonVenues: seasonVenues,
              nameById: nameById,
              seasonStart: _startDate,
              seasonEnd: _endDate,
              seasonDayStartHour: _dayStartHour,
              seasonDayEndHour: _dayEndHour,
              seasonMatchMinutes: _minutesFor(entry),
              onChanged: () => setState(() {}),
            ),
        ],
      ),
    );
  }

  /// Every category as the capacity engine needs it — see the identical
  /// getter in `create_season_screen.dart`. Both forms build the same season,
  /// so both measure it the same way.
  List<SeasonEventPlan> get _eventPlans => [
        for (final sport in _sports)
          SeasonEventPlan(
            key: '${sport.sportId}/${sport.sideFormat.id}/'
                '${sport.category.label}',
            label: '${sport.sport.name} ${sport.category.label}',
            sportId: sport.sportId,
            entrants: sport.maxEntrants < 2 ? 16 : sport.maxEntrants,
            format: sport.format,
            drawConfig: sport.drawToSubmit,
            groundIds: sport.venueIds,
            matchMinutes: _minutesFor(sport),
            turnaroundMinutes: _changeoverMinutes,
            isTimetabled: !sport.sport.isPerformance,
          ),
      ];

  /// Minutes one match of [sport] takes: its own override, then the season's
  /// if the organizer set one, then the sport's ruleset.
  int _minutesFor(_SeasonSport sport) =>
      sport.matchMinutes ??
      (_matchMinutesSet
          ? _matchMinutes
          : MatchDuration.estimate(sportId: sport.sportId));

  /// The season as typed, measured against the grounds it has.
  SeasonPlanPreview get _preview => DraftSeasonPlan.build(
        start: _startDate,
        end: _endDate,
        grounds: _grounds.grounds,
        events: _eventPlans,
        defaultTurnaroundMinutes: _changeoverMinutes,
      );

  /// Adds a day, from the verdict's own suggestion.
  void _addADay() {
    final start = _startDate;
    if (start == null) return;
    final end = _endDate ?? start;
    setState(() => _endDate = DateTime(end.year, end.month, end.day + 1));
  }

  Widget _settingsStep(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WizardToggle(
            label: 'Live Scoring',
            help: 'Matches are followed ball by ball as they are played',
            value: _liveScoring,
            onChanged: (v) => setState(() => _liveScoring = v),
          ),
          WizardToggle(
            label: 'Leaderboard',
            help: 'Publish standings across the season',
            value: _leaderboard,
            onChanged: (v) => setState(() => _leaderboard = v),
          ),
          WizardToggle(
            label: 'Player Statistics',
            help: 'Every result counts towards each player\'s career record',
            value: _playerStats,
            onChanged: (v) => setState(() => _playerStats = v),
          ),
          WizardToggle(
            label: 'Results Approval',
            help: 'A result stays provisional until an organizer confirms it',
            value: _resultsApproval,
            onChanged: (v) => setState(() => _resultsApproval = v),
          ),
          WizardToggle(
            label: 'Allow Protests',
            help: 'Entrants can formally dispute a result',
            value: _allowProtests,
            onChanged: (v) => setState(() => _allowProtests = v),
          ),
        ],
      ),
    );
  }

  Widget _registrationStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WizardToggle(
                label: 'Open to other clubs',
                help: 'Clubs outside yours can enter this season',
                value: _externalEntries,
                onChanged: (v) => setState(() => _externalEntries = v),
              ),
              const SizedBox(height: 8),
              Text(
                _externalEntries
                    // Stated plainly rather than left as a second toggle: it
                    // is not a choice, it is what opening a season to
                    // strangers necessarily means.
                    ? 'Entries from outside your club must be approved by you '
                        'before they are confirmed. Your own members are '
                        'confirmed as they enter.'
                    : 'Only members of your club can enter. Their entries are '
                        'confirmed straight away.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Ps.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        // An internal season's team events are entered house by house, so the
        // houses are part of setting one up — not something to discover as
        // four colours after the fact. An open season is entered by whole
        // clubs and has no use for them.
        if (!_externalEntries) ...[
          const SizedBox(height: 12),
          PsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Houses & Groups',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'What your students pick from when they enter a team event. '
                  'Houses, departments, years, sections — whatever you '
                  'actually split by. You can change these later.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Ps.muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                HouseListEditor(
                  initial: _presetHouses,
                  onChanged: (h) => setState(() => _presetHouses = h),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _reviewStep(BuildContext context) {
    final start = _startDate;
    final end = _endDate;
    final entrants = _sports.fold<int>(0, (sum, s) => sum + s.maxEntrants);

    // One sport across every category means the generated art can be that
    // sport's; five sports under one season have no single colour, which is
    // the same rule the season page itself applies.
    final sportIds = {for (final s in _sports) s.sportId};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header the season will open with, artwork and all — see
        // [SeasonBrandingPreview] for why the review step draws the real
        // thing rather than a trophy tile.
        SeasonBrandingPreview(
          branding: _branding,
          name: _name.text,
          sportId: sportIds.length == 1 ? sportIds.first : null,
        ),
        const SizedBox(height: 12),
        // The last chance to see the season is impossible before it exists.
        // The Schedule step already showed this; repeating it here is not
        // duplication — an organizer who added two more categories on the
        // steps in between has changed the answer without going back.
        SeasonPlanVerdict(
          preview: _preview,
          hasGrounds: !_grounds.isEmpty,
          hasDates: _startDate != null,
          onAddDay: _addADay,
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            children: [
              WizardReviewRow(label: 'Sports', value: '${_sports.length}'),
              WizardReviewRow(
                label: 'Officials',
                value: _officials.isEmpty
                    ? 'None yet'
                    : '${_officials.officials.length} on the panel',
              ),
              WizardReviewRow(
                label: 'Events created',
                value: '${_sports.length}',
              ),
              WizardReviewRow(
                label: 'Entry places',
                value: psGrouped(entrants),
              ),
              WizardReviewRow(
                label: 'Start date',
                value: start == null
                    ? 'Not set'
                    : DateFormat('d MMM yyyy').format(start),
              ),
              WizardReviewRow(
                label: 'End date',
                value: end == null
                    ? 'Same day'
                    : DateFormat('d MMM yyyy').format(end),
              ),
              WizardReviewRow(
                label: 'Venue',
                value: _venue.text.trim().isEmpty
                    ? 'Not set'
                    : _venue.text.trim(),
              ),
              WizardReviewRow(
                label: 'Grounds for scheduling',
                // Surfaced on the review step because it is the one omission
                // that does not announce itself until the organizer tries to
                // build a timetable and is told there are no courts.
                value: _venueIds.isEmpty
                    ? 'None — the schedule cannot be generated'
                    : '${_venueIds.length} selected',
              ),
              WizardReviewRow(
                label: 'Match timings',
                // Worth confirming here now that these are genuinely editable
                // — they were fixed at 30 minutes and 09:00–19:00 for every
                // season the product had ever created.
                value: '$_matchMinutes min + $_changeoverMinutes min '
                    'changeover, '
                    '${_dayStartHour.toString().padLeft(2, '0')}:00–'
                    '${_dayEndHour.toString().padLeft(2, '0')}:00',
              ),
              WizardReviewRow(
                label: 'Entries',
                value: _externalEntries
                    ? 'Open to other clubs, by approval'
                    : 'Your club only',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Events in this season',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 10),
              for (final entry in _sports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SportBadge(sportId: entry.sportId, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.sport.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Ps.ink,
                              ),
                            ),
                            // The two per-sport answers worth re-reading
                            // before publishing: what this sport costs, and
                            // where and when it is played. Both were set
                            // several steps back, and both are wrong in a way
                            // that is expensive to discover afterwards — a
                            // fee is quoted to entrants, and a ground is
                            // where people physically turn up.
                            if (_reviewLineFor(entry) case final line?)
                              Text(
                                line,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Ps.muted,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.format.label} · ${entry.maxEntrants}',
                        style: const TextStyle(fontSize: 11.5, color: Ps.muted),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'The season and its events are created as drafts so you can check '
            'them first. The season page opens entries on all of them in one '
            'tap — nobody can register until you do.',
            style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
        ),
      ],
    );
  }

  /// The review line under one sport: its own fee, ground, days and hours —
  /// whichever of them it actually has. Null when the sport is priced with
  /// the season and follows it everywhere, so an ordinary season's review
  /// stays a plain list rather than four identical repetitions of what the
  /// card above already says.
  String? _reviewLineFor(_SeasonSport entry) {
    final nameById = {
      for (final g in _grounds.grounds) g.venue.id: g.venue.name,
    };
    final fmt = DateFormat('d MMM');

    final parts = <String>[
      if (_feeMode == SeasonFeeMode.perEvent)
        entry.entryFeeRupees == 0 ? 'Free' : '₹${entry.entryFeeRupees}',
      if (entry.venueIds.isNotEmpty)
        entry.venueIds.map((id) => nameById[id] ?? 'Ground').join(', '),
      if (entry.startDate != null || entry.endDate != null)
        switch ((entry.startDate, entry.endDate)) {
          (final a?, final b?) when a == b => fmt.format(a),
          (final a?, final b?) => '${fmt.format(a)} – ${fmt.format(b)}',
          (final a?, null) => 'from ${fmt.format(a)}',
          (null, final b?) => 'until ${fmt.format(b)}',
          _ => '',
        },
      if (entry.dayStartHour != null || entry.dayEndHour != null)
        '${(entry.dayStartHour ?? _dayStartHour).toString().padLeft(2, '0')}'
            ':00–'
            '${(entry.dayEndHour ?? _dayEndHour).toString().padLeft(2, '0')}'
            ':00',
      if (entry.matchMinutes != null) '${entry.matchMinutes} min',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // --- Shared pieces -------------------------------------------------------

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Ps.faint),
        filled: true,
        fillColor: Ps.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: _border(Ps.border),
        enabledBorder: _border(Ps.border),
        focusedBorder: _border(Ps.primary),
      );

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        borderSide: BorderSide(color: color),
      );

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: Ps.ink),
      icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Ps.muted),
      decoration: _input(''),
    );
  }
}

/// A sport with a checkbox and + quick category selector button.
class _SportCheckRow extends StatelessWidget {
  const _SportCheckRow({
    required this.spec,
    required this.selected,
    required this.onChanged,
    this.categoryCount = 0,
    this.onAddCustomCategories,
  });

  final SportSpec spec;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final int categoryCount;
  final VoidCallback? onAddCustomCategories;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: Ps.primary,
            ),
            const SizedBox(width: 4),
            SportBadge(sportId: spec.id, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Ps.ink,
                    ),
                  ),
                  if (categoryCount > 1)
                    Text(
                      '$categoryCount categories selected',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Ps.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (onAddCustomCategories != null)
              IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add Singles / Doubles / Age categories for ${spec.name}',
                visualDensity: VisualDensity.compact,
                onPressed: onAddCustomCategories,
              ),
          ],
        ),
      ),
    );
  }
}

/// Says that logo and banner upload is not wired up, rather than offering a
/// button that fails.
///
/// Firebase Storage is not configured on this project. An upload control that
/// throws on tap is worse than one that explains itself — the organizer would
/// assume their season was broken rather than that a feature is pending.
/// Says which of the chosen sports will not appear on the timetable.
///
/// ## Why this is a notice and not a block
///
/// Track, field and swimming produce measured marks, not pairwise matches:
/// eight sprinters in one heat is one race, and `Fixture` holds exactly two
/// sides. So `FixtureGenerator` builds nothing for them and
/// `CompetitionRepository.generateDraw` refuses outright — heats, lanes and
/// progression are a real piece of work that has not been done.
///
/// They stay selectable because a school sports week is half athletics and
/// dropping them from the catalogue would silently shrink the product's main
/// use case. What must not happen is finding out at schedule time: the
/// organizer built a season, opened entries, took forty registrations, and
/// only then got one line in a skipped list. So the season says it here,
/// while the choice is still being made.
class _PerformanceSportNotice extends StatelessWidget {
  const _PerformanceSportNotice({required this.sports});

  final List<_SeasonSport> sports;

  @override
  Widget build(BuildContext context) {
    final names = <String>{
      for (final s in sports)
        if (s.sport.isPerformance) s.sport.name,
    };
    if (names.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PsCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.timer_outlined, size: 20, color: Ps.live),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${names.join(', ')} will not be timetabled',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Ps.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'These are recorded as marks and times rather than as '
                    'matches, so they take entries and results but are not '
                    'drawn or placed on the schedule. Everything else in the '
                    'season is.',
                    style:
                        TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageNotice extends StatelessWidget {
  const _StorageNotice();

  @override
  Widget build(BuildContext context) {
    return const PsCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.image_outlined, size: 20, color: Ps.faint),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logo and banner',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Image upload is not switched on for this project yet. The '
                  'season can be created without one and images added later.',
                  style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable box that opens a date picker.
/// One sport's row in the per-sport schedule card — collapsed to a summary
/// until an organizer opens it.
///
/// Collapsed by default and summarised in one line, because the card lists
/// every category in the season and a season can hold a dozen. Six expanded
/// forms of six fields each is not a screen anybody reads; a list saying
/// "Badminton (Singles) · Season default" and "Cricket · Main Field · 12–13
/// Sep" is one they can check at a glance.
class _SportScheduleTile extends StatelessWidget {
  const _SportScheduleTile({
    required this.entry,
    required this.seasonVenues,
    required this.nameById,
    required this.seasonStart,
    required this.seasonEnd,
    required this.seasonDayStartHour,
    required this.seasonDayEndHour,
    required this.seasonMatchMinutes,
    required this.onChanged,
  });

  final _SeasonSport entry;
  final List<Venue> seasonVenues;
  final Map<String, String> nameById;
  final DateTime? seasonStart;
  final DateTime? seasonEnd;
  final int seasonDayStartHour;
  final int seasonDayEndHour;
  final int seasonMatchMinutes;
  final VoidCallback onChanged;

  String get _summary {
    if (!entry.hasScheduleOverride) return 'Follows the season';
    final parts = <String>[
      if (entry.venueIds.isNotEmpty)
        entry.venueIds.map((id) => nameById[id] ?? 'Ground').join(', '),
      if (entry.startDate != null || entry.endDate != null)
        _dayRangeLabel(),
      if (entry.dayStartHour != null || entry.dayEndHour != null)
        '${_hh(entry.dayStartHour ?? seasonDayStartHour)}–'
            '${_hh(entry.dayEndHour ?? seasonDayEndHour)}',
      if (entry.matchMinutes != null) '${entry.matchMinutes} min',
    ];
    return parts.join(' · ');
  }

  String _dayRangeLabel() {
    final fmt = DateFormat('d MMM');
    final from = entry.startDate ?? seasonStart;
    final to = entry.endDate ?? seasonEnd;
    if (from == null) return to == null ? '' : 'until ${fmt.format(to)}';
    if (to == null) return 'from ${fmt.format(from)}';
    return from == to
        ? fmt.format(from)
        : '${fmt.format(from)} – ${fmt.format(to)}';
  }

  static String _hh(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    final overridden = entry.hasScheduleOverride;

    return Theme(
      // The divider the default ExpansionTile draws above and below itself
      // stacks into a double rule between adjacent tiles.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Text(
          entry.displayName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Ps.ink,
          ),
        ),
        subtitle: Text(
          _summary,
          style: TextStyle(
            fontSize: 12,
            color: overridden ? Ps.ink : Ps.muted,
            fontWeight: overridden ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        children: [
          if (seasonVenues.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Pick the season’s grounds above first, then choose which of '
                'them this sport uses.',
                style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
              ),
            )
          else ...[
            const _FieldLabel('Grounds for this sport'),
            // "All of them" is a real, selectable state rather than the
            // absence of a selection: an organizer who unticks the last
            // ground has said nothing about this sport, and silently reading
            // that as "no grounds" would make the sport unschedulable for a
            // reason the screen never showed them.
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: false,
              groupValue: entry.venueIds.isNotEmpty,
              title: const Text(
                'Every ground the season uses',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (_) {
                entry.venueIds.clear();
                onChanged();
              },
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: true,
              groupValue: entry.venueIds.isNotEmpty,
              title: const Text(
                'Only these grounds',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (_) {
                if (entry.venueIds.isEmpty && seasonVenues.isNotEmpty) {
                  entry.venueIds.add(seasonVenues.first.id);
                }
                onChanged();
              },
            ),
            if (entry.venueIds.isNotEmpty)
              for (final v in seasonVenues)
                CheckboxListTile(
                  contentPadding: const EdgeInsets.only(left: 24),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: entry.venueIds.contains(v.id),
                  title: Text(
                    v.name,
                    style: const TextStyle(fontSize: 13, color: Ps.ink),
                  ),
                  subtitle: Text(
                    '${v.usableCourts.length} usable '
                    '${v.usableCourts.length == 1 ? "court" : "courts"}',
                    style: const TextStyle(fontSize: 11, color: Ps.muted),
                  ),
                  onChanged: (on) {
                    if (on ?? false) {
                      entry.venueIds.add(v.id);
                    } else {
                      entry.venueIds.remove(v.id);
                      // Back to "all grounds" rather than to none — see the
                      // radio above.
                    }
                    onChanged();
                  },
                ),
            const SizedBox(height: 8),
          ],
          if (seasonStart != null) ...[
            const _FieldLabel('Days this sport runs'),
            Row(
              children: [
                Expanded(
                  child: _DateBox(
                    value: entry.startDate,
                    hint: 'Season start',
                    firstDate: seasonStart!,
                    lastDate: seasonEnd,
                    onPick: (d) {
                      entry.startDate = d;
                      final end = entry.endDate;
                      if (end != null && end.isBefore(d)) entry.endDate = d;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateBox(
                    value: entry.endDate,
                    hint: 'Season end',
                    firstDate: entry.startDate ?? seasonStart!,
                    lastDate: seasonEnd,
                    onPick: (d) {
                      entry.endDate = d;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: WizardField(
                  label: 'Daily hours',
                  child: DailyHoursField(
                    startHour: entry.dayStartHour ?? seasonDayStartHour,
                    endHour: entry.dayEndHour ?? seasonDayEndHour,
                    onChanged: (start, end) {
                      entry.dayStartHour = start;
                      entry.dayEndHour = end;
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WizardField(
                  label: 'Match duration',
                  child: _TimingStepper(
                    value: entry.matchMinutes ?? seasonMatchMinutes,
                    unit: 'min',
                    min: 5,
                    max: 480,
                    step: 5,
                    onChanged: (v) {
                      entry.matchMinutes = v;
                      onChanged();
                    },
                  ),
                ),
              ),
            ],
          ),
          if (overridden)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  entry.venueIds.clear();
                  entry.startDate = null;
                  entry.endDate = null;
                  entry.dayStartHour = null;
                  entry.dayEndHour = null;
                  entry.matchMinutes = null;
                  onChanged();
                },
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Follow the season again'),
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Ps.muted,
          ),
        ),
      );
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.value,
    required this.hint,
    required this.firstDate,
    required this.onPick,
    this.lastDate,
  });

  final DateTime? value;
  final String hint;
  final DateTime firstDate;

  /// The last date offerable. Given for a per-sport window, which cannot run
  /// past the season containing it — bounding the picker is how that is said,
  /// rather than accepting the date and complaining afterwards.
  final DateTime? lastDate;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final last = lastDate ?? firstDate.add(const Duration(days: 365 * 3));
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? firstDate,
          firstDate: firstDate,
          // A caller that hands over a window narrower than one day would
          // otherwise crash the picker on its own assertion.
          lastDate: last.isBefore(firstDate) ? firstDate : last,
        );
        if (picked != null) onPick(picked);
      },
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          border: Border.all(color: Ps.border),
          color: Ps.surface,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? hint
                    : DateFormat('d MMM yyyy').format(value!),
                style: TextStyle(
                  fontSize: 14,
                  color: value == null ? Ps.faint : Ps.ink,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Ps.faint,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimingStepper extends StatelessWidget {
  const _TimingStepper({
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final int value;
  final String unit;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Ps.surface,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: Ps.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.remove, size: 16),
            onPressed: value > min ? () => onChanged(value - step) : null,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '$value $unit',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          IconButton(
            tooltip: 'Add',
            icon: const Icon(Icons.add, size: 16),
            onPressed: value < max ? () => onChanged(value + step) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

