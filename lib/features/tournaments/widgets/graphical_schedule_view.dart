import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/fixture.dart';
import '../../../core/models/tournament.dart';
import '../../../shared/live_dot.dart';

/// What the organizer answered when asked how the day should be paced.
///
/// A record rather than three loose ints so the callback cannot silently swap
/// two of them — every value here is minutes, and "45, 10, 20" is a valid
/// argument list in any order.
typedef ScheduleTimings = ({
  /// One length for every match in the solve, or null for each event's own —
  /// the length its sport and category were created with.
  int? matchMinutes,
  int changeoverMinutes,
  int restGapMinutes,
});

/// The tournament timetable, drawn as a court-by-time matrix per event.
///
/// Two things make this readable rather than merely present:
///
/// **It is a grid, not a list.** Courts are columns and start times are rows,
/// so "what is happening at 11:00" and "is Court 2 free after lunch" are
/// answered by looking, which is the entire reason an organizer opens a
/// timetable. A vertical list of match cards sorted by time cannot answer
/// either without reading every row.
///
/// **It is split by event, not by sport id.** A season's badminton is not one
/// thing — it is Singles U-19, Doubles Open and Mixed, each a separate
/// [Competition] with its own draw. Grouping on `Fixture.sportId` collapses
/// all three into one bucket labelled "badminton", which is exactly the case
/// the multi-category season exists to support.
class GraphicalScheduleView extends StatefulWidget {
  const GraphicalScheduleView({
    super.key,
    required this.tournament,
    required this.events,
    required this.fixtures,
    required this.canManage,
    this.sportId,
    this.sportName,
    this.onRegenerateDraft,
    this.onDrawAndSchedule,
    this.onLockSchedule,
    this.onOpenSport,
    this.onMoveMatch,
    this.onOpenMatch,
    this.onOpenFullPage,
    this.embedded = true,
  });

  final Tournament tournament;

  /// Every event hanging off this tournament, for naming the sections. A
  /// fixture carries `compId` but not the competition's name.
  final List<Competition> events;

  final List<Fixture> fixtures;
  final bool canManage;

  /// The one sport this timetable is for, or null for the whole season.
  ///
  /// Schedules are built and published per sport: the actions below are
  /// only offered with a sport, and the season-wide view is read-only with a
  /// way into each sport's own page ([onOpenSport]).
  final String? sportId;
  final String? sportName;

  /// Receives the organizer's timings so they can be persisted before the
  /// solve. Deliberately not a [VoidCallback]: it was one, and the dialog's
  /// answers went nowhere. Null (with the other two) makes this view
  /// read-only.
  final Future<void> Function(ScheduleTimings timings)? onRegenerateDraft;

  /// Draws this sport's events and places their matches. The organizer's
  /// first action on a sport, and the one that replaces a per-event tour of
  /// draw sheets.
  final Future<void> Function(ScheduleTimings timings)? onDrawAndSchedule;

  /// Publishes this sport's timetable.
  final VoidCallback? onLockSchedule;

  /// Opens one sport's own schedule page, where it is built and published.
  /// Offered on the season-wide view instead of season-wide actions.
  final void Function(String sportId)? onOpenSport;

  bool get _hasActions =>
      sportId != null && onRegenerateDraft != null && onLockSchedule != null;

  /// Opens the "move this match" flow. Null hides the affordance, which is
  /// what a spectator's copy of the timetable gets — moving a match is an
  /// organizer's action and the grid is shown to everybody.
  final void Function(Fixture fixture)? onMoveMatch;

  /// Opens the match itself — the Match Center before it starts, the pad or
  /// the scoreboard once it has. Separate from [onMoveMatch] because a live
  /// or finished match cannot be moved, and those blocks had no tap at all:
  /// an organizer watching "LIVE" in the grid had no way in from here.
  final void Function(Fixture fixture)? onOpenMatch;

  /// Shown as a "full screen" affordance when this is the embedded copy.
  final VoidCallback? onOpenFullPage;

  /// False on the dedicated schedule page, where the card chrome and the
  /// width cap are the page itself.
  final bool embedded;

  @override
  State<GraphicalScheduleView> createState() => _GraphicalScheduleViewState();
}

class _GraphicalScheduleViewState extends State<GraphicalScheduleView> {
  String? _selectedDateKey;

  /// Sections the organizer has collapsed. Tracked as the exception rather
  /// than the rule so a newly generated schedule opens showing its matches —
  /// a page of shut drawers reads as an empty schedule.
  final Set<String> _collapsed = {};

  static const _tbdKey = '~tbd';

  Competition? _eventFor(String compId) {
    for (final e in widget.events) {
      if (e.id == compId) return e;
    }
    return null;
  }

  /// The event's own name, minus the season prefix every season-created event
  /// carries. "Spring Meet — Badminton (Doubles) — U19" is the document's
  /// name; inside the season's own schedule the first part is noise.
  String _eventLabel(String compId) {
    final event = _eventFor(compId);
    if (event == null) return 'Event';
    final seasonName = widget.tournament.name.trim();
    var name = event.name.trim();
    if (seasonName.isNotEmpty && name.startsWith(seasonName)) {
      name = name.substring(seasonName.length).replaceFirst(RegExp(r'^\s*—\s*'), '');
    }
    return name.isEmpty ? event.sportName : name;
  }

  String _dayKey(Fixture f) {
    final date = f.scheduledAt;
    if (date == null) return _tbdKey;
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Every day the schedule touches, earliest first, with unscheduled matches
  /// gathered into a trailing bucket rather than silently dropped — a match
  /// the solver could not place is the one an organizer most needs to see.
  List<String> get _dayKeys {
    final keys = widget.fixtures.map(_dayKey).toSet().toList();
    final hasTbd = keys.remove(_tbdKey);
    keys.sort();
    return [...keys, if (hasTbd) _tbdKey];
  }

  List<Fixture> get _fixturesForSelectedDay {
    final key = _selectedDateKey;
    if (key == null) return widget.fixtures;
    return [
      for (final f in widget.fixtures)
        if (_dayKey(f) == key) f,
    ];
  }

  /// Matches for the selected day, bucketed by event and ordered the way an
  /// organizer reads a programme: earliest event first.
  List<({String compId, List<Fixture> fixtures})> get _sections {
    final byComp = <String, List<Fixture>>{};
    for (final f in _fixturesForSelectedDay) {
      byComp.putIfAbsent(f.compId, () => []).add(f);
    }

    final sections = [
      for (final entry in byComp.entries)
        (compId: entry.key, fixtures: entry.value),
    ];

    DateTime? earliest(List<Fixture> fs) {
      DateTime? best;
      for (final f in fs) {
        final at = f.scheduledAt;
        if (at == null) continue;
        if (best == null || at.isBefore(best)) best = at;
      }
      return best;
    }

    sections.sort((a, b) {
      final ea = earliest(a.fixtures);
      final eb = earliest(b.fixtures);
      if (ea == null && eb == null) {
        return _eventLabel(a.compId).compareTo(_eventLabel(b.compId));
      }
      if (ea == null) return 1;
      if (eb == null) return -1;
      return ea.compareTo(eb);
    });
    return sections;
  }

  String _formatDateHeader(String dateKey) {
    if (dateKey == _tbdKey) return 'Unscheduled';
    try {
      return DateFormat('EEE, d MMM').format(DateTime.parse(dateKey));
    } catch (_) {
      return dateKey;
    }
  }

  Future<void> _promptScheduleParamsAndRegenerate({
    bool drawFirst = false,
  }) async {
    final sport = widget.sportName ?? 'this sport';
    final sportLower = sport.toLowerCase();
    // Null by default: each event keeps the length it was created with. This
    // dialog used to send one number for the whole season, pre-filled with
    // 30, and the scheduler applied it to every event — a season of T20
    // cricket and badminton was laid out as thirty-minute matches the first
    // time anybody pressed Generate.
    int? matchMins;
    // Zero is a real answer (a table-tennis hall turns a table round at once;
    // some organisers want no enforced rest between league rounds). It used
    // to be read as "unset" and replaced with 10 and 20.
    int changeoverMins = widget.tournament.changeoverMinutes >= 0
        ? widget.tournament.changeoverMinutes
        : 10;
    int restMins = widget.tournament.restGapMinutes >= 0
        ? widget.tournament.restGapMinutes
        : 20;

    // Whatever is stored has to be offered, or the dropdown falls back to its
    // first item and the act of opening the dialog quietly changes the
    // tournament's timings.
    List<int> options(List<int> base, int current) =>
        ({...base, current}.toList()..sort());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.tune_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('Schedule Timings')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'These decide how the $sportLower day is paced. Its matches '
                  'are placed around them and around every other sport '
                  'already on the courts, so no court is double-booked and '
                  'nobody is called straight off one court onto another.',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  value: matchMins,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'How long is one $sportLower match?',
                    helperText: 'Each event keeps the length set when it was '
                        'created unless you choose one here. A length you '
                        'choose is saved on the $sportLower events.',
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Each event’s own (recommended)'),
                    ),
                    for (final m in const [
                      15, 20, 30, 45, 60, 90, 120, 150, 180, 210, 240, 300, 360,
                    ])
                      DropdownMenuItem<int?>(
                        value: m,
                        child: Text('$m minutes'),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => matchMins = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: changeoverMins,
                  decoration: const InputDecoration(
                    labelText: 'Time needed between matches',
                    helperText:
                        'Court reset — players off, kit changed, next pair on',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in options(const [0, 5, 10, 15, 20, 30], changeoverMins))
                      DropdownMenuItem(
                        value: m,
                        child: Text(m == 10 ? '10 minutes (recommended)' : '$m minutes'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => changeoverMins = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: restMins,
                  decoration: const InputDecoration(
                    labelText: 'Minimum rest for a player',
                    helperText:
                        'Between two of their own matches, across every event '
                        'they entered',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in options(const [0, 10, 20, 30, 45, 60], restMins))
                      DropdownMenuItem(value: m, child: Text('$m minutes')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => restMins = v);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'The time between matches and the rest gap are shared by '
                  'every sport in the season, because they share the courts '
                  'and the players.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                drawFirst ? 'Draw & Schedule $sport' : 'Generate Schedule',
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final timings = (
      matchMinutes: matchMins,
      changeoverMinutes: changeoverMins,
      restGapMinutes: restMins,
    );
    final setUp = widget.onDrawAndSchedule;
    if (drawFirst && setUp != null) {
      await setUp(timings);
    } else {
      await widget.onRegenerateDraft?.call(timings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The stored flag first, the status second.
    //
    // Status alone was the whole test, which made "published" a thing this
    // widget INFERRED rather than something the season recorded — and the
    // inference is not sound in both directions. A season can reach
    // `scheduled` by a route that never published anything, and the header
    // would announce a timetable nobody had been sent. `lockSchedule` has
    // always written `isScheduleLocked`; nothing read it until now.
    //
    // The status clause stays as the fallback for seasons locked before the
    // field existed: they have the old status and no flag, and treating them
    // as unpublished would re-open a schedule that has already gone out.
    //
    // `scheduled` is not in that fallback. Generating a draft used to write
    // it, so a season showed "Published" the moment a draft existed and hid
    // the button that would have published it.
    //
    // With a sport, the question is that sport's own publication. Both
    // questions keep the fallback for seasons published season-wide, on a
    // sport page too: without it such a season, already running, opened as
    // a draft there and its unplayed matches could be moved again. See
    // `Tournament.publishedSeasonWide`.
    final t = widget.tournament;
    final sportId = widget.sportId;
    final isLocked = sportId != null
        ? t.isSportScheduleLocked(sportId)
        : t.isWholeScheduleLocked({
            for (final e in widget.events)
              if (e.status != CompetitionStatus.cancelled &&
                  !e.format.isPerformanceFormat &&
                  e.archetype != CompetitionArchetype.performance)
                e.sportId,
          });

    final dayKeys = _dayKeys;
    if (_selectedDateKey == null || !dayKeys.contains(_selectedDateKey)) {
      _selectedDateKey = dayKeys.isNotEmpty ? dayKeys.first : null;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(theme, isLocked),
        const SizedBox(height: 16),
        if (widget.fixtures.isEmpty)
          _emptyState(theme)
        else ...[
          if (dayKeys.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final k in dayKeys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_formatDateHeader(k)),
                        selected: _selectedDateKey == k,
                        onSelected: (sel) {
                          if (sel) setState(() => _selectedDateKey = k);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final section in _sections) ...[
            _EventSection(
              title: _eventLabel(section.compId),
              sportName: _eventFor(section.compId)?.sportName ?? '',
              fixtures: section.fixtures,
              expanded: !_collapsed.contains(section.compId),
              onExpansionChanged: (open) => setState(() {
                if (open) {
                  _collapsed.remove(section.compId);
                } else {
                  _collapsed.add(section.compId);
                }
              }),
              onMoveMatch: widget.canManage ? widget.onMoveMatch : null,
              onOpenMatch: widget.onOpenMatch,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );

    if (!widget.embedded) return body;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }

  // --- What the box is actually reporting ---------------------------------
  //
  // The header used to say two things: "Schedule", and whether it was a draft.
  // Neither is a fact about THIS season, so the box was three buttons over a
  // grid and an organizer could not tell from it whether the timetable was
  // finished, half-placed, or hadn't started. These are the numbers they were
  // reading the grid to work out.

  /// Matches that exist but have nowhere to be. The number that decides
  /// whether the schedule is done, and the one the old header never showed.
  int get _unplaced =>
      widget.fixtures.where((f) => f.scheduledAt == null).length;

  /// Placeholder matches from a draft bracket — "Team A vs Team B". A season
  /// full of these has not been drawn, however complete the grid looks, and
  /// publishing would send them out under those names. See `Fixture.isDraft`.
  int get _placeholders => widget.fixtures.where((f) => f.isDraft).length;

  int get _dayCount =>
      _dayKeys.where((k) => k != _tbdKey).length;

  /// One line of plain arithmetic: what is here, spread over how long, and
  /// what is still missing.
  String get _summaryLine {
    if (widget.fixtures.isEmpty) return 'Nothing drawn yet';
    final parts = <String>[
      '${widget.fixtures.length} '
          '${widget.fixtures.length == 1 ? 'match' : 'matches'}',
      if (_dayCount > 1) 'across $_dayCount days' else if (_dayCount == 1) 'in one day',
      if (_unplaced > 0) '$_unplaced with no time yet',
    ];
    return parts.join(' · ');
  }

  /// The one thing to do next, as a sentence rather than as a choice between
  /// three buttons that all say "schedule".
  ///
  /// Ordered by what actually blocks publishing: a placeholder draw blocks it
  /// outright (`lockSchedule` refuses), an unplaced match makes the timetable
  /// wrong, and everything else is ready to go out.
  ({String text, bool isProblem}) get _nextStep {
    if (widget.fixtures.isEmpty) {
      return (
        text: widget.onDrawAndSchedule != null
            ? 'Draw every ${widget.sportName ?? 'event'} event and place '
                'its matches around the rest of the season in one pass.'
            : 'Make the draws first, then place them on the courts.',
        isProblem: false,
      );
    }
    if (_placeholders > 0) {
      return (
        text: '$_placeholders of these are placeholders, not real entrants. '
            'Generate the real draw for those events before publishing.',
        isProblem: true,
      );
    }
    if (_unplaced > 0) {
      return (
        text: '$_unplaced ${_unplaced == 1 ? 'match has' : 'matches have'} no '
            'court or time. Reschedule to place them, or move them by hand.',
        isProblem: true,
      );
    }
    return (
      text: 'Every match has a court and a time. Publish it and everyone '
          'entered is told.',
      isProblem: false,
    );
  }

  Widget _header(ThemeData theme, bool isLocked) {
    final step = _nextStep;
    final stateColour =
        isLocked ? theme.colorScheme.primary : theme.colorScheme.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.grid_view_outlined,
                color: theme.colorScheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Schedule',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      // The draft/published state as a badge rather than a
                      // sentence, so the line under it is free to carry the
                      // numbers instead.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: stateColour.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isLocked
                              ? 'Published'
                              : widget.sportId == null &&
                                      widget.tournament.sportSchedulesReleasedAt
                                          .isNotEmpty
                                  ? 'Partly published'
                                  : 'Draft',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: stateColour,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _summaryLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.embedded && widget.onOpenFullPage != null)
              IconButton(
                icon: const Icon(Icons.open_in_full, size: 20),
                tooltip: 'Open full schedule',
                onPressed: widget.onOpenFullPage,
              ),
          ],
        ),

        // Nothing below this is for a spectator: they came for the grid, and
        // the grid is what follows.
        if (!widget.canManage) ...[
          if (!isLocked) ...[
            const SizedBox(height: 8),
            Text(
              'This is a draft. Times and courts can still change.',
              style: theme.textTheme.bodySmall?.copyWith(color: stateColour),
            ),
          ],
        ] else if (!widget._hasActions) ...[
          _sportLinks(theme),
        ] else ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: step.isProblem
                  ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  step.isProblem
                      ? Icons.error_outline
                      : isLocked
                          ? Icons.check_circle_outline
                          : Icons.arrow_forward,
                  size: 16,
                  color: step.isProblem
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // Once published there is no next step to nag about; the
                    // sentence becomes the record of what went out.
                    isLocked
                        ? 'Published — courts and times are final. Everyone '
                            'entered in ${widget.sportName ?? 'it'} has been '
                            'told.'
                        : step.text,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // One primary, chosen by the same order the sentence above uses, and
          // the rest demoted. Three buttons that all said "schedule" was the
          // reason this box needed reading twice.
          if (!isLocked)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.fixtures.isEmpty)
                  FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      widget.onDrawAndSchedule != null
                          ? 'Draw & schedule ${widget.sportName ?? 'this sport'}'
                          : 'Place the matches on courts',
                    ),
                    onPressed: () => _promptScheduleParamsAndRegenerate(
                      drawFirst: widget.onDrawAndSchedule != null,
                    ),
                  )
                else if (_unplaced > 0 || _placeholders > 0)
                  FilledButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Fix the gaps & reschedule'),
                    onPressed: () => _promptScheduleParamsAndRegenerate(
                      drawFirst: widget.onDrawAndSchedule != null,
                    ),
                  )
                else
                  FilledButton.icon(
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: Text('Publish ${widget.sportName ?? ''} schedule'
                        .replaceAll('  ', ' ')),
                    onPressed: widget.onLockSchedule,
                  ),
                if (widget.fixtures.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.tune_outlined, size: 18),
                    label: const Text('Change timings'),
                    onPressed: _promptScheduleParamsAndRegenerate,
                  ),
                // Still reachable when it is not the primary — an organizer
                // who knows a draw is placeholder-free and wants it out is
                // allowed to publish over the warning.
                if (widget.fixtures.isNotEmpty &&
                    (_unplaced > 0 || _placeholders > 0))
                  TextButton.icon(
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Publish anyway'),
                    onPressed: widget.onLockSchedule,
                  ),
              ],
            ),
          // No reschedule button once published, deliberately. Re-solving a
          // timetable people have already been sent would move matches
          // underneath them with no notification; a published season's late
          // start is shifted through `RunningLateCard`, which moves everything
          // together and says so.
        ],
      ],
    );
  }

  /// The season-wide view's organizer box: no actions, one way into each
  /// sport's own schedule, and whether that sport is published yet.
  ///
  /// Season-wide "Draw & schedule everything" and "Lock & publish" used to
  /// sit here. They redrew and published every sport from one press, and
  /// on a page filtered to one sport they still acted on the whole season.
  /// Scheduling is per sport now, so this box only points the way.
  Widget _sportLinks(ThemeData theme) {
    final sports = <String, String>{};
    for (final e in widget.events) {
      if (e.status == CompetitionStatus.cancelled) continue;
      sports.putIfAbsent(e.sportId, () => e.sportName);
    }
    if (sports.isEmpty || widget.onOpenSport == null) {
      return const SizedBox.shrink();
    }
    final entries = sports.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Timetables are drawn, scheduled and published one sport at a '
            'time. Each sport is fitted around the courts and players the '
            'others already use.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in entries)
                ActionChip(
                  avatar: Icon(
                    widget.tournament.isSportScheduleLocked(e.key)
                        ? Icons.check_circle_outline
                        : Icons.edit_calendar_outlined,
                    size: 18,
                  ),
                  label: Text(
                    widget.tournament.isSportScheduleLocked(e.key)
                        ? '${e.value} · published'
                        : 'Schedule ${e.value}',
                  ),
                  onPressed: () => widget.onOpenSport!(e.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.event_busy,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'No matches scheduled yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              widget.canManage
                  ? 'Pick your timings and let it draw every event and place '
                      'every match — one press, no clashes.'
                  : 'The organizer has not published a timetable yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// One event's matches, behind a disclosure so a fifteen-event season is a
/// page of headings rather than a scroll of grids.
class _EventSection extends StatelessWidget {
  const _EventSection({
    required this.title,
    required this.sportName,
    required this.fixtures,
    required this.expanded,
    required this.onExpansionChanged,
    this.onMoveMatch,
    this.onOpenMatch,
  });

  final String title;
  final String sportName;
  final List<Fixture> fixtures;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(Fixture fixture)? onMoveMatch;
  final void Function(Fixture fixture)? onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveCount =
        fixtures.where((f) => f.status == FixtureStatus.live).length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The default divider on an open tile fights the container border.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(title),
          initiallyExpanded: expanded,
          onExpansionChanged: onExpansionChanged,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            sportName.isEmpty
                ? '${fixtures.length} matches'
                : '$sportName · ${fixtures.length} matches',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          trailing: liveCount > 0
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [LiveDot(), SizedBox(width: 8), Icon(Icons.expand_more)],
                )
              : const Icon(Icons.expand_more),
          children: [
            _CourtTimeGrid(
              fixtures: fixtures,
              onMoveMatch: onMoveMatch,
              onOpenMatch: onOpenMatch,
            ),
          ],
        ),
      ),
    );
  }
}

/// The timetable proper: one column per court, one row per start time.
class _CourtTimeGrid extends StatelessWidget {
  const _CourtTimeGrid({
    required this.fixtures,
    this.onMoveMatch,
    this.onOpenMatch,
  });

  final List<Fixture> fixtures;
  final void Function(Fixture fixture)? onMoveMatch;
  final void Function(Fixture fixture)? onOpenMatch;

  static const _cellWidth = 196.0;
  static const _cellHeight = 74.0;
  static const _gutterWidth = 72.0;

  static String _courtOf(Fixture f) =>
      f.courtId ?? f.venue ?? 'Unassigned';

  /// Times as `HH:mm`, so two fixtures a few seconds apart share a row rather
  /// than opening a second one that looks like a gap.
  static String _slotOf(Fixture f) {
    final at = f.scheduledAt;
    if (at == null) return '';
    return DateFormat('HH:mm').format(at);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final courts = fixtures.map(_courtOf).toSet().toList()..sort();
    final slots = fixtures.map(_slotOf).toSet().toList();
    final hasUntimed = slots.remove('');
    slots.sort();
    final rows = [...slots, if (hasUntimed) ''];

    // key: '$slot|$court'
    final cells = <String, List<Fixture>>{};
    for (final f in fixtures) {
      cells.putIfAbsent('${_slotOf(f)}|${_courtOf(f)}', () => []).add(f);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Court header
          Row(
            children: [
              const SizedBox(width: _gutterWidth),
              for (final court in courts)
                Container(
                  width: _cellWidth,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  margin: const EdgeInsets.only(right: 6, bottom: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.stadium_outlined,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          court,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          for (final slot in rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _gutterWidth,
                  height: _cellHeight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Text(
                      slot.isEmpty ? 'TBD' : _pretty(slot),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: slot.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                ),
                for (final court in courts)
                  Container(
                    width: _cellWidth,
                    height: _cellHeight,
                    margin: const EdgeInsets.only(right: 6, bottom: 6),
                    child: _cell(context, cells['$slot|$court'] ?? const []),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// A slot holds one match. More than one means the solver was overridden by
  /// hand, and hiding the extra would hide a genuine double-booking.
  Widget _cell(BuildContext context, List<Fixture> here) {
    final theme = Theme.of(context);
    if (here.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: const SizedBox.expand(),
      );
    }
    if (here.length == 1) {
      return _MatchBlock(
        fixture: here.first,
        onMove: onMoveMatch,
        onOpen: onOpenMatch,
      );
    }

    return Stack(
      children: [
        _MatchBlock(
          fixture: here.first,
          onMove: onMoveMatch,
          onOpen: onOpenMatch,
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Tooltip(
            message: '${here.length} matches booked on this court at this time',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '×${here.length}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _pretty(String hhmm) {
    try {
      final parts = hhmm.split(':');
      final dt = DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return hhmm;
    }
  }
}

/// One match, as it appears in a grid cell.
class _MatchBlock extends StatelessWidget {
  const _MatchBlock({required this.fixture, this.onMove, this.onOpen});

  final Fixture fixture;

  /// Organizer-only, and only while the match is still movable.
  final void Function(Fixture fixture)? onMove;

  /// Everybody's way into the match itself.
  final void Function(Fixture fixture)? onOpen;

  /// A slot whose entrants are not yet known — a semi-final before its groups
  /// finish, or a bracket place nobody has registered into. Drawn differently
  /// on purpose: an organizer scanning for gaps needs "nobody yet" to look
  /// unlike "these two people".
  static bool _isPlaceholder(String name) {
    final n = name.trim();
    return n.isEmpty ||
        n.toUpperCase().startsWith('TBD') ||
        n.toLowerCase() == 'bye';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = fixture.status == FixtureStatus.live;
    final isDone = fixture.status == FixtureStatus.completed;
    // Asked of the ids, not the names. `_isPlaceholder` sniffs for "TBD",
    // and the draw generator writes "To be decided" — which does not start
    // with it — so a generated knockout placeholder never once greyed out.
    // An empty entrant id is what "nobody here yet" actually means.
    final unknown = fixture.entrantAId.isEmpty && fixture.entrantBId.isEmpty;

    final Color background;
    if (isLive) {
      background = theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
    } else if (isDone) {
      background = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    } else if (unknown) {
      background = theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4);
    } else {
      background = theme.colorScheme.surfaceContainerLow;
    }

    final move = onMove;
    // A played or playing match is not movable, and offering the affordance
    // on one is offering something that will be refused.
    final movable = move != null && !isLive && !isDone;
    // So a block that cannot be moved opens instead of doing nothing. The
    // grid is where an organizer stands on match day; a LIVE cell that
    // swallows taps is the reason the pad was unreachable from the season.
    final open = onOpen;

    final block = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLive
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          width: isLive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (fixture.roundLabel != null && fixture.roundLabel!.isNotEmpty)
                Flexible(
                  child: Text(
                    fixture.roundLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                )
              else
                Text(
                  'Match ${fixture.matchIndex}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              if (isLive) const LiveDot(),
              if (isDone)
                Icon(Icons.check_circle,
                    size: 13, color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 3),
          // "Group B winner" rather than "To be decided" while the group is
          // still being played — every other screen already says which table
          // position a slot is waiting on, and this one was the odd one out.
          _name(theme, fixture.displayNameA(), fixture.entrantAId.isNotEmpty),
          _name(theme, fixture.displayNameB(), fixture.entrantBId.isNotEmpty),
        ],
      ),
    );

    if (!movable && open == null) return block;
    return InkWell(
      onTap: movable ? () => move(fixture) : () => open!(fixture),
      borderRadius: BorderRadius.circular(10),
      child: block,
    );
  }

  /// [decided] comes from the entrant id, never from reading the name.
  /// Sniffing the text got this wrong both ways: "To be decided" was styled
  /// as a real side because it does not start with "TBD", and "Group B
  /// winner" would be too.
  Widget _name(ThemeData theme, String name, bool decided) {
    final placeholder = !decided || _isPlaceholder(name);
    return Text(
      placeholder ? (name.trim().isEmpty ? 'Open slot' : name.trim()) : name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 11.5,
        height: 1.35,
        fontWeight: placeholder ? FontWeight.w400 : FontWeight.w600,
        fontStyle: placeholder ? FontStyle.italic : FontStyle.normal,
        color: placeholder ? theme.colorScheme.onSurfaceVariant : null,
      ),
    );
  }
}
