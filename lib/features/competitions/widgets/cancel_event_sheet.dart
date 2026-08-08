import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Calls an event off, with the reason that makes the notification worth
/// sending.
///
/// The reason box has no "skip" and the button stays disabled until something
/// is typed. That is deliberate friction on the one action in the product that
/// wastes other people's Saturdays: everyone who entered is about to be told,
/// and "Sunday Cricket was cancelled" with nothing after it produces a round
/// of messages asking why — which is the work the notification was meant to
/// remove.
class CancelEventSheet extends ConsumerStatefulWidget {
  const CancelEventSheet({super.key, required this.competition});

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => CancelEventSheet(competition: competition),
      );

  @override
  ConsumerState<CancelEventSheet> createState() => _CancelEventSheetState();
}

class _CancelEventSheetState extends ConsumerState<CancelEventSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  /// A few reasons that cover most cancellations, as one-tap fills rather than
  /// a closed list. An organizer standing in the rain should not have to type
  /// "ground waterlogged" — but they must still be able to say something the
  /// presets do not.
  static const _presets = [
    'Ground unavailable',
    'Rain / weather',
    'Not enough entries',
    'Rescheduling — new date to follow',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    final c = widget.competition;
    try {
      await ref.read(competitionRepositoryProvider).cancelCompetition(
            orgId: c.orgId,
            compId: c.id,
            reason: _reason.text,
            byUid: uid,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event cancelled. Everyone who entered has been told.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.competition;
    final entered = c.confirmedCount + c.waitlistCount;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cancel ${c.name}?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                entered == 0
                    ? 'Nobody has entered yet. The event stays on the club\'s '
                        'page, marked cancelled.'
                    : '$entered ${entered == 1 ? 'person' : 'people'} entered. '
                        'They will each get a notification with your reason.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    ActionChip(
                      label: Text(p),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _reason.text = p;
                                _reason.selection = TextSelection.collapsed(
                                  offset: p.length,
                                );
                              }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: !_busy,
                autofocus: true,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Why is it cancelled?',
                  helperText: 'Everyone who entered will read this.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Keep the event'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || _reason.text.trim().isEmpty
                          ? null
                          : _cancel,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      child: Text(_busy ? 'Cancelling…' : 'Cancel event'),
                    ),
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

/// Sends a note to everyone who entered, without changing the event.
///
/// The other half of "give the owner a way to handle the situation": most
/// situations are not a cancellation. The ground moved, the start slipped an
/// hour, bring studs. Organizers were doing this on WhatsApp, to a group that
/// never contains everyone who registered.
class EventNoteSheet extends ConsumerStatefulWidget {
  const EventNoteSheet({super.key, required this.competition});

  final Competition competition;

  static Future<void> show(
    BuildContext context, {
    required Competition competition,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => EventNoteSheet(competition: competition),
      );

  @override
  ConsumerState<EventNoteSheet> createState() => _EventNoteSheetState();
}

class _EventNoteSheetState extends ConsumerState<EventNoteSheet> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    final c = widget.competition;
    try {
      await ref.read(competitionRepositoryProvider).noteToEntrants(
            orgId: c.orgId,
            compId: c.id,
            note: _note.text,
            byUid: uid,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note sent to everyone who entered.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.competition;
    final entered = c.confirmedCount + c.waitlistCount;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Note to entrants', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                entered == 0
                    ? 'Nobody has entered yet, so this will not reach anyone.'
                    : 'Goes to all $entered who entered ${c.name}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                enabled: !_busy,
                autofocus: true,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'What do they need to know?',
                  hintText: 'Start moved to 7am. Ground is soft — bring studs.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _busy || _note.text.trim().isEmpty ? null : _send,
                      child: Text(_busy ? 'Sending…' : 'Send'),
                    ),
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
