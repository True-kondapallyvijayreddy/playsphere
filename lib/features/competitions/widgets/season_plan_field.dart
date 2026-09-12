import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/billing.dart';
import '../../../core/models/ground.dart';
import '../../../core/models/venue.dart';
import '../../../core/models/venue_plan.dart';
import '../../../core/providers.dart';
import '../../../data/tournament_repository.dart';
import '../../../domain/draw/draft_season_plan.dart';
import '../../../shared/app_scaffold.dart';
import '../../../shared/ui_kit.dart';
import '../../tournaments/widgets/venue_selector_dialog.dart'
    show showQuickAddVenueDialog;

/// The grounds a season being created has, and the terms it has them on.
///
/// Mutable and held by the form, like `SeasonBranding`: the grounds are
/// chosen before the season document exists, some of them are venues that do
/// not exist yet either, and none of it can be written until Create is
/// pressed. [ensureVenues] and [savePlans] are the two halves of committing
/// it, in that order, because a tournament is created with venue ids and a
/// venue plan is written under a tournament id.
class SeasonGroundsDraft extends ChangeNotifier {
  final List<SeasonGround> _grounds = [];

  List<SeasonGround> get grounds => List.unmodifiable(_grounds);

  bool get isEmpty => _grounds.isEmpty;

  bool contains(String venueId) => _grounds.any((g) => g.venue.id == venueId);

  /// Venue ids, for the tournament document and for every event's schedule
  /// config. Only meaningful after [ensureVenues] has run for new grounds.
  List<String> get venueIds => [for (final g in _grounds) g.venue.id];

  void add(SeasonGround ground) {
    if (ground.venue.id.isNotEmpty && contains(ground.venue.id)) return;
    _grounds.add(ground);
    notifyListeners();
  }

  void remove(String venueId) {
    _grounds.removeWhere((g) => g.venue.id == venueId);
    notifyListeners();
  }

  void toggle(Venue venue) {
    if (contains(venue.id)) {
      remove(venue.id);
    } else {
      add(SeasonGround(venue: venue, plan: VenuePlan(venueId: venue.id)));
    }
  }

  /// Replaces one ground's playing windows — the "9 to 6" / "floodlit until
  /// 11" answer that decides how many matches the day actually holds.
  void setSessions(String venueId, List<DaySession> sessions) {
    final index = _grounds.indexWhere((g) => g.venue.id == venueId);
    if (index < 0) return;
    final current = _grounds[index];
    _grounds[index] = current.copyWith(
      plan: current.plan.copyWith(sessions: sessions),
    );
    notifyListeners();
  }

  /// Creates every ground that does not exist yet, and reports which local
  /// ids became which real ones.
  ///
  /// Runs before the tournament is created, because the tournament document
  /// carries the ids. A ground typed on the form is a real venue afterwards —
  /// the club will play there again, and re-typing it next season is exactly
  /// the friction this whole flow exists to remove.
  ///
  /// The returned map is not a convenience: a category pinned to a ground
  /// added on this form holds the local id, and a restriction naming an id
  /// nothing has is a restriction that confines that draw to no courts at
  /// all. The caller has to re-point them, so it is handed what changed.
  Future<Map<String, String>> ensureVenues({
    required TournamentRepository repo,
    required String orgId,
  }) async {
    final remap = <String, String>{};
    for (var i = 0; i < _grounds.length; i++) {
      final ground = _grounds[i];
      if (!ground.isNew && ground.venue.id.isNotEmpty) continue;
      // The id on the draft is a local key; `createVenue` allocates the real
      // one. Everything else on the venue — its courts and its hours, which
      // the rules check — goes up exactly as the organizer set it.
      final id = await repo.createVenue(ground.venue);
      remap[ground.venue.id] = id;
      _grounds[i] = SeasonGround(
        venue: ground.venue.withId(id),
        plan: ground.plan.rekeyed(id),
        hourlyRatePaise: ground.hourlyRatePaise,
        marketGroundId: ground.marketGroundId,
      );
    }
    if (remap.isNotEmpty) notifyListeners();
    return remap;
  }

  /// Writes the per-ground terms under the season, once it has an id.
  ///
  /// Only for grounds the organizer actually set something on: a plan that
  /// says nothing is a document that changes nothing, and the venue's own
  /// hours already say it.
  Future<void> savePlans({
    required TournamentRepository repo,
    required String orgId,
    required String tournamentId,
  }) async {
    for (final ground in _grounds) {
      if (ground.plan.isUnrestricted) continue;
      await repo.saveVenuePlan(
        orgId: orgId,
        tournamentId: tournamentId,
        plan: ground.plan.copyWith(venueName: ground.venue.name),
      );
    }
  }
}

/// A named pattern of playing hours, offered instead of two time pickers.
///
/// The complaint these answer: an organizer knows their ground as "we have it
/// mornings", "it is ours all day Saturday", "there are lights so we can run
/// till eleven". Turning that into a start minute and an end minute is work
/// the app can do, and every organizer who skipped it got the venue's default
/// hours and a capacity number that did not match their ground.
enum GroundHoursPreset {
  morning('Morning', 6, 12),
  day('Day', 9, 18),
  afternoon('Afternoon', 12, 18),
  evening('Evening', 16, 22),
  floodlit('Floodlit', 6, 23),
  allDay('All day', 0, 24);

  const GroundHoursPreset(this.label, this.startHour, this.endHour);

  final String label;
  final int startHour;
  final int endHour;

  DaySession get session => DaySession(
        startMinute: startHour * 60,
        endMinute: endHour * 60,
        label: label,
      );

  String get hoursLabel =>
      '${startHour.toString().padLeft(2, '0')}:00–'
      '${endHour.toString().padLeft(2, '0')}:00';
}

/// The grounds step of season creation, with a live answer to "does this
/// fit?" underneath it.
///
/// ## Why the verdict lives on the form
///
/// This is the screen the Play Store feedback was about. An organizer added
/// four grounds for twelve cricket matches, created the season, generated a
/// schedule, found it did not fit, came back, added a fifth, and generated
/// again. Every number needed to answer that was on this form before anything
/// was written — twelve matches, four grounds, three and a quarter hours a
/// cricket match, the hours each ground is open.
///
/// So the answer is here, and it recomputes on every tick: add a ground and
/// the shortfall drops in front of you. Nothing is hidden behind a Generate
/// button, and the arithmetic is [DraftSeasonPlan], which is the scheduler's
/// own — so the verdict cannot promise something the schedule then refuses.
class SeasonPlanField extends ConsumerWidget {
  const SeasonPlanField({
    super.key,
    required this.orgId,
    required this.draft,
    required this.events,
    required this.start,
    required this.end,
    required this.onChanged,
    this.defaultTurnaroundMinutes = 5,
    this.onAddDay,
  });

  final String orgId;
  final SeasonGroundsDraft draft;

  /// What the season is being asked to hold, straight off the category list.
  final List<SeasonEventPlan> events;

  final DateTime? start;
  final DateTime? end;

  final VoidCallback onChanged;
  final int defaultTurnaroundMinutes;

  /// Lets the verdict's "add a day" suggestion actually add one, rather than
  /// telling the organizer to scroll up and do it themselves.
  final VoidCallback? onAddDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final venuesAsync = ref.watch(venuesProvider(orgId));
    final saved = venuesAsync.valueOrNull ?? const <Venue>[];

    final preview = DraftSeasonPlan.build(
      start: start,
      end: end,
      grounds: draft.grounds,
      events: events,
      defaultTurnaroundMinutes: defaultTurnaroundMinutes,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Grounds & schedule',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (draft.isEmpty)
                  Text(
                    'Required',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Pick where this season is played and when each ground is '
              'yours. The plan below updates as you go.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            for (final ground in draft.grounds)
              _GroundRow(
                ground: ground,
                onHours: (sessions) {
                  draft.setSessions(ground.venue.id, sessions);
                  onChanged();
                },
                onRemove: () {
                  draft.remove(ground.venue.id);
                  onChanged();
                },
              ),

            // Saved grounds this season is not using yet, as one-tap adds.
            // A club plays at the same two or three places all year, so the
            // common case is picking from this list and never opening a
            // dialog at all.
            if (saved.any((v) => !v.isArchived && !draft.contains(v.id))) ...[
              const SizedBox(height: 4),
              Text(
                'Your other grounds',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in saved)
                    if (!v.isArchived && !draft.contains(v.id))
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text(
                          '${v.name} · ${v.usableCourts.length} '
                          '${v.usableCourts.length == 1 ? "court" : "courts"}',
                        ),
                        onPressed: () {
                          draft.toggle(v);
                          onChanged();
                        },
                      ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addOwnGround(context, ref),
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('Add a ground'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rentGround(context, ref),
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: const Text('Rent a ground'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            SeasonPlanVerdict(
              preview: preview,
              hasGrounds: !draft.isEmpty,
              hasDates: start != null,
              onAddDay: onAddDay,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOwnGround(BuildContext context, WidgetRef ref) async {
    final venue = await showQuickAddVenueDialog(context, orgId: orgId);
    if (venue == null) return;
    // A local id until it is written. The season is not saved yet, so this
    // has to be something the plan and the category pickers can key on
    // without a round trip to Firestore.
    // The dialog does not ask for hours, so the venue's own defaults apply —
    // 06:00 to 22:00, which satisfies the rules' open-before-close check. The
    // organizer narrows them with the hours menu on the row.
    final local = venue.withId('new_${DateTime.now().microsecondsSinceEpoch}');
    draft.add(
      SeasonGround(
        venue: local,
        plan: VenuePlan(venueId: local.id, venueName: local.name),
        isNew: true,
      ),
    );
    onChanged();
  }

  Future<void> _rentGround(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<Ground>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RentGroundSheet(
        sportId: events.isEmpty ? null : events.first.sportId,
      ),
    );
    if (picked == null) return;

    final id = 'new_${DateTime.now().microsecondsSinceEpoch}';

    // `firestore.rules` refuses a venue whose day ends before it starts, and
    // a listing is somebody else's document — it can carry anything. Falling
    // back to the venue defaults keeps a badly-filled listing from making the
    // season un-creatable with an error about a field the organizer never saw.
    final opens = picked.openHour;
    final closes = picked.closeHour;
    final validHours = opens >= 0 && closes <= 24 && opens < closes;

    final venue = Venue(
      id: id,
      orgId: orgId,
      name: picked.name,
      address: picked.address,
      city: picked.city,
      district: picked.district,
      latitude: picked.latitude,
      longitude: picked.longitude,
      openHour: validHours ? opens : 6,
      closeHour: validHours ? closes : 22,
      // One playing area unless the listing says otherwise. A rented ground
      // is a pitch, not a hall of six courts, and claiming courts it does
      // not have would inflate the capacity this whole panel exists to
      // report honestly.
      courts: [Court(id: '${id}_c1', name: picked.name)],
    );
    draft.add(
      SeasonGround(
        venue: venue,
        plan: VenuePlan(
          venueId: id,
          venueName: picked.name,
          sessions: [
            DaySession(
              startMinute: (validHours ? opens : 6) * 60,
              endMinute: (validHours ? closes : 22) * 60,
              label: 'Booked hours',
            ),
          ],
        ),
        hourlyRatePaise: picked.hourlyRatePaise,
        marketGroundId: picked.id,
        isNew: true,
      ),
    );
    onChanged();
  }
}

/// One ground on the form: what it is, when it is ours, what it holds.
class _GroundRow extends StatelessWidget {
  const _GroundRow({
    required this.ground,
    required this.onHours,
    required this.onRemove,
  });

  final SeasonGround ground;
  final ValueChanged<List<DaySession>> onHours;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = ground.plan.sessionsFor(ground.venue);
    final hours = sessions.map((s) => s.timeLabel).join(', ');
    final rate = ground.hourlyRatePaise;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Ps.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ground.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (rate != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        rate == 0
                            ? 'Free'
                            : '${Pricing.formatPaise(rate)}/hr',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${ground.courts} '
                  '${ground.courts == 1 ? "playing area" : "playing areas"} · '
                  '$hours',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _HoursMenu(current: sessions, onPicked: onHours),
          IconButton(
            tooltip: 'Remove this ground',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// The "when is this ground ours?" control.
class _HoursMenu extends StatelessWidget {
  const _HoursMenu({required this.current, required this.onPicked});

  final List<DaySession> current;
  final ValueChanged<List<DaySession>> onPicked;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<GroundHoursPreset>(
      tooltip: 'Playing hours',
      icon: const Icon(Icons.schedule, size: 18),
      onSelected: (preset) => onPicked([preset.session]),
      itemBuilder: (context) => [
        for (final preset in GroundHoursPreset.values)
          PopupMenuItem(
            value: preset,
            height: 44,
            child: Row(
              children: [
                Expanded(child: Text(preset.label)),
                const SizedBox(width: 12),
                Text(
                  preset.hoursLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The verdict: what the season needs, what the grounds hold, and — when they
/// do not hold it — what would fix it.
class SeasonPlanVerdict extends StatelessWidget {
  const SeasonPlanVerdict({
    super.key,
    required this.preview,
    required this.hasGrounds,
    required this.hasDates,
    this.onAddDay,
  });

  final SeasonPlanPreview preview;
  final bool hasGrounds;
  final bool hasDates;
  final VoidCallback? onAddDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!hasDates || !hasGrounds || preview.matchesRequired == 0) {
      return _Frame(
        color: theme.colorScheme.surfaceContainerHighest,
        icon: Icons.calculate_outlined,
        title: 'The plan appears here',
        body: Text(
          !hasDates
              ? 'Pick the dates and this will say whether the season fits.'
              : !hasGrounds
                  ? 'Add a ground and this will say whether the season fits.'
                  : 'Add a category and this will say whether it fits the '
                      'grounds and the days you have.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final fits = preview.fits;
    final scheme = theme.colorScheme;

    return _Frame(
      color: fits ? const Color(0x1A2E7D32) : scheme.errorContainer,
      icon: fits ? Icons.check_circle_outline : Icons.error_outline,
      iconColor: fits ? const Color(0xFF2E7D32) : scheme.onErrorContainer,
      title: fits
          ? '${preview.matchesRequired} matches fit'
          : 'Short by ${preview.unplacedMatches == 0 ? preview.report.shortfall : preview.unplacedMatches} '
              '${(preview.unplacedMatches == 0 ? preview.report.shortfall : preview.unplacedMatches) == 1 ? "match" : "matches"}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${preview.matchesRequired} matches · '
            '${preview.report.totalCapacity} slots on ${preview.courts} '
            '${preview.courts == 1 ? "playing area" : "playing areas"} · '
            '${preview.days.length} '
            '${preview.days.length == 1 ? "day" : "days"}'
            '${fits && preview.spareSlots > 0 ? " · ${preview.spareSlots} spare" : ""}',
            style: theme.textTheme.bodySmall,
          ),
          if (!fits) ...[
            const SizedBox(height: 8),
            for (final problem in preview.report.problems.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $problem', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 4),
            Text(
              'What would fix it',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onAddDay != null)
                  ActionChip(
                    avatar: const Icon(Icons.today_outlined, size: 15),
                    label: const Text('Add a day'),
                    onPressed: onAddDay,
                  ),
                const _Hint('Extend a ground\'s hours'),
                const _Hint('Add another ground'),
                const _Hint('Use a shorter format'),
              ],
            ),
          ],
          if (preview.days.length > 1) ...[
            const SizedBox(height: 12),
            _DayStrip(days: preview.days),
          ],
        ],
      ),
    );
  }
}

/// Day by day, how full the season is. The "provide the schedule" half: an
/// organizer deciding how many days to book can see that day three is empty
/// before they book it.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.days});

  final List<SeasonDayLoad> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = DateFormat('EEE d MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Day by day', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        for (final day in days.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    format.format(day.day),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: day.slots == 0
                          ? 0
                          : (day.matches / day.slots).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 54,
                  child: Text(
                    '${day.matches}/${day.slots}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (days.length > 10)
          Text(
            '… and ${days.length - 10} more days',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(text),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        backgroundColor: Colors.transparent,
      );
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor,
  });

  final Color color;
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Ps.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

/// Finds a ground to rent, without leaving the season form.
///
/// Search and pick only — no booking. A season spans days and its matches are
/// not placed on a clock yet, so there are no hours to reserve; the organizer
/// books the hours from the season page once the timetable exists. What this
/// gives the form is the thing it actually needs: a real ground, its opening
/// hours and its rate, so the capacity arithmetic below is about a ground
/// that exists.
class _RentGroundSheet extends ConsumerStatefulWidget {
  const _RentGroundSheet({this.sportId});

  final String? sportId;

  @override
  ConsumerState<_RentGroundSheet> createState() => _RentGroundSheetState();
}

class _RentGroundSheetState extends ConsumerState<_RentGroundSheet> {
  final _terms = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _query.isEmpty
        ? const AsyncValue<List<Ground>>.data([])
        : ref.watch(groundSearchProvider(
            GroundQuery(keywords: _query, sportId: widget.sportId),
          ));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rent a ground', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Grounds listed on PlaySphere. Adding one here puts its hours '
              'and its rate into the season plan — you book the hours from '
              'the season page once the timetable is set.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _terms,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'City or ground name',
                hintText: 'e.g. Warangal',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: results.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(errorMessage(e)),
                ),
                data: (grounds) {
                  if (_query.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Search by the city you are playing in.',
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }
                  if (grounds.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No grounds listed for "$_query" yet. Add your own '
                        'ground instead — it works exactly the same in the '
                        'plan.',
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: grounds.length,
                    itemBuilder: (context, i) {
                      final g = grounds[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(g.name),
                        subtitle: Text(
                          '${g.city} · ${g.openHour.toString().padLeft(2, '0')}:00–'
                          '${g.closeHour.toString().padLeft(2, '0')}:00 · '
                          '${g.rateLabel}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => Navigator.of(context).pop(g),
                          child: const Text('Use'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
