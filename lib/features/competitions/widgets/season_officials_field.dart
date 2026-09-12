import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/organization.dart';
import '../../../core/models/tournament_official.dart';
import '../../../core/models/umpire_profile.dart';
import '../../../core/providers.dart';
import '../../../data/tournament_repository.dart';
import '../../../domain/draw/draft_season_plan.dart';
import '../../../domain/draw/officials_coverage.dart';
import '../../../domain/scoring/scoring_registry.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';

/// The officiating panel a season is being created with.
///
/// Staged for the same reason the grounds and the artwork are: the panel is
/// decided while the season is being written and the roster lives at
/// `tournaments/{id}/officials`, which does not exist yet. [commit] writes it
/// the moment the season has an id.
///
/// ## Why the panel is asked for at creation and not afterwards
///
/// It was only ever asked for afterwards, on a screen an organizer reached by
/// opening the season they had just made and finding the officials tab. The
/// Play Store feedback is what that costs: seasons went out with no panel,
/// and the assigner — which is good, and which respects sport, availability
/// and neutrality — had nothing to assign. Nothing about an umpire is harder
/// to state on the create form than a ground is.
class SeasonOfficialsDraft extends ChangeNotifier {
  final List<TournamentOfficial> _officials = [];

  List<TournamentOfficial> get officials => List.unmodifiable(_officials);

  bool get isEmpty => _officials.isEmpty;

  bool contains(String uid) => _officials.any((o) => o.uid == uid);

  void add(TournamentOfficial official) {
    if (contains(official.uid)) return;
    _officials.add(official);
    notifyListeners();
  }

  void replace(TournamentOfficial official) {
    final i = _officials.indexWhere((o) => o.uid == official.uid);
    if (i < 0) return;
    _officials[i] = official;
    notifyListeners();
  }

  void remove(String uid) {
    _officials.removeWhere((o) => o.uid == uid);
    notifyListeners();
  }

  /// Writes the panel onto the season that now exists.
  ///
  /// Reports rather than throws, like the artwork upload: the season and its
  /// events are already written by the time this runs, and losing them
  /// because one roster row was refused would be far worse than an organizer
  /// re-adding a name on the officials screen.
  Future<String?> commit({
    required TournamentRepository repo,
    required String orgId,
    required String tournamentId,
    required String addedByUid,
  }) async {
    final failed = <String>[];
    for (final official in _officials) {
      try {
        await repo.addOfficialToRoster(
          orgId: orgId,
          tournamentId: tournamentId,
          official: official,
          addedByUid: addedByUid,
        );
      } catch (_) {
        failed.add(official.name);
      }
    }
    if (failed.isEmpty) return null;
    return 'The season was created, but ${failed.join(', ')} could not be '
        'added to the panel. Add them from the season\'s Officials screen.';
  }
}

/// The officials step of season creation.
class SeasonOfficialsField extends ConsumerWidget {
  const SeasonOfficialsField({
    super.key,
    required this.orgId,
    required this.draft,
    required this.events,
    required this.days,
    required this.onChanged,
    this.seasonStart,
    this.seasonEnd,
  });

  final String orgId;
  final SeasonOfficialsDraft draft;
  final List<SeasonEventPlan> events;
  final List<SeasonDayLoad> days;
  final VoidCallback onChanged;
  final DateTime? seasonStart;
  final DateTime? seasonEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coverage = OfficialsCoverage.of(
      panel: draft.officials,
      events: events,
      days: days,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Match officials', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Optional, and much easier now than on match day. Say who can '
              'come, which sports they take and which days — the season will '
              'assign them across the timetable for you.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            for (final official in draft.officials)
              _OfficialRow(
                official: official,
                seasonStart: seasonStart,
                seasonEnd: seasonEnd,
                onEdit: (updated) {
                  draft.replace(updated);
                  onChanged();
                },
                onRemove: () {
                  draft.remove(official.uid);
                  onChanged();
                },
              ),

            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: Text(
                draft.isEmpty ? 'Add an official' : 'Add another official',
              ),
            ),

            if (!coverage.isEmpty) ...[
              const SizedBox(height: 12),
              _CoverageStrip(coverage: coverage, panelSize: draft.officials.length),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final sportIds = <String>{for (final e in events) e.sportId};
    final added = await showModalBottomSheet<TournamentOfficial>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AddOfficialSheet(
        orgId: orgId,
        seasonSportIds: sportIds.toList(),
        seasonStart: seasonStart,
        seasonEnd: seasonEnd,
        alreadyOn: {for (final o in draft.officials) o.uid},
      ),
    );
    if (added == null) return;
    draft.add(added);
    onChanged();
  }
}

class _OfficialRow extends StatelessWidget {
  const _OfficialRow({
    required this.official,
    required this.onEdit,
    required this.onRemove,
    this.seasonStart,
    this.seasonEnd,
  });

  final TournamentOfficial official;
  final ValueChanged<TournamentOfficial> onEdit;
  final VoidCallback onRemove;
  final DateTime? seasonStart;
  final DateTime? seasonEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sports = official.sports.isEmpty
        ? 'Any sport'
        : [for (final s in official.sports) SportCatalog.byId(s).name].join(', ');
    final dates = official.availableDates.isEmpty
        ? 'Every day'
        : '${official.availableDates.length} '
            '${official.availableDates.length == 1 ? "day" : "days"}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        official.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (isGuestOfficial(official.uid)) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Guest',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$sports · $dates · up to ${official.maxMatchesPerDay}/day'
                  '${official.scoringRightsGranted ? " · can score" : ""}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Availability',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_calendar_outlined, size: 18),
            onPressed: () async {
              final updated = await showModalBottomSheet<TournamentOfficial>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => OfficialAvailabilitySheet(
                  official: official,
                  seasonStart: seasonStart,
                  seasonEnd: seasonEnd,
                  sportIds: const [],
                ),
              );
              if (updated != null) onEdit(updated);
            },
          ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CoverageStrip extends StatelessWidget {
  const _CoverageStrip({required this.coverage, required this.panelSize});

  final OfficialsCoverage coverage;
  final int panelSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (panelSize == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Ps.radiusSm),
        ),
        child: Text(
          '${coverage.matches} matches will need an official. You can add '
          'the panel later from the season page — but a season created with '
          'one has its umpires assigned the moment the timetable is built.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final ok = coverage.fits;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok
            ? const Color(0x1A2E7D32)
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: ok
                    ? const Color(0xFF2E7D32)
                    : theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? 'The panel covers the season'
                      : coverage.uncoveredSports.isNotEmpty
                          ? 'Nobody covers '
                              '${coverage.uncoveredSports.join(", ")}'
                          : 'Short by ${coverage.shortfall} matches',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$panelSize on the panel · ${coverage.capacity} match-slots '
            'against ${coverage.matches} matches',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Finds somebody to officiate, four ways, and asks the three things the
/// assigner needs before it can use them.
///
/// ## Why availability is asked here and not later
///
/// "Which sport, which days, how many matches" were editable only from a
/// second sheet on the officials screen, so the overwhelmingly common panel
/// was a list of names with no constraints at all — which the assigner reads
/// as "anyone, any sport, any day, eight a day". That is how a badminton
/// umpire ends up on the kabaddi final. Asked once, while the organizer is
/// thinking about that person, it costs three taps.
class AddOfficialSheet extends ConsumerStatefulWidget {
  const AddOfficialSheet({
    super.key,
    required this.orgId,
    this.seasonSportIds = const [],
    this.seasonStart,
    this.seasonEnd,
    this.alreadyOn = const {},
  });

  final String orgId;

  /// The sports this season runs, offered as the tick list. A panel is built
  /// for this season, so offering the whole catalogue would be offering
  /// mostly wrong answers.
  final List<String> seasonSportIds;

  final DateTime? seasonStart;
  final DateTime? seasonEnd;
  final Set<String> alreadyOn;

  @override
  ConsumerState<AddOfficialSheet> createState() => _AddOfficialSheetState();
}

class _AddOfficialSheetState extends ConsumerState<AddOfficialSheet> {
  final _search = TextEditingController();
  final _guestName = TextEditingController();
  final _code = TextEditingController();

  bool _searchingRegistry = false;
  bool _lookingUpCode = false;
  List<UmpireProfile> _registry = const [];
  String? _codeError;

  @override
  void dispose() {
    _search.dispose();
    _guestName.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = ref.watch(orgMembersProvider(widget.orgId)).valueOrNull ??
        const <Membership>[];
    final query = _search.text.trim().toLowerCase();
    final memberMatches = query.isEmpty
        ? const <Membership>[]
        : [
            for (final m in members)
              if (m.isActive &&
                  !widget.alreadyOn.contains(m.uid) &&
                  m.displayName.toLowerCase().contains(query))
                m,
          ].take(6).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add an official', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'By name, by PlaySphere ID, from the umpire registry, or as '
                'a guest who has never opened the app.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // --- By name, across this club -------------------------------
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search this club by name',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              for (final m in memberMatches)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text(m.displayName),
                  trailing: TextButton(
                    onPressed: () => _pick(
                      uid: m.uid,
                      name: m.displayName,
                      clubId: widget.orgId,
                    ),
                    child: const Text('Choose'),
                  ),
                ),

              const SizedBox(height: 16),

              // --- By PlaySphere ID ----------------------------------------
              //
              // The code a player reads down a phone line. An umpire from
              // another club has no membership here to be found by name, and
              // this is how everything else in the product adds one.
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'PlaySphere ID',
                  hintText: 'e.g. 7KQ2-M914',
                  errorText: _codeError,
                  prefixIcon: const Icon(Icons.badge_outlined),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _lookingUpCode
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                        tooltip: 'Next',
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: _lookUpCode,
                        ),
                ),
                onSubmitted: (_) => _lookUpCode(),
              ),

              const SizedBox(height: 16),

              // --- From the open registry ----------------------------------
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Certified umpires',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (_searchingRegistry)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sportId in widget.seasonSportIds)
                    ActionChip(
                      label: Text(SportCatalog.byId(sportId).name),
                      onPressed: () => _searchRegistry(sportId),
                    ),
                  if (widget.seasonSportIds.isEmpty)
                    const _Muted('Add a category first to search the registry'),
                ],
              ),
              for (final u in _registry)
                if (!widget.alreadyOn.contains(u.uid))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(u.displayName),
                    subtitle: Text(u.sports.join(', ')),
                    trailing: TextButton(
                      onPressed: () => _pick(
                        uid: u.uid,
                        name: u.displayName,
                        sports: u.sports,
                      ),
                      child: const Text('Choose'),
                    ),
                  ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // --- As a guest ----------------------------------------------
              Text('Or add a guest', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                'Somebody with no PlaySphere account. They can be assigned '
                'to matches and named on the sheet; they cannot be sent '
                'notifications.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _guestName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Their name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _guestName.text.trim().isEmpty
                        ? null
                        : () => _pick(
                              uid: newGuestOfficialId(),
                              name: _guestName.text.trim(),
                            ),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _searchRegistry(String sportId) async {
    setState(() => _searchingRegistry = true);
    try {
      final found =
          await ref.read(umpireRepositoryProvider).fetchUmpiresForSport(sportId);
      if (mounted) setState(() => _registry = found);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searchingRegistry = false);
    }
  }

  Future<void> _lookUpCode() async {
    final typed = _code.text.trim();
    if (typed.isEmpty) return;
    setState(() {
      _lookingUpCode = true;
      _codeError = null;
    });
    try {
      final found = await ref.read(userRepositoryProvider).findByPlayerCode(typed);
      if (!mounted) return;
      if (found == null) {
        setState(() => _codeError = 'No player with that ID.');
        return;
      }
      if (widget.alreadyOn.contains(found.uid)) {
        setState(() => _codeError = '${found.displayName} is already on the '
            'panel.');
        return;
      }
      await _pick(uid: found.uid, name: found.displayName);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _lookingUpCode = false);
    }
  }

  /// Whoever was chosen, then the three questions the assigner needs.
  Future<void> _pick({
    required String uid,
    required String name,
    List<String> sports = const [],
    String? clubId,
  }) async {
    // Their registry sports, narrowed to what this season actually runs —
    // a cricket umpire in a season with no cricket covers nothing here.
    final seasonSports = widget.seasonSportIds.toSet();
    final relevant = [
      for (final s in sports)
        if (seasonSports.contains(s)) s,
    ];

    final configured = await showModalBottomSheet<TournamentOfficial>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => OfficialAvailabilitySheet(
        official: TournamentOfficial(
          uid: uid,
          name: name,
          sports: relevant,
          clubId: clubId,
        ),
        sportIds: widget.seasonSportIds,
        seasonStart: widget.seasonStart,
        seasonEnd: widget.seasonEnd,
      ),
    );
    if (configured == null || !mounted) return;
    Navigator.of(context).pop(configured);
  }
}

/// "Which sports, which days, how many a day" — asked once, about one person.
class OfficialAvailabilitySheet extends StatefulWidget {
  const OfficialAvailabilitySheet({
    super.key,
    required this.official,
    required this.sportIds,
    this.seasonStart,
    this.seasonEnd,
  });

  final TournamentOfficial official;
  final List<String> sportIds;
  final DateTime? seasonStart;
  final DateTime? seasonEnd;

  @override
  State<OfficialAvailabilitySheet> createState() =>
      _OfficialAvailabilitySheetState();
}

class _OfficialAvailabilitySheetState extends State<OfficialAvailabilitySheet> {
  late final Set<String> _sports = {...widget.official.sports};
  late final Set<String> _days = {...widget.official.availableDates};
  late int _maxPerDay = widget.official.maxMatchesPerDay;
  late bool _canScore = widget.official.scoringRightsGranted;
  late String _role = widget.official.role;

  static const _roles = <String, String>{
    'main_umpire': 'Umpire / referee',
    'square_leg_umpire': 'Square leg umpire',
    'third_umpire': 'Third umpire',
    'referee': 'Match referee',
    'linesman': 'Linesman',
  };

  List<DateTime> get _seasonDays {
    final start = widget.seasonStart;
    if (start == null) return const [];
    final first = DateTime(start.year, start.month, start.day);
    final end = widget.seasonEnd;
    final last = end == null ? first : DateTime(end.year, end.month, end.day);
    final count = last.difference(first).inDays + 1;
    if (count < 1 || count > 60) return [first];
    return [
      for (var i = 0; i < count; i++)
        DateTime(first.year, first.month, first.day + i),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayFormat = DateFormat('EEE d MMM');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.official.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'What they will take, and when they can come.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              if (widget.sportIds.isNotEmpty) ...[
                Text('Sports they will officiate',
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sportId in widget.sportIds)
                      FilterChip(
                        label: Text(SportCatalog.byId(sportId).name),
                        selected: _sports.contains(sportId),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _sports.add(sportId);
                          } else {
                            _sports.remove(sportId);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _sports.isEmpty
                      ? 'None ticked means any sport in this season.'
                      : 'They will only be put on these.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
              ],

              if (_seasonDays.isNotEmpty) ...[
                Text('Days they can come', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final day in _seasonDays)
                      FilterChip(
                        label: Text(dayFormat.format(day)),
                        selected: _days.contains(_key(day)),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _days.add(_key(day));
                          } else {
                            _days.remove(_key(day));
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _days.isEmpty
                      ? 'None ticked means every day of the season.'
                      : 'They will not be given a match on any other day.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
              ],

              DropdownButtonFormField<String>(
                value: _roles.containsKey(_role) ? _role : 'main_umpire',
                decoration: const InputDecoration(
                  labelText: 'Role',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry in _roles.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Matches a day',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove one',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _maxPerDay > 1
                        ? () => setState(() => _maxPerDay--)
                        : null,
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$_maxPerDay',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add one',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _maxPerDay < 20
                        ? () => setState(() => _maxPerDay++)
                        : null,
                  ),
                ],
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _canScore,
                onChanged: (v) => setState(() => _canScore = v),
                title: const Text('Can score their matches'),
                subtitle: const Text(
                  'Gives them the scoring pad for matches they are assigned '
                  'to. Revocable per match afterwards.',
                ),
              ),

              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  widget.official.copyWith(
                    role: _role,
                    sports: _sports.toList(),
                    availableDates: _days.toList()..sort(),
                    maxMatchesPerDay: _maxPerDay,
                    scoringRightsGranted: _canScore,
                  ),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}
