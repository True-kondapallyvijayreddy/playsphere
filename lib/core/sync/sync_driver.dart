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
    this.retryInterval = const Duration(minutes: 2),
  })  : _reconcile = reconcile,
        _pendingCount = pendingCount;

  final Future<void> Function() _reconcile;
  final Future<int> Function() _pendingCount;

  /// How often to retry while something is queued.
  ///
  /// Two minutes rather than seconds: every attempt that fails costs a
  /// network round trip and a `SharedPreferences` rewrite, and the entries
  /// have their own per-entry backoff underneath this. Two minutes is well
  /// inside "immediately" as a user experiences it and nowhere near often
  /// enough to matter to a battery.
  final Duration retryInterval;

  Timer? _timer;
  bool _running = false;
  bool _started = false;

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

  /// Runs one reconcile pass, then schedules another only if work remains.
  ///
  /// Re-entrant calls are dropped rather than queued. A resume that lands
  /// while a tick is already replaying should not start a second pass over
  /// the same entries — both would read the same queue and race to rewrite
  /// it.
  Future<void> sync() async {
    if (_running) return;
    _running = true;
    try {
      await _reconcile();
    } catch (e) {
      // Never rethrow. This runs from a lifecycle callback and from a timer,
      // neither of which has anywhere to deliver an error, and a failed
      // replay is an expected condition — the entries stay queued and the
      // next tick tries again.
      debugPrint('[PlaySphere] sync pass failed: $e');
    } finally {
      _running = false;
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
