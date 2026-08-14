import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/competition.dart';
import '../../core/models/enums.dart';
import '../../core/models/tournament.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

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
  })  : format = SportCatalog.byId(sportId).competitionFormats.first,
        entries = TextEditingController();

  final String sportId;
  final SideFormat sideFormat;
  final CompetitionCategory category;

  /// Editable after the draft is added — an organizer picks the draw shape
  /// once they can see the whole season laid out, not while still choosing
  /// the sport.
  CompetitionFormat format;
  final TextEditingController entries;

  SportSpec get sport => SportCatalog.byId(sportId);

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

  /// Every sport/arrangement/category combination this season runs. Presence
  /// in this list is what "included" means, so the entries, format and
  /// category for one draw can never drift out of step with each other.
  final List<_CategoryDraft> _categories = [];

  DateTime? _startDate;
  DateTime? _endDate;
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

  Future<void> _addCategory() async {
    final draft = await showModalBottomSheet<_CategoryDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddCategorySheet(cutOff: _startDate),
    );
    if (draft == null) return;
    if (_categories.any(draft.clashesWith)) {
      if (mounted) {
        showError(
          context,
          '${draft.sport.name} · ${draft.sideFormat.name} · '
          '${draft.category.label} is already in this season.',
        );
      }
      draft.dispose();
      return;
    }
    setState(() => _categories.add(draft));
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
    // Defence in depth alongside the date pickers' own bounds: the pickers
    // stop these being chosen, this stops them being submitted if the device
    // clock moved on while the form sat open.
    if (start.isBefore(_earliestStart)) {
      showError(context, 'Start date must be at least tomorrow.');
      return;
    }
    final end = _endDate;
    if (end != null && end.isBefore(start)) {
      showError(context, 'End date cannot be before the start date.');
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      final tournaments = ref.read(tournamentRepositoryProvider);
      final competitions = ref.read(competitionRepositoryProvider);

      // The season container first: every event created below carries its id,
      // and an event pointing at a season that does not exist yet would be a
      // dangling reference for however long the writes take.
      final seasonId = await tournaments.createTournament(
        Tournament(
          id: '',
          orgId: widget.orgId,
          name: _name.text.trim(),
          status: TournamentStatus.draft,
          startDate: start,
          endDate: end ?? start,
          eventCount: _categories.length,
          createdBy: uid,
        ),
      );

      for (final draft in _categories) {
        final sport = draft.sport;
        // Only worth saying in the name when the sport actually has more
        // than one arrangement — cricket does not need "(11 a side)"
        // appended to every event when that is the only option it has.
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
            status: CompetitionStatus.draft,
            category: draft.category,
            scoringPluginKey: sport.pluginKey,
            // The arrangement's own rule tweaks — doubles' serve rotation,
            // a smaller side's player count — layered over the sport's
            // default preset. See [Competition.effectiveScoringConfig].
            scoringConfig: draft.sideFormat.configOverrides,
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

      // The sports above were created already attached, which is the one path
      // that bypasses `addEvent` and its increment. Without this the season
      // reports no events, and the rule that refuses to delete a tournament
      // with events in it stops protecting the ones it has.
      tournaments.noteEventsCreated(
        orgId: widget.orgId,
        tournamentId: seasonId,
        count: _categories.length,
      );

      if (mounted) {
        // Replace: the season exists now, and a back press should reach the
        // club rather than a form that would create a second copy.
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
                      labelText: 'Venue (optional)',
                      hintText: 'e.g. School grounds',
                      border: OutlineInputBorder(),
                    ),
                  ),
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
                      TextButton.icon(
                        onPressed: _addCategory,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  Text(
                    'Each one becomes its own draw with its own entry list — '
                    'add Badminton Singles and Badminton Doubles separately '
                    'if this season runs both.',
                    style: theme.textTheme.bodySmall,
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
}

/// One category already added to the season, shown with its format and
/// entry limit editable in place.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.draft,
    required this.onFormatChanged,
    required this.onRemove,
  });

  final _CategoryDraft draft;
  final ValueChanged<CompetitionFormat> onFormatChanged;
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
