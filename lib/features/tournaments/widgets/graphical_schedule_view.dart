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
  int matchMinutes,
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
    required this.onRegenerateDraft,
    this.onSetUpWholeSeason,
    required this.onLockSchedule,
    this.onOpenFullPage,
    this.embedded = true,
  });

  final Tournament tournament;

  /// Every event hanging off this tournament, for naming the sections. A
  /// fixture carries `compId` but not the competition's name.
  final List<Competition> events;

  final List<Fixture> fixtures;
  final bool canManage;

  /// Receives the organizer's timings so they can be persisted before the
  /// solve. Deliberately not a [VoidCallback]: it was one, and the dialog's
  /// answers went nowhere.
  final Future<void> Function(ScheduleTimings timings) onRegenerateDraft;

  /// Draws every event and schedules the lot. The organizer's first action on
  /// a fresh season, and the one that replaces a per-event tour of draw
  /// sheets.
  final Future<void> Function(ScheduleTimings timings)? onSetUpWholeSeason;

  final VoidCallback onLockSchedule;

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
    bool wholeSeason = false,
  }) async {
    int matchMins = widget.tournament.matchMinutesDefault > 0
        ? widget.tournament.matchMinutesDefault
        : 30;
    int changeoverMins = widget.tournament.changeoverMinutes > 0
        ? widget.tournament.changeoverMinutes
        : 10;
    int restMins = widget.tournament.restGapMinutes > 0
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
                const Text(
                  'These decide how the day is paced. Every match is placed '
                  'around them, so no court is double-booked and nobody is '
                  'called straight off one court onto another.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: matchMins,
                  decoration: const InputDecoration(
                    labelText: 'How long is one match?',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in options(const [15, 20, 30, 45, 60, 90], matchMins))
                      DropdownMenuItem(value: m, child: Text('$m minutes')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => matchMins = v);
                  },
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
                wholeSeason ? 'Draw & Schedule Everything' : 'Generate Schedule',
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
    final setUp = widget.onSetUpWholeSeason;
    if (wholeSeason && setUp != null) {
      await setUp(timings);
    } else {
      await widget.onRegenerateDraft(timings);
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
    final isLocked = widget.tournament.isScheduleLocked ||
        widget.tournament.status == TournamentStatus.scheduled ||
        widget.tournament.status == TournamentStatus.inProgress ||
        widget.tournament.status == TournamentStatus.completed;

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

  Widget _header(ThemeData theme, bool isLocked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                  Text(
                    'Schedule',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isLocked
                        ? 'Published — courts and times are final'
                        : 'Draft — not yet visible to players',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isLocked
                          ? theme.colorScheme.primary
                          : theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
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
        if (widget.canManage) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isLocked) ...[
                if (widget.onSetUpWholeSeason != null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Draw & schedule everything'),
                    onPressed: () => _promptScheduleParamsAndRegenerate(
                      wholeSeason: true,
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: Text(
                    widget.fixtures.isEmpty
                        ? 'Schedule existing draws'
                        : 'Change timings & reschedule',
                  ),
                  onPressed: _promptScheduleParamsAndRegenerate,
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Lock & Publish'),
                  onPressed:
                      widget.fixtures.isEmpty ? null : widget.onLockSchedule,
                ),
              ] else
                Chip(
                  avatar: Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 18,
                  ),
                  label: const Text('Locked & Published'),
                  side: BorderSide.none,
                ),
            ],
          ),
        ],
      ],
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
  });

  final String title;
  final String sportName;
  final List<Fixture> fixtures;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;

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
          children: [_CourtTimeGrid(fixtures: fixtures)],
        ),
      ),
    );
  }
}

/// The timetable proper: one column per court, one row per start time.
class _CourtTimeGrid extends StatelessWidget {
  const _CourtTimeGrid({required this.fixtures});

  final List<Fixture> fixtures;

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
    if (here.length == 1) return _MatchBlock(fixture: here.first);

    return Stack(
      children: [
        _MatchBlock(fixture: here.first),
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
  const _MatchBlock({required this.fixture});

  final Fixture fixture;

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
    final unknown = _isPlaceholder(fixture.entrantAName) &&
        _isPlaceholder(fixture.entrantBName);

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

    return Container(
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
          _name(theme, fixture.entrantAName),
          _name(theme, fixture.entrantBName),
        ],
      ),
    );
  }

  Widget _name(ThemeData theme, String name) {
    final placeholder = _isPlaceholder(name);
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
