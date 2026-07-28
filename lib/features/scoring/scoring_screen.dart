import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_plugin.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../shared/app_scaffold.dart';

/// The scoring pad.
///
/// Design goals, in priority order:
///
///  1. **One tap per event.** A scorer is watching a match, not a screen. The
///     buttons come from the sport's plugin, so only legal actions are ever
///     shown and nothing needs a confirmation dialog.
///  2. **Works on a phone at the boundary and a laptop at the desk.** Large
///     touch targets on compact windows; on a laptop every control also has a
///     keyboard shortcut, which is several times faster during a rally.
///  3. **Never loses a score.** Writes go through Firestore's offline queue,
///     and a conflict with a second scorer resolves by re-syncing rather than
///     by overwriting.
class ScoringScreen extends ConsumerStatefulWidget {
  const ScoringScreen({
    super.key,
    required this.orgId,
    required this.compId,
    required this.fixtureId,
  });

  final String orgId;
  final String compId;
  final String fixtureId;

  @override
  ConsumerState<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends ConsumerState<ScoringScreen> {
  final _focusNode = FocusNode();
  bool _busy = false;

  StreamSubscription<AppException>? _failureSub;

  @override
  void initState() {
    super.initState();
    // Reconcile anything queued from a previous offline session as soon as
    // the pad opens, so the pending badge is honest.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = ref.read(scoringServiceProvider);
      service.reconcileQueue();
      // Writes are not awaited, so a rejected one cannot surface as a thrown
      // exception from _submit. It arrives here instead.
      _failureSub = service.writeFailures.listen((error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      });
    });
  }

  @override
  void dispose() {
    _failureSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(Fixture fixture, ScoreAction action) async {
    if (_busy) return;
    setState(() => _busy = true);

    // The config is frozen on the fixture at draw time, so the pad scores
    // under exactly the rules a spectator sees it scored under.
    final ctx = fixture.scoringContext();

    try {
      await ref.read(scoringServiceProvider).submit(
            fixture: fixture,
            action: action,
            context: ctx,
            byUid: ref.read(currentUidProvider) ?? '',
          );
      // Haptic confirmation matters when the scorer is looking at the pitch
      // rather than the screen.
      unawaitedHaptic();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void unawaitedHaptic() {
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final key = FixtureRef(widget.orgId, widget.compId, widget.fixtureId);
    final fixtureAsync = ref.watch(fixtureProvider(key));
    final myUid = ref.watch(currentUidProvider);
    final competition = ref
        .watch(competitionProvider(CompRef(widget.orgId, widget.compId)))
        .valueOrNull;

    return AppScaffold(
      orgId: widget.orgId,
      title: 'Scoring',
      subtitle: competition?.name,
      body: AsyncView(
        value: fixtureAsync,
        builder: (fixture) {
          if (fixture == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This match no longer exists',
            );
          }

          if (myUid == null || !fixture.scorerUids.contains(myUid)) {
            return const EmptyState(
              icon: Icons.lock_outline,
              title: 'You are not assigned to score this match',
              message: 'An event manager can add you as a scorer.',
            );
          }

          final ctx = fixture.scoringContext();
          final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
          final groups = plugin.controls(fixture.scoreState, ctx);

          // Flatten shortcuts so a keypress on a laptop maps to the same code
          // path as a tap on a phone — one behaviour, two input methods.
          final shortcuts = <String, ScoreControl>{
            for (final g in groups)
              for (final c in g.controls)
                if (c.shortcut != null) c.shortcut!: c,
          };

          return KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is! KeyDownEvent) return;
              final char = event.character?.toLowerCase();
              final control = char == null ? null : shortcuts[char];
              if (control != null) {
                _submit(
                  fixture,
                  ScoreAction(
                    type: control.action,
                    side: control.side,
                    payload: control.payload,
                  ),
                );
              }
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ContentBounds(
                  maxWidth: 900,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Scoreboard(
                        fixture: fixture,
                        headline: plugin.headline(fixture.scoreState, ctx),
                        status: plugin.statusLine(fixture.scoreState, ctx),
                        summary: plugin.summary(fixture.scoreState, ctx),
                      ),
                      const SizedBox(height: 8),
                      // Keyed on the sequence number so the count is
                      // recomputed after every scoring action rather than
                      // showing whatever it was when the pad opened.
                      _PendingBanner(key: ValueKey(fixture.lastSeq)),
                      const SizedBox(height: 16),
                      for (final group in groups) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 8),
                          child: Text(
                            group.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        _ControlRow(
                          controls: group.controls,
                          enabled: !_busy,
                          showShortcuts: !context.isCompact,
                          onPressed: (c) => _submit(
                            fixture,
                            ScoreAction(
                              type: c.action,
                              side: c.side,
                              payload: c.payload,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _AdminActions(fixture: fixture),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.fixture,
    required this.headline,
    required this.status,
    required this.summary,
  });

  final Fixture fixture;
  final String headline;
  final String? status;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fixture.entrantAName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    fixture.entrantBName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              headline,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: 6),
              Text(
                status!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (summary != headline) ...[
              const SizedBox(height: 4),
              Text(summary, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.controls,
    required this.onPressed,
    required this.enabled,
    required this.showShortcuts,
  });

  final List<ScoreControl> controls;
  final void Function(ScoreControl) onPressed;
  final bool enabled;
  final bool showShortcuts;

  @override
  Widget build(BuildContext context) {
    // Touch targets stay at least 56pt tall on phones — a scorer's thumb is
    // not precise while they are watching play.
    final minHeight = context.responsive<double>(compact: 60, medium: 54, expanded: 48);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in controls)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight, minWidth: 84),
            child: Tooltip(
              message: c.tooltip ?? '',
              child: _styledButton(context, c, minHeight),
            ),
          ),
      ],
    );
  }

  Widget _styledButton(BuildContext context, ScoreControl c, double h) {
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          c.label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        if (showShortcuts && c.shortcut != null)
          Text(
            c.shortcut!.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).hintColor,
            ),
          ),
      ],
    );

    final onTap = enabled ? () => onPressed(c) : null;
    final padding = EdgeInsets.symmetric(
      horizontal: 20,
      vertical: h > 52 ? 12 : 8,
    );

    return switch (c.style) {
      ControlStyle.primary => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(padding: padding),
          child: label,
        ),
      ControlStyle.danger => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            padding: padding,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          child: label,
        ),
      ControlStyle.secondary => FilledButton.tonal(
          onPressed: onTap,
          style: FilledButton.styleFrom(padding: padding),
          child: label,
        ),
      ControlStyle.subtle => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(padding: padding),
          child: label,
        ),
    };
  }
}

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref.read(scoringServiceProvider).pendingCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_queue, size: 20),
            title: Text(
              '$count ${count == 1 ? 'action is' : 'actions are'} waiting to '
              'sync — they are saved and will upload automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }
}

/// Walkover, abandonment and dispute — the outcomes every real tournament
/// needs and most apps forget, leaving an organizer with a match they can
/// neither finish nor delete.
class _AdminActions extends ConsumerWidget {
  const _AdminActions({required this.fixture});
  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> set(FixtureStatus status, {String? winnerId}) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Record as ${status.label.toLowerCase()}?'),
          content: Text(
            'This ends the match without a normal score. It will show as '
            '"${status.label}" in the results and can only be changed by an '
            'event manager.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await ref.read(scoringServiceProvider).setFixtureOutcome(
              fixture: fixture,
              status: status,
              winnerEntrantId: winnerId,
            );
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return ExpansionTile(
      title: const Text('Match did not play normally'),
      subtitle: const Text('Walkover, abandoned or disputed'),
      children: [
        ListTile(
          leading: const Icon(Icons.directions_walk),
          title: Text('Walkover to ${fixture.entrantAName}'),
          onTap: () =>
              set(FixtureStatus.walkover, winnerId: fixture.entrantAId),
        ),
        ListTile(
          leading: const Icon(Icons.directions_walk),
          title: Text('Walkover to ${fixture.entrantBName}'),
          onTap: () =>
              set(FixtureStatus.walkover, winnerId: fixture.entrantBId),
        ),
        ListTile(
          leading: const Icon(Icons.thunderstorm_outlined),
          title: const Text('Abandoned'),
          subtitle: const Text('Rain, injury, or the match could not finish'),
          onTap: () => set(FixtureStatus.abandoned),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Mark as disputed'),
          subtitle: const Text('Freezes the result pending a decision'),
          onTap: () => set(FixtureStatus.disputed),
        ),
      ],
    );
  }
}
