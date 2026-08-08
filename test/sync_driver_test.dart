import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/sync/sync_driver.dart';

/// Bug #9 — matches sat "waiting to sync" for twelve days on good internet.
///
/// The replay machinery was never the problem: poison eviction, causal
/// ordering, batching and per-entry backoff were all in place and tested.
/// Nothing *drove* it. `reconcileQueue()` was called from exactly one place,
/// `initState` on the scoring pad, so a queued action was only retried if the
/// scorer reopened that specific match's pad — which is the last thing anyone
/// does with a match they have finished. The queue was therefore write-only in
/// practice, and the twelve days were real.
///
/// These pin the triggers, and just as importantly pin that an idle app with
/// nothing queued schedules no work at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A stand-in for the queue: counts replay attempts and drains on demand.
  ///
  /// Deliberately not a mock of `ScoringService` — what is being tested is
  /// the driver's decisions about *when*, and the real service would drag
  /// Firestore and SharedPreferences into a question that is purely about
  /// scheduling.
  ({
    SyncDriver Function({Duration retry}) build,
    int Function() attempts,
    void Function(int) setPending,
    void Function() failEveryPass,
  }) harness() {
    var attempts = 0;
    var pending = 0;
    var shouldThrow = false;

    SyncDriver build({Duration retry = const Duration(milliseconds: 40)}) {
      return SyncDriver(
        reconcile: () async {
          attempts++;
          // A pass that throws drains nothing — which is the real behaviour:
          // entries that could not be pushed stay in the queue.
          if (shouldThrow) throw StateError('no network');
          if (pending > 0) pending--;
        },
        pendingCount: () async => pending,
        retryInterval: retry,
      );
    }

    return (
      build: build,
      attempts: () => attempts,
      setPending: (n) => pending = n,
      failEveryPass: () => shouldThrow = true,
    );
  }

  group('the queue actually gets driven', () {
    test('starting the app replays whatever was left behind', () async {
      final h = harness();
      h.setPending(1);
      final driver = h.build();
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(Duration.zero);

      // The whole point: a scorer who finished a match yesterday and never
      // reopened its pad still gets their events pushed.
      expect(h.attempts(), greaterThanOrEqualTo(1));
    });

    test('resuming the app replays again', () async {
      // A phone coming out of a pocket is overwhelmingly the moment it comes
      // back into signal — walking off the ground, arriving home to wi-fi.
      final h = harness();
      h.setPending(5);
      final driver = h.build(retry: const Duration(hours: 1));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(Duration.zero);
      final afterStart = h.attempts();

      driver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(h.attempts(), greaterThan(afterStart));
    });

    test('being backgrounded does not trigger a replay', () async {
      final h = harness();
      h.setPending(5);
      final driver = h.build(retry: const Duration(hours: 1));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(Duration.zero);
      final afterStart = h.attempts();

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        driver.didChangeAppLifecycleState(state);
      }
      await Future<void>.delayed(Duration.zero);

      expect(h.attempts(), afterStart);
    });

    test('keeps retrying on a tick while entries remain', () async {
      final h = harness();
      h.setPending(3);
      final driver = h.build(retry: const Duration(milliseconds: 20));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Three entries, one drained per pass — it must have come back for the
      // rest without anybody opening a screen.
      expect(h.attempts(), greaterThanOrEqualTo(3));
    });
  });

  group('an idle app costs nothing', () {
    test('an empty queue schedules no further work', () async {
      final h = harness();
      h.setPending(0);
      final driver = h.build(retry: const Duration(milliseconds: 20));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(Duration.zero);
      final afterStart = h.attempts();

      await Future<void>.delayed(const Duration(milliseconds: 120));

      // One pass to check, then silence. A device with nothing pending must
      // not wake up every couple of minutes forever.
      expect(h.attempts(), afterStart);
    });

    test('stops ticking once the queue drains', () async {
      final h = harness();
      h.setPending(2);
      final driver = h.build(retry: const Duration(milliseconds: 20));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final settled = h.attempts();

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.attempts(), settled);
    });
  });

  group('failure handling', () {
    test('a failed pass never throws out of the driver', () async {
      // It runs from a lifecycle callback and from a timer. Neither has
      // anywhere to deliver an error.
      final h = harness();
      h.setPending(2);
      h.failEveryPass();
      final driver = h.build(retry: const Duration(hours: 1));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(Duration.zero);

      expect(h.attempts(), greaterThanOrEqualTo(1));
    });

    test('a failed pass still leaves the retry armed', () async {
      final h = harness();
      h.setPending(2);
      h.failEveryPass();
      final driver = h.build(retry: const Duration(milliseconds: 20));
      addTearDown(driver.dispose);

      driver.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Losing signal must not end the loop — that is exactly how a queue
      // ends up twelve days old.
      expect(h.attempts(), greaterThanOrEqualTo(2));
    });
  });

  group('re-entrancy', () {
    test('a resume during a running pass does not start a second', () async {
      var concurrent = 0;
      var maxConcurrent = 0;

      final driver = SyncDriver(
        reconcile: () async {
          concurrent++;
          maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          concurrent--;
        },
        pendingCount: () async => 0,
        retryInterval: const Duration(hours: 1),
      );
      addTearDown(driver.dispose);

      driver.start();
      driver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      driver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Two passes over the same queue would race to rewrite it.
      expect(maxConcurrent, 1);
    });

    test('start is idempotent', () async {
      final h = harness();
      h.setPending(0);
      final driver = h.build(retry: const Duration(hours: 1));
      addTearDown(driver.dispose);

      driver.start();
      driver.start();
      driver.start();
      await Future<void>.delayed(Duration.zero);

      expect(h.attempts(), 1);
    });

    test('disposing stops the loop', () async {
      final h = harness();
      h.setPending(10);
      final driver = h.build(retry: const Duration(milliseconds: 20));

      driver.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      driver.dispose();
      final atDispose = h.attempts();

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.attempts(), atDispose);
    });
  });
}
