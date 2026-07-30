import 'sync_queue_entry.dart';

/// Backoff schedule for a queued entry that has failed a replay attempt.
///
/// ## Why exponential, and why a poison-pill limit exists at all
///
/// A "still offline" entry and a "permanently broken" entry look identical
/// after one failure — both just threw. The only way to tell them apart from
/// the client's side is time: the offline case resolves itself within
/// seconds to minutes once the device gets signal again, while a malformed
/// payload or a rules rejection (a fixture that got deleted server-side, or
/// a security-rule change that outlaws a field an old app build still
/// writes) fails forever no matter how many times it is retried. Retrying a
/// genuinely broken entry at full speed on every reconnect does two things
/// wrong at once: it burns a request on something that can never succeed,
/// and — because entries within one fixture must replay in `seq` order —
/// it blocks every legitimate action queued after it for that fixture,
/// indefinitely.
///
/// Exponential backoff buys the "still offline" case time to resolve itself
/// without hammering the network on every reconnect attempt; the attempt cap
/// is what tells it apart from the broken case and gets the broken entry out
/// of the way instead of leaving it to jam the queue forever.
class SyncBackoff {
  const SyncBackoff._();

  /// Entries that have failed this many replay attempts are evicted rather
  /// than retried again. Chosen high enough that a scorer offline for days —
  /// a multi-day rural tournament with one evening of signal — is never
  /// mistaken for broken, but low enough that a genuinely poisoned entry
  /// does not sit blocking its fixture's queue for the rest of the
  /// tournament.
  static const maxAttempts = 8;

  /// Delay before attempt number [attempts] (1-based: the wait *after* the
  /// first failure). Doubles from a 5-second base and caps at 30 minutes, so
  /// a device that regains signal overnight retries promptly rather than
  /// waiting until morning for its next scheduled attempt.
  static Duration delayFor(int attempts) {
    if (attempts <= 0) return Duration.zero;
    // Clamp the exponent, not just the result: 2^30 seconds would overflow
    // a 32-bit int on some platforms before the outer clamp ever runs.
    final exponent = attempts.clamp(1, 10);
    final seconds = 5 * (1 << (exponent - 1));
    return Duration(seconds: seconds.clamp(0, 30 * 60));
  }

  static bool isPoison(int attempts) => attempts >= maxAttempts;
}

/// The result of [SyncBatchPlanner.plan]: what to attempt right now, and
/// what to leave in the queue untouched.
class SyncBatchPlan {
  const SyncBatchPlan({
    required this.toReplay,
    required this.deferred,
    required this.overflow,
  });

  /// Entries due for a replay attempt now, grouped by fixture and ordered by
  /// `seq` ascending within each group — the causal order CLAUDE.md §4
  /// requires ("pushes unsynced records in causal order"). Group order
  /// itself follows first-appearance in the input queue: stable, and good
  /// enough, since there is no ordering requirement *between* fixtures.
  final List<SyncQueueEntry> toReplay;

  /// Entries still inside their backoff window from a previous failure.
  /// Left untouched; not counted against the batch cap since they were never
  /// going to be attempted this round anyway.
  final List<SyncQueueEntry> deferred;

  /// Entries that were due, but did not fit inside the batch cap this round.
  /// Left untouched and not penalised with a backoff delay — sitting behind
  /// a busy queue is not this entry's fault, and it may be first in line
  /// next time. A fixture's group can straddle the cutoff; the entries that
  /// do make the cut are still exactly its earliest-queued ones, so a
  /// partial round still makes genuine forward progress in the right order.
  final List<SyncQueueEntry> overflow;
}

/// Turns a flat, arbitrarily-ordered queue into a plan that respects the
/// constraints CLAUDE.md places on sync replay: causal order per fixture
/// (§4), a per-batch cap of 500 events (§12.9), and — this planner's own
/// addition — never retrying an entry before its backoff window has passed.
///
/// Deliberately pure: no Firestore, no IO, nothing async. `ScoringService`
/// is the only caller that touches the network; everything here is a
/// question about a `List<SyncQueueEntry>` that can be answered, and tested,
/// with plain data.
class SyncBatchPlanner {
  const SyncBatchPlanner._();

  static SyncBatchPlan plan(
    List<SyncQueueEntry> queue, {
    int maxBatchSize = 500,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();

    final due = <SyncQueueEntry>[];
    final deferred = <SyncQueueEntry>[];
    for (final e in queue) {
      final backedOff =
          e.nextAttemptAt != null && e.nextAttemptAt!.isAfter(at);
      (backedOff ? deferred : due).add(e);
    }

    // Group by fixture, preserving the order fixtures first appear in the
    // queue, then sort each group by seq — "fixture, then events by seq".
    final order = <String>[];
    final groups = <String, List<SyncQueueEntry>>{};
    for (final e in due) {
      final key = e.fixtureKey;
      if (!groups.containsKey(key)) order.add(key);
      groups.putIfAbsent(key, () => <SyncQueueEntry>[]).add(e);
    }
    for (final key in order) {
      groups[key]!.sort((a, b) => a.seq.compareTo(b.seq));
    }

    final ordered = <SyncQueueEntry>[
      for (final key in order) ...groups[key]!,
    ];

    if (ordered.length <= maxBatchSize) {
      return SyncBatchPlan(
        toReplay: ordered,
        deferred: deferred,
        overflow: const [],
      );
    }
    return SyncBatchPlan(
      toReplay: ordered.sublist(0, maxBatchSize),
      deferred: deferred,
      overflow: ordered.sublist(maxBatchSize),
    );
  }

  /// Splits a set of entries into those still worth attempting and those
  /// that have exhausted [SyncBackoff.maxAttempts] and must be evicted
  /// instead of retried again. Run this over the *whole* queue before
  /// [plan], not just the entries [plan] selected for this round — a
  /// poisoned entry sitting in backoff or past the batch cap must still be
  /// found and evicted rather than waiting for a round where it happens to
  /// be selected.
  static (List<SyncQueueEntry> alive, List<SyncQueueEntry> poisoned)
      partitionPoison(List<SyncQueueEntry> entries) {
    final alive = <SyncQueueEntry>[];
    final poisoned = <SyncQueueEntry>[];
    for (final e in entries) {
      (SyncBackoff.isPoison(e.attempts) ? poisoned : alive).add(e);
    }
    return (alive, poisoned);
  }
}
