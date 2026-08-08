import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/billing.dart';
import '../../core/models/ground.dart';
import '../../core/providers.dart';
import '../../data/ground_repository.dart';
import '../../shared/app_scaffold.dart';

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
  late final _city = TextEditingController(text: widget.initialCity ?? '');

  /// The city actually searched, as opposed to what is currently being typed.
  /// Kept separate so the query does not re-run on every keystroke — each one
  /// would be a new Firestore listener.
  String _searchedCity = '';

  late DateTime _date = widget.initialDate ?? DateTime.now();
  int _hours = 2;

  Ground? _selected;
  DayAvailability? _availability;
  bool _loadingSlots = false;
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    // A city handed in from the event form is a city the person already
    // chose; making them press Search again to confirm their own input is
    // busywork.
    if ((widget.initialCity ?? '').trim().isNotEmpty) {
      _searchedCity = widget.initialCity!.trim();
    }
  }

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  Future<void> _pickGround(Ground g) async {
    setState(() {
      _selected = g;
      _availability = null;
      _loadingSlots = true;
    });
    await _loadSlots();
  }

  Future<void> _loadSlots() async {
    final g = _selected;
    if (g == null) return;
    setState(() => _loadingSlots = true);
    try {
      final availability = await ref
          .read(groundRepositoryProvider)
          .availabilityFor(ground: g, day: _date);
      if (mounted) setState(() => _availability = availability);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _book(int startHour) async {
    final g = _selected;
    final me = ref.read(currentUserProvider).valueOrNull;
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
            sportId: widget.sportId,
          );
      if (mounted) {
        Navigator.of(context).pop(BookedGround(ground: g, booking: booking));
      }
    } catch (e) {
      // Almost always "somebody just took that slot" — thrown by the booking
      // transaction. Reloading the slots is the useful next thing, so the
      // person sees what is actually left rather than a stale grid with the
      // gone slot still on it.
      if (mounted) {
        showError(context, e);
        await _loadSlots();
      }
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
                  onPressed: () => setState(() {
                    _selected = null;
                    _availability = null;
                  }),
                  child: const Text('Change'),
                ),
              IconButton(
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

  Widget _searchStep(ThemeData theme) {
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => setState(() => _searchedCity = v.trim()),
          decoration: InputDecoration(
            labelText: 'City',
            hintText: 'e.g. Hyderabad',
            prefixIcon: const Icon(Icons.location_on_outlined),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () =>
                  setState(() => _searchedCity = _city.text.trim()),
            ),
          ),
        ),
        const SizedBox(height: 12),
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

        if (_searchedCity.isEmpty)
          const EmptyState(
            icon: Icons.travel_explore_outlined,
            title: 'Where are you playing?',
            message: 'Enter a city to see the grounds listed there.',
          )
        else
          _Results(
            city: _searchedCity,
            sportId: widget.sportId,
            onPick: _pickGround,
          ),
      ],
    );
  }

  Widget _slotStep(ThemeData theme) {
    final g = _selected!;
    final availability = _availability;
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

        _DateRow(
          date: _date,
          onPick: (d) async {
            setState(() => _date = d);
            await _loadSlots();
          },
        ),
        const SizedBox(height: 12),
        _HoursRow(
          hours: _hours,
          onChanged: (h) => setState(() => _hours = h),
        ),
        const SizedBox(height: 16),

        if (_loadingSlots)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (availability == null)
          const SizedBox.shrink()
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Available start times',
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
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final starts = availability.startsFitting(_hours);
            if (starts.isEmpty) {
              return const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'Nothing free that long',
                message:
                    'Try a shorter slot, another day, or a different ground.',
              );
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in starts)
                  ActionChip(
                    label: Text(
                      '${groundHourLabel(h)}–${groundHourLabel(h + _hours)}',
                    ),
                    onPressed: _booking ? null : () => _book(h),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          Text(
            _booking
                ? 'Booking…'
                : 'Tap a time to hold it. The slot is yours as soon as it is '
                    'booked — nobody else can take it.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.city,
    required this.sportId,
    required this.onPick,
  });

  final String city;
  final String? sportId;
  final ValueChanged<Ground> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(
      groundSearchProvider(GroundQuery(city: city, sportId: sportId)),
    );

    return AsyncView(
      value: results,
      onRetry: () => ref.invalidate(
        groundSearchProvider(GroundQuery(city: city, sportId: sportId)),
      ),
      builder: (grounds) {
        if (grounds.isEmpty) {
          return EmptyState(
            icon: Icons.stadium_outlined,
            title: 'No grounds listed in $city yet',
            message:
                'PlaySphere is new here. You can still run the event — just '
                'type where you are playing instead.',
          );
        }
        return Column(
          children: [
            for (final g in grounds)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(g.isIndoor ? '🏟️' : '🌳'),
                  ),
                  title: Row(
                    children: [
                      Flexible(child: Text(g.name)),
                      if (g.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary),
                      ],
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
                  trailing: const Icon(Icons.chevron_right),
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
