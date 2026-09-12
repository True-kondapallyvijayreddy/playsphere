import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/errors/app_exception.dart';
import '../core/models/geo.dart';
import 'app_scaffold.dart';

/// Where somebody is, entered once and reused everywhere that asks.
///
/// ## Why free text and not a picker
///
/// There is no district reference list in this product. Building one that
/// covers Telangana would be a morning's work and would quietly make every
/// other state — and every country somebody has moved from — unenterable,
/// which is the opposite of what the screens asking for this are for. So the
/// names are typed, matched case-insensitively wherever they are searched,
/// and the point below is what makes "near me" exact regardless of spelling.
///
/// ## Why the coordinates are a separate, optional act
///
/// Tapping "use my current location" stores a latitude and longitude and
/// nothing else — no address is derived from it, because deriving one needs a
/// geocoding service this app does not carry, and inventing a village name
/// from a GPS fix would be a guess presented as a fact. The point is used for
/// one thing: sorting and filtering "who is near me" by real distance. It is
/// never rendered back to anybody as a position, and the person can clear it.
class LocationFields extends StatefulWidget {
  const LocationFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.showVillage = true,
    this.pointHelper,
  });

  final GeoLocation value;
  final ValueChanged<GeoLocation> onChanged;

  /// The directory publishes district and state only, so it hides the finer
  /// row rather than collecting a village it will refuse to store.
  final bool showVillage;

  /// What the point will be used for, in the words of the screen asking.
  final String? pointHelper;

  @override
  State<LocationFields> createState() => _LocationFieldsState();
}

class _LocationFieldsState extends State<LocationFields> {
  late final _state = TextEditingController(text: widget.value.state ?? '');
  late final _district =
      TextEditingController(text: widget.value.district ?? '');
  late final _village = TextEditingController(text: widget.value.village ?? '');
  bool _locating = false;

  @override
  void dispose() {
    _state.dispose();
    _district.dispose();
    _village.dispose();
    super.dispose();
  }

  /// Rebuilt whole rather than `copyWith`-ed, because copyWith on
  /// [GeoLocation] cannot clear a field — `?? this.x` keeps the old value —
  /// and clearing a district somebody typed by mistake has to work.
  void _emit({double? lat, double? lng, bool clearPoint = false}) {
    String? clean(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    widget.onChanged(GeoLocation(
      state: clean(_state),
      district: clean(_district),
      mandal: widget.value.mandal,
      village: widget.showVillage ? clean(_village) : widget.value.village,
      pincode: widget.value.pincode,
      lat: clearPoint ? null : (lat ?? widget.value.lat),
      lng: clearPoint ? null : (lng ?? widget.value.lng),
    ));
  }

  /// The same permission dance the ground form already does, in the same
  /// order and with the same three refusals spelled out — a person who has
  /// blocked location needs to be told which of the three things to fix.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const ValidationException(
          'PlaySphere needs your location to show you people and clubs near '
          'you. Allow location access and try again.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const ValidationException(
          'Location access is blocked for PlaySphere. Turn it on in your '
          'phone\'s settings for this app, then try again.',
        );
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ValidationException(
          'Turn on location services on your phone, then try again.',
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        // Medium, not best: this pins a neighbourhood, not a doorstep, and
        // asking for the best fix would spend twenty seconds of GPS on
        // precision the feature deliberately does not use.
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      _emit(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPoint = widget.value.lat != null && widget.value.lng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _district,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'District / city',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _state,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'State',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
        if (widget.showVillage) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _village,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Town / village (optional)',
              helperText: 'Only people who can already see your profile',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 18),
                label: Text(
                  _locating
                      ? 'Getting your location…'
                      : hasPoint
                          ? 'Update my location'
                          : 'Use my current location',
                ),
              ),
            ),
            if (hasPoint) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Forget my location',
                icon: const Icon(Icons.location_off_outlined),
                onPressed: () => _emit(clearPoint: true),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hasPoint
              ? 'Saved. ${widget.pointHelper ?? 'Used only to work out who is near you — never shown as an address.'}'
              : widget.pointHelper ??
                  'Optional. Lets "near me" searches measure real distance '
                      'instead of matching a district name.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}

/// A one-off "where am I" for a search, with the same permission dance
/// [LocationFields] uses and the same three refusals spelled out.
///
/// Returned as a bare pair rather than a model: a search point is not stored
/// anywhere and does not need a type of its own. Throws a [ValidationException]
/// carrying the sentence to show — every caller here is a button, and a button
/// that fails silently is worse than one that explains.
Future<(double lat, double lng)> currentSearchPoint() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const ValidationException(
      'PlaySphere needs your location to show you who is nearby. Allow '
      'location access and try again.',
    );
  }
  if (permission == LocationPermission.deniedForever) {
    throw const ValidationException(
      'Location access is blocked for PlaySphere. Turn it on in your phone\'s '
      'settings for this app, then try again.',
    );
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const ValidationException(
      'Turn on location services on your phone, then try again.',
    );
  }

  final pos = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
  );
  return (pos.latitude, pos.longitude);
}
