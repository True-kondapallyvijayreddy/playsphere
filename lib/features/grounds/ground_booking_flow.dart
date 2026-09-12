import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/models/billing.dart';
import '../../core/models/ground.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../data/ground_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/identity.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ground_trust.dart';
import '../../shared/offline_fee_notice.dart';
import 'report_ground_sheet.dart';
import 'widgets/day_slot_grid.dart';

/// What a completed booking hands back to whoever asked for one.
///
/// The event form needs the ground's name to put in its venue field and the
/// booking id to hold on to, and wants neither the whole `Ground` nor a
/// second read to get them.
class BookedGround {
  const BookedGround({
    required this.ground,
    required this.booking,
  });

  final Ground ground;
  final GroundBooking booking;

  /// What goes in `Competition.venue` — the human answer to "where is this
  /// being played", which is what gets printed on a team sheet and read out
  /// in a WhatsApp group.
  String get venueLabel => [
        ground.name,
        if (ground.city.isNotEmpty) ground.city,
      ].join(', ');
}

/// Finds a ground and books an hour on it, as one flow.
///
/// ## Why this is a sheet and not a screen
///
/// It is opened *during* something else — creating an event, most of the
/// time. Pushing a full screen would mean the organizer leaves a half-filled
/// form to go shopping for a pitch, and a form left to go somewhere else is a
/// form that gets abandoned. A sheet keeps the event underneath it, and
/// closing it without booking leaves everything typed so far exactly where it
/// was.
///
/// Returns null if the person backs out — which is a first-class outcome, not
/// a failure. "We'll play somewhere else" is the answer most village and
/// school clubs will give, and the flow that asks has to accept it gracefully
/// rather than making a booking feel compulsory.
Future<BookedGround?> showGroundBookingSheet(
  BuildContext context, {
  String? sportId,
  String? initialCity,
  DateTime? initialDate,
  String? orgId,
}) {
  return showModalBottomSheet<BookedGround>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => _GroundBookingSheet(
        scrollController: controller,
        sportId: sportId,
        initialCity: initialCity,
        initialDate: initialDate,
        orgId: orgId,
      ),
    ),
  );
}

class _GroundBookingSheet extends ConsumerStatefulWidget {
  const _GroundBookingSheet({
    required this.scrollController,
    this.sportId,
    this.initialCity,
    this.initialDate,
    this.orgId,
  });

  final ScrollController scrollController;
  final String? sportId;
  final String? initialCity;
  final DateTime? initialDate;
  final String? orgId;

  @override
  ConsumerState<_GroundBookingSheet> createState() =>
      _GroundBookingSheetState();
}

class _GroundBookingSheetState extends ConsumerState<_GroundBookingSheet> {
  late final _terms = TextEditingController(text: widget.initialCity ?? '');

  /// What was actually searched, as opposed to what is currently being typed.
  /// Kept separate so the query does not re-run on every keystroke — each one
  /// would be a fresh pair of Firestore reads.
  String _searchedTerms = '';

  /// Which sport they are looking for a ground for.
  ///
  /// Asked first, and asked at all, because it is the question that decides
  /// whether a listing is an answer: a badminton hall is not a ground for a
  /// cricket match, and a search that ignores the sport spends somebody's
  /// evening ringing round places that were never going to work. Pre-filled
  /// and left alone when the caller already knows — booking from an event
  /// form should not re-ask a question the event already answered.
  late String? _sportId = widget.sportId;

  /// The hour they want to start. Null until they say, which is a real
  /// answer — "anything on Sunday" is how half of these searches begin — so
  /// it filters the results only when it is set.
  int? _wantedHour;

  /// "Near me" is a separate mode from the city search, not a filter on top
  /// of it — a search-by-distance and a search-by-name return genuinely
  /// different result sets (a ground can be 4km away in the next town over,
  /// which a city search for "Warangal" would never surface).
  List<GroundNearby>? _nearby;
  bool _locating = false;
  String? _nearbyError;

  late DateTime _date = widget.initialDate ?? DateTime.now();
  int _hours = 2;

  Ground? _selected;
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    // A city handed in from the event form is a city the person already
    // chose; making them press Search again to confirm their own input is
    // busywork.
    if ((widget.initialCity ?? '').trim().isNotEmpty) {
      _searchedTerms = widget.initialCity!.trim();
    }
  }

  @override
  void dispose() {
    _terms.dispose();
    super.dispose();
  }

  void _runSearch() => setState(() {
        _searchedTerms = _terms.text.trim();
        _nearby = null;
      });

  Future<void> _searchNearby() async {
    setState(() {
      _locating = true;
      _nearbyError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _nearbyError =
            'Location permission was declined. Allow it in your phone '
            'settings to search nearby, or search by city instead.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() =>
            _nearbyError = 'Turn on location services and try again.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final hits = await ref.read(groundRepositoryProvider).nearby(
            latitude: pos.latitude,
            longitude: pos.longitude,
            sportId: _sportId,
          );
      if (mounted) setState(() => _nearby = hits);
    } catch (e) {
      if (mounted) setState(() => _nearbyError = e.toString());
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Picking a ground no longer loads anything.
  ///
  /// `DaySlotGrid` watches the day's bookings itself, so there is no fetch to
  /// kick off and no loading flag to hold — which is the point: the read this
  /// method used to make was a snapshot, and a snapshot of a calendar two
  /// people are booking against is out of date the moment it arrives.
  void _pickGround(Ground g) => setState(() => _selected = g);

  Future<void> _book(int startHour) async {
    final g = _selected;
    final me = ref.read(authUserProvider).valueOrNull;
    if (g == null || me == null) return;

    setState(() => _booking = true);
    try {
      final booking = await ref.read(groundRepositoryProvider).book(
            ground: g,
            day: _date,
            startHour: startHour,
            endHour: startHour + _hours,
            bookedBy: me,
            orgId: widget.orgId,
            sportId: _sportId,
          );
      if (mounted) {
        Navigator.of(context).pop(BookedGround(ground: g, booking: booking));
      }
    } catch (e) {
      // Almost always "somebody just took that slot" — thrown by the booking
      // transaction. Nothing to reload: the grid is watching the day and has
      // already redrawn that hour as booked, which is the explanation the
      // error message on its own does not give.
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selected == null ? 'Find a ground' : _selected!.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selected != null)
                TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('Change'),
                ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _selected == null ? _searchStep(theme) : _slotStep(theme),
        ),
      ],
    );
  }

  /// Which sport, when, and then where.
  ///
  /// ## Why it asks in that order
  ///
  /// It used to open on a city box and nothing else, which quietly assumed
  /// the two facts that actually decide whether a listing is any use: the
  /// sport, because a badminton hall is not a cricket ground, and the hour,
  /// because a ground that shuts at six is not an answer to "somewhere to
  /// play at seven". Both were knowable before a single result was drawn,
  /// and asking afterwards means the person rings round places that were
  /// never going to work.
  ///
  /// The sport is a filter that cannot be got wrong, and the time is a
  /// filter and a head start — the ground they pick opens with that hour
  /// already selected.
  Widget _searchStep(ThemeData theme) {
    final nearby = _nearby;
    final query = GroundQuery(
      keywords: _searchedTerms,
      sportId: _sportId,
      openAtHour: _wantedHour,
    );

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // ---- 1. Which sport ------------------------------------------
        Text('Which sport?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Any'),
              selected: _sportId == null,
              onSelected: (_) => setState(() => _sportId = null),
            ),
            for (final sport in SportCatalog.all)
              ChoiceChip(
                label: Text('${sport.icon}  ${sport.name}'),
                selected: _sportId == sport.id,
                onSelected: (on) =>
                    setState(() => _sportId = on ? sport.id : null),
              ),
          ],
        ),

        // ---- 2. When -------------------------------------------------
        const SizedBox(height: 20),
        Text('When?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _DateRow(date: _date, onPick: (d) => setState(() => _date = d)),
        const SizedBox(height: 12),
        _HoursRow(hours: _hours, onChanged: (h) => setState(() => _hours = h)),
        const SizedBox(height: 12),
        _StartHourRow(
          hour: _wantedHour,
          onChanged: (h) => setState(() => _wantedHour = h),
        ),

        // ---- 3. Where ------------------------------------------------
        const SizedBox(height: 20),
        Text('Where?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _terms,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runSearch(),
          decoration: InputDecoration(
            labelText: 'Ground, area, city or sport',
            hintText: 'e.g. Gachibowli turf',
            helperText: 'Any word will do — a name, an area, or a city.',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.arrow_forward),
              onPressed: _runSearch,
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _locating ? null : _searchNearby,
          icon: _locating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.near_me_outlined),
          label: Text(nearby == null ? 'Grounds near me' : 'Search again'),
        ),
        if (_nearbyError != null) ...[
          const SizedBox(height: 8),
          Text(_nearbyError!,
              style: TextStyle(color: theme.colorScheme.error)),
        ],

        const SizedBox(height: 20),

        if (nearby != null)
          _NearbyResults(hits: nearby, onPick: _pickGround)
        else if (query.isEmpty)
          const EmptyState(
            icon: Icons.travel_explore_outlined,
            title: 'Where are you playing?',
            message: 'Pick a sport, type a name or an area, or tap '
                '"Grounds near me".',
          )
        else
          _Results(query: query, onPick: _pickGround),
      ],
    );
  }

  Widget _slotStep(ThemeData theme) {
    final g = _selected!;
    final price = g.priceForPaise(_hours);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          [g.city, if (g.address != null) g.address!].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${g.rateLabel} · open ${groundHourLabel(g.openHour)}'
          '–${groundHourLabel(g.closeHour)}',
          style: theme.textTheme.bodyMedium,
        ),
        if (g.facilities.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(g.facilities.join(' · '), style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 16),

        // Changing the day re-keys the grid's provider family, which
        // subscribes to the new day on its own. Nothing to fetch here.
        _DateRow(
          date: _date,
          onPick: (d) => setState(() => _date = d),
        ),
        const SizedBox(height: 12),
        _HoursRow(
          hours: _hours,
          onChanged: (h) => setState(() => _hours = h),
        ),
        const SizedBox(height: 16),

        // The trust surface, above the calendar rather than below it. Somebody
        // deciding whether to give this listing an evening and a phone call
        // should meet what is known about it before they meet the slots.
        GroundTrustPanel(
          ground: g,
          onReport: () => showReportGroundSheet(context, ground: g),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: Text(
                'Pick a time',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              price == 0
                  ? 'Free'
                  : '${Pricing.formatPaise(price)} for $_hours hr'
                      '${_hours == 1 ? '' : 's'}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_wantedHour != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'You asked for ${groundHourLabel(_wantedHour!)}.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 6),

        DaySlotGrid(
          ground: g,
          day: _date,
          hours: _hours,
          busy: _booking,
          onBook: _book,
        ),

        const SizedBox(height: 16),
        Text(
          _booking
              ? 'Booking…'
              : 'Tap a free time to hold it. The slot is yours as soon as it '
                  'is booked — nobody else can take it.',
          style: theme.textTheme.bodySmall,
        ),
        // Sits directly under the tap target that takes the slot, because
        // this is the exact moment somebody could believe they have just
        // paid for it. `GroundRepository.book` records the rate as what is
        // OWED and writes no `payments/` row at all.
        if (g.hourlyRatePaise > 0) ...[
          const SizedBox(height: 10),
          const OfflineFeeNotice.ground(),
          const SizedBox(height: 10),
          // And the sentence the fee notice does not say: the fraud in this
          // marketplace is a phone call asking for an advance, and the person
          // has to still be carrying this when it comes.
          const AdvancePaymentWarning(),
        ],
      ],
    );
  }
}

class _NearbyResults extends StatelessWidget {
  const _NearbyResults({required this.hits, required this.onPick});

  final List<GroundNearby> hits;
  final ValueChanged<Ground> onPick;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return const EmptyState(
        icon: Icons.stadium_outlined,
        title: 'Nothing registered nearby yet',
        message:
            'No ground within 15km has its location set. Try a city search '
            'instead — plenty of listings haven\'t pinned their map location.',
      );
    }
    return Column(
      children: [
        for (final hit in hits)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              // The photo is the whole reason `Ground.photoUrl` exists:
              // somebody choosing between two grounds an hour apart is
              // choosing on the strength of a picture. It was on the model
              // from the start and rendered nowhere. Falls back to the
              // indoor/outdoor glyph, so a ground with no photo still reads.
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: PsNetworkImage(
                    url: hit.ground.photoUrl,
                    fallback: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Text(hit.ground.isIndoor ? '\u{1F3DF}' : '\u{1F333}'),
                      ),
                    ),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Flexible(child: Text(hit.ground.name)),
                  const SizedBox(width: 5),
                  GroundTrustBadge.of(hit.ground, compact: true),
                ],
              ),
              subtitle: Text(
                [hit.distanceLabel, hit.ground.rateLabel].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Ground details & food',
                    icon: const Icon(Icons.info_outline),
                    onPressed: () =>
                        context.push(Routes.ground(hit.ground.id)),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => onPick(hit.ground),
            ),
          ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onPick});

  final GroundQuery query;
  final ValueChanged<Ground> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(groundSearchProvider(query));

    return AsyncView(
      value: results,
      onRetry: () => ref.invalidate(groundSearchProvider(query)),
      builder: (grounds) {
        if (grounds.isEmpty) {
          // Named filters, because "no results" with three of them applied
          // is unactionable — the person cannot tell which one to loosen.
          final applied = [
            if (query.keywords.trim().isNotEmpty) '"${query.keywords.trim()}"',
            if (query.sportId != null)
              SportCatalog.byId(query.sportId!).name.toLowerCase(),
            if (query.openAtHour != null)
              'open at ${groundHourLabel(query.openAtHour!)}',
          ];
          return EmptyState(
            icon: Icons.stadium_outlined,
            title: 'No grounds match that yet',
            message: applied.isEmpty
                ? 'PlaySphere is new here. You can still run the event — '
                    'just type where you are playing instead.'
                : 'Nothing listed for ${applied.join(' · ')}. Try fewer '
                    'words, another sport, or a different time — and you can '
                    'still run the event by typing where you are playing.',
          );
        }
        return Column(
          children: [
            for (final g in grounds)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
              // The photo is the whole reason `Ground.photoUrl` exists:
                  // somebody choosing between two grounds an hour apart is
                  // choosing on the strength of a picture. It was on the model
                  // from the start and rendered nowhere. Falls back to the
                  // indoor/outdoor glyph, so a ground with no photo still reads.
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: PsNetworkImage(
                        url: g.photoUrl,
                        fallback: ColoredBox(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Text(g.isIndoor ? '\u{1F3DF}' : '\u{1F333}'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(child: Text(g.name)),
                      const SizedBox(width: 5),
                      GroundTrustBadge.of(g, compact: true),
                    ],
                  ),
                  subtitle: Text(
                    [
                      g.rateLabel,
                      '${groundHourLabel(g.openHour)}–'
                          '${groundHourLabel(g.closeHour)}',
                      if (g.facilities.isNotEmpty) g.facilities.first,
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A separate tap target from the tile itself: the tile
                      // picks this ground for the booking in progress, but a
                      // captain buying water for the team is not always
                      // creating an event to reach this ground at all — see
                      // `GroundDetailScreen`.
                      IconButton(
                        tooltip: 'Ground details & food',
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => context.push(Routes.ground(g.id)),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => onPick(g),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onPick});

  final DateTime date;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: date.isBefore(now) ? now : date,
          firstDate: now.subtract(const Duration(days: 1)),
          lastDate: now.add(const Duration(days: 180)),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          prefixIcon: Icon(Icons.calendar_today_outlined),
          border: OutlineInputBorder(),
        ),
        child: Text(DateFormat('EEEE, d MMMM yyyy').format(date)),
      ),
    );
  }
}

/// What time they want to start, or "any time".
///
/// Optional on purpose. "Anything on Sunday" is how a good half of these
/// searches begin, and a required time would force an answer that then
/// silently filters out the ground they would have taken at four instead of
/// three. Set, it does two jobs: grounds shut at that hour never appear, and
/// the ground they pick opens with that hour already chosen.
class _StartHourRow extends StatelessWidget {
  const _StartHourRow({required this.hour, required this.onChanged});

  final int? hour;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      value: hour,
      decoration: const InputDecoration(
        labelText: 'Start time',
        prefixIcon: Icon(Icons.access_time),
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Any time'),
        ),
        for (var h = 5; h <= 23; h++)
          DropdownMenuItem<int?>(value: h, child: Text(groundHourLabel(h))),
      ],
      onChanged: onChanged,
    );
  }
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.hours, required this.onChanged});

  final int hours;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: hours,
      decoration: const InputDecoration(
        labelText: 'How long',
        prefixIcon: Icon(Icons.schedule),
        border: OutlineInputBorder(),
      ),
      items: [
        for (var h = 1; h <= 8; h++)
          DropdownMenuItem(
            value: h,
            child: Text('$h hour${h == 1 ? '' : 's'}'),
          ),
      ],
      onChanged: (h) => onChanged(h ?? hours),
    );
  }
}
