import 'dart:async';

import 'package:flutter/material.dart';
import 'widgets/dispute_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import '../../core/layout/responsive.dart';
import '../../core/models/enums.dart';
import '../../core/models/fixture.dart';
import '../../core/permissions/capability.dart';
import '../../core/providers.dart';
import '../../core/sync/device_id.dart';
import '../../domain/scoring/scoring_plugin.dart';
import '../../domain/scoring/scoring_registry.dart';
import '../../core/models/match_player.dart';
import '../../shared/app_scaffold.dart';
import '../profile/widgets/match_memories_section.dart';
import 'match_setup.dart';
import 'registered_squad.dart';
import 'widgets/ask_to_score.dart';
import 'widgets/box_score_table.dart';
import 'widgets/crease_pad.dart';
import 'widgets/duel_pad.dart';
import 'widgets/mat_pad.dart';
import 'widgets/pad_chrome.dart';
import 'widgets/scoring_control.dart';
import 'widgets/share_match_button.dart';
import 'widgets/point_log.dart';
import 'widgets/rally_scorecard_table.dart';

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

  /// True only while something genuinely asynchronous and modal is in flight
  /// — the player picker, or an undo (which reads the event log first).
  ///
  /// It is NOT set by an ordinary scoring tap any more. It used to be, and it
  /// gated `enabled:` on every control in the pad, so the whole pad went dead
  /// from the moment a tap was made until a disk write and a platform-channel
  /// round trip had finished. Taps made in that window were not queued, they
  /// were discarded — a scorer tapping at the speed of a rally lost most of
  /// them. [ScoringService.submit] returns synchronously now, so a tap has no
  /// async window to guard.
  bool _busy = false;

  /// This pad's own projection of the match, ahead of the fixture listener.
  ///
  /// ## The bug this exists for
  ///
  /// The pad rendered straight from `fixtureProvider`, a Firestore snapshot
  /// stream, and threw away the projection `submit` handed back. So the score
  /// on the scorer's screen did not move when they tapped — it moved when
  /// Firestore got round to echoing the local write back through the
  /// listener, one or more frames later, behind a disk write and a dead pad.
  /// That is the lag: the arithmetic was never slow, the round trip through
  /// the database was.
  ///
  /// Worse, the next tap was handed that same stale `fixture`, so two quick
  /// taps both computed from `lastSeq = n` and both claimed sequence `n + 1`.
  /// The event document id IS the sequence number, so the second one lost the
  /// race, was rolled back by Firestore, and the score visibly snapped back
  /// to where it had been. Tapping faster made it worse, which is exactly
  /// backwards for a scoring pad.
  ///
  /// Holding the projection here fixes both: the tap renders from local
  /// arithmetic at the speed of a `setState`, and the NEXT tap folds onto
  /// this state, so a burst of taps takes consecutive sequence numbers
  /// instead of fighting over one.
  ///
  /// The listener still wins as soon as it catches up ([_local] is only
  /// preferred while its `lastSeq` is strictly ahead), so a genuine
  /// server-side correction — a takeover, a rebuild — is never masked by it.
  Fixture? _local;

  /// Set when the scorer explicitly declines to record the toss.
  ///
  /// Deliberately per-visit state and not a field on the fixture: skipping is
  /// "let me get on with it", not a decision worth persisting, and a scorer
  /// who skips by mistake gets the prompt back by reopening the pad. The toss
  /// can still be recorded afterwards from the match-day card below — it is
  /// only refused once a ball has been scored, which is the point at which
  /// there is a log to honour.
  bool _tossSkipped = false;

  /// Whether the match was already over the last time this pad drew.
  ///
  /// Null until the first frame, and that distinction is the whole point: the
  /// ending is announced on the TRANSITION, not on the state. A scorer who
  /// opens a finished match a day later to check a scoreline is not finishing
  /// anything, and greeting them with a trophy and a "Done" button would make
  /// the sheet the thing you have to dismiss before you can read the pad.
  bool? _wasComplete;

  /// One attempt per visit at filling empty team sheets from the
  /// registrations — see [adoptRegisteredSquads].
  ///
  /// Needed here as well as on the Start button because the pad is reachable
  /// directly from the fixture list, the entrant screen, the live-matches
  /// list, a notification and the start-early sheet. Without it, a match
  /// opened by any of those five doors reaches the engine with no line-up,
  /// and every player prompt offers a single made-up player named after the
  /// team instead of the squad that registered.
  bool _adoptedSquads = false;

  /// One-shot guard on the organizer taking the pen for a match nobody was
  /// assigned to. Same shape as [_adoptedSquads] and for the same reason: the
  /// write is fire-and-forget and this screen already rebuilds from the
  /// fixture's own listener.
  bool _tookPen = false;

  /// This installation's id — which device the pen is pinned to.
  ///
  /// Null only for the first frame or two, while it is read. The pad renders
  /// a spinner for that moment rather than guessing: guessing "not my device"
  /// would flash a takeover prompt at the person who is legitimately scoring,
  /// and guessing "my device" would open a second live pad for exactly as
  /// long as it takes the real answer to arrive.
  String? _deviceId;

  StreamSubscription<AppException>? _failureSub;
  StreamSubscription<void>? _resyncSub;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveDeviceId());
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
        // Drop this pad's own projection and fall back to the listener. A
        // resync means the server's log, not ours, is the truth for this
        // fixture — keeping [_local] would hold the losing score on screen
        // for as long as its `lastSeq` stayed nominally ahead.
        setState(() => _local = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Showing the saved score for this match.'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    });
  }

  Future<void> _resolveDeviceId() async {
    String id;
    try {
      id = await DeviceId.get(await SharedPreferences.getInstance());
    } catch (e) {
      // Storage is unreadable — an OS that refused the plugin, a full disk.
      // The scorer is not locked out over it: a process-local id makes this
      // device distinct from every other one for as long as the app is
      // running, which is the whole job, and the only thing lost is that the
      // pen has to be reclaimed after a restart.
      debugPrint('[PlaySphere] device id unavailable ($e) — using a '
          'session-scoped one.');
      id = DeviceId.session();
    }
    if (!mounted) return;
    setState(() => _deviceId = id);
  }

  /// Pins the pen to this account and this device.
  ///
  /// Fire-and-forget on purpose, and the gate above deliberately does not
  /// wait for it: this is a transaction, a transaction needs the network, and
  /// the network is the one thing a ground does not have. A scorer who was
  /// granted the pen before they walked out of signal must be able to score
  /// the whole match without it — so the pad opens on the local answer
  /// ([Fixture.mayScoreNow], which reads an unclaimed device as "claimed
  /// here") and this write catches up whenever the signal does.
  ///
  /// Errors are swallowed rather than shown. The only ones reachable are
  /// "someone else holds it" and "no connection", and both are already
  /// answered on screen by the pen state the pad is rendering from.
  void _claimPen(Fixture fixture, String uid, String deviceId, {bool takeOver = false}) {
    unawaited(
      ref
          .read(umpireRepositoryProvider)
          .claimPen(
            orgId: fixture.orgId,
            compId: fixture.compId,
            fixtureId: fixture.id,
            scorerUid: uid,
            deviceId: deviceId,
            byUid: uid,
            takeOver: takeOver,
          )
          .catchError((Object _) {}),
    );
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
        control.choices.isEmpty &&
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
            : (control.values.isNotEmpty
                ? control.values.first.label
                : control.choices.first.label),
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
        choices: control.choices,
      ),
    );
  }

  /// The whole tap path, for a control that needs no extra input: validate,
  /// fold, repaint. No `await`, no disk, no network. A press costs what a
  /// button press on a calculator costs, whatever the signal is doing.
  ///
  /// Controls that need a player named (a wicket, an assist) still open a
  /// picker first — that is a modal decision, not latency — and the tap path
  /// below is identical once it closes.
  void _submit(Fixture fixture, ScoreControl control) {
    if (_busy) return;

    final action = ScoreAction(
      type: control.action,
      side: control.side,
      payload: control.payload,
    );

    if (control.needsInput) {
      unawaited(_submitWithPrompt(fixture, control, action));
      return;
    }

    _apply(fixture, action);
  }

  Future<void> _submitWithPrompt(
    Fixture fixture,
    ScoreControl control,
    ScoreAction action,
  ) async {
    setState(() => _busy = true);
    try {
      final payload = await _askPlayers(fixture, control);
      if (payload == null) return; // cancelled
      if (!mounted) return;
      // Fold onto whatever the pad is showing NOW, not onto the fixture
      // captured before the picker opened. The scorer may have used the
      // keyboard while it was up, and the listener may have delivered a
      // correction — either way the projection has moved on and applying to
      // the stale one would claim a sequence number that is already taken.
      _apply(
        _local ?? fixture,
        ScoreAction(
          type: action.type,
          side: action.side,
          payload: {...action.payload, ...payload},
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The engine's own way back out of a finished match — every sport that can
  /// finish itself offers one, because a scorer who mis-taps the match point
  /// must not be stuck with the result. Found by action name because that is
  /// what the base class defines it as; null when the sport has none, and both
  /// callers then simply do not offer it.
  static ScoreControl? _reopenControl(
    ScoringPlugin plugin,
    Fixture fixture,
    ScoringContext ctx,
  ) {
    for (final g in plugin.controls(fixture.scoreState, ctx)) {
      for (final c in g.controls) {
        if (c.action == 'reopen') return c;
      }
    }
    return null;
  }

  /// Writes the result the engine has already decided onto a fixture that is
  /// somehow still live. See [ScoringService.finalizeMatch] for how a pad ends
  /// up in that state; from here it is one press.
  void _finish(Fixture fixture) {
    if (_busy) return;
    try {
      final updated = ref.read(scoringServiceProvider).finalizeMatch(
            fixture: fixture,
            context: fixture.scoringContext(),
            byUid: ref.read(currentUidProvider) ?? '',
          );
      unawaitedHaptic();
      setState(() => _local = updated);
    } catch (e) {
      showError(context, e);
    }
  }

  /// The ending. Shown once, the moment the engine says the match is over.
  ///
  /// Deliberately a sheet and not a snackbar: this is the last thing that
  /// happens on a pad, two players are usually standing at the umpire's chair
  /// waiting to hear it, and it carries a decision — is that the result, or
  /// was the last point wrong. A notice that slides away after four seconds
  /// cannot carry a decision.
  Future<void> _showFinished(
    Fixture fixture,
    ScoringPlugin plugin,
    ScoringContext ctx,
    MatchOutcome outcome,
  ) async {
    final reopen = _reopenControl(plugin, fixture, ctx);

    final winner = outcome.isDraw || outcome.winnerSide == null
        ? null
        : ctx.nameFor(outcome.winnerSide!);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.emoji_events,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  winner == null ? 'Match drawn' : '$winner won',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  plugin.summary(fixture.scoreState, ctx),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 16),
                Text(
                  'The result is recorded. Standings, ratings and both '
                  'players\' records have it already.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheet),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                ),
                if (reopen != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheet);
                      _submit(_local ?? fixture, reopen);
                    },
                    icon: const Icon(Icons.undo),
                    // Named for the mistake it undoes, not for the mechanism.
                    // "Reopen" is what the engine calls it; "the last point
                    // was wrong" is what the scorer is actually thinking.
                    label: const Text('The last point was wrong — reopen'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _apply(Fixture fixture, ScoreAction action) {
    // The config is frozen on the fixture at draw time, so the pad scores
    // under exactly the rules a spectator sees it scored under.
    final ctx = fixture.scoringContext();

    try {
      // Synchronous. The durable enqueue and the Firestore write are chained
      // behind this call and settle on their own time — see the note on
      // [ScoringService.submit]. Deliberately no `syncNow()`: replay is the
      // recovery path, and firing it per tap put a stale reconcile pass in
      // permanent flight against the fixture being scored. What reaches a
      // spectator quickly is the commit, which is already on its way.
      final updated = ref.read(scoringServiceProvider).submit(
            fixture: fixture,
            action: action,
            context: ctx,
            byUid: ref.read(currentUidProvider) ?? '',
          );
      // Haptic confirmation matters when the scorer is looking at the pitch
      // rather than the screen.
      unawaitedHaptic();
      setState(() => _local = updated);
    } catch (e) {
      // Only a rejected action (an illegal move, or not holding the pen) can
      // land here now — a write failure cannot, because no write is awaited.
      // Those arrive on `writeFailures`, wired up in `initState`.
      showError(context, e);
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
      final updated = await ref.read(scoringServiceProvider).undo(
            fixture: _local ?? fixture,
            context: fixture.scoringContext(),
            byUid: ref.read(currentUidProvider) ?? '',
          );
      unawaitedHaptic();
      // Same local-first rule as a score: the withdrawal shows on this pad
      // immediately rather than when the listener echoes it back. `undo`
      // rebuilds from the log, so this is the authoritative projection.
      if (mounted) setState(() => _local = updated);
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
    // An organizer of this club is never a stranger to their own match. The
    // gate below used to ask only "are you on scorerUids", which told the
    // person who decides who scores to go and ask somebody who decides who
    // scores.
    final canManage = ref
        .watch(myCapabilitiesProvider(widget.orgId))
        .contains(Capability.manageCompetitions);
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
        builder: (remote) {
          if (remote == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'This match no longer exists',
            );
          }

          // The pad renders its OWN projection, not the listener's, whenever
          // it is ahead. See [_local].
          final fixture = _local != null && _local!.lastSeq > remote.lastSeq
              ? _local!
              : remote;

          // ── Scorer access gate ────────────────────────────────────────────
          //
          // Who may operate the pad? In priority order:
          //   (a) Anyone already on scorerUids — always allowed.
          //   (b) An org manager — they ARE the admin, see comment below.
          //   (c) A match official with grantedScoringAccess — the umpire
          //       standing at the ground IS the authority; making them ask an
          //       admin defeats the whole point of assigning an umpire.
          //   (d) A registered entrant player (entrantAUid / entrantBUid) in
          //       an individual event — they are the match, not a spectator.
          //
          // Firestore rules mirror this logic: branch (a) checks scorerUids,
          // branch (b) checks orgManager, and branch (c)/(d) check
          // officialsUids / entrantUids on the fixture document.
          final isAssignedOfficial = myUid != null &&
              fixture.officials.any(
                (o) => o.uid == myUid && o.grantedScoringAccess,
              );
          final isEntrantPlayer = myUid != null &&
              (fixture.entrantAUid == myUid || fixture.entrantBUid == myUid);
          // Being NAMED IN A LINE-UP is deliberately not on this list, and
          // was, which is the whole reason a pad could open on a match where
          // every single tap came back refused.
          //
          // `firestore.rules` has no idea what a line-up is: `isFixtureOfficial`
          // knows `officials` and the two entrant uids, and nothing on the
          // server reads `lineupA`/`lineupB` when deciding who may score. So a
          // plain member listed in a line-up got the full pad, a free pen, and
          // permission-denied on every write — verified against the emulator,
          // which refuses that exact write with 403.
          //
          // Nor could the rule simply be widened to match. A line-up is
          // client-written match data, so "whoever is in the line-up may
          // score" would let anyone who can edit a line-up add themselves and
          // score — the privilege escalation the `scorerUids` list exists to
          // prevent. The right answer is the one the product already has: the
          // player is shown `AskToScoreButton` and an admin grants the pen.
          final hasNativeScoringRight = myUid != null &&
              fixture.scorerUids.contains(myUid);
          final hasImpliedScoringRight =
              canManage || isAssignedOfficial || isEntrantPlayer;

          if (!hasNativeScoringRight && !hasImpliedScoringRight) {
            // Truly unrelated member — show the request button.
            return EmptyState(
              icon: Icons.lock_outline,
              title: 'You are not assigned to score this match',
              message: 'An admin of this club decides who holds the pen. '
                  'You can ask them for it.',
              action: AskToScoreButton(fixture: fixture, expanded: true),
            );
          }

          // ── Exclusive control: who is scoring, on which device ────────────
          //
          // Eligibility (above) answers "may this person score this match".
          // It is a list, and a list was never going to answer the question
          // that actually decides whether a tap counts: is this the pad?
          //
          // Two people eligible for the same match — an umpire and the club
          // admin, or one person on a phone and a tablet — both had a live
          // pad, both wrote authoritative events, and the loser of every race
          // for a sequence number had their tap thrown away. That is what a
          // scorer sees as the score moving backwards under their thumb, and
          // no amount of retrying fixes it, because both writes were correct.
          //
          // So one device holds the pen. Everyone else — the owner very much
          // included — watches. Handing it over is an explicit, recorded act
          // (see `UmpireRepository.grantPen`), which is also what a disputed
          // result needs: not "who could have scored" but "who was scoring".
          // The device id is read asynchronously and is deliberately NOT
          // waited for. A spinner here would be on screen for a frame or two
          // on every open, and it would be a spinner in front of a live
          // match — the one screen where a moment of "please wait" is worst.
          // Until it arrives the pad simply does not offer the take-over
          // step, which is the only decision that needs it; the account-level
          // gate below does not, and neither does the security rule.
          final deviceId = _deviceId;

          if (myUid != null && fixture.penIsHeld && !fixture.penHeldBy(myUid)) {
            // Somebody else has the pen. This includes the owner, on purpose:
            // an organizer who wants it back takes it deliberately, which
            // leaves a record, rather than by opening a screen.
            return _PenHeldElsewhere(
              fixture: fixture,
              canManage: canManage,
              myUid: myUid,
            );
          }

          if (myUid != null &&
              deviceId != null &&
              fixture.penHeldBy(myUid) &&
              !fixture.penIsLiveOn(myUid, deviceId)) {
            // Same person, different device. Taking over is one tap, and it
            // is a tap rather than an automatic claim so that a phone left
            // open in a bag cannot silently steal the match back from the
            // tablet being scored on.
            return _PenOnAnotherDevice(
              onTakeOver: () => _claimPen(fixture, myUid, deviceId,
                  takeOver: true),
            );
          }

          // Register this scorer on the fixture so the match log is honest
          // and the match appears in their scoring history, and pin the pen
          // to this device. Fire-and-forget: an awaited Firestore write does
          // not complete while offline, and the ground is exactly where
          // offline happens.
          if (!_tookPen && myUid != null && deviceId != null) {
            _tookPen = true;
            _claimPen(fixture, myUid, deviceId);
          }

          // Fill the sheets from the registrations before anything asks who
          // is playing. Fire-and-forget: it writes to the fixture, and this
          // screen is already rendering from that document's listener, so the
          // result arrives as an ordinary rebuild.
          if (!_adoptedSquads) {
            _adoptedSquads = true;
            unawaited(adoptRegisteredSquads(ref, fixture));
          }

          // A match cannot be scored until the engine knows who is playing.
          // Offering the pad first would only produce rejections.
          if (!fixture.hasLineups) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'Set the line-ups first',
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

          // The toss, before the pad rather than buried inside it.
          //
          // It used to be a row in an admin card halfway down the scoring
          // screen, which is both too late and too quiet: by the time a
          // scorer is looking at the scoring pad the match has started in
          // every sense that matters, and the toss is what decides who bats,
          // serves or raids first. Recording it afterwards means the opening
          // innings was built for the wrong side and the scorer has to notice
          // and unpick it.
          //
          // Gated here, on the pad itself, rather than only on the Start
          // Match button in Match Center — the pad is reachable directly from
          // the fixture list, the entrant screen, a notification and the
          // live-matches list, and a gate that only one of five doors passes
          // through is not a gate.
          //
          // `lastSeq == 0` is the same condition `recordToss` and
          // `firestore.rules` allow a toss to be written under, so this can
          // never appear in front of a match already in progress.
          if (!fixture.tossDone && fixture.lastSeq == 0 && !_tossSkipped) {
            return _TossGate(
              fixture: fixture,
              onSkip: () => setState(() => _tossSkipped = true),
            );
          }

          final ctx = fixture.scoringContext();
          final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
          final groups = plugin.controls(fixture.scoreState, ctx);
          final outcome = plugin.outcome(fixture.scoreState, ctx);

          // The moment the result is decided, say so.
          //
          // Everything needed for this was already here and nothing used it:
          // the engines flip `complete` on the last point of the last game,
          // `ScoringService.submit` writes `status: completed` in the same
          // batch, and the pad's controls quietly swap to a lone "Reopen to
          // correct". That is the entire announcement a scorer got that the
          // match they were scoring had ended. So they kept the pad open, saw
          // nothing that looked like an ending, and the match sat there — on
          // their screen as a pad with no buttons, and on everybody else's as
          // a fixture still marked Live.
          //
          // Post-frame because it is a route push out of a build.
          final justFinished =
              outcome.isComplete && _wasComplete == false;
          _wasComplete = outcome.isComplete;
          if (justFinished) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showFinished(fixture, plugin, ctx, outcome);
            });
          }

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

          // Three pads, chosen by the sport's own account of its shape.
          //
          // A rally sport is two big targets hit forty times a game by
          // somebody watching the court; a mat sport is two rosters, a turn
          // clock and a queue of details the scorer had no time for;
          // everything else is a scoreboard and a set of labelled events.
          // Those are different objects, not the same object with different
          // padding — see [DuelPad] and [MatPad]. The choice comes from
          // `plugin.padLayout`, never from a sport id in this file, or the
          // plugin inversion the whole product rests on would be back in the
          // screen through the side door.
          final board = plugin.padLayout == PadLayout.duel
              ? plugin.duelBoard(fixture.scoreState, ctx)
              : null;
          final mat = plugin.padLayout == PadLayout.mat
              ? plugin.matBoard(fixture.scoreState, ctx)
              : null;
          final crease = plugin.padLayout == PadLayout.crease
              ? plugin.creaseBoard(fixture.scoreState, ctx)
              : null;

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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                ContentBounds(
                  maxWidth: 900,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (board != null)
                        DuelPad(
                          board: board,
                          groups: groups,
                          enabled: !_busy,
                          canUndo: canUndo,
                          onUndo: () => _undo(fixture),
                          onControl: (c) => _submit(fixture, c),
                        )
                      else if (crease != null)
                        CreasePad(
                          board: crease,
                          groups: groups,
                          enabled: !_busy,
                          canUndo: canUndo,
                          onUndo: () => _undo(fixture),
                          onControl: (c) => _submit(fixture, c),
                          showShortcuts: !context.isCompact,
                        )
                      else if (mat != null)
                        MatPad(
                          board: mat,
                          groups: groups,
                          enabled: !_busy,
                          canUndo: canUndo,
                          onUndo: () => _undo(fixture),
                          onControl: (c) => _submit(fixture, c),
                        )
                      else
                        PadScoreboard(
                          fixture: fixture,
                          headline: plugin.headline(fixture.scoreState, ctx),
                          status: plugin.statusLine(fixture.scoreState, ctx),
                          summary: plugin.summary(fixture.scoreState, ctx),
                          live: fixture.status != FixtureStatus.completed,
                        ),
                      // Full time. Two jobs, never both at once.
                      //
                      // Before the engine decides: the sports that cannot know
                      // their own ending need somebody to blow the whistle —
                      // see [ScoringPlugin.finishControl].
                      //
                      // After it decides: the result itself, stated on the pad
                      // and staying there. It used to be announced once, by a
                      // bottom sheet, on the frame the match ended — so a
                      // scorer who was looking at the court, or who had backed
                      // out and come back, or whose phone had been restarted,
                      // got no announcement at all and found a pad with every
                      // button gone. And if the fixture had come apart from
                      // its own projection (a protest reopened it, a
                      // completing write was refused), there was then nothing
                      // anywhere that could record the result: the engine
                      // offered no controls because it was finished, and the
                      // finish bar drew nothing because it only drew while the
                      // match was unfinished. The match stayed Live for
                      // everybody else, permanently. See
                      // [ScoringService.finalizeMatch].
                      if (!outcome.isComplete)
                        _FinishBar(
                          control: plugin.finishControl(fixture.scoreState, ctx),
                          headline: plugin.headline(fixture.scoreState, ctx),
                          status: plugin.statusLine(fixture.scoreState, ctx),
                          enabled: !_busy,
                          onFinish: (c) => _submit(fixture, c),
                        )
                      else
                        _ResultBar(
                          headline: plugin.headline(fixture.scoreState, ctx),
                          summary: plugin.summary(fixture.scoreState, ctx),
                          winnerName: outcome.isDraw ||
                                  outcome.winnerSide == null
                              ? null
                              : ctx.nameFor(outcome.winnerSide!),
                          recorded:
                              fixture.status == FixtureStatus.completed,
                          enabled: !_busy,
                          reopen: _reopenControl(plugin, fixture, ctx),
                          onFinish: () => _finish(fixture),
                          onReopen: (c) => _submit(fixture, c),
                        ),
                      const SizedBox(height: 8),
                      // Deliberately NOT a sync banner.
                      //
                      // The pad used to carry a "N actions are waiting to
                      // sync" card here, and on a ground it was on screen for
                      // most of the match — it is the normal state of an
                      // offline-first app doing its job. What it communicated
                      // was not "your work is safe", which is what it said,
                      // but "something is wrong with the thing recording this
                      // match", to the one person who cannot afford to
                      // believe that and cannot do anything about it either.
                      // Replay is a background concern (see `SyncDriver`) and
                      // now stays in the background. Nothing is hidden: the
                      // count still lives in the shell's app bar
                      // (`SyncStatusIcon`), which is a quieter place and a
                      // more useful one — it is on every screen, including
                      // the ones a scorer is actually looking at after the
                      // match, whereas the banner could only be read by
                      // somebody who had reopened a pad they were finished
                      // with.
                      //
                      // What DOES belong in front of the scorer is who holds
                      // the pen, because that is the one piece of state that
                      // changes whether their next tap counts.
                      _PenBar(fixture: fixture),
                      const SizedBox(height: 8),
                      // "UNDO always visible" (CLAUDE.md §6). A scorer who
                      // mis-taps while watching the pitch needs the correction
                      // in reach, not buried in the admin menu below. The
                      // duel pad carries its own, in the strip between the two
                      // halves, so this is only for the stacked one.
                      if (board == null && crease == null) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: canUndo ? () => _undo(fixture) : null,
                            icon: const Icon(Icons.undo),
                            label: const Text('Undo last'),
                          ),
                        ),
                        ControlDeck(
                          groups: groups,
                          enabled: !_busy,
                          showShortcuts: !context.isCompact,
                          onControl: (c) => _submit(fixture, c),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Below the pad, above the photos. A scorer checks the
                      // card constantly — "how many has he faced", "who has
                      // an over left" — and until now the only way to answer
                      // either was to keep a paper book beside the phone.
                      MatchScorecard(fixture: fixture),
                      const SizedBox(height: 8),
                      // Set by set, above the point log for the same reason
                      // the box score is: a scorer checks the card far more
                      // often than they read back individual points. Draws
                      // nothing for a sport that cannot say who was serving.
                      RallyScorecardTable(fixture: fixture),
                      const SizedBox(height: 8),
                      // Directly under the card, above the photos. It is the
                      // scorer's own check on their own work — the thing they
                      // reach for when a player disputes a point — so it goes
                      // where a disputed point is actually argued, not in an
                      // admin section three screens down.
                      PointLog(fixture: fixture),
                      const SizedBox(height: 8),
                      // Which match, where, since when. Never urgent, which is
                      // why it is this far down, and never absent, which is
                      // why it is on the pad at all rather than three screens
                      // away in an admin section.
                      MatchMetaStrip(fixture: fixture),
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

/// Who holds the pen, on the pad of the person holding it.
///
/// One quiet line, not a banner. The scorer already knows they are scoring —
/// what this is for is the moment the pen moves: an organizer reassigns
/// mid-match, and this row is what tells the person who just lost it why
/// their buttons stopped working, on the same frame the buttons go away.
class _PenBar extends ConsumerWidget {
  const _PenBar({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = ref
        .watch(myCapabilitiesProvider(fixture.orgId))
        .contains(Capability.manageCompetitions);

    return Row(
      children: [
        Icon(Icons.edit_note, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            fixture.penIsHeld
                ? 'You are scoring this match on this device.'
                : 'You have the pen for this match.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (canManage)
          TextButton(
            onPressed: () async {
              final name = await showHandOverPenSheet(
                context: context,
                ref: ref,
                fixture: fixture,
              );
              if (name != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$name is now scoring this match.')),
                );
              }
            },
            child: const Text('Hand over'),
          ),
      ],
    );
  }
}

/// Full time, on the sports that cannot work it out for themselves.
///
/// A badminton match ends when somebody wins the last game and the engine
/// says so. A football match ends when the referee blows, and nothing in this
/// app can know that: no clock runs on its own, the match minute only moves
/// when an event carries one, and so the only signal that a game is over is
/// the scorer saying it is. Until now the button for that lived in the tray
/// underneath the pad, between "Timeout" and "Change ends" — a place nobody
/// looks at full time — and matches were left running for days because of it.
///
/// So the plugin says when the last period is under way, and from that moment
/// this sits directly under the pad: not a modal, because there may well be
/// injury time and a goal still to come, but not hidden either.
class _FinishBar extends StatelessWidget {
  const _FinishBar({
    required this.control,
    required this.headline,
    required this.status,
    required this.enabled,
    required this.onFinish,
  });

  /// Null while there is still a match to play, and for every sport that ends
  /// itself. Drawing nothing is the common case.
  final ScoreControl? control;
  final String headline;

  /// The engine's own one-liner — "Half 2 of 2 · 71'". Null for a sport that
  /// keeps no clock and no periods, in which case the bar shows the score
  /// alone rather than a dangling separator.
  final String? status;
  final bool enabled;
  final void Function(ScoreControl) onFinish;

  @override
  Widget build(BuildContext context) {
    final c = control;
    if (c == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.sports, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last period — end the match when the whistle goes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    status == null ? headline : '$headline · $status',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              // Confirmed, because it is the one press on the pad an undo
              // cannot take back — the result goes to the standings, the
              // ratings and both careers on the same commit.
              onPressed: !enabled
                  ? null
                  : () async {
                      final sure = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('End this match?'),
                          content: Text(
                            'The result is recorded as $headline. '
                            'It goes to the standings and to both sides\' '
                            'records straight away.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Not yet'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('End match'),
                            ),
                          ],
                        ),
                      );
                      if (sure == true) onFinish(c);
                    },
              child: Text(c.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The result, on the pad, for as long as the pad is open.
///
/// The counterpart to [_FinishBar]: that one draws while a match still has to
/// be ended by hand, this one draws from the moment the engine says it is
/// over. Two states, and the difference between them is the whole point.
///
///  * **Recorded.** The ordinary case — `submit` wrote `completed` in the same
///    batch as the deciding event. Says who won and that it counts, so a
///    scorer who missed the sheet, or reopened the pad an hour later, is not
///    looking at a screen with no buttons on it wondering whether anything
///    happened.
///  * **Not recorded.** The match is decided and the fixture still says Live —
///    a protest reopened it, or the completing write was refused. Nothing else
///    in the app can get out of this state, because a finished engine offers
///    no controls to score with. So this is the button that does, and it is
///    the loud one.
class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.headline,
    required this.summary,
    required this.winnerName,
    required this.recorded,
    required this.enabled,
    required this.reopen,
    required this.onFinish,
    required this.onReopen,
  });

  final String headline;
  final String summary;

  /// Null for a draw, and for a completed match with no winning side.
  final String? winnerName;

  /// Whether the FIXTURE agrees with the engine that this match is over.
  final bool recorded;
  final bool enabled;

  /// The engine's way back, when it has one. See `_reopenControl`.
  final ScoreControl? reopen;
  final VoidCallback onFinish;
  final void Function(ScoreControl) onReopen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = winnerName == null ? 'Match drawn' : '$winnerName won';
    // Error colours, deliberately, on the unrecorded case. This is not a
    // neutral piece of news: the match is over, the app is telling everybody
    // else it is still being played, and the only person who can fix that is
    // reading this.
    final scheme = theme.colorScheme;
    final background =
        recorded ? scheme.primaryContainer : scheme.errorContainer;
    final foreground =
        recorded ? scheme.onPrimaryContainer : scheme.onErrorContainer;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  recorded ? Icons.emoji_events : Icons.report_problem_outlined,
                  color: foreground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recorded ? result : 'Match over — not recorded yet',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: foreground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recorded ? summary : '$result · $summary',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              recorded
                  ? 'Recorded. Standings, ratings and both sides\' records '
                      'have it already.'
                  : 'Everyone else still sees this match as in progress. '
                      'Finish it to record the result.',
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
            if (!recorded) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                // Confirmed for the same reason [_FinishBar] confirms: the
                // result goes to the standings, the ratings and both careers
                // on the same commit, and an undo does not take it back.
                onPressed: !enabled
                    ? null
                    : () async {
                        final sure = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Finish this match?'),
                            content: Text(
                              'The result is recorded as $headline. '
                              'It goes to the standings and to both sides\' '
                              'records straight away.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Not yet'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Finish match'),
                              ),
                            ],
                          ),
                        );
                        if (sure == true) onFinish();
                      },
                icon: const Icon(Icons.flag),
                label: const Text('Finish match'),
              ),
            ],
            if (reopen case final control?)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: enabled ? () => onReopen(control) : null,
                  icon: const Icon(Icons.undo),
                  // Named for the mistake it undoes, not for the mechanism —
                  // same wording as the finish sheet, on purpose.
                  label: const Text('The last point was wrong — reopen'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What everybody who is not the scorer sees, the owner included.
///
/// Deliberately not an error and not a locked padlock: the match is being
/// scored, correctly, by the person who was given it. This is the live view
/// with an honest explanation of why there are no buttons — plus, for an
/// organizer, the one action that changes it.
class _PenHeldElsewhere extends ConsumerWidget {
  const _PenHeldElsewhere({
    required this.fixture,
    required this.canManage,
    required this.myUid,
  });

  final Fixture fixture;
  final bool canManage;
  final String myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ctx = fixture.scoringContext();
    final plugin = ScoringRegistry.resolve(fixture.scoringPluginKey);
    final board = plugin.padLayout == PadLayout.duel
        ? plugin.duelBoard(fixture.scoreState, ctx)
        : null;
    final mat = plugin.padLayout == PadLayout.mat
        ? plugin.matBoard(fixture.scoreState, ctx)
        : null;
    final holderUid = fixture.activeScorerUid!;
    final holder =
        ref.watch(userProfileProvider(holderUid)).valueOrNull?.displayName ??
            'The assigned scorer';

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ContentBounds(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The same board the scorer is looking at, with nothing to
              // press. Passing no controls is what makes it read-only: the
              // halves take their tap action from the control list, so an
              // empty one leaves them inert by construction rather than by a
              // flag somebody could forget to pass.
              if (board != null)
                DuelPad(
                  board: board,
                  groups: const [],
                  enabled: false,
                  canUndo: false,
                  onUndo: () {},
                  onControl: (_) {},
                )
              else if (mat != null)
                MatPad(
                  board: mat,
                  groups: const [],
                  enabled: false,
                  canUndo: false,
                  onUndo: () {},
                  onControl: (_) {},
                )
              else
                PadScoreboard(
                  fixture: fixture,
                  headline: plugin.headline(fixture.scoreState, ctx),
                  status: plugin.statusLine(fixture.scoreState, ctx),
                  summary: plugin.summary(fixture.scoreState, ctx),
                  live: fixture.status != FixtureStatus.completed,
                ),
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$holder is scoring this match',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        canManage
                            ? 'Only one person can score a match, so nobody '
                                'else can enter points while they hold it — '
                                'including you. The score here updates live. '
                                'You can move control at any time.'
                            : 'Only one person can score a match. The score '
                                'here updates live as they enter it.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.how_to_reg),
                              label: const Text('Take control'),
                              onPressed: () => confirmTakeControl(
                                context: context,
                                ref: ref,
                                fixture: fixture,
                                myUid: myUid,
                                holderName: holder,
                              ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Give to someone else'),
                              onPressed: () async {
                                final name = await showHandOverPenSheet(
                                  context: context,
                                  ref: ref,
                                  fixture: fixture,
                                );
                                if (name != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '$name is now scoring this match.',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              MatchScorecard(fixture: fixture),
              const SizedBox(height: 8),
              MatchMemoriesSection(fixture: fixture),
            ],
          ),
        ),
      ],
    );
  }
}

/// The pen is this account's, but it was claimed on a different screen.
///
/// A separate state from [_PenHeldElsewhere] because the remedy is different
/// and needs no organizer: it is the same person, so they can simply say
/// which screen they are actually standing at.
class _PenOnAnotherDevice extends StatelessWidget {
  const _PenOnAnotherDevice({required this.onTakeOver});

  final VoidCallback onTakeOver;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.devices_other,
      title: 'This match is being scored on another device',
      message: 'You hold the pen, but it is pinned to the device you started '
          'on. Two live pads race each other and lose points, so only one '
          'counts at a time.',
      action: FilledButton.icon(
        onPressed: onTakeOver,
        icon: const Icon(Icons.phonelink_setup),
        label: const Text('Score on this device instead'),
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
              // Names the official who made the call, and — for a retirement
              // or a disqualification — is what turns this into a logged
              // event rather than a bare field write the rules refuse from
              // anybody who is not an organizer. See [setFixtureOutcome].
              byUid: ref.read(currentUidProvider),
            );
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    /// Starts the match again from nothing — see
    /// [ScoringService.restartMatch] for why the old score survives it.
    Future<void> restart() async {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restart this match?'),
          content: const Text(
            'The score goes back to nothing and the match starts again. '
            'Nothing is deleted — if you did not mean to do this, '
            '"Continue the previous score" brings it all back exactly as it '
            'stood.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restart'),
            ),
          ],
        ),
      );
      if (agreed != true) return;
      try {
        await ref.read(scoringServiceProvider).restartMatch(
              fixture: fixture,
              context: fixture.scoringContext(),
              byUid: ref.read(currentUidProvider) ?? '',
            );
        // No `syncNow()` here. The commit is already on its way, and replay
        // is the recovery path, not the live one. The pad's own projection
        // needs no clearing either: both of these append an event, so the
        // listener's `lastSeq` overtakes it and wins on the next frame.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Match restarted. The previous score is kept.'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    /// Takes the restart back. An ordinary undo of the restart event, which
    /// is what makes the previous score recoverable rather than gone.
    Future<void> continuePrevious() async {
      try {
        await ref.read(scoringServiceProvider).continuePreviousScore(
              fixture: fixture,
              context: fixture.scoringContext(),
              byUid: ref.read(currentUidProvider) ?? '',
            );
        // No `syncNow()` here. The commit is already on its way, and replay
        // is the recovery path, not the live one. The pad's own projection
        // needs no clearing either: both of these append an event, so the
        // listener's `lastSeq` overtakes it and wins on the next frame.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The previous score is back.')),
          );
        }
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    final a = fixture.entrantAName;
    final b = fixture.entrantBName;

    // Which of these outcomes THIS person may actually record.
    //
    // Not decoration, and not defensive coding: `firestore.rules` admits a
    // scorer's write only into `live` or `completed` (branch b). A walkover,
    // an abandonment and a dispute are their own statuses, so a scorer's
    // attempt at one is refused by the server after the local cache has
    // already applied it — the sheet closes, the match looks abandoned for a
    // few seconds, and then quietly goes back to Live. Offering a button that
    // can only do that is worse than not offering it, so an umpire is shown
    // the two outcomes that are theirs to call — a retirement and a
    // disqualification, both of which end the match at the score it reached —
    // and told who to ask for the rest.
    final canManage = ref
        .watch(myCapabilitiesProvider(fixture.orgId))
        .contains(Capability.manageCompetitions);

    // Collapsed by default and staying that way: these are the outcomes a
    // scorer needs perhaps once a season, and the per-option hints inside are
    // NOT trimmed — "awards the points; moves no rating" is the difference
    // between two outcomes that look identical on the card, and a scorer
    // picking between them is making a decision the hint is the only source
    // for. Explanation that changes what someone chooses is not decoration.
    return ExpansionTile(
      title: const Text('Match did not play normally'),
      children: [
        // First, because a restart is the only one of these that is usually
        // tapped by mistake, and the way back from it has to be as easy to
        // find as the way in.
        if (fixture.lastRestartSeq != null)
          ListTile(
            leading: const Icon(Icons.history, color: Colors.green),
            title: const Text('Continue the previous score'),
            subtitle: const Text(
              'Undoes the restart and brings back every point scored before '
              'it',
            ),
            onTap: continuePrevious,
          ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('Restart the match'),
          subtitle: const Text(
            'Back to 0. Nothing is deleted — you can bring the old score '
            'back afterwards',
          ),
          onTap: restart,
        ),
        if (canManage)
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
        if (canManage) ...[
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
        ] else
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'A walkover, an abandonment or a dispute is recorded by an '
              'organizer. Retiring or disqualifying a side is yours to call '
              'and takes effect immediately.',
            ),
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

/// The pre-match step: the toss, in the sport's own words, before the pad.
///
/// Shows what the toss will DO before it is taken — "the winner bats first",
/// "the winner serves first" — because that is the part a scorer needs to
/// have right, and it is the part the old buried-in-a-card version never
/// said. Once recorded, [TossDialog] writes both the frozen config and the
/// opening state, so the side that did not win the toss is put into the
/// other role automatically: choose to bat and the opposition is bowling
/// before the pad is drawn.
class _TossGate extends ConsumerWidget {
  const _TossGate({required this.fixture, required this.onSkip});

  final Fixture fixture;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isChess = fixture.sport == 'chess';
    final choices = TossOptions.forSport(fixture.sport);

    return Center(
      child: ContentBounds(
        maxWidth: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                isChess ? Icons.grid_on : Icons.casino_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                isChess ? 'Draw for colours' : 'Take the toss',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${fixture.entrantAName}  vs  ${fixture.entrantBName}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                // Named per sport, from the same catalogue the dialog itself
                // offers, so this sentence can never describe a choice the
                // next screen does not present.
                'Who won it, and what they took — '
                '${choices.map((c) => c.label.toLowerCase()).join(', ')}. '
                'The other side is put into the opposite role automatically.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  final done = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => TossDialog(fixture: fixture),
                  );
                  // The dialog answers `true` both for a recorded toss and
                  // for its own "Skip toss" button, and either way the scorer
                  // has finished with this step. Recording it would clear the
                  // gate on its own once the fixture listener delivers the
                  // write; skipping would not, and leaving them staring at
                  // the same prompt they just dismissed is the loop this
                  // avoids. `false` is Cancel, which keeps the gate.
                  if (done == true) onSkip();
                },
                icon: const Icon(Icons.casino_outlined),
                label: Text(isChess ? 'Record colours' : 'Record the toss'),
              ),
              const SizedBox(height: 8),
              TextButton(
                // Kept, and kept quiet. A club playing an evening friendly
                // that genuinely did not toss must not be locked out of its
                // own scoring pad — but skipping should look like the
                // exception it is, not like the other half of a choice.
                onPressed: onSkip,
                child: const Text('Skip and start scoring'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
