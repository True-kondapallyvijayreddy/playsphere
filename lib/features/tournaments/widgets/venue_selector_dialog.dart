import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/tournament.dart';
import '../../../core/models/venue.dart';
import '../../../core/providers.dart';

/// Modal dialog allowing the tournament organizer to select which venues and
/// courts are attached to this tournament for smart scheduling, or add new ones on the fly.
class VenueSelectorDialog extends ConsumerStatefulWidget {
  const VenueSelectorDialog({
    super.key,
    required this.tournament,
  });

  final Tournament tournament;

  @override
  ConsumerState<VenueSelectorDialog> createState() => _VenueSelectorDialogState();
}

class _VenueSelectorDialogState extends ConsumerState<VenueSelectorDialog> {
  late final Set<String> _selectedVenueIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedVenueIds = Set<String>.from(widget.tournament.venueIds);
  }

  Future<void> _quickAddVenue() async {
    final venue = await showQuickAddVenueDialog(
      context,
      orgId: widget.tournament.orgId,
    );
    if (venue == null) return;

    try {
      final newVenueId =
          await ref.read(tournamentRepositoryProvider).createVenue(venue);
      setState(() => _selectedVenueIds.add(newVenueId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added "${venue.name}" with ${venue.courts.length} courts.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add venue: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(tournamentRepositoryProvider).updateTournamentVenues(
            orgId: widget.tournament.orgId,
            tournamentId: widget.tournament.id,
            venueIds: _selectedVenueIds.toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update venues: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final venuesAsync = ref.watch(venuesProvider(widget.tournament.orgId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.stadium_outlined, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tournament Venues & Courts',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select or add the venues and courts available for this event. '
                'The smart scheduler will allocate match times across these courts without overlap.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _quickAddVenue,
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Add New Venue / Courts (+)'),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: venuesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error loading venues: $err')),
                  data: (venues) {
                    if (venues.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                'No venues configured in this club yet.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: _quickAddVenue,
                                child: const Text('Add First Venue & Courts'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: venues.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final v = venues[index];
                        final isSelected = _selectedVenueIds.contains(v.id);
                        final courtCount = v.courts.length;

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedVenueIds.add(v.id);
                              } else {
                                _selectedVenueIds.remove(v.id);
                              }
                            });
                          },
                          title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '$courtCount ${courtCount == 1 ? 'court' : 'courts'} (${v.courts.map((c) => c.name).join(', ')}) · ${v.address ?? 'On-site'}',
                            style: theme.textTheme.bodySmall,
                          ),
                          secondary: CircleAvatar(
                            backgroundColor: isSelected
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.location_on_outlined,
                              color: isSelected
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save Venues & Courts'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collects a venue and its courts, without saving it.
///
/// Lifted out of [VenueSelectorDialog] so the season wizard can offer the same
/// thing at creation time. A tournament with no venue cannot be scheduled at
/// all — `generateSchedule` refuses with "no usable courts" — so the moment an
/// organizer is laying out a season is exactly the moment to ask, rather than
/// sending them to a different screen afterwards to discover why the
/// timetable would not generate.
///
/// Returns an unsaved [Venue] with a blank id; the caller decides when to
/// write it.
Future<Venue?> showQuickAddVenueDialog(
  BuildContext context, {
  required String orgId,
}) async {
  final nameCtrl = TextEditingController();
  final courtsCtrl = TextEditingController(text: 'Court 1, Court 2');
  final addressCtrl = TextEditingController();

  try {
    return await showDialog<Venue>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.add_location_alt_outlined),
            SizedBox(width: 8),
            Expanded(child: Text('Add Venue & Courts')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Venue / Ground Name',
                  hintText: 'e.g. Sports Arena Hyderabad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: courtsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Courts / Pitches (comma-separated)',
                  hintText: 'e.g. Court 1, Court 2, Court 3',
                  helperText:
                      'One line per playing area. This is what the schedule '
                      'spreads matches across.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address / Location (optional)',
                  hintText: 'e.g. Ground Floor, Sector 4',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final courtNames = courtsCtrl.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (courtNames.isEmpty) courtNames.add('Court 1');
              // Millisecond-stamped so two courts added in the same second
              // cannot collide on id — they did, when the stamp was the only
              // varying part and the index was not in the key.
              final stamp = DateTime.now().millisecondsSinceEpoch;
              final courts = [
                for (int i = 0; i < courtNames.length; i++)
                  Court(
                    id: 'court_${i + 1}_$stamp',
                    name: courtNames[i],
                    isAvailable: true,
                  ),
              ];
              Navigator.of(ctx).pop(
                Venue(
                  id: '',
                  orgId: orgId,
                  name: name,
                  address: addressCtrl.text.trim().isEmpty
                      ? null
                      : addressCtrl.text.trim(),
                  courts: courts,
                ),
              );
            },
            child: const Text('Add Venue'),
          ),
        ],
      ),
    );
  } finally {
    nameCtrl.dispose();
    courtsCtrl.dispose();
    addressCtrl.dispose();
  }
}
