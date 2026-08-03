import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/responsive.dart';
import '../../core/models/venue.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../shared/app_scaffold.dart';

/// Where a club plays — defined once, used by every event.
///
/// This is the screen that has to come before any of the scheduling work is
/// usable by a human. A venue's court list is what the scheduler allocates
/// against, and until it could be entered, the only alternative was typing
/// court names into each competition separately — which makes the U-13 draw's
/// "Court 1" and the senior draw's "Court 1" unrelated pieces of text, so
/// nothing can tell that two events are competing for the same hall.
class VenuesScreen extends ConsumerWidget {
  const VenuesScreen({super.key, required this.orgId});

  final String orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venuesAsync = ref.watch(venuesProvider(orgId));
    final canManage = ref
        .watch(myCapabilitiesProvider(orgId))
        .contains(Capability.manageCompetitions);

    return AppScaffold(
      orgId: orgId,
      title: 'Venues',
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a venue'),
            )
          : null,
      body: AsyncView(
        value: venuesAsync,
        builder: (venues) {
          if (venues.isEmpty) {
            return EmptyState(
              icon: Icons.stadium_outlined,
              title: 'No venues yet',
              message: canManage
                  ? 'Add the halls and grounds this club plays at, with their '
                      'courts. Events then share them, so two draws can never '
                      'be booked onto the same court at once.'
                  : 'Nobody has added a venue for this club yet.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ContentBounds(
                maxWidth: 800,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final venue in venues)
                      _VenueCard(
                        venue: venue,
                        canManage: canManage,
                        onEdit: () => _edit(context, ref, venue),
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

  Future<void> _edit(BuildContext context, WidgetRef ref, Venue? existing) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => VenueEditor(orgId: orgId, existing: existing),
      );
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({
    required this.venue,
    required this.canManage,
    required this.onEdit,
  });

  final Venue venue;
  final bool canManage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unusable = venue.courts.length - venue.usableCourts.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(venue.name, style: theme.textTheme.titleMedium),
                ),
                if (canManage)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    tooltip: 'Edit',
                  ),
              ],
            ),
            if (venue.city != null || venue.district != null)
              Text(
                [venue.city, venue.district].whereType<String>().join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.grid_view_outlined, size: 16),
                  label: Text(
                    '${venue.capacity} court'
                    '${venue.capacity == 1 ? '' : 's'}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.schedule_outlined, size: 16),
                  label: Text('${venue.openHour}:00–${venue.closeHour}:00'),
                ),
                if (unusable > 0)
                  Chip(
                    avatar: const Icon(Icons.block_outlined, size: 16),
                    label: Text('$unusable unavailable'),
                  ),
              ],
            ),
            if (venue.usableCourts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                venue.usableCourts.map((c) => c.name).join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Creates or edits one venue and its courts.
class VenueEditor extends ConsumerStatefulWidget {
  const VenueEditor({super.key, required this.orgId, this.existing});

  final String orgId;
  final Venue? existing;

  @override
  ConsumerState<VenueEditor> createState() => _VenueEditorState();
}

class _VenueEditorState extends ConsumerState<VenueEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _district =
      TextEditingController(text: widget.existing?.district ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');

  late int _openHour = widget.existing?.openHour ?? 6;
  late int _closeHour = widget.existing?.closeHour ?? 22;
  late List<Court> _courts = [...?widget.existing?.courts];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A venue with no courts can host nothing, so a new one starts with one
    // rather than making the first thing an organizer does be "add a court".
    if (_courts.isEmpty) _courts = [_newCourt(1)];
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _district.dispose();
    _address.dispose();
    super.dispose();
  }

  /// Ids are generated and never reused. Renaming "Court 1" to "Show Court"
  /// must not orphan the fixtures already scheduled on it.
  Court _newCourt(int n) => Court(
        id: 'c${DateTime.now().microsecondsSinceEpoch}_$n',
        name: 'Court $n',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.existing == null;

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
            Text(
              isNew ? 'Add a venue' : 'Edit venue',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: isNew,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Gachibowli Indoor Stadium',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _district,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'District'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
              ),
            ),
            const SizedBox(height: 20),

            Text('Open hours', style: theme.textTheme.labelLarge),
            Row(
              children: [
                Expanded(
                  child: _HourField(
                    label: 'Opens',
                    value: _openHour,
                    onChanged: (v) => setState(() => _openHour = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HourField(
                    label: 'Closes',
                    value: _closeHour,
                    onChanged: (v) => setState(() => _closeHour = v),
                  ),
                ),
              ],
            ),
            if (_closeHour <= _openHour)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Closing time must be after opening time — otherwise there '
                  'are no slots to schedule into at all.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),

            const SizedBox(height: 20),
            Row(
              children: [
                Text('Courts', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(
                    () => _courts = [..._courts, _newCourt(_courts.length + 1)],
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            for (var i = 0; i < _courts.length; i++)
              _CourtRow(
                court: _courts[i],
                onChanged: (c) => setState(() => _courts[i] = c),
                // Never deleted outright once saved: a fixture may already name
                // it. Marking it unavailable is the reversible answer.
                onRemove: _courts.length > 1
                    ? () => setState(() => _courts = [..._courts]..removeAt(i))
                    : null,
              ),

            const SizedBox(height: 20),
            Row(
              children: [
                if (!isNew)
                  TextButton.icon(
                    onPressed: _busy ? null : _archive,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: Text(isNew ? 'Add venue' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave =>
      !_busy &&
      _name.text.trim().isNotEmpty &&
      _closeHour > _openHour &&
      _courts.isNotEmpty;

  Future<void> _save() async {
    setState(() => _busy = true);
    final repo = ref.read(tournamentRepositoryProvider);
    final uid = ref.read(currentUidProvider);

    final venue = Venue(
      id: widget.existing?.id ?? '',
      orgId: widget.orgId,
      name: _name.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      district: _district.text.trim().isEmpty ? null : _district.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      courts: _courts,
      openHour: _openHour,
      closeHour: _closeHour,
      isArchived: widget.existing?.isArchived ?? false,
      createdBy: widget.existing?.createdBy ?? uid,
      createdAt: widget.existing?.createdAt,
    );

    try {
      if (widget.existing == null) {
        await repo.createVenue(venue);
      } else {
        await repo.updateVenue(venue);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(tournamentRepositoryProvider)
          .archiveVenue(widget.orgId, widget.existing!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _CourtRow extends StatelessWidget {
  const _CourtRow({
    required this.court,
    required this.onChanged,
    required this.onRemove,
  });

  final Court court;
  final ValueChanged<Court> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: court.name,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Court name',
              ),
              onChanged: (v) => onChanged(court.copyWith(name: v)),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: court.isAvailable
                ? 'Available'
                : 'Unavailable — no match will be scheduled here',
            child: Switch(
              value: court.isAvailable,
              onChanged: (v) => onChanged(court.copyWith(isAvailable: v)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onRemove,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _HourField extends StatelessWidget {
  const _HourField({
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
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (var h = 0; h <= 24; h++)
          DropdownMenuItem(value: h, child: Text('$h:00')),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}
