import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/fixture.dart';
import '../../../core/models/venue.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Moves one match — the organizer's override on everything the scheduler
/// decided.
///
/// The bulk shift handles a day that slipped as a whole. This handles the
/// cases a solver cannot know about: a court that flooded, two players who
/// asked to swap, a referee's call, a family that has to leave by four. No
/// scheduling system survives contact with a real venue without one of these,
/// and an organizer who cannot make the change in the app makes it on paper —
/// at which point the app is wrong and everyone stops trusting it.
///
/// Deliberately unconstrained: it does not re-check rest gaps or court
/// clashes. The organizer is standing in the hall and can see what the
/// solver cannot. Warnings are shown, and none of them block.
class MoveMatchSheet extends ConsumerStatefulWidget {
  const MoveMatchSheet({
    super.key,
    required this.fixture,
    required this.siblings,
  });

  final Fixture fixture;

  /// The other matches in the same competition, for clash warnings.
  final List<Fixture> siblings;

  static Future<void> show(
    BuildContext context, {
    required Fixture fixture,
    required List<Fixture> siblings,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => MoveMatchSheet(fixture: fixture, siblings: siblings),
      );

  @override
  ConsumerState<MoveMatchSheet> createState() => _MoveMatchSheetState();
}

class _MoveMatchSheetState extends ConsumerState<MoveMatchSheet> {
  late DateTime _when =
      widget.fixture.scheduledAt ?? DateTime.now().add(const Duration(hours: 1));
  late String? _courtId = widget.fixture.courtId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.fixture;
    final venues =
        ref.watch(venuesProvider(f.orgId)).valueOrNull ?? const <Venue>[];
    final courtNames = <String>{
      for (final v in venues)
        for (final c in v.usableCourts) c.name,
      if (f.courtId != null) f.courtId!,
    }.toList()
      ..sort();

    final clash = _clashAt(_when, _courtId);

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
            Text('Move this match', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${f.displayNameA()}  v  ${f.displayNameB()}'
              '${f.roundLabel != null ? ' · ${f.roundLabel}' : ''}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      '${_when.day.toString().padLeft(2, '0')}/'
                      '${_when.month.toString().padLeft(2, '0')}/${_when.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(
                      '${_when.hour.toString().padLeft(2, '0')}:'
                      '${_when.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (courtNames.isEmpty)
              Text(
                'No courts defined. Add a venue from the club menu to place '
                'matches on specific courts.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              DropdownButtonFormField<String?>(
                value: courtNames.contains(_courtId) ? _courtId : null,
                decoration: const InputDecoration(labelText: 'Court'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No court set'),
                  ),
                  for (final name in courtNames)
                    DropdownMenuItem<String?>(value: name, child: Text(name)),
                ],
                onChanged: (v) => setState(() => _courtId = v),
              ),

            if (clash != null) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(clash, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                // Enabled even with a clash: the organizer is in the room and
                // can see what the solver cannot.
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Move'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Warns, never blocks. A double-booked court is usually a mistake and
  /// occasionally exactly what the organizer means — two halves of a hall
  /// that the venue record calls one court, say.
  String? _clashAt(DateTime when, String? courtId) {
    if (courtId == null) return null;
    for (final other in widget.siblings) {
      if (other.id == widget.fixture.id) continue;
      if (other.courtId != courtId) continue;
      if (other.status.isResulted) continue;
      final at = other.scheduledAt;
      if (at == null) continue;
      if (at.difference(when).abs() < const Duration(minutes: 20)) {
        return '$courtId already has ${other.displayNameA()} v '
            '${other.displayNameB()} at '
            '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}. '
            'You can still move it here.';
      }
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(_when.year - 1),
      lastDate: DateTime(_when.year + 2),
    );
    if (picked == null) return;
    setState(() => _when = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _when.hour,
          _when.minute,
        ));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked == null) return;
    setState(() => _when = DateTime(
          _when.year,
          _when.month,
          _when.day,
          picked.hour,
          picked.minute,
        ));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final f = widget.fixture;
    try {
      await ref.read(competitionRepositoryProvider).rescheduleFixture(
            orgId: f.orgId,
            compId: f.compId,
            fixtureId: f.id,
            scheduledAt: _when,
            courtId: _courtId,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
