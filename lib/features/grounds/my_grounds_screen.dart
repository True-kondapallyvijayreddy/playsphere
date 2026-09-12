import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/billing.dart';
import '../../core/models/ground.dart';
import '../../core/models/ground_verification.dart';
import '../../core/providers.dart';
import '../../data/ground_repository.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';
import '../../shared/ground_trust.dart';
import 'list_ground_flow.dart';

/// The ground owner's side of the marketplace.
///
/// ## Why a ground owner is not a club member
///
/// Everyone else in PlaySphere reaches the product through a club. A ground
/// owner does not: they own a turf, they want it booked, and they have no
/// reason to join a school or a village team to do it. So this screen is
/// reachable by any signed-in account, needs no membership, and lists only
/// what that account owns.
///
/// That is also why grounds are a top-level collection — see `Refs.grounds`.
class MyGroundsScreen extends ConsumerWidget {
  const MyGroundsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grounds = ref.watch(myGroundsProvider);

    return AppScaffold(
      title: 'My grounds',
      subtitle: 'Grounds you own and the bookings on them',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _listNewGround(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('List a ground'),
      ),
      body: AsyncView(
        value: grounds,
        onRetry: () => ref.invalidate(myGroundsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return ContentBounds(
              maxWidth: 620,
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const EmptyState(
                    icon: Icons.stadium_outlined,
                    title: 'No grounds listed yet',
                    message:
                        'List your ground, turf or court and clubs nearby can '
                        'find it and book it by the hour.',
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What listing does',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Your ground appears in searches by city and '
                            'sport. Clubs pick a date and an hour, and '
                            'PlaySphere holds the slot so nobody else can '
                            'take it. You set the hourly rate and the opening '
                            'hours, and you can switch the listing off at any '
                            'time without losing the bookings already made.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ContentBounds(
                maxWidth: 700,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in list)
                      _GroundCard(
                        ground: g,
                        onEdit: () => _openEditor(context, ref, g),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    Ground? existing,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroundEditor(existing: existing),
        fullscreenDialog: existing == null,
      ),
    );
  }

  /// Listing a new ground goes through on-site capture first.
  ///
  /// ## Why creating and editing take different routes
  ///
  /// Editing is a listing whose evidence already exists being corrected — a
  /// changed rate, a new closing time — and demanding a fresh trip to the
  /// ground to fix a typo would mean typos never get fixed. Creating is the
  /// act this whole feature exists to make expensive, so it is the one that
  /// goes through `ListGroundProofScreen`.
  ///
  /// The proof is gathered first and the details second, not the other way
  /// round, because an owner who has typed out their rates and facilities and
  /// is *then* told to walk outside and photograph the pitch will abandon the
  /// form. Asking for the hard part while they are still standing there is
  /// the difference between a flow that completes and one that does not.
  static Future<void> _listNewGround(BuildContext context, WidgetRef ref) async {
    final proof = await Navigator.of(context).push<GroundProofBundle>(
      MaterialPageRoute<GroundProofBundle>(
        builder: (_) => const ListGroundProofScreen(),
        fullscreenDialog: true,
      ),
    );
    if (proof == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroundEditor(proof: proof),
        fullscreenDialog: true,
      ),
    );
  }
}

class _GroundCard extends ConsumerWidget {
  const _GroundCard({required this.ground, required this.onEdit});

  final Ground ground;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bookings =
        ref.watch(groundBookingsProvider(ground.id)).valueOrNull ?? const [];
    final upcoming = bookings
        .where((b) =>
            b.holdsSlot && b.startsAt.isAfter(DateTime.now().subtract(
              const Duration(hours: 2),
            )))
        .toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // The owner's own view of where their listing
                          // stands. This is the only screen that shows it to
                          // the person who can do something about it — an
                          // owner whose listing is sitting in `pending`, or
                          // has been suspended, finds out here.
                          GroundTrustBadge.of(ground),
                        ],
                      ),
                      Text(
                        [ground.city, if (ground.address != null) ground.address!]
                            .join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Food menu',
                  icon: const Icon(Icons.fastfood_outlined),
                  onPressed: () => context.push('/grounds/${ground.id}/food/manage'),
                ),
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _Pill(ground.rateLabel, emphasis: true),
                _Pill('${groundHourLabel(ground.openHour)}'
                    '–${groundHourLabel(ground.closeHour)}'),
                if (!ground.isActive) const _Pill('Paused'),
                for (final s in ground.sportIds) _Pill(_sportName(s)),
              ],
            ),
            const Divider(height: 24),
            Text(
              upcoming.isEmpty
                  ? 'No upcoming bookings'
                  : '${upcoming.length} upcoming booking'
                      '${upcoming.length == 1 ? '' : 's'}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            for (final b in upcoming.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined, size: 20),
                title: Text(
                  '${DateFormat('EEE d MMM').format(b.startsAt)} · '
                  '${groundHourLabel(b.startHour)}–'
                  '${groundHourLabel(b.endHour)}',
                ),
                subtitle: Text(b.bookedByName),
                trailing: Text(
                  b.amountPaise == 0
                      ? 'Free'
                      : Pricing.formatPaise(b.amountPaise),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _sportName(String id) {
    final spec = SportCatalog.all.where((s) => s.id == id);
    return spec.isEmpty ? id : spec.first.name;
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.emphasis = false});

  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasis
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }
}

/// Lists a new ground, or edits one.
class GroundEditor extends ConsumerStatefulWidget {
  const GroundEditor({super.key, this.existing, this.proof});

  final Ground? existing;

  /// The on-site evidence gathered before this screen opened.
  ///
  /// Present exactly when a new ground is being listed, absent when an
  /// existing one is being edited — the two are mutually exclusive and the
  /// assert below says so, because a screen that silently accepted both would
  /// let somebody attach fresh proof to somebody else's listing.
  final GroundProofBundle? proof;

  @override
  ConsumerState<GroundEditor> createState() => _GroundEditorState();
}

class _GroundEditorState extends ConsumerState<GroundEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.contactPhone ?? '');
  late final _rate = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.hourlyRatePaise ~/ 100).toString(),
  );
  late final _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  late final Set<String> _sports = {...?widget.existing?.sportIds};
  late final Set<String> _facilities = {...?widget.existing?.facilities};
  late int _openHour = widget.existing?.openHour ?? 6;
  late int _closeHour = widget.existing?.closeHour ?? 22;
  late bool _isIndoor = widget.existing?.isIndoor ?? false;
  late bool _isActive = widget.existing?.isActive ?? true;
  /// The listing's pin.
  ///
  /// When the ground was captured on site, this is the capture's own best fix
  /// and is not editable — the whole point of the capture is that the pin and
  /// the photographs are the same place, and a pin the owner can drag
  /// afterwards is a pin that proves nothing. `listGroundWithProof` re-checks
  /// the two against each other regardless, so a caller that ignores this
  /// still cannot publish a mismatched listing.
  late double? _lat = widget.proof?.pin.latitude ?? widget.existing?.latitude;
  late double? _lng = widget.proof?.pin.longitude ?? widget.existing?.longitude;
  bool _locating = false;
  bool _busy = false;

  /// Pins the listing to exactly where the owner is standing. This is the
  /// realistic version of "drop a pin on the map" for a ground owner filling
  /// this form on a phone — see `Ground.latitude`'s doc comment on why the
  /// search never depends on this being set, but "grounds near me" does.
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          showError(
            context,
            'Location permission was declined. You can still list the '
            'ground — it just won\'t show up in "near me" search until '
            'you allow location and try again.',
          );
        }
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          showError(context, 'Turn on location services and try again.');
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  static const _facilityOptions = [
    'Floodlights',
    'Parking',
    'Changing rooms',
    'Drinking water',
    'Toilets',
    'Seating',
    'Equipment on hire',
    'First aid',
  ];

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    _rate.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// True while the person is agreeing to the undertaking on a new listing.
  ///
  /// Only asked when there is proof attached, i.e. only when creating. An
  /// owner editing their closing time is not re-signing a declaration.
  bool _undertakingAccepted = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(authUidProvider);
    if (uid == null) return;

    if (_closeHour <= _openHour) {
      showError(context, 'Closing time has to be after opening time.');
      return;
    }

    final proof = widget.proof;
    if (proof != null && !_undertakingAccepted) {
      showError(
        context,
        'Please read and accept the declaration before publishing.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(groundRepositoryProvider);
      final rateRupees = int.tryParse(_rate.text.trim()) ?? 0;

      final ground = Ground(
        id: widget.existing?.id ?? '',
        ownerUid: widget.existing?.ownerUid ?? uid,
        name: _name.text.trim(),
        city: _city.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        district: widget.existing?.district,
        latitude: _lat,
        longitude: _lng,
        sportIds: _sports.toList(),
        // Rupees in the form, paise in the model. The conversion happens in
        // exactly one place so it cannot be done twice or not at all.
        hourlyRatePaise: rateRupees * 100,
        openHour: _openHour,
        closeHour: _closeHour,
        facilities: _facilities.toList(),
        isIndoor: _isIndoor,
        contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isActive: _isActive,
        verificationStatus: widget.existing?.verificationStatus ??
            (proof == null
                ? GroundVerificationStatus.unverified
                : GroundVerificationStatus.pending),
        bookingCount: widget.existing?.bookingCount ?? 0,
        checkInCount: widget.existing?.checkInCount ?? 0,
      );

      if (widget.existing != null) {
        await repo.updateGround(ground);
      } else if (proof != null) {
        await repo.listGroundWithProof(
          ground: ground,
          proofs: proof.proofs,
          claimType: proof.claimType,
          holderName: proof.holderName,
          documentKind: proof.documentKind,
          documentBytes: proof.documentBytes,
          documentContentType: proof.documentContentType,
          uid: uid,
        );
      } else {
        // Unreachable from the UI — the FAB always routes through capture —
        // and kept as a real branch rather than an assert because the editor
        // is a public widget and a future call site that forgets the proof
        // should get a listing marked `unverified`, not a crash.
        await repo.registerGround(ground);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;

    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'List a ground' : 'Edit ground')),
      body: SingleChildScrollView(
        child: ContentBounds(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Ground name',
                    hintText: 'e.g. Gachibowli Turf Arena',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'At least 3 characters'
                      : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    helperText: 'This is what people search by',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Address / landmark (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                const _Heading('Map location'),
                const SizedBox(height: 4),
                Text(
                  'Lets players find this ground in "near me" search. Stand '
                  'at the ground and tap below, or leave it — the listing '
                  'still works, it just won\'t appear in distance search.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (widget.proof != null)
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: const Text('Pinned where you took the photos'),
                      subtitle: Text(
                        '${_lat!.toStringAsFixed(5)}, '
                        '${_lng!.toStringAsFixed(5)} · '
                        '±${widget.proof!.pin.accuracyMetres.round()}m',
                      ),
                    ),
                  )
                else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _useMyLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(
                          _lat == null
                              ? 'Use my current location'
                              : 'Update to my current location',
                        ),
                      ),
                    ),
                    if (_lat != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Clear location',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() {
                              _lat = null;
                              _lng = null;
                            }),
                      ),
                    ],
                  ],
                ),
                if (_lat != null && widget.proof == null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Pinned at ${_lat!.toStringAsFixed(5)}, '
                    '${_lng!.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 20),

                const _Heading('Sports played here'),
                const SizedBox(height: 4),
                Text(
                  'Leave all unticked if the ground suits any sport.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in SportCatalog.all)
                      FilterChip(
                        label: Text('${s.icon} ${s.name}'),
                        selected: _sports.contains(s.id),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _sports.add(s.id);
                          } else {
                            _sports.remove(s.id);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Rate per hour (₹)',
                    hintText: 'e.g. 1500',
                    helperText: 'Leave at 0 if the ground is free to use',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    if (n == null || n < 0) return 'Enter a number';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                const _Heading('Opening hours'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _HourDropdown(
                        label: 'Opens',
                        value: _openHour,
                        onChanged: (h) => setState(() => _openHour = h),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HourDropdown(
                        label: 'Closes',
                        value: _closeHour,
                        onChanged: (h) => setState(() => _closeHour = h),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Bookings can only be made inside these hours.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),

                const _Heading('Facilities'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final f in _facilityOptions)
                      FilterChip(
                        label: Text(f),
                        selected: _facilities.contains(f),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _facilities.add(f);
                          } else {
                            _facilities.remove(f);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact number (optional)',
                    helperText: 'Shown to whoever books the ground',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes for players (optional)',
                    hintText: 'e.g. Gate closes at 10pm. No spikes on turf.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _isIndoor,
                        onChanged: (v) => setState(() => _isIndoor = v),
                        title: const Text('Indoor'),
                        subtitle: const Text('A hall or covered court'),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        title: const Text('Taking bookings'),
                        subtitle: const Text(
                          'Turn off to hide the listing without losing '
                          'bookings already made',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // The declaration, asked once, at the moment of publishing.
                //
                // Placed here rather than in the capture wizard on purpose:
                // it declares that "the details above are true", and until
                // this screen is filled in there are no details to be true
                // about. Signing it three screens before typing the rate
                // would make it the empty ritual it is on most forms.
                if (widget.proof != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                      child: CheckboxListTile(
                        value: _undertakingAccepted,
                        onChanged: (v) =>
                            setState(() => _undertakingAccepted = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('I agree'),
                        subtitle: Text(
                          GroundOwnershipClaim.undertaking,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : isNew
                            ? 'List this ground'
                            : 'Save changes',
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall,
      );
}

class _HourDropdown extends StatelessWidget {
  const _HourDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (var h = 0; h <= 24; h++)
          DropdownMenuItem(value: h, child: Text(groundHourLabel(h))),
      ],
      onChanged: (h) => onChanged(h ?? value),
    );
  }
}
