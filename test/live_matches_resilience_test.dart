import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/async_combine.dart';

/// Bug #4 — "Could not load live Matches".
///
/// The home dashboard fans out one collection-group read per club a person
/// belongs to and stitches the answers together. It used to do that with
/// [combineAsyncAll], which fails the whole combination if any single input
/// failed. So one unreadable club — most often a membership still pointing at
/// a club that no longer exists — took down the live section for ALL of that
/// person's clubs at once, and the screen showed the error with no matches
/// behind it.
///
/// The rule these pin: keep what loaded, and never hide the fact that
/// something did not.
void main() {
  group('one club failing does not erase the others', () {
    test('matches from the clubs that loaded are still returned', () {
      final result = combineAsyncTolerant<String>([
        const AsyncValue.data(['nizampet-match']),
        AsyncValue.error(Exception('permission-denied'), StackTrace.empty),
        const AsyncValue.data(['kompally-match']),
      ]);

      expect(result.items, ['nizampet-match', 'kompally-match']);
      expect(result.failures, hasLength(1));
      expect(result.hasFailures, isTrue);
      // Not a total failure: there is real data to show.
      expect(result.isTotalFailure, isFalse);
    });

    test('the failure is reported, not swallowed', () {
      // The old behaviour was honest but catastrophic; silently dropping the
      // club would be the opposite mistake. Both are refused.
      final result = combineAsyncTolerant<String>([
        const AsyncValue.data(['a']),
        AsyncValue.error(Exception('boom'), StackTrace.empty),
      ]);

      expect(result.failures, hasLength(1));
      expect(result.items, ['a']);
    });

    test('several clubs failing are each counted', () {
      final result = combineAsyncTolerant<String>([
        AsyncValue.error(Exception('one'), StackTrace.empty),
        const AsyncValue.data(['b']),
        AsyncValue.error(Exception('two'), StackTrace.empty),
      ]);

      expect(result.failures, hasLength(2));
      expect(result.items, ['b']);
    });
  });

  group('when there is genuinely nothing to show', () {
    test('every club failing is a total failure', () {
      final result = combineAsyncTolerant<String>([
        AsyncValue.error(Exception('one'), StackTrace.empty),
        AsyncValue.error(Exception('two'), StackTrace.empty),
      ]);

      // Nothing loaded, so an empty list would be a lie and the screen must
      // be allowed to say the read failed.
      expect(result.isTotalFailure, isTrue);
      expect(result.items, isEmpty);
    });

    test('a clean empty fan-out is not a failure', () {
      final result = combineAsyncTolerant<String>([
        const AsyncValue.data([]),
        const AsyncValue.data([]),
      ]);

      expect(result.isTotalFailure, isFalse);
      expect(result.hasFailures, isFalse);
      expect(result.isLoading, isFalse);
      expect(result.items, isEmpty);
    });

    test('no clubs at all is not a failure', () {
      final result = combineAsyncTolerant<String>([]);

      expect(result.isTotalFailure, isFalse);
      expect(result.hasFailures, isFalse);
    });
  });

  group('loading', () {
    test('a club still in flight marks the whole thing loading', () {
      final result = combineAsyncTolerant<String>([
        const AsyncValue.data(['a']),
        const AsyncValue.loading(),
      ]);

      expect(result.isLoading, isTrue);
      // The club that HAS answered is shown immediately rather than held back
      // behind the slowest one.
      expect(result.items, ['a']);
    });

    test('a refreshing stream keeps showing what it already delivered', () {
      // Riverpod carries both a value and the loading flag while a stream
      // re-subscribes. Dropping the value there makes the live list flicker
      // empty on every rebuild.
      const refreshing = AsyncValue<List<String>>.data(['held']);

      final result = combineAsyncTolerant<String>([
        refreshing.copyWithPrevious(const AsyncValue.loading()),
      ]);

      expect(result.items, ['held']);
    });

    test('a failure alongside a loading club is still not total', () {
      final result = combineAsyncTolerant<String>([
        AsyncValue.error(Exception('nope'), StackTrace.empty),
        const AsyncValue.loading(),
      ]);

      // Still loading, so we cannot yet claim everything failed.
      expect(result.isLoading, isTrue);
      expect(result.isTotalFailure, isFalse);
    });
  });

  group('the strict combiner is unchanged', () {
    test('combineAsyncAll still fails fast where that is wanted', () {
      // Deliberately left alone: the challenge and approval fan-outs are
      // gated on a capability, so a rejection there is a real bug rather
      // than a stale membership, and it should be loud.
      final result = combineAsyncAll<String>([
        const AsyncValue.data(['a']),
        AsyncValue.error(Exception('boom'), StackTrace.empty),
      ]);

      expect(result.hasError, isTrue);
    });
  });
}
