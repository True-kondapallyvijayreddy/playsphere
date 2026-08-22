import 'dart:async';

import 'package:flutter/widgets.dart';

/// Decides *when* the offline scoring queue gets replayed.
///
/// ## The bug this exists for
///
/// The replay machinery itself — poison eviction, causal ordering, batching,
/// backoff — was complete and correct. Nothing drove it. `reconcileQueue()`
/// was called from exactly one place: `initState` on the scoring pad. So a
/// queued action was only ever retried if the scorer happened to reopen the
/// scoring screen *for that match*.
///
/// That is the least likely thing a scorer does. They finish the match, close
/// the app and go home; there is no reason to open a finished match's pad
/// again. The queued events sat there — through app restarts, through the
/// phone getting full signal — because nothing ever asked them to move. Users
/// reported matches waiting to sync for twelve days on good internet, and
/// that is precisely what the code did.
///
/// ## What drives it now
///
/// Three triggers, chosen to need no new plugin and no background execution:
///
///  - **App start**, once the shell is mounted. Catches the queue left by any
///    previous session.
///  - **App resume.** This is the important one. A phone coming out of a
///    pocket is overwhelmingly the moment it also comes back into signal —
///    walking off the ground, getting home to wi-fi. Every resume is a free,
///    well-timed retry.
///  - **A retry tick** while the queue is non-empty, and only then. An idle
///    app with an empty queue schedules nothing at all, so this costs a
///    device with nothing pending exactly zero.
///
/// Deliberately NOT a connectivity plugin. Replay is already safe to attempt
/// with no network — a failed attempt just re-queues, and
/// [SyncBatchPlanner] holds each entry inside its own backoff window — so
/// knowing the radio state would only let us skip attempts that are already
/// cheap. That is not worth a platform dependency on a product targeting
/// ₹8k phones.
class SyncDriver with WidgetsBindingObserver {
  SyncDriver({
    required Future<void> Function() reconcile,
    required Future<int> Function() pendingCount,
    this.retryInterval = const Duration(seconds: 8),
    this.passTimeout = const Duration(seconds: 20),
  })  : _reconcile = reconcile,
        _pendingCount = pendingCount;

  final Future<void> Function() _reconcile;
  final Future<int> Function() _pendingCount;

  /// How often to retry replay while actions are still queued.
  ///
  /// Deliberately NOT tuned down towards zero, which is what it was: a pass
  /// costs two SERVER reads and a batch commit per affected fixture, and a
  /// three-second tick during active scoring meant one was in flight
  /// essentially all the time. That did not make anything faster — replay is
  /// the RECOVERY path, not the live one. What makes a spectator's screen
  /// update promptly is `batch.commit()` on the scoring path, which the
  /// Firestore SDK sends the moment it has a connection, with no help from
  /// this driver at all.
  ///
  /// What the constant tick did instead was keep a stale queue snapshot
  /// permanently open against a fixture the scorer was still tapping on —
  /// the window both the `_localHead` guard and the mid-pass queue merge in
  /// `ScoringService` now exist to close. Eight seconds is well inside the
  /// acceptable lag for a queue that only matters when the local cache has
  /// been lost, and it leaves that window shut for most of a match.
  final Duration retryInterval;

  /// The watchdog on one reconcile pass.
  ///
  /// ## The bug this exists for
  ///
  /// `_running` is what stops two passes racing over the same queue, and it
  /// is only cleared in the `finally` of [sync]. That is sound exactly as
  /// long as `_reconcile()` is guaranteed to settle — and it was not. The
  /// replay path ends in an awaited `WriteBatch.commit()`, and with offline
  /// persistence on, an awaited Firestore write does not complete until the
  /// SERVER acknowledges it. Off signal, that is never.
  ///
  /// So one reconcile pass attempted in a dead spot never returned, `_running`
  /// stayed true for the life of the process, and every later call — the
  /// resume trigger, the retry tick, the `syncNow()` fired after each score —
  /// hit the re-entrancy guard and returned instantly without doing anything.
  /// The queue then sat there on full signal until the app was force-quit,
  /// which is precisely the "not even 10 minutes later" report.
  ///
  /// A pass that has not settled inside this window is abandoned, not
  /// cancelled: the Firestore write it is waiting on stays in the SDK's own
  /// durable queue and still flushes on reconnect. All this does is give the
  /// driver its ability to run again back.
  final Duration passTimeout;

  Timer? _timer;
  bool _running = false;
  bool _started = false;

  /// Set when a trigger arrives while a pass is already in flight.
  ///
  /// Dropping that trigger outright is wrong for the case that matters: a
  /// scorer tapping four runs while the previous pass is still going has
  /// queued something the in-flight pass has already read past, and without
  /// this it waits a full [retryInterval] for no reason. One extra pass is
  /// scheduled instead, immediately after the current one.
  bool _dirty = false;

  /// True while a replay is in flight. Exposed for tests and for a UI that
  /// wants to show "syncing" rather than "waiting".
  bool get isRunning => _running;

  /// Begins driving. Safe to call more than once — the second call is a no-op
  /// rather than a second observer and a second timer.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // Not awaited: app start must not block on a network round trip.
    unawaited(sync());
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(sync());
    }
  }

  /// Requests a replay pass at the next opportunity.
  ///
  /// NOT for the scoring path. Calling this after every tap was a mistake
  /// built on a misreading of what replay does: it does not push the score
  /// out to spectators — `batch.commit()` already did that — it reconciles a
  /// durable backup queue against the server. Firing it per tap bought no
  /// speed and cost a permanently in-flight pass racing the scorer. See
  /// [retryInterval].
  ///
  /// Legitimate callers are the ones that change what is in the queue or
  /// what the network can do about it: app start, app resume, and a manual
  /// "retry sync" control.
  void syncNow() => unawaited(sync());

  /// Runs one reconcile pass, then schedules another only if work remains.
  ///
  /// Re-entrant calls are dropped rather than queued. A resume that lands
  /// while a tick is already replaying should not start a second pass over
  /// the same entries — both would read the same queue and race to rewrite
  /// it.
  Future<void> sync() async {
    if (_running) {
      // Not dropped — remembered. See [_dirty].
      _dirty = true;
      return;
    }
    _running = true;
    try {
      // The watchdog. See [passTimeout] for the failure this is guarding
      // against; without it a single pass attempted off signal wedges the
      // driver permanently.
      await _reconcile().timeout(passTimeout);
    } on TimeoutException {
      debugPrint(
        '[PlaySphere] sync pass did not settle within $passTimeout — '
        'abandoning it and rearming. Queued writes stay queued.',
      );
    } catch (e) {
      // Never rethrow. This runs from a lifecycle callback and from a timer,
      // neither of which has anywhere to deliver an error, and a failed
      // replay is an expected condition — the entries stay queued and the
      // next tick tries again.
      debugPrint('[PlaySphere] sync pass failed: $e');
    } finally {
      _running = false;
    }

    if (_dirty) {
      _dirty = false;
      // Scheduled rather than recursed, so a steady stream of score actions
      // cannot build an unbounded call stack.
      _timer?.cancel();
      _timer = Timer(Duration.zero, () => unawaited(sync()));
      return;
    }
    await _scheduleNext();
  }

  /// Arms the retry timer if and only if something is still waiting.
  Future<void> _scheduleNext() async {
    _timer?.cancel();
    _timer = null;
    if (!_started) return;

    int remaining;
    try {
      remaining = await _pendingCount();
    } catch (_) {
      // Cannot tell, so assume there is work rather than stopping forever.
      // Stopping on an unreadable queue is how a sync loop dies silently.
      remaining = 1;
    }
    if (remaining <= 0) return;
    if (!_started) return;

    _timer = Timer(retryInterval, () => unawaited(sync()));
  }
}
