import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/async_combine.dart';

/// Pins the rule that a failed read must not be presentable as an empty one.
///
/// The repository shipped 31 `ref.watch(x).valueOrNull ?? const []` sites. That
/// idiom silently folds "rejected", "still loading" and "genuinely empty" into
/// the same rendered output, which is how a `permission-denied` on fixtures
/// showed up as a competition nobody had entered. These tests exist so that
/// collapsing behaviour cannot be reintroduced without a red suite.
void main() {
  final boom = Exception('permission-denied');

  group('combineAsync2', () {
    test('data only when every input has data', () {
      final r = combineAsync2(
        const AsyncValue.data(2),
        const AsyncValue.data(3),
        (a, b) => a * b,
      );
      expect(r.value, 6);
    });

    test('an error on either side wins over data on the other', () {
      final left = combineAsync2<int, int, int>(
        AsyncValue.error(boom, StackTrace.empty),
        const AsyncValue.data(3),
        (a, b) => a * b,
      );
      final right = combineAsync2<int, int, int>(
        const AsyncValue.data(2),
        AsyncValue.error(boom, StackTrace.empty),
        (a, b) => a * b,
      );

      expect(left.hasError, isTrue);
      expect(right.hasError, isTrue);
      expect(left.error, boom);
    });

    test('an error wins over a sibling still loading', () {
      // Precedence matters: were loading to win, the UI would sit on a spinner
      // forever instead of ever showing the failure.
      final r = combineAsync2<int, int, int>(
        AsyncValue.error(boom, StackTrace.empty),
        const AsyncValue.loading(),
        (a, b) => a * b,
      );
      expect(r.hasError, isTrue);
      expect(r.isLoading, isFalse);
    });

    test('loading while any input is still in flight', () {
      final r = combineAsync2<int, int, int>(
        const AsyncValue.data(2),
        const AsyncValue.loading(),
        (a, b) => a * b,
      );
      expect(r.isLoading, isTrue);
      expect(r.hasValue, isFalse);
    });

    test('the builder never runs on failure', () {
      var ran = false;
      combineAsync2<int, int, int>(
        AsyncValue.error(boom, StackTrace.empty),
        const AsyncValue.data(3),
        (a, b) {
          ran = true;
          return a * b;
        },
      );
      expect(ran, isFalse,
          reason: 'a half-built result is worse than an honest failure');
    });
  });

  group('combineAsync3', () {
    test('data only when all three have data', () {
      final r = combineAsync3(
        const AsyncValue.data(1),
        const AsyncValue.data(2),
        const AsyncValue.data(3),
        (a, b, c) => a + b + c,
      );
      expect(r.value, 6);
    });

    test('a failure in the third input fails the whole combination', () {
      // This is exactly the standings case: competition and entrants load,
      // fixtures are rejected, and the table must not be computed from the
      // fixtures that happened to arrive.
      final r = combineAsync3<int, int, int, int>(
        const AsyncValue.data(1),
        const AsyncValue.data(2),
        AsyncValue.error(boom, StackTrace.empty),
        (a, b, c) => a + b + c,
      );
      expect(r.hasError, isTrue);
      expect(r.error, boom);
    });

    test('preserves the stack trace it was given', () {
      final trace = StackTrace.current;
      final r = combineAsync3<int, int, int, int>(
        AsyncValue.error(boom, trace),
        const AsyncValue.data(2),
        const AsyncValue.data(3),
        (a, b, c) => a + b + c,
      );
      expect(r.stackTrace, trace);
    });
  });
}
