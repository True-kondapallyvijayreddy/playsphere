import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/ui_kit.dart';
import '../../shared/wizard.dart';

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
  final _shortName = TextEditingController();
  final _venue = TextEditingController();

  SportSpec _sport = SportCatalog.byId('cricket');
  late CompetitionCategory _category = CompetitionCategory.presets().first;
  CompetitionFormat _format = CompetitionFormat.groupThenKnockout;
  ParticipationModel _participation = ParticipationModel.open;
  TeamEntryMode _teamEntryMode = TeamEntryMode.preformedTeam;
  final List<String> _presetHouses = ['Red House', 'Blue House', 'Green House', 'Yellow House'];

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
                  status: CompetitionStatus.registrationOpen,
                  category: _category,
                  scoringPluginKey: _sport.pluginKey,
                  teamEntryMode: _sport.defaultEntrantType == EntrantType.individual
                      ? TeamEntryMode.individual
                      : _teamEntryMode,
                  presetHouses: _presetHouses,
                  venue:
                      _venue.text.trim().isEmpty ? null : _venue.text.trim(),
                  startDate: _startsAt,
                  maxEntrants: _maxEntrants,
                  participationModel: _approvalRequired
                      ? ParticipationModel.approval
                      : _participation,
                  teamSize: _minSquad,
                  createdBy: uid,
                ),
              );
      if (!mounted) return;
      // Replace, not push: the tournament exists now, and a back press must
      // not land on a filled-in form that would create a second one.
      context.pushReplacement(Routes.competition(widget.orgId, compId));
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
        WizardStep(title: 'Schedule', builder: _scheduleStep),
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
                  help: 'Students register individually by selecting their House (Red, Blue, Green, Yellow)',
                  selected: _teamEntryMode == TeamEntryMode.houseBatch,
                  onTap: () => setState(
                    () => _teamEntryMode = TeamEntryMode.houseBatch,
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
        ],
      ),
    );
  }

  Widget _scheduleStep(BuildContext context) {
    return PsCard(
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
                // Keep the end on or after the start rather than validating
                // afterwards: an impossible range is easier to prevent than
                // to explain.
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
    );
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
        PsCard(
          child: Row(
            children: [
              SportBadge(sportId: _sport.id, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _name.text.trim().isEmpty
                      ? 'Untitled tournament'
                      : _name.text.trim(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Ps.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PsCard(
          child: Column(
            children: [
              WizardReviewRow(label: 'Sport', value: _sport.name),
              WizardReviewRow(label: 'Category', value: _category.label),
              WizardReviewRow(label: 'Format', value: _format.label),
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
