import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/draw_config.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/club_context_banner.dart';
import '../tournaments/widgets/venue_selector_dialog.dart'
    show showQuickAddVenueDialog;
import 'widgets/bulk_category_selector_sheet.dart';
import 'widgets/group_stage_fields.dart';

/// One configured entry in a season: a sport, played in one arrangement
/// (singles, doubles, 11-a-side...), for one age/gender category.
///
/// A season is not "sports", it is "categories" — a school sports week
/// genuinely runs Badminton Singles Boys U-14 *and* Badminton Doubles Open as
/// two separate draws with two separate entry lists, not one Badminton entry
/// that can only ever mean one of them. Each draft here becomes exactly one
/// [Competition] when the season is created, which is also what lets the
/// same sport appear twice — once per arrangement — instead of being capped
/// at one entry each.
class _CategoryDraft {
  _CategoryDraft({
    required this.sportId,
    required this.sideFormat,
    required this.category,
  })  : format = SportCatalog.byId(sportId).defaultCompetitionFormat,
        entries = TextEditingController();

  final String sportId;
  final SideFormat sideFormat;
  final CompetitionCategory category;

  /// Editable after the draft is added — an organizer picks the draw shape
  /// once they can see the whole season laid out, not while still choosing
  /// the sport.
  CompetitionFormat format;
  final TextEditingController entries;

  /// How this category's field is split up — groups, how many, and how many
  /// of each go through to the knockout.
  ///
  /// Editable here for the same reason [format] is, and it has to be: a
  /// season is drawn by `setUpWholeSeason`, which reads this off each
  /// competition and never opens the draw sheet where these were the only
  /// settable settings in the product.
  DrawConfig draw = const DrawConfig();

  SportSpec get sport => SportCatalog.byId(sportId);

  /// Entrants to plan the group split against. An organizer who left the
  /// entry limit blank has told us nothing, so a mid-sized field is assumed
  /// and re-clamped against the real one at draw time.
  int get plannedEntrants {
    final typed = int.tryParse(entries.text.trim());
    return (typed == null || typed < 2) ? 16 : typed;
  }

  /// The draw config as stored, clamped to what this format and field allow.
  DrawConfig get drawToSubmit => GroupStageFields.normalize(
        format: format,
        entrantCount: plannedEntrants,
        config: draw,
      );

  /// Whether [other] configures the same slot — same sport, same
  /// arrangement, same category — which would otherwise silently create two
  /// identical draws under one season with no way to tell them apart.
  bool clashesWith(_CategoryDraft other) =>
      sportId == other.sportId &&
      sideFormat.id == other.sideFormat.id &&
      category.label == other.category.label;

  void dispose() => entries.dispose();
}

/// Creating a multi-sport season (Feature #8).
///
/// ## What a season is, and why it is not just several tournaments
///
/// A school sports week, a village community's annual meet, a college's
/// inter-department calendar: one banner, several sports, each with its own
/// entry list, all sharing dates, a venue and a rest gap. The pieces already
/// existed — a [Tournament] is a container that events hang off, and each
/// sport is an ordinary [Competition] — but nothing put them together, so an
/// organizer had to create the container, then remember to open each sport
/// separately and attach it by hand.
///
/// This creates the whole thing in one pass: the season, plus one event per
/// category chosen, each carrying its own arrangement, its own age/gender
/// band and its own entry limit.
///
/// ## External entries
///
/// The one genuinely new setting. A school running its own sports day wants
/// its own students only; the same school hosting a zonal meet wants other
/// schools to enter and expects to approve them. That is the difference
/// between [ParticipationModel.open] within the club and
/// `openToNonMembers` with [ParticipationModel.approval], and it is asked as
/// the plain question an organizer actually has in mind.
class CreateSeasonScreen extends ConsumerStatefulWidget {
  const CreateSeasonScreen({super.key, required this.orgId});

  final String orgId;

  @override
  ConsumerState<CreateSeasonScreen> createState() => _CreateSeasonScreenState();
}

class _CreateSeasonScreenState extends ConsumerState<CreateSeasonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _venue = TextEditingController();
  final Set<String> _venueIds = {};

  /// Every sport/arrangement/category combination this season runs. Presence
  /// in this list is what "included" means, so the entries, format and
  /// category for one draw can never drift out of step with each other.
  final List<_CategoryDraft> _categories = [];

  DateTime? _startDate;
  DateTime? _endDate;

  /// The timetable's shape, captured here rather than left to defaults.
  ///
  /// These four numbers are what `generateSchedule` lays matches out with, and
  /// this screen used to write `ScheduleConfig(venueIds: ...)` and nothing
  /// else — so every season created from it ran on 30-minute matches between
  /// 09:00 and 19:00 whatever the sport and whatever hours the ground was
  /// actually available for. A hockey season and a table-tennis season are not
  /// the same match length, and an organizer finding that out from a generated
  /// timetable is finding out too late.
  int _matchMinutes = 30;
  int _changeoverMinutes = 5;
  int _restGapMinutes = 20;
  int _dayStartHour = 9;
  int _dayEndHour = 19;
  bool _externalEntries = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    for (final c in _categories) {
      c.dispose();
    }
    super.dispose();
  }

  /// The earliest a season is allowed to start: tomorrow.
  ///
  /// A season starting today gives entrants no notice at all, and a start
  /// date in the past is not a smaller season, it is a mistake. Bounding the
  /// date picker here means the wrong date is never offered in the first
  /// place, rather than being accepted and rejected on submit.
  static DateTime get _earliestStart {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day + 1);
  }

  /// Entries from outside the club must be approved, not auto-confirmed.
  ///
  /// The whole point of opening a season to other clubs is that the host
  /// decides who is in — an open model would let anyone who found the link
  /// confirm themselves a place in a school's meet.
  ParticipationModel get _participation =>
      _externalEntries ? ParticipationModel.approval : ParticipationModel.open;

  void _onStartDateChanged(DateTime picked) {
    setState(() {
      _startDate = picked;
      // The end date answers "and ends when" — once it is earlier than a
      // newly-picked start it is not a shorter season, it is nonsense, so it
      // is cleared rather than silently carried forward invalid.
      if (_endDate != null && _endDate!.isBefore(picked)) {
        _endDate = null;
      }
    });
  }

  Future<void> _addCategory({String? sportId}) async {
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
      if (_categories.any((c) =>
          c.sportId == draft.sportId &&
          c.sideFormat.id == draft.sideFormat.id &&
          c.category.label == draft.category.label)) {
        continue;
      }
      _categories.add(
        _CategoryDraft(
          sportId: draft.sportId,
          sideFormat: draft.sideFormat,
          category: draft.category,
        ),
      );
      addedCount++;
    }

    if (mounted) {
      setState(() {});
      if (addedCount < drafts.length) {
        showError(
          context,
          'Added $addedCount categories (${drafts.length - addedCount} were already in the list)',
        );
      }
    }
  }

  void _removeCategory(_CategoryDraft draft) {
    setState(() => _categories.remove(draft));
    draft.dispose();
  }

  int? _entriesFor(_CategoryDraft draft) {
    final text = draft.entries.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categories.isEmpty) {
      showError(context, 'Add at least one category for this season.');
      return;
    }
    final start = _startDate;
    if (start == null) {
      showError(context, 'Pick a start date.');
      return;
    }
    if (start.isBefore(_earliestStart)) {
      showError(context, 'Start date must be at least tomorrow.');
      return;
    }
    final end = _endDate;
    if (end != null && end.isBefore(start)) {
      showError(context, 'End date cannot be before the start date.');
      return;
    }
    // A season with no ground cannot be scheduled at all — `generateSchedule`
    // resolves its courts from these venue documents and refuses when there
    // are none. Caught here, at creation, rather than weeks later when
    // somebody presses the only button that would have told them.
    if (_venueIds.isEmpty) {
      showError(
        context,
        'Pick at least one ground. Matches are scheduled onto their courts.',
      );
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final tournaments = ref.read(tournamentRepositoryProvider);
      final competitions = ref.read(competitionRepositoryProvider);

      // The season container is automatically created OPEN for entries
      final seasonId = await tournaments.createTournament(
        Tournament(
          id: '',
          orgId: widget.orgId,
          name: _name.text.trim(),
          status: TournamentStatus.entriesOpen,
          startDate: start,
          endDate: end ?? start,
          venueIds: _venueIds.toList(),
          eventCount: _categories.length,
          createdBy: uid,
        ),
      );

      for (final draft in _categories) {
        final sport = draft.sport;
        final showsArrangement = sport.sideFormats.length > 1;
        await competitions.createCompetition(
          Competition(
            id: '',
            orgId: widget.orgId,
            tournamentId: seasonId,
            name: showsArrangement
                ? '${_name.text.trim()} — ${sport.name} '
                    '(${draft.sideFormat.name})'
                : '${_name.text.trim()} — ${sport.name}',
            sportId: sport.id,
            sportName: sport.name,
            archetype: sport.archetype,
            entrantType: sport.defaultEntrantType,
            format: draft.format,
            status: CompetitionStatus.registrationOpen,
            category: draft.category,
            scoringPluginKey: sport.pluginKey,
            scoringConfig: draft.sideFormat.configOverrides,
            drawConfig: draft.drawToSubmit,
            scheduleConfig: ScheduleConfig(
              venueIds: _venueIds.toList(),
              matchMinutes: _matchMinutes,
              changeoverMinutes: _changeoverMinutes,
              restGapMinutes: _restGapMinutes,
              dayStartHour: _dayStartHour,
              dayEndHour: _dayEndHour,
            ),
            venue: _venue.text.trim().isEmpty ? null : _venue.text.trim(),
            startDate: start,
            maxEntrants: _entriesFor(draft),
            participationModel: _participation,
            waitlistEnabled: true,
            openToNonMembers: _externalEntries,
            createdBy: uid,
          ),
        );
      }

      tournaments.noteEventsCreated(
        orgId: widget.orgId,
        tournamentId: seasonId,
        count: _categories.length,
      );

      if (mounted) {
        context.pushReplacement(Routes.tournament(widget.orgId, seasonId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      orgId: widget.orgId,
      title: 'New season',
      subtitle: 'Several sports on one calendar',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ContentBounds(
            maxWidth: 640,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  ClubContextBanner(orgId: widget.orgId),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Season name',
                      hintText: 'e.g. Nizampet Sports Week 2026',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'At least 3 characters'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  _DateField(
                    label: 'Starts',
                    helper: 'Ages are measured on this date. Must be at '
                        'least tomorrow.',
                    value: _startDate,
                    firstSelectableDate: _earliestStart,
                    onPick: _onStartDateChanged,
                  ),
                  const SizedBox(height: 20),
                  _DateField(
                    label: 'Ends (optional)',
                    helper: 'Leave blank for a one-day season',
                    value: _endDate,
                    firstSelectableDate: _startDate ?? _earliestStart,
                    onPick: (d) => setState(() => _endDate = d),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _venue,
                    decoration: const InputDecoration(
                      labelText: 'Venue label (optional)',
                      hintText: 'e.g. School grounds',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _venuePicker(context),
                  const SizedBox(height: 16),
                  _timingsCard(context),
                  const SizedBox(height: 28),

                  // ---- Categories -----------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Categories',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _addCategory(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Categories (+)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pick any sport and choose multiple arrangements, age bands, and equipment all at once.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  // Quick sport shortcuts with '+' buttons
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final sport in SportCatalog.all.take(8))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: Text(sport.icon),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(sport.name),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.add_circle_outline, size: 16),
                                ],
                              ),
                              onPressed: () => _addCategory(sportId: sport.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_categories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No categories yet — add at least one.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    )
                  else
                    for (final draft in _categories)
                      _CategoryCard(
                        key: ObjectKey(draft),
                        draft: draft,
                        onFormatChanged: (f) =>
                            setState(() => draft.format = f),
                        onDrawChanged: (d) => setState(() => draft.draw = d),
                        onRemove: () => _removeCategory(draft),
                      ),
                  const SizedBox(height: 28),

                  // ---- Who may enter -------------------------------------
                  Text('Who may enter', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _externalEntries,
                    onChanged: (v) => setState(() => _externalEntries = v),
                    title: const Text('Allow entries from outside this club'),
                    subtitle: Text(
                      _externalEntries
                          ? 'Anyone can apply, and every entry waits for you '
                              'to approve it.'
                          : 'Only members of this club can enter, and they '
                              'are confirmed straight away.',
                    ),
                  ),
                  const SizedBox(height: 28),

                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _categories.isEmpty
                          ? 'Create season'
                          : 'Create season with ${_categories.length} '
                              '${_categories.length == 1 ? 'category' : 'categories'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Match length, the gap between matches, the rest a side is owed, and the
  /// hours the ground is open. Everything `generateSchedule` needs to lay a
  /// day out, asked for once, where the person setting up the season already
  /// is.
  Widget _timingsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Match timings',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            const Text(
              'Used to build the timetable. A match plus its changeover is '
              'the spacing between two matches on the same court.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MinutesField(
                    label: 'Match length',
                    value: _matchMinutes,
                    min: 5,
                    max: 240,
                    step: 5,
                    onChanged: (v) => setState(() => _matchMinutes = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MinutesField(
                    label: 'Changeover',
                    value: _changeoverMinutes,
                    min: 0,
                    max: 30,
                    step: 5,
                    onChanged: (v) => setState(() => _changeoverMinutes = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MinutesField(
                    label: 'Rest between a side\'s matches',
                    value: _restGapMinutes,
                    min: 0,
                    max: 120,
                    step: 5,
                    onChanged: (v) => setState(() => _restGapMinutes = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HoursField(
                    startHour: _dayStartHour,
                    endHour: _dayEndHour,
                    onChanged: (start, end) => setState(() {
                      _dayStartHour = start;
                      _dayEndHour = end;
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _venuePicker(BuildContext context) {
    final venuesAsync = ref.watch(venuesProvider(widget.orgId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Grounds & Courts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                if (_venueIds.isEmpty)
                  Text(
                    'Required',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Pick every ground this season may use. Matches are allocated across their courts.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 10),
            venuesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Text(
                'Could not load grounds: $e',
                style: const TextStyle(fontSize: 12),
              ),
              data: (venues) {
                final usable = [
                  for (final v in venues)
                    if (!v.isArchived) v,
                ];
                if (usable.isEmpty) {
                  return const Text(
                    'No grounds saved yet. Add one below.',
                    style: TextStyle(fontSize: 12, height: 1.4),
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
                          ),
                        ),
                        subtitle: Text(
                          '${v.usableCourts.length} usable '
                          '${v.usableCourts.length == 1 ? "court" : "courts"}'
                          '${v.address == null ? "" : " · ${v.address}"}',
                          style: const TextStyle(fontSize: 12),
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
            ),
          ],
        ),
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
}

/// One category already added to the season, shown with its format and
/// entry limit editable in place.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.draft,
    required this.onFormatChanged,
    required this.onDrawChanged,
    required this.onRemove,
  });

  final _CategoryDraft draft;
  final ValueChanged<CompetitionFormat> onFormatChanged;
  final ValueChanged<DrawConfig> onDrawChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sport = draft.sport;
    final showsArrangement = sport.sideFormats.length > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${sport.icon}  ${sport.name}',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (showsArrangement) _Chip(draft.sideFormat.name),
                      if (!draft.category.isOpen) _Chip(draft.category.label),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<CompetitionFormat>(
                    value: draft.format,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final f in sport.competitionFormats)
                        DropdownMenuItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (f) {
                      if (f != null) onFormatChanged(f);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: draft.entries,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Entries',
                      hintText: 'Any',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null;
                      final n = int.tryParse(t);
                      return (n == null || n < 1) ? 'No' : null;
                    },
                  ),
                ),
              ],
            ),
            GroupStageFields(
              format: draft.format,
              entrantCount: draft.plannedEntrants,
              config: draft.draw,
              onChanged: onDrawChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// Asks the questions that fully describe one season category, in the order
/// an organizer actually thinks in: which sport, then which arrangement it
/// is played in (skipped entirely when the sport only has one), then which
/// age/gender band it is for.
class _AddCategorySheet extends StatefulWidget {
  const _AddCategorySheet({required this.cutOff});

  /// The season's start date, so age presets are measured against it rather
  /// than today — a U-14 category should not silently mean something
  /// different depending on when the organizer happened to build the season.
  final DateTime? cutOff;

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  late SportSpec _sport = SportCatalog.all.first;
  late SideFormat _sideFormat = _sport.defaultSideFormat;
  late final List<CompetitionCategory> _presets =
      CompetitionCategory.presets(cutOff: widget.cutOff);
  late CompetitionCategory _category = _presets.first;

  void _pickSport(String id) {
    setState(() {
      _sport = SportCatalog.byId(id);
      _sideFormat = _sport.defaultSideFormat;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showsArrangement = _sport.sideFormats.length > 1;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a category', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _sport.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sport',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in SportCatalog.all)
                DropdownMenuItem(
                  value: s.id,
                  child: Text('${s.icon}  ${s.name}'),
                ),
            ],
            onChanged: (id) {
              if (id != null) _pickSport(id);
            },
          ),
          const SizedBox(height: 16),

          if (showsArrangement) ...[
            DropdownButtonFormField<String>(
              value: _sideFormat.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sport type',
                helperText: 'How this category is played',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final f in _sport.sideFormats)
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (id) {
                if (id == null) return;
                setState(
                  () => _sideFormat =
                      _sport.sideFormats.firstWhere((f) => f.id == id),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          DropdownButtonFormField<String>(
            value: _category.label,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in _presets)
                DropdownMenuItem(value: c.label, child: Text(c.label)),
            ],
            onChanged: (label) => setState(
              () => _category = _presets.firstWhere((c) => c.label == label),
            ),
          ),
          const SizedBox(height: 20),

          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _CategoryDraft(
                sportId: _sport.id,
                sideFormat: _sideFormat,
                category: _category,
              ),
            ),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Add category'),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.helper,
    required this.value,
    required this.onPick,
    this.firstSelectableDate,
  });

  final String label;
  final String helper;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  /// Earliest date the picker will offer. This is what actually enforces
  /// "start date is at least tomorrow" and "end date is not before the
  /// start date" — the wheel simply never shows anything earlier, rather
  /// than accepting a bad date and rejecting it after the fact.
  final DateTime? firstSelectableDate;

  @override
  Widget build(BuildContext context) {
    final first = firstSelectableDate ?? DateTime.now();
    return InkWell(
      onTap: () async {
        final initial =
            value != null && !value!.isBefore(first) ? value! : first;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: DateTime(first.year + 3),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          value == null ? 'Not set' : DateFormat('d MMMM yyyy').format(value!),
        ),
      ),
    );
  }
}

/// A minutes value with a label and a pair of steppers.
///
/// A stepper rather than a text field: every one of these is a round number
/// in practice, a free-text minute count invites "1hr" and "45 mins" to be
/// typed into an int field, and on a phone a stepper is two taps against a
/// keyboard, a selection and a dismiss.
class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: value > min ? () => onChanged(value - step) : null,
              ),
              Text(
                '$value min',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: value < max ? () => onChanged(value + step) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The window a ground is available each day.
///
/// Stored as two whole hours because that is what `ScheduleConfig` holds, so
/// the picker opens in its keyboard mode — a dial that accepts 09:37 for a
/// field that keeps only the 9 is a control that lies about what it saved.
class _HoursField extends StatelessWidget {
  const _HoursField({
    required this.startHour,
    required this.endHour,
    required this.onChanged,
  });

  final int startHour;
  final int endHour;
  final void Function(int start, int end) onChanged;

  static String _label(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: isStart ? startHour : endHour, minute: 0),
      helpText: isStart ? 'Play may start from' : 'Play must finish by',
      initialEntryMode: TimePickerEntryMode.inputOnly,
    );
    if (picked == null) return;

    var start = isStart ? picked.hour : startHour;
    var end = isStart ? endHour : picked.hour;
    // Kept in order, by moving the other end rather than rejecting the entry
    // — a day that finishes before it starts has no slots in it at all.
    if (end <= start) {
      if (isStart) {
        end = start + 1 > 23 ? 23 : start + 1;
      } else {
        start = end - 1 < 0 ? 0 : end - 1;
      }
    }
    onChanged(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ground hours', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => _pick(context, isStart: true),
                child: Text(
                  _label(startHour),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('–'),
              ),
              InkWell(
                onTap: () => _pick(context, isStart: false),
                child: Text(
                  _label(endHour),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
