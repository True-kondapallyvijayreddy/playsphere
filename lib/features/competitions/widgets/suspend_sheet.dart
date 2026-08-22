import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/competition.dart';
import '../../../core/models/tournament.dart';
import '../../../core/providers.dart';
import '../../../shared/app_scaffold.dart';

/// Puts a season or an event on hold, with the reason everyone who entered
/// will read.
///
/// ## Why this exists next to [CancelEventSheet] rather than inside it
///
/// Cancelling is final: it tells everyone the event is off, and it has to
/// stay final or the message means nothing. What organizers kept reaching for
/// it to do, though, is not final at all — a monsoon week, an exam fortnight,
/// a ground the municipality took back for a fair. They cancelled, then
/// re-created the season from scratch and lost the draws, the standings and
/// every registration with it.
///
/// So this is the reversible door, and the two are deliberately different
/// shapes: the cancel sheet's confirm is painted in the error colour and
/// warns about wasted Saturdays, this one says when it comes back.
///
/// The reason box has no skip, for the same reason cancelling has none. A
/// season that simply stops is indistinguishable from the app being broken.
class SuspendSheet extends ConsumerStatefulWidget {
  const SuspendSheet._({
    required this.title,
    required this.audienceLine,
    required this.onConfirm,
  });

  /// Pauses a whole season, and every event under it.
  static Future<void> showForSeason(
    BuildContext context, {
    required Tournament tournament,
    required int eventCount,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SuspendSheet._(
          title: 'Put ${tournament.name} on hold?',
          audienceLine: eventCount == 0
              ? 'Nothing is drawn yet. The season stays exactly as it is, '
                  'marked on hold, and you can bring it back any time.'
              : 'All $eventCount ${eventCount == 1 ? 'event' : 'events'} stop '
                  'taking entries. Draws, standings and results are untouched '
                  'and come straight back when you resume.',
          onConfirm: (ref, reason, uid) =>
              ref.read(tournamentRepositoryProvider).suspendTournament(
                    orgId: tournament.orgId,
                    tournamentId: tournament.id,
                    reason: reason,
                    byUid: uid,
                  ),
        ),
      );

  /// Pauses one event, leaving the rest of its season running.
  static Future<void> showForEvent(
    BuildContext context, {
    required Competition competition,
  }) {
    final entered = competition.confirmedCount + competition.waitlistCount;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SuspendSheet._(
        title: 'Put ${competition.name} on hold?',
        audienceLine: entered == 0
            ? 'Nobody has entered yet. The event stays on the club\'s page, '
                'marked on hold.'
            : '$entered ${entered == 1 ? 'person has' : 'people have'} '
                'entered. Their places are kept — the event just takes no new '
                'ones until you resume it.',
        onConfirm: (ref, reason, uid) =>
            ref.read(competitionRepositoryProvider).suspendCompetition(
                  orgId: competition.orgId,
                  compId: competition.id,
                  reason: reason,
                  byUid: uid,
                ),
      ),
    );
  }

  final String title;
  final String audienceLine;
  final Future<void> Function(WidgetRef ref, String reason, String uid)
      onConfirm;

  @override
  ConsumerState<SuspendSheet> createState() => _SuspendSheetState();
}

class _SuspendSheetState extends ConsumerState<SuspendSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  /// The reasons a grassroots season actually stops, as one-tap fills. An
  /// organizer standing on a wet ground should not have to type "rain".
  static const _presets = [
    'Rain / weather',
    'Ground unavailable',
    'Exams',
    'Resuming next week',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _suspend() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm(ref, _reason.text, uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('On hold. Resume it whenever you are ready.'),
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
              Text(widget.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                widget.audienceLine,
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
                  labelText: 'Why is it on hold?',
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
                      child: const Text('Keep it running'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _busy || _reason.text.trim().isEmpty ? null : _suspend,
                      child: Text(_busy ? 'Pausing…' : 'Put on hold'),
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

/// The strip that says a season or event is paused, and why.
///
/// Shown to everybody, not just the organizer: the whole point of recording a
/// reason is that the person who blocked out next Saturday reads it. It sits
/// at the top of the page rather than inside a card, because "this is not
/// running" changes how every number under it should be read.
class OnHoldBanner extends StatelessWidget {
  const OnHoldBanner({
    super.key,
    required this.reason,
    required this.what,
    this.onResume,
    this.resumeLabel = 'Resume',
  });

  /// Free text the organizer wrote. Null renders the banner without a
  /// second line rather than inventing one.
  final String? reason;

  /// 'season' or 'event' — the noun in the headline.
  final String what;

  /// Null for anyone who cannot manage it, which is most readers.
  final VoidCallback? onResume;
  final String resumeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = reason?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 20,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This $what is on hold',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    text == null || text.isEmpty
                        ? 'No new entries until the organizer resumes it.'
                        : '$text · No new entries until it resumes.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            if (onResume != null)
              TextButton(
                onPressed: onResume,
                child: Text(resumeLabel),
              ),
          ],
        ),
      ),
    );
  }
}
