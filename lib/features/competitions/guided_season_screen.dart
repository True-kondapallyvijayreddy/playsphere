import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/ui_kit.dart';
import '../../shared/wizard.dart';

/// One sport in a season, in one arrangement.
///
/// A thinner cousin of `CreateSeasonScreen`'s `_CategoryDraft`. That screen
/// lets an organizer add the same sport twice under different age bands,
/// because a school sports week genuinely runs Badminton Singles Boys U-14
/// and Badminton Doubles Open as two separate draws. This flow deliberately
/// does not: a guided path that opens with "you may add the same sport more
/// than once" is a guided path nobody finishes. Someone who needs that runs
/// the one-page form, which is still one tap away.
class _SeasonSport {
  _SeasonSport(this.sportId)
      : sideFormat = SportCatalog.byId(sportId).defaultSideFormat,
        format = SportCatalog.byId(sportId).competitionFormats.first,
        maxEntrants = 16;

  final String sportId;
  SideFormat sideFormat;
  CompetitionFormat format;
  int maxEntrants;

  SportSpec get sport => SportCatalog.byId(sportId);
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
/// - **Venues & Locations** offers several venues with photographs, each
///   assigned to particular sports. A [Competition] carries a single `venue`
///   string and no photograph, so this asks for one venue for the season.
///   Per-sport venues would be a schema change, not a screen.
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

  final List<_SeasonSport> _sports = [];

  DateTime? _startDate;
  DateTime? _endDate;

  bool _externalEntries = false;
  bool _liveScoring = true;
  bool _leaderboard = true;
  bool _playerStats = true;
  bool _resultsApproval = false;
  bool _allowProtests = false;

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _shortName.dispose();
    _organizer.dispose();
    _venue.dispose();
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

  Future<void> _submit() async {
    final uid = ref.read(currentUidProvider);
    final start = _startDate;
    if (uid == null || start == null || _sports.isEmpty) return;

    setState(() => _busy = true);
    try {
      final tournaments = ref.read(tournamentRepositoryProvider);
      final competitions = ref.read(competitionRepositoryProvider);
      final end = _endDate ?? start;

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
          eventCount: _sports.length,
          createdBy: uid,
        ),
      );

      for (final entry in _sports) {
        final sport = entry.sport;
        // Worth naming the arrangement only when the sport has more than one
        // — cricket does not need "(11 a side)" appended when that is its
        // only option.
        final showsArrangement = sport.sideFormats.length > 1;
        await competitions.createCompetition(
          Competition(
            id: '',
            orgId: widget.orgId,
            tournamentId: seasonId,
            name: showsArrangement
                ? '${_name.text.trim()} — ${sport.name} '
                    '(${entry.sideFormat.name})'
                : '${_name.text.trim()} — ${sport.name}',
            sportId: sport.id,
            sportName: sport.name,
            archetype: sport.archetype,
            entrantType: sport.defaultEntrantType,
            format: entry.format,
            status: CompetitionStatus.draft,
            category: CompetitionCategory.presets().first,
            scoringPluginKey: sport.pluginKey,
            scoringConfig: entry.sideFormat.configOverrides,
            venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
            startDate: start,
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

      if (!mounted) return;
      context.pushReplacement(Routes.tournament(widget.orgId, seasonId));
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
          subtitle: 'Choose the sports this season runs',
          // A season with no sports is a container with nothing in it — the
          // one-page form rejects this on submit, and blocking here means it
          // is never reachable.
          canAdvance: () => _sports.isNotEmpty,
          builder: _sportsStep,
        ),
        WizardStep(
          title: 'Competition Structure',
          subtitle: 'Set the draw shape and entry limit for each sport',
          builder: _structureStep,
        ),
        WizardStep(
          title: 'Schedule',
          canAdvance: () => _startDate != null,
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _StorageNotice(),
      ],
    );
  }

  Widget _sportsStep(BuildContext context) {
    return PsCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final spec in SportCatalog.versusSports)
            _SportCheckRow(
              spec: spec,
              selected: _sports.any((s) => s.sportId == spec.id),
              onChanged: (on) => setState(() {
                if (on) {
                  _sports.add(_SeasonSport(spec.id));
                } else {
                  _sports.removeWhere((s) => s.sportId == spec.id);
                }
              }),
            ),
        ],
      ),
    );
  }

  Widget _structureStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in _sports) ...[
          PsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SportBadge(sportId: entry.sportId, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.sport.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Ps.ink,
                        ),
                      ),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
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
                label: 'Venue',
                child: TextField(
                  controller: _venue,
                  decoration: _input('Green Field Ground'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'One venue for the season. Assigning a different ground to each '
            'sport is not supported yet — an event carries a single venue.',
            style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
        ),
      ],
    );
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
      ],
    );
  }

  Widget _reviewStep(BuildContext context) {
    final start = _startDate;
    final end = _endDate;
    final entrants = _sports.fold<int>(0, (sum, s) => sum + s.maxEntrants);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PsCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Ps.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Ps.radiusSm),
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Ps.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _name.text.trim().isEmpty
                      ? 'Untitled season'
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
              WizardReviewRow(label: 'Sports', value: '${_sports.length}'),
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
                    children: [
                      SportBadge(sportId: entry.sportId, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.sport.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Ps.ink,
                          ),
                        ),
                      ),
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
            'The season and its events are created as drafts. Entries do not '
            'open until you open them.',
            style: TextStyle(fontSize: 12, color: Ps.muted, height: 1.4),
          ),
        ),
      ],
    );
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

/// A sport with a checkbox, as the Select Sports step is built from.
class _SportCheckRow extends StatelessWidget {
  const _SportCheckRow({
    required this.spec,
    required this.selected,
    required this.onChanged,
  });

  final SportSpec spec;
  final bool selected;
  final ValueChanged<bool> onChanged;

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
              child: Text(
                spec.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Ps.ink,
                ),
              ),
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
class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.value,
    required this.hint,
    required this.firstDate,
    required this.onPick,
  });

  final DateTime? value;
  final String hint;
  final DateTime firstDate;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? firstDate,
          firstDate: firstDate,
          lastDate: firstDate.add(const Duration(days: 365 * 3)),
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
