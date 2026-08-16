import 'package:flutter/material.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/draw_config.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/venue.dart';
import '../../../domain/draw/group_bounds.dart';

/// Asks the organizer how the draw should be shaped and laid out, immediately
/// before it is generated.
///
/// ## Why this screen has to exist
///
/// Every setting here was already a parameter of the draw generator and had no
/// way to be set. A groups+knockout competition therefore always took the
/// generator's fallback — roughly four per group, two qualifiers each — and
/// every fixture in the draw was stamped with the competition's single start
/// time and its single venue string. So a 38-entrant tournament told all 38
/// entrants to arrive at 10:00 on one line of text, which is not a schedule,
/// and is exactly how a day planned to finish at six finishes at eleven.
///
/// The court list is the highest-value field on this sheet. Without it the
/// scheduler cannot run at all, because it has nowhere to put anything.
class DrawSetupSheet extends StatefulWidget {
  const DrawSetupSheet({
    super.key,
    required this.competition,
    required this.entrantCount,
    this.venues = const [],
  });

  final Competition competition;
  final int entrantCount;

  /// Venues this club has defined. Empty is normal and supported — the sheet
  /// falls back to typed court names.
  final List<Venue> venues;

  /// Returns the organizer's choices, or null if they backed out.
  static Future<({DrawConfig draw, ScheduleConfig schedule})?> show(
    BuildContext context, {
    required Competition competition,
    required int entrantCount,
    List<Venue> venues = const [],
  }) {
    return showModalBottomSheet<({DrawConfig draw, ScheduleConfig schedule})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DrawSetupSheet(
        competition: competition,
        entrantCount: entrantCount,
        venues: venues,
      ),
    );
  }

  @override
  State<DrawSetupSheet> createState() => _DrawSetupSheetState();
}

class _DrawSetupSheetState extends State<DrawSetupSheet> {
  late DrawConfig _draw = widget.competition.drawConfig;
  late ScheduleConfig _schedule = widget.competition.scheduleConfig;
  late final TextEditingController _courts = TextEditingController(
    text: _schedule.courts.join(', '),
  );
  late final Set<String> _venueIds = {..._schedule.venueIds};

  @override
  void dispose() {
    _courts.dispose();
    super.dispose();
  }

  /// Formats that can carry a group stage at all.
  ///
  /// Swiss pairs by standing each round and double elimination already gives
  /// everyone a second life, so neither has a group phase to add. Everything
  /// else does.
  bool get _canUseGroups =>
      widget.competition.format == CompetitionFormat.groupThenKnockout ||
      widget.competition.format == CompetitionFormat.knockout ||
      widget.competition.format == CompetitionFormat.roundRobin ||
      widget.competition.format == CompetitionFormat.leagueTable;

  /// Groups+Knockout says it in the format; every other format asks.
  bool get _groupsAreImplied =>
      widget.competition.format == CompetitionFormat.groupThenKnockout;

  bool get _isGroups => _groupsAreImplied || (_canUseGroups && _draw.useGroups);

  /// Whether the group stage feeds a knockout, which is what decides if
  /// "qualifiers per group" is a real question.
  bool get _groupsFeedKnockout =>
      _isGroups &&
      widget.competition.format != CompetitionFormat.roundRobin &&
      widget.competition.format != CompetitionFormat.leagueTable;

  bool get _isDoubleElim =>
      widget.competition.format == CompetitionFormat.doubleElimination;

  bool get _isRoundRobin =>
      widget.competition.format == CompetitionFormat.roundRobin ||
      widget.competition.format == CompetitionFormat.leagueTable;

  /// Group sizing, delegated to [GroupBounds] so the rule the generator
  /// obeys and the rule the stepper offers are the same rule.
  int get _minGroups => GroupBounds.minGroups(widget.entrantCount);

  int get _maxGroups => GroupBounds.maxGroups(
        widget.entrantCount,
        // Nothing to qualify into in a pool format, so group size is bounded
        // only by what makes a group a group.
        qualifiersPerGroup: _groupsFeedKnockout ? _draw.qualifiersPerGroup : 1,
      );

  /// The group count the generator will actually use, so the summary line
  /// below cannot promise something different from what gets drawn.
  int get _effectiveGroups => GroupBounds.resolve(
        entrants: widget.entrantCount,
        requested: _draw.numGroups,
        qualifiersPerGroup: _groupsFeedKnockout ? _draw.qualifiersPerGroup : 1,
      );

  /// A fresh draw number when the organizer has not fixed one, so a
  /// supervised draw is genuinely drawn rather than repeating yesterday's.
  late final int _suggestedSeed =
      DateTime.now().millisecondsSinceEpoch % 100000;

  List<String> get _parsedCourts => _courts.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Set up the draw', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.entrantCount} entrants · '
              '${widget.competition.format.label}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            if (_canUseGroups && !_groupsAreImplied)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Split into groups'),
                subtitle: Text(
                  widget.competition.format == CompetitionFormat.knockout
                      ? 'A group stage first, with the top of each group '
                          'going through to the knockout.'
                      : 'Pools — everyone plays everyone in their own group '
                          'instead of one table of ${widget.entrantCount}.',
                ),
                value: _draw.useGroups,
                onChanged: (v) => setState(
                  () => _draw = _draw.copyWith(useGroups: v),
                ),
              ),

            if (_isGroups) ...[
              const _SectionLabel('Groups'),
              _Stepper(
                label: 'Number of groups',
                // Bounded so the organizer cannot choose a group size the
                // draw is not allowed to have, rather than accepting the
                // number and quietly generating something else.
                value: _effectiveGroups,
                min: _minGroups,
                max: _maxGroups,
                onChanged: (v) =>
                    setState(() => _draw = _draw.copyWith(numGroups: v)),
              ),
              if (_groupsFeedKnockout)
                _Stepper(
                  label: 'Qualifiers from each group',
                  value: _draw.qualifiersPerGroup,
                  min: 1,
                  max: 4,
                  onChanged: (v) => setState(() {
                    // Raising the qualifier count can shrink [_maxGroups] below
                    // the chosen group count, so the choice is re-clamped here
                    // instead of being left invalid until the next rebuild.
                    _draw = _draw.copyWith(qualifiersPerGroup: v);
                    _draw = _draw.copyWith(numGroups: _effectiveGroups);
                  }),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 16),
                child: Text(
                  _groupSummary(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],

            if (_isRoundRobin)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Play home and away'),
                subtitle: const Text(
                  'Everyone plays everyone twice. Twice the matches, and '
                  'twice the days to fit them in.',
                ),
                value: _draw.doubleRoundRobin,
                onChanged: (v) => setState(
                  () => _draw = _draw.copyWith(doubleRoundRobin: v),
                ),
              ),

            if (_isDoubleElim)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow a bracket reset'),
                subtitle: const Text(
                  'If the losers-bracket side wins the grand final, a decider '
                  'is played — one loss should not eliminate the side that '
                  'came through undefeated.',
                ),
                value: _draw.bracketReset,
                onChanged: (v) =>
                    setState(() => _draw = _draw.copyWith(bracketReset: v)),
              ),

            const SizedBox(height: 8),
            const _SectionLabel('Seeding and the draw'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Seed from ratings'),
              subtitle: const Text(
                'Ranks the field on Glicko-2. A player without enough rated '
                'matches is left unseeded and drawn at random rather than '
                'being protected on a rating nobody has earned yet.',
              ),
              value: _draw.seedFromRatings,
              onChanged: (v) =>
                  setState(() => _draw = _draw.copyWith(seedFromRatings: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Supervised draw'),
              subtitle: const Text(
                'Seeds pinned to their positions, everyone else drawn at '
                'random, and two players from the same club kept apart in '
                'round one where the bracket allows. Off, the bracket is a '
                'ranked ladder — fine for a club event.',
              ),
              value: _draw.method == 'federation',
              onChanged: (v) => setState(
                () =>
                    _draw = _draw.copyWith(method: v ? 'federation' : 'ranked'),
              ),
            ),
            if (_draw.method == 'federation')
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Draw number ${_draw.shuffleSeed ?? _suggestedSeed}. '
                  'Recorded with the draw so it can be re-run and checked — '
                  '"it was random" is not an answer to "why did I get the top '
                  'seed".',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 12),

            const _SectionLabel('Courts and timing'),

            // Real venues where the club has defined them, typed names where
            // it has not. Both, rather than forcing one: a district
            // championship needs venue documents so several events can share
            // courts, and a Sunday club afternoon should not have to fill in
            // a venue form before it can start.
            if (widget.venues.isNotEmpty) ...[
              Text(
                'Play at',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              for (final venue in widget.venues)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _venueIds.contains(venue.id),
                  title: Text(venue.name),
                  subtitle: Text(
                    '${venue.capacity} court'
                    '${venue.capacity == 1 ? '' : 's'} · '
                    '${venue.openHour}:00–${venue.closeHour}:00'
                    '${venue.city != null ? ' · ${venue.city}' : ''}',
                  ),
                  onChanged: (on) => setState(() {
                    if (on == true) {
                      _venueIds.add(venue.id);
                    } else {
                      _venueIds.remove(venue.id);
                    }
                  }),
                ),
              const SizedBox(height: 8),
            ],

            if (_venueIds.isEmpty)
              TextField(
                controller: _courts,
                decoration: InputDecoration(
                  labelText: 'Courts, separated by commas',
                  hintText: 'Court 1, Court 2, Court 3',
                  helperText: widget.venues.isEmpty
                      ? 'Leave empty to give every match the same start time '
                          '— which is what makes tournaments run late. Set up '
                          'venues to share courts between events.'
                      : 'Or type court names for a one-off.',
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 12),
            _Stepper(
              label: 'Minutes per match',
              value: _schedule.matchMinutes,
              min: 5,
              max: 240,
              step: 5,
              onChanged: (v) => setState(
                () => _schedule = _schedule.copyWith(matchMinutes: v),
              ),
            ),
            _Stepper(
              label: 'Changeover between matches',
              value: _schedule.changeoverMinutes,
              min: 0,
              max: 30,
              step: 5,
              onChanged: (v) => setState(
                () => _schedule = _schedule.copyWith(changeoverMinutes: v),
              ),
            ),
            _Stepper(
              label: 'Minimum rest for a player',
              value: _schedule.restGapMinutes,
              min: 0,
              max: 120,
              step: 5,
              onChanged: (v) => setState(
                () => _schedule = _schedule.copyWith(restGapMinutes: v),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _scheduleSummary(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop((
                    // The group count is clamped on the way out as well as in
                    // the stepper: a competition saved under the old bounds
                    // carries a `numGroups` the stepper only ever displayed
                    // clamped, and handing that stored value to the generator
                    // would draw the groups the organizer was shown they
                    // could not have.
                    draw: _drawToSubmit,
                    schedule: _schedule.copyWith(
                      courts: _venueIds.isEmpty ? _parsedCourts : const [],
                      venueIds: _venueIds.toList(),
                    ),
                  )),
                  child: const Text('Generate the draw'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// [_draw] with every derived bound applied, ready for the generator.
  DrawConfig get _drawToSubmit {
    var out = _draw;
    if (_isGroups) out = out.copyWith(numGroups: _effectiveGroups);
    if (out.method == 'federation' && out.shuffleSeed == null) {
      out = out.copyWith(shuffleSeed: _suggestedSeed);
    }
    return out;
  }

  String _groupSummary() {
    final groups = _effectiveGroups;
    final qualifiers = groups * _draw.qualifiersPerGroup;
    final smallest = GroupBounds.smallestGroupSize(widget.entrantCount, groups);
    final largest = GroupBounds.largestGroupSize(widget.entrantCount, groups);
    // "About four" hid the uneven split that an organizer has to explain to
    // whoever drew the group of five.
    final size = smallest == largest ? '$smallest' : '$smallest–$largest';
    // Pools have no knockout to promise anybody into, and saying "8 into the
    // knockout stage" under a format that has none is the summary lying.
    if (!_groupsFeedKnockout) {
      return '$groups groups of $size, each playing its own table.';
    }
    return '$groups groups of $size, '
        '$qualifiers into the knockout stage.';
  }

  String _scheduleSummary() {
    final courts = _parsedCourts;
    if (courts.isEmpty) {
      return 'Without courts, every match is scheduled at the competition '
          'start time and players have no idea when they are on.';
    }
    final perHour = 60 ~/
        (_schedule.matchMinutes + _schedule.changeoverMinutes).clamp(1, 240);
    final hours = _schedule.dayEndHour - _schedule.dayStartHour;
    final capacity = perHour * hours * courts.length;
    return '${courts.length} courts · about $perHour matches per court per '
        'hour · roughly $capacity matches in a '
        '${_schedule.dayStartHour}:00–${_schedule.dayEndHour}:00 day. '
        'Anything that does not fit rolls to the next day.';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed:
                value - step >= min ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed:
                value + step <= max ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}
