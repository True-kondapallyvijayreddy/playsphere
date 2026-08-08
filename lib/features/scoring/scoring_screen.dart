import 'dart:async';

import 'package:flutter/material.dart';
import 'widgets/dispute_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/providers.dart';
import '../../domain/scoring/scoring_plugin.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/models/match_player.dart';
import '../../shared/app_scaffold.dart';
import '../profile/widgets/match_memories_section.dart';
import 'match_setup.dart';
import 'widgets/ask_to_score.dart';
import 'widgets/box_score_table.dart';
import 'widgets/share_match_button.dart';

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
  StreamSubscription<void>? _resyncSub;

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
      // A lost race is not a failure and no longer arrives as one. The pad
      // re-renders from the fixture listener on its own; this only tells the
      // scorer why the number in front of them just moved, briefly and
      // without the error styling that made a routine condition look broken.
      _resyncSub = service.resyncs.listen((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Score updated from another device.'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _failureSub?.cancel();
    _resyncSub?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Asks who fills each role the plugin declared, returning the payload to
  /// merge into the action. Null means the scorer backed out.
  ///
  /// The list of roles comes from the CONTROL, not from a set of action names
  /// kept here. It used to be the latter — three cricket actions, recognised
  /// by name — which meant every other engine's demand for a player went
  /// unasked and unmet. Eleven of the thirteen refuse an action that names
  /// nobody, so football's Goal, kho-kho's Tag, kabaddi's Raid and the rest
  /// were rejected on every press: those sports had a full pad and no way to
  /// record anything with it.
  Future<Map<String, dynamic>?> _askPlayers(
    Fixture fixture,
    ScoreControl control,
  ) async {
    final ctx = fixture.scoringContext();

    /// The side a prompt draws from, resolved against the button's own side.
    ///
    /// `actingSide` is the button's side, so one declaration serves both
    /// halves of the pad. A neutral control has no side of its own, so both
    /// line-ups are offered rather than guessing one.
    List<MatchPlayer> candidates(PlayerPrompt prompt) {
      final acting = control.side;
      var pool =
          acting == Side.neutral || prompt.from == PromptSource.eitherSide
              ? [...ctx.lineupFor(Side.a), ...ctx.lineupFor(Side.b)]
              : switch (prompt.from) {
                  PromptSource.actingSide => ctx.lineupFor(acting),
                  PromptSource.opposingSide => ctx.lineupFor(acting.opposite),
                  PromptSource.eitherSide => const <MatchPlayer>[],
                };

      // Bug #10: For batter selection prompts ('new_batter', 'striker', 'nonStriker'),
      // filter out players who have already been dismissed (out == true) so out batters
      // do not appear in the selection list.
      if (fixture.scoringPluginKey == 'cricket' &&
          (prompt.key == 'playerId' || prompt.key == 'striker' || prompt.key == 'nonStriker')) {
        final state = fixture.scoreState;
        final curInnings = (state['innings'] as List?)?.lastOrNull as Map?;
        if (curInnings != null) {
          final batting = (curInnings['batting'] as Map?) ?? const {};
          pool = pool.where((p) {
            final stats = batting[p.id] as Map?;
            return stats?['out'] != true;
          }).toList();
        }
      }

      // An explicit list narrows the side to the people the plugin says are
      // eligible right now.
      final only = prompt.only;
      if (only == null) return pool;
      final byId = {for (final p in pool) p.id: p};
      return [
        for (final id in only)
          if (byId[id] case final player?) player,
      ];
    }

    final byKey = {for (final p in control.prompts) p.key: p};

    // Singles needs no dialog. When every prompt has exactly one possible
    // answer, asking is a tap that can only produce the answer already known
    // — and in a singles badminton game that is one extra tap per rally, on
    // top of the forty the scorer already makes. The side IS the player, so
    // the pad fills it in and gets out of the way.
    //
    // Only when every prompt is REQUIRED. An optional one — an assist — has
    // "nobody" as a real answer that no candidate count can imply, so a
    // control carrying one is always worth asking about. A control that also
    // wants a NUMBER can never be skipped: nothing about a line-up implies a
    // time of 10.94.
    final everyAnswerForced = control.values.isEmpty &&
        control.prompts.every(
          (p) => !p.optional && !p.multiple && candidates(p).length == 1,
        );
    if (everyAnswerForced) {
      return {
        for (final p in control.prompts) p.key: candidates(p).single.id,
      };
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PlayerPicker(
        // The first question asked is the best title available and costs
        // nothing to maintain — the plugin already had to phrase it. A
        // control may ask only for a number (a wind reading), so this falls
        // through to the values.
        title: control.prompts.isNotEmpty
            ? control.prompts.first.label
            : control.values.first.label,
        roles: {for (final p in control.prompts) p.key: p.label},
        optionalRoles: {
          for (final p in control.prompts)
            if (p.optional) p.key,
        },
        multiRoles: {
          for (final p in control.prompts)
            if (p.multiple) p.key,
        },
        candidatesFor: (key) => candidates(byKey[key]!),
        // Two prompts drawing on the SAME pool cannot name the same person.
        //
        // This is the general form of "striker and non-striker cannot be the
        // same player": whatever the sport, if a control asks twice for
        // somebody out of one side, it is asking about two different people —
        // a footballer does not assist their own goal, a kho-kho attacker does
        // not tag himself. Grouping by [PromptSource] gets that for every
        // engine at once and leaves cross-side prompts alone, which is what
        // keeps the bowler (drawn from the opposing side) selectable while the
        // batters are being chosen.
        //
        // Optional prompts are excluded: "nobody" is a legitimate answer and
        // must not be crowded out of a list by the required roles beside it.
        exclusiveRoleGroups: [
          for (final source in PromptSource.values)
            {
              for (final p in control.prompts)
                if (p.from == source && !p.optional) p.key,
            },
        ].where((group) => group.length > 1).toList(),
        values: control.values,
      ),
    );
  }

  Future<void> _submit(Fixture fixture, ScoreControl control) async {
    if (_busy) return;

    var action = ScoreAction(
      type: control.action,
      side: control.side,
      payload: control.payload,
    );

    if (control.needsInput) {
      final payload = await _askPlayers(fixture, control);
      if (payload == null) return; // cancelled
      action = ScoreAction(
        type: action.type,
        side: action.side,
        payload: {...action.payload, ...payload},
      );
    }

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

  /// UNDO — appends a reversal rather than editing the log, so both the mistake
  /// and its withdrawal survive in the audit trail (CLAUDE.md §2.4). Because a
  /// reversal is itself an event, an undo can be undone, which is why this asks
  /// for no confirmation: on a ground, a fast correction beats a safe one.
  Future<void> _undo(Fixture fixture) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(scoringServiceProvider).undo(
            fixture: fixture,
            context: fixture.scoringContext(),
            byUid: ref.read(currentUidProvider) ?? '',
          );
      unawaitedHaptic();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Last action withdrawn.')),
        );
      }
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
      actions: [
        // The scorer is the person standing next to the match, so they are
        // the one everybody asks for the link.
        if (fixtureAsync.valueOrNull case final f?)
          ShareMatchButton(fixture: f, compact: true),
      ],
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
            // Was a dead end: it named the person who could fix it and gave
            // no way to reach them. An umpire standing at the ground now asks
            // from here, and the request lands on the admin's home screen.
            return EmptyState(
              icon: Icons.lock_outline,
              title: 'You are not assigned to score this match',
              message: 'An admin of this club decides who holds the pen. You '
                  'can ask them for it.',
              action: AskToScoreButton(fixture: fixture, expanded: true),
            );
          }

          // A match cannot be scored until the engine knows who is playing.
          // Offering the pad first would only produce rejections.
          if (!fixture.hasLineups) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'Set the line-ups first',
              message: 'Scoring records who did what, so both sides need '
                  'their players before the first ball.',
              action: FilledButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => LineupEditor(fixture: fixture),
                ),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Choose players'),
              ),
            );
          }

          final ctx = fixture.scoringContext();
          final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
          final groups = plugin.controls(fixture.scoreState, ctx);

          // Nothing to withdraw before the first event, and a completed match
          // is frozen — the rules reject a scorer write to it either way, so
          // the button says so rather than letting the tap fail.
          final canUndo = fixture.lastSeq > 0 &&
              fixture.status != FixtureStatus.completed;

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
              if (control != null) _submit(fixture, control);
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
                      const _PendingBanner(),
                      const SizedBox(height: 8),
                      // "UNDO always visible" (CLAUDE.md §6). A scorer who
                      // mis-taps while watching the pitch needs the correction
                      // in reach, not buried in the admin menu below.
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: canUndo ? () => _undo(fixture) : null,
                          icon: const Icon(Icons.undo),
                          label: const Text('Undo last'),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                          onPressed: (c) => _submit(fixture, c),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Below the pad, above the photos. A scorer checks the
                      // card constantly — "how many has he faced", "who has
                      // an over left" — and until now the only way to answer
                      // either was to keep a paper book beside the phone.
                      MatchScorecard(fixture: fixture),
                      const SizedBox(height: 8),
                      // Below the pad on purpose. The scoring controls must be
                      // the first thing under the scoreboard — a scorer
                      // watching the pitch should never have to scroll past a
                      // photo grid to record a delivery.
                      MatchMemoriesSection(fixture: fixture),
                      const SizedBox(height: 24),
                      _MatchDayActions(fixture: fixture),
                      DisputeCard(fixture: fixture),
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
  const _PendingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingScoreEventsProvider).valueOrNull ?? 0;
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
  }
}

/// Toss and line-ups: the two things that happen before the first ball.
class _MatchDayActions extends ConsumerWidget {
  const _MatchDayActions({required this.fixture});
  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toss = fixture.tossWonByEntrantId;
    final tossName = toss == null
        ? null
        : (toss == fixture.entrantAId
            ? fixture.entrantAName
            : fixture.entrantBName);

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.casino_outlined),
            title: Text(
              toss == null
                  ? 'Record the toss'
                  : '$tossName won the toss and chose to '
                      '${fixture.tossDecision ?? ""}',
            ),
            subtitle: toss == null
                ? const Text('Decides which side starts')
                : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => TossDialog(fixture: fixture),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Line-ups'),
            subtitle: Text(
              '${fixture.lineupA.length} and ${fixture.lineupB.length} players',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => LineupEditor(fixture: fixture),
            ),
          ),
        ],
      ),
    );
  }
}

/// Walkover, retirement, disqualification, abandonment and dispute — the
/// outcomes every real tournament needs and most apps forget, leaving an
/// organizer with a match they can neither finish nor delete.
///
/// Each option records a [MatchResultType], not just a [FixtureStatus]. That
/// distinction is what stops a walkover moving anyone's Glicko rating and
/// what lets a scorecard still say "RET" a season later — a retirement and a
/// straight-games win are both `completed` with a winner, and once written
/// without a result type they are indistinguishable forever.
class _AdminActions extends ConsumerWidget {
  const _AdminActions({required this.fixture});
  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> set(
      FixtureStatus status,
      MatchResultType type, {
      String? winnerId,
    }) async {
      final note = await showDialog<String?>(
        context: context,
        builder: (context) => _OutcomeDialog(type: type),
      );
      // Null is "cancelled". An empty string is "confirmed, no note" — the
      // two must not collapse, or backing out of the dialog would end the
      // match.
      if (note == null) return;

      try {
        await ref.read(scoringServiceProvider).setFixtureOutcome(
              fixture: fixture,
              status: status,
              resultType: type,
              winnerEntrantId: winnerId,
              note: note.isEmpty ? null : note,
            );
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    final a = fixture.entrantAName;
    final b = fixture.entrantBName;

    return ExpansionTile(
      title: const Text('Match did not play normally'),
      subtitle: const Text(
        'Walkover, retirement, disqualification, abandonment or dispute',
      ),
      children: [
        _OutcomeGroup(
          icon: Icons.directions_walk,
          label: 'Walkover',
          hint: 'One side never arrived. Awards the points; moves no rating.',
          optionA: 'to $a',
          optionB: 'to $b',
          onA: () => set(
            FixtureStatus.walkover,
            MatchResultType.walkover,
            winnerId: fixture.entrantAId,
          ),
          onB: () => set(
            FixtureStatus.walkover,
            MatchResultType.walkover,
            winnerId: fixture.entrantBId,
          ),
        ),
        _OutcomeGroup(
          icon: Icons.healing_outlined,
          label: 'Retired',
          hint: 'Started and could not continue. A real result — the play '
              'that happened still counts.',
          optionA: '$a wins',
          optionB: '$b wins',
          onA: () => set(
            FixtureStatus.completed,
            MatchResultType.retired,
            winnerId: fixture.entrantAId,
          ),
          onB: () => set(
            FixtureStatus.completed,
            MatchResultType.retired,
            winnerId: fixture.entrantBId,
          ),
        ),
        _OutcomeGroup(
          icon: Icons.block_outlined,
          label: 'Disqualified',
          hint: 'Conduct, eligibility or equipment. The result stands; no '
              'rating moves.',
          optionA: '$b disqualified',
          optionB: '$a disqualified',
          onA: () => set(
            FixtureStatus.completed,
            MatchResultType.disqualified,
            winnerId: fixture.entrantAId,
          ),
          onB: () => set(
            FixtureStatus.completed,
            MatchResultType.disqualified,
            winnerId: fixture.entrantBId,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.person_off_outlined),
          title: const Text('Neither side arrived'),
          subtitle: const Text('No winner, and nothing counts anywhere'),
          onTap: () =>
              set(FixtureStatus.walkover, MatchResultType.noShow),
        ),
        ListTile(
          leading: const Icon(Icons.thunderstorm_outlined),
          title: const Text('Abandoned'),
          subtitle: const Text('Rain, light, or the venue became unusable'),
          onTap: () =>
              set(FixtureStatus.abandoned, MatchResultType.abandoned),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Mark as disputed'),
          subtitle: const Text('Freezes the result pending a decision'),
          onTap: () =>
              set(FixtureStatus.disputed, MatchResultType.normal),
        ),
      ],
    );
  }
}

/// One result type with a side to pick.
class _OutcomeGroup extends StatelessWidget {
  const _OutcomeGroup({
    required this.icon,
    required this.label,
    required this.hint,
    required this.optionA,
    required this.optionB,
    required this.onA,
    required this.onB,
  });

  final IconData icon;
  final String label;
  final String hint;
  final String optionA;
  final String optionB;
  final VoidCallback onA;
  final VoidCallback onB;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: onA, child: Text(optionA)),
              OutlinedButton(onPressed: onB, child: Text(optionB)),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

/// Confirms an unusual result and captures why.
///
/// The note is the point. `forceResult` has always accepted one and no screen
/// ever offered a field to type it in, so the record a protest needs weeks
/// later — "opponent did not arrive by the 20-minute cut-off" — was never
/// captured at the one moment somebody knew it.
class _OutcomeDialog extends StatefulWidget {
  const _OutcomeDialog({required this.type});
  final MatchResultType type;

  @override
  State<_OutcomeDialog> createState() => _OutcomeDialogState();
}

class _OutcomeDialogState extends State<_OutcomeDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type;
    return AlertDialog(
      title: Text('Record as ${t.label.toLowerCase()}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This ends the match without a normal score. It can only be '
            'changed by an event manager.',
          ),
          const SizedBox(height: 8),
          Text(
            t.countsForRating
                ? 'Counts towards ratings and career statistics.'
                : 'Does not move any rating or career statistic — nobody '
                    'played.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Why (optional)',
              hintText: 'Opponent did not arrive by the cut-off',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _note.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
