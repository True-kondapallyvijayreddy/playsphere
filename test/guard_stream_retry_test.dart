import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/errors/app_exception.dart';
import 'package:playsphere/data/org_repository.dart' show guardStream;

/// Pins the behaviour that keeps a founder's first four seconds clean.
///
/// Writes are deliberately not awaited, so a new club and its owner
/// membership reach the LOCAL cache before the server. In that window the
/// dashboard fans out over the new club and every org-scoped read is refused,
/// because the rules ask the server for an owner membership it does not have
/// yet. A Firestore listener that errors is finished — nothing re-subscribes
/// it — so without a retry those refusals became five permanent red strips on
/// the Notifications screen of somebody who had just created a club.
void main() {
  FirebaseException denied() =>
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  group('guardStream', () {
    test('a refusal that clears on retry never reaches the screen', () async {
      var attempts = 0;

      final values = await guardStream<int>(() {
        attempts++;
        return attempts == 1
            ? Stream<int>.error(denied())
            : Stream<int>.value(7);
      }).toList();

      expect(attempts, 2);
      expect(values, [7]);
    });

    test('a refusal that is real still surfaces, named', () async {
      var attempts = 0;

      await expectLater(
        guardStream<int>(() {
          attempts++;
          return Stream<int>.error(denied());
        }).toList(),
        throwsA(isA<PermissionDeniedException>()),
      );

      // The first attempt plus the two backed-off retries, and no more: a
      // denial that is genuinely permanent must not become an infinite
      // re-subscribe loop billing reads forever.
      expect(attempts, 3);
    });

    test('a failure a retry cannot fix is not retried', () async {
      var attempts = 0;

      await expectLater(
        guardStream<int>(() {
          attempts++;
          return Stream<int>.error(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'failed-precondition',
            ),
          );
        }).toList(),
        throwsA(isA<BackendNotReadyException>()),
      );

      // A missing index is rejected identically on every attempt. Retrying it
      // only delays the one message that tells the operator to go deploy it.
      expect(attempts, 1);
    });

    test('data already delivered is not swallowed by a later refusal',
        () async {
      var attempts = 0;

      final seen = <int>[];
      await guardStream<int>(() {
        attempts++;
        return attempts == 1
            ? Stream<int>.fromIterable([1, 2]).followedBy(denied())
            : Stream<int>.value(3);
      }).forEach(seen.add);

      // A listener that had already painted a screen and then lost the right
      // to read re-delivers from scratch, which is what a re-subscribed
      // Firestore query does too.
      expect(seen, [1, 2, 3]);
    });
  });
}

extension on Stream<int> {
  /// Emits everything this stream has, then fails.
  Stream<int> followedBy(Object error) async* {
    yield* this;
    throw error;
  }
}
