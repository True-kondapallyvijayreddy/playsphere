import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/competition.dart';
import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart' show showError;
import '../../shared/club_context_banner.dart';
import '../../shared/season_branding_field.dart';
import '../../shared/offline_fee_notice.dart';
import '../../shared/ui_kit.dart';
import '../../shared/wizard.dart';
import 'widgets/daily_hours_field.dart';
import 'widgets/group_stage_fields.dart';
import '../tournaments/widgets/venue_selector_dialog.dart'
    show showQuickAddVenueDialog;
import '../../domain/tournament/house_roster.dart';
import 'widgets/house_list_editor.dart';

/// Tournament creation, one decision at a time.
///
/// ## Why this exists alongside [CreateCompetitionScreen]
///
/// That screen is one page on purpose — its own doc comment explains that an
/// organizer setting up eight events for a sports day should not click
/// through five pages each time, and that is still true. This does not
/// replace it. It is the guided route for somebody creating their first
/// tournament, who does not yet know what a "participation model" is or which
/// of six formats they want; the single page remains reachable as "Quick
/// create" for the organizer who does.
///
/// Both write the same [Competition] through the same repository, so an event
/// created either way is indistinguishable afterwards. That is the constraint
/// that makes having two entrances safe.
class GuidedTournamentScreen extends ConsumerStatefulWidget {
  const GuidedTournamentScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<GuidedTournamentScreen> createState() =>
      _GuidedTournamentScreenState();
}

class _GuidedTournamentScreenState
    extends ConsumerState<GuidedTournamentScreen> {
  final _name = TextEditingController();

  /// The tournament's crest and header art, staged until it has an id — see
  /// [SeasonBranding]. The same block the season forms use, so a tournament
  /// and a season are brandable in the same way.
  final _branding = SeasonBranding();
  final _shortName = TextEditingController();
  final _venue = TextEditingController();

  /// Blank means free — see `FeeSettlement`. Kept as text rather than an int
  /// so an empty field and a typed zero look the same to the organizer.
  final _entryFee = TextEditingController();

  final Set<String> _venueIds = {};
  int _matchMinutes = 30;
  int _changeoverMinutes = 5;
  int _restGapMinutes = 20;
  /// Editable, which they were not — see [DailyHoursField] for what that
  /// cost every tournament created before this.
  int _dayStartHour = 9;
  int _dayEndHour = 19;

  SportSpec _sport = SportCatalog.byId('cricket');
  late CompetitionCategory _category = CompetitionCategory.presets().first;
  CompetitionFormat _format = CompetitionFormat.groupThenKnockout;

  /// The shape of the group stage — how many groups, and how many of each go
  /// through to the knockout.
  ///
  /// Asked on the Format step rather than left to "Make the draw", because
  /// the format chosen there is Groups+Knockout by default and an organizer
  /// picking it is already thinking about exactly this. Persisted onto the
  /// competition, so the draw sheet opens on the organizer's own numbers
  /// instead of the generator's fallback.
  DrawConfig _draw = const DrawConfig();

  /// The declared fee in whole rupees, floored at zero.
  ///
  /// Unparseable text reads as free rather than blocking the save — see
  /// `_CategoryDraft.entryFeeRupees` in `create_season_screen.dart` for why
  /// the failure direction is deliberate.
  int get _entryFeeRupees {
    final n = int.tryParse(_entryFee.text.trim());
    return (n == null || n < 0) ? 0 : n;
  }

  /// [_draw] clamped to what the format and the expected field allow.
  DrawConfig get _drawToSubmit => GroupStageFields.normalize(
        format: _format,
        entrantCount: _maxEntrants,
        config: _draw,
      );
  ParticipationModel _participation = ParticipationModel.open;
  TeamEntryMode _teamEntryMode = TeamEntryMode.preformedTeam;
  /// Seeded from the school-colours template only because a list has to open
  /// with something. Editable right here — see [HouseListEditor], and
  /// [HouseRoster] for why four colours were the wrong thing to hard-code.
  List<String> _presetHouses = [...HouseTemplates.schoolColours];

  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);

  int _maxEntrants = 32;
  int _minSquad = 11;

  bool _approvalRequired = false;
  bool _liveScoring = true;
  bool _resultsApproval = false;
  bool _pointsTable = true;
  bool _allowWithdrawal = true;

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    _venue.dispose();
    _entryFee.dispose();
    super.dispose();
  }

  /// The formats a tournament can actually take.
  ///
  /// `singleMatch` is excluded deliberately: it is its own event type with its
  /// own flow, and creating it here would write a competition with no fixture
  /// — an event that shows up in the club's list and can never be played.
  /// This is the same trap `CreateCompetitionScreen._create` guards against.
  List<CompetitionFormat> get _formats => [
        for (final f in CompetitionFormat.values)
          if (!f.isSingleMatch &&
              f != CompetitionFormat.finalOnly &&
              f != CompetitionFormat.heatsThenFinal)
            f,
      ];

  DateTime? get _startsAt {
    final date = _startDate;
    if (date == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      _startTime.hour,
      _startTime.minute,
    );
  }

  Future<void> _submit() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final compId =
          await ref.read(competitionRepositoryProvider).createCompetition(
                Competition(
                  id: '',
                  orgId: widget.orgId,
                  name: _name.text.trim(),
                  sportId: _sport.id,
                  sportName: _sport.name,
                  archetype: _sport.archetype,
                  entrantType: _sport.defaultEntrantType,
                  format: _format,
                  drawConfig: _drawToSubmit,
                  status: CompetitionStatus.registrationOpen,
                  category: _category,
                  scoringPluginKey: _sport.pluginKey,
                  teamEntryMode: _sport.defaultEntrantType == EntrantType.individual
                      ? TeamEntryMode.individual
                      : _teamEntryMode,
                  // Only the house mode authored these. `_presetHouses`
                  // holds the school-colour default from the moment the
                  // wizard opens, and persisting it on a pre-formed-club or
                  // player-pool event would put four houses nobody chose in
                  // front of everyone who enters.
                  presetHouses: _teamEntryMode == TeamEntryMode.houseBatch &&
                          _sport.defaultEntrantType == EntrantType.team
                      ? _presetHouses
                      : const [],
                  venue:
                      _venue.text.trim().isEmpty ? null : _venue.text.trim(),
                  startDate: _startsAt,
                  entryFeeRupees: _entryFeeRupees,
                  maxEntrants: _maxEntrants,
                  scheduleConfig: ScheduleConfig(
                    venueIds: _venueIds.toList(),
                    matchMinutes: _matchMinutes,
                    changeoverMinutes: _changeoverMinutes,
                    restGapMinutes: _restGapMinutes,
                    dayStartHour: _dayStartHour,
                    dayEndHour: _dayEndHour,
                  ),
                  participationModel: _approvalRequired
                      ? ParticipationModel.approval
                      : _participation,
                  teamSize: _minSquad,
                  createdBy: uid,
                ),
              );
      // After the document, because the storage path is keyed on its id, and
      // allowed to fail on its own — see [SeasonBranding.uploadTo].
      final brandingProblem = await _branding.uploadToEvent(
        repo: ref.read(competitionRepositoryProvider),
        orgId: widget.orgId,
        compId: compId,
        uid: uid,
      );

      if (!mounted) return;
      // Replace, not push: the tournament exists now, and a back press must
      // not land on a filled-in form that would create a second one.
      context.pushReplacement(Routes.competition(widget.orgId, compId));
      if (brandingProblem != null) showError(context, brandingProblem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WizardScaffold(
      title: 'Create Tournament',
      submitLabel: 'Create Tournament',
      submitting: _busy,
      onSubmit: _submit,
      steps: [
        WizardStep(
          title: 'Details',
          // Only the name is genuinely required. Everything else on this step
          // has a defensible default, and a flow that blocks on six fields at
          // step one is a flow people abandon at step one.
          canAdvance: () => _name.text.trim().isNotEmpty,
          builder: _detailsStep,
        ),
        WizardStep(title: 'Teams', builder: _teamsStep),
        WizardStep(title: 'Format', builder: _formatStep),
        WizardStep(
          title: 'Schedule',
          // Same requirement as the season flow, for the same reason: without
          // a ground there are no courts, and `generateSchedule` refuses.
          canAdvance: () => _venueIds.isNotEmpty,
          builder: _scheduleStep,
        ),
        WizardStep(title: 'Settings', builder: _settingsStep),
        WizardStep(title: 'Review', builder: _reviewStep),
      ],
    );
  }

  // --- Steps ---------------------------------------------------------------

  Widget _detailsStep(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Whose tournament this is, on the first step, where the decision
          // is still reversible. Read-only: this wizard is opened from one
          // club's pages and half its later steps (venues, members) are that
          // club's, so switching here would invalidate them silently.
          ClubContextBanner(orgId: widget.orgId),
          WizardField(
            label: 'Tournament Name',
            required: true,
            child: TextField(
              controller: _name,
              decoration: _input('Hyderabad Champions Cup 2026'),
              // Rebuilds so the Next button enables as soon as there is a
              // name, rather than on the next unrelated interaction.
              onChanged: (_) => setState(() {}),
            ),
          ),
          WizardField(
            label: 'Short Name',
            child: TextField(
              controller: _shortName,
              decoration: _input('HCC 2026'),
            ),
          ),
          WizardField(
            label: 'Sport',
            required: true,
            child: _dropdown<String>(
              value: _sport.id,
              items: [
                for (final s in SportCatalog.all)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(
                () => _sport = SportCatalog.byId(v ?? _sport.id),
              ),
            ),
          ),
          WizardField(
            label: 'Category',
            child: _dropdown<String>(
              value: _category.label,
              items: [
                for (final c in CompetitionCategory.presets())
                  DropdownMenuItem(value: c.label, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() {
                _category = CompetitionCategory.presets()
                    .firstWhere((c) => c.label == v, orElse: () => _category);
              }),
            ),
          ),
          const SizedBox(height: 8),
          // On the first step with the name and the sport, because the
          // preview is drawn from all three: the generated header takes the
          // sport's colour, so a tournament with no artwork still shows the
          // organizer what they are about to publish.
          SeasonBrandingField(
            branding: _branding,
            name: _name.text,
            sportId: _sport.id,
            subject: 'Tournament',
            title: 'Tournament look',
            helper: 'Optional. Both show on the tournament page and on the '
                'public link you share — the logo on the header, in lists, '
                'and beside every result.',
            onChanged: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _teamsStep(BuildContext context) {
    final isTeamSport = _sport.defaultEntrantType == EntrantType.team;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isTeamSport) ...[
          PsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Team Formation & Registration Model',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Ps.ink,
                  ),
                ),
                const SizedBox(height: 8),
                _ParticipationChoice(
                  label: 'Pre-formed Club / Team (Pro Leagues)',
                  help: 'Captains or managers submit a team name & full squad roster',
                  selected: _teamEntryMode == TeamEntryMode.preformedTeam,
                  onTap: () => setState(
                    () => _teamEntryMode = TeamEntryMode.preformedTeam,
                  ),
                ),
                const SizedBox(height: 8),
                _ParticipationChoice(
                  label: 'School Houses / Class Batches',
                  help: _teamEntryMode == TeamEntryMode.houseBatch
                      ? 'Students register individually by picking one of the '
                          '${_presetHouses.length} groups below'
                      : 'Students register individually by picking their house, '
                          'department, year or section',
                  selected: _teamEntryMode == TeamEntryMode.houseBatch,
                  onTap: () => setState(
                    () => _teamEntryMode = TeamEntryMode.houseBatch,
                  ),
                ),
                // Shown only once the mode is chosen: the names are the whole
                // substance of this mode, and a list of text boxes under an
                // unselected radio is noise on a phone screen.
                if (_teamEntryMode == TeamEntryMode.houseBatch)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
                    child: HouseListEditor(
                      initial: _presetHouses,
                      onChanged: (h) => setState(() => _presetHouses = h),
                    ),
                  ),
                const SizedBox(height: 8),
                _ParticipationChoice(
                  label: 'Player Pool & Organizer Draft',
                  help: 'Players register solo into a pool, and organizer uses 1-click Auto-Draft',
                  selected: _teamEntryMode == TeamEntryMode.playerPool,
                  onTap: () => setState(
                    () => _teamEntryMode = TeamEntryMode.playerPool,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Participation Access',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Ps.ink,
                ),
              ),
              const SizedBox(height: 8),
              _ParticipationChoice(
                label: 'Open Registration',
                help: isTeamSport
                    ? 'Any team can register and participate'
                    : 'Anyone can register and participate',
                selected: _participation == ParticipationModel.open,
                onTap: () => setState(
                  () => _participation = ParticipationModel.open,
                ),
              ),
              const SizedBox(height: 8),
              _ParticipationChoice(
                label: 'Invitation Only',
                help: isTeamSport
                    ? 'Only invited teams can participate'
                    : 'Only invited players can participate',
                selected: _participation == ParticipationModel.approval,
                onTap: () => setState(
                  () => _participation = ParticipationModel.approval,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Stepper(
                label: isTeamSport ? 'Maximum Teams' : 'Maximum Players',
                required: true,
                value: _maxEntrants,
                // Two is the floor a draw can be generated from. Below that
                // there is no fixture to play.
                min: 2,
                max: 256,
                onChanged: (v) => setState(() => _maxEntrants = v),
              ),
              if (isTeamSport)
                _Stepper(
                  label: 'Minimum Players in Squad',
                  required: true,
                  value: _minSquad,
                  // The engine's floor, not the rulebook's — see SideFormat.
                  // A six-a-side school game is still football.
                  min: 1,
                  max: 30,
                  onChanged: (v) => setState(() => _minSquad = v),
                ),
              const SizedBox(height: 4),
              // Asked at creation, never at entry: an entrant deciding
              // whether to play has to see the price before they commit,
              // and PlaySphere has no way to ask for it later because it
              // never handles the money — see `FeeSettlement`.
              WizardField(
                label: 'Entry Fee',
                child: TextFormField(
                  controller: _entryFee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Free',
                    prefixText: '₹ ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const OfflineFeeNotice(
                message: FeeSettlement.organiserHelper,
              ),
              const SizedBox(height: 4),
              WizardToggle(
                label: 'Approval Required',
                help: 'Every entry waits for an organizer to confirm it',
                value: _approvalRequired,
                onChanged: (v) => setState(() => _approvalRequired = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formatStep(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WizardField(
            label: 'Tournament Format',
            child: _dropdown<CompetitionFormat>(
              value: _format,
              items: [
                for (final f in _formats)
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
          ),
          Text(
            _formatExplanation(_format),
            style: const TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
          GroupStageFields(
            format: _format,
            entrantCount: _maxEntrants,
            config: _draw,
            onChanged: (v) => setState(() => _draw = v),
          ),
        ],
      ),
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
                child: _DateField(
                  value: _startDate,
                  hint: 'Pick a start date',
                  onPick: (d) => setState(() {
                    _startDate = d;
                    if (_endDate != null && _endDate!.isBefore(d)) _endDate = d;
                  }),
                ),
              ),
              WizardField(
                label: 'End Date',
                child: _DateField(
                  value: _endDate,
                  hint: 'Pick an end date',
                  firstDate: _startDate,
                  onPick: (d) => setState(() => _endDate = d),
                ),
              ),
              WizardField(
                label: 'Match Start Time',
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _startTime,
                    );
                    if (picked != null) setState(() => _startTime = picked);
                  },
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                  child: _FakeField(text: _startTime.format(context)),
                ),
              ),
              WizardField(
                label: 'Venue',
                child: TextField(
                  controller: _venue,
                  decoration: _input('Green Field Ground'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _venuePicker(context),
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
                        onChanged: (v) => setState(() => _matchMinutes = v),
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
      ],
    );
  }

  Widget _venuePicker(BuildContext context) {
    final venuesAsync = ref.watch(venuesProvider(widget.orgId));

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Grounds & Courts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Ps.ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Pick every ground this tournament may use. Matches are spread across '
            'their courts when the schedule is generated.',
            style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          venuesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, _) => Text(
              'Could not load your venues: $e',
              style: const TextStyle(fontSize: 12, color: Ps.muted),
            ),
            data: (venues) {
              final usable = [
                for (final v in venues)
                  if (!v.isArchived) v,
              ];
              if (usable.isEmpty) {
                return const Text(
                  'No grounds saved yet. Add one below — a tournament with no '
                  'courts cannot be scheduled.',
                  style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
                );
              }
              return Column(
                children: [
                  for (final v in usable)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _venueIds.contains(v.id),
                      title: Text(
                        v.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Ps.ink,
                        ),
                      ),
                      subtitle: Text(
                        '${v.usableCourts.length} usable '
                        '${v.usableCourts.length == 1 ? "court" : "courts"}'
                        '${v.address == null ? "" : " · ${v.address}"}',
                        style: const TextStyle(fontSize: 12, color: Ps.muted),
                      ),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _venueIds.add(v.id);
                        } else {
                          _venueIds.remove(v.id);
                        }
                      }),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addVenue,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Add a ground & its courts'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addVenue() async {
    final draft = await showQuickAddVenueDialog(context, orgId: widget.orgId);
    if (draft == null || !mounted) return;
    try {
      final id = await ref.read(tournamentRepositoryProvider).createVenue(draft);
      if (!mounted) return;
      setState(() => _venueIds.add(id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save that ground: $e')),
      );
    }
  }

  Widget _settingsStep(BuildContext context) {
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WizardToggle(
            label: 'Live Scoring',
            help: 'Anyone with the link follows the match ball by ball',
            value: _liveScoring,
            onChanged: (v) => setState(() => _liveScoring = v),
          ),
          WizardToggle(
            label: 'Results Approval',
            help: 'A result is provisional until an organizer confirms it',
            value: _resultsApproval,
            onChanged: (v) => setState(() => _resultsApproval = v),
          ),
          WizardToggle(
            label: 'Points Table',
            help: 'Publish a standings table as matches finish',
            value: _pointsTable,
            onChanged: (v) => setState(() => _pointsTable = v),
          ),
          WizardToggle(
            label: 'Allow Withdrawal',
            help: 'Entrants can pull out before the draw is made',
            value: _allowWithdrawal,
            onChanged: (v) => setState(() => _allowWithdrawal = v),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep(BuildContext context) {
    final start = _startDate;
    final end = _endDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header the tournament will open with, artwork included — see
        // [SeasonBrandingPreview]. A tournament is one sport, so the
        // generated art behind an organizer who picked no banner is that
        // sport's, which is what the tournament page will show too.
        SeasonBrandingPreview(
          branding: _branding,
          name: _name.text,
          fallbackName: 'Untitled tournament',
          sportId: _sport.id,
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            children: [
              WizardReviewRow(label: 'Sport', value: _sport.name),
              WizardReviewRow(label: 'Category', value: _category.label),
              WizardReviewRow(label: 'Format', value: _format.label),
              if (GroupStageFields.isGrouped(_format, _draw))
                WizardReviewRow(
                  label: 'Groups',
                  value: GroupStageFields.summary(
                    format: _format,
                    entrantCount: _maxEntrants,
                    config: _draw,
                  ),
                ),
              WizardReviewRow(
                label: _sport.defaultEntrantType == EntrantType.team
                    ? 'Maximum teams'
                    : 'Maximum players',
                value: '$_maxEntrants',
              ),
              WizardReviewRow(
                label: 'Entry',
                value: _approvalRequired
                    ? 'Approval required'
                    : _participation.label,
              ),
              WizardReviewRow(
                label: 'Start date',
                value: start == null
                    ? 'Not set'
                    : DateFormat('d MMM yyyy').format(start),
              ),
              WizardReviewRow(
                label: 'End date',
                value:
                    end == null ? 'Not set' : DateFormat('d MMM yyyy').format(end),
              ),
              WizardReviewRow(
                label: 'Venue',
                value: _venue.text.trim().isEmpty
                    ? 'Not set'
                    : _venue.text.trim(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Says what pressing the button actually does. A tournament is created
        // as a draft — entries are not open until the organizer opens them —
        // and somebody who expects it to be live will wonder why nobody has
        // entered.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'This creates the tournament as a draft. Entries do not open '
            'until you open them on the next screen.',
            style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
        ),
      ],
    );
  }

  // --- Small shared pieces -------------------------------------------------

  static String _formatExplanation(CompetitionFormat format) =>
      switch (format) {
        CompetitionFormat.roundRobin =>
          'Everyone plays everyone. Fairest, and the most matches.',
        CompetitionFormat.knockout =>
          'Lose once and you are out. Fewest matches, shortest event.',
        CompetitionFormat.doubleElimination =>
          'Two losses to go out, so one bad match does not end an entry.',
        CompetitionFormat.groupThenKnockout =>
          'Groups first, then the top of each group play a knockout.',
        CompetitionFormat.swiss =>
          'Paired against whoever is on a similar record each round.',
        CompetitionFormat.leagueTable =>
          'A season-long table rather than a single event.',
        _ => '',
      };

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

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
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

/// A radio-style card, as the Participation Type step draws.
class _ParticipationChoice extends StatelessWidget {
  const _ParticipationChoice({
    required this.label,
    required this.help,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String help;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Ps.primary.withValues(alpha: 0.06) : Ps.surface,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          border: Border.all(color: selected ? Ps.primary : Ps.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? Ps.primary : Ps.faint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Ps.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    help,
                    style: const TextStyle(fontSize: 11.5, color: Ps.muted),
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

/// A number with minus and plus buttons either side.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return WizardField(
      label: label,
      required: required,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Ps.radiusSm),
                border: Border.all(color: Ps.border),
              ),
              child: Text(
                '$value',
                style: const TextStyle(fontSize: 14, color: Ps.ink),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StepButton(
            icon: Icons.remove,
            // Disabled at the bound rather than silently clamping, so the
            // control tells the truth about where the limit is.
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          const SizedBox(width: 6),
          _StepButton(
            icon: Icons.add,
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: Container(
        width: 42,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ps.radiusSm),
          border: Border.all(color: Ps.border),
          color: enabled ? Ps.surface : Ps.canvas,
        ),
        child: Icon(icon, size: 18, color: enabled ? Ps.ink : Ps.faint),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.hint,
    required this.onPick,
    this.firstDate,
  });

  final DateTime? value;
  final String hint;
  final DateTime? firstDate;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? firstDate ?? now,
          // Yesterday, not today: an organizer entering a tournament that
          // started this morning is a real and common case.
          firstDate: firstDate ?? now.subtract(const Duration(days: 1)),
          lastDate: now.add(const Duration(days: 365 * 3)),
        );
        if (picked != null) onPick(picked);
      },
      borderRadius: BorderRadius.circular(Ps.radiusSm),
      child: _FakeField(
        text: value == null ? hint : DateFormat('d MMM yyyy').format(value!),
        muted: value == null,
        icon: Icons.calendar_today_outlined,
      ),
    );
  }
}

/// A tappable box that looks like a text field but opens a picker.
class _FakeField extends StatelessWidget {
  const _FakeField({
    required this.text,
    this.muted = false,
    this.icon = Icons.schedule,
  });

  final String text;
  final bool muted;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              text,
              style: TextStyle(
                fontSize: 14,
                color: muted ? Ps.faint : Ps.ink,
              ),
            ),
          ),
          Icon(icon, size: 18, color: Ps.faint),
        ],
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
            icon: const Icon(Icons.add, size: 16),
            onPressed: value < max ? () => onChanged(value + step) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
