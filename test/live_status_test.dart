import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';

/// Bug #1 — matches that are not live were being displayed as Live.
///
/// The cause was that `status == live` is a claim a fixture makes about
/// itself and then never retracts. A match enters `live` on its first ball
/// and only leaves on the event its scoring plugin calls a result, so every
/// match a scorer abandons — a dead phone, rain, a last over nobody entered —
/// keeps claiming to be live indefinitely. Users saw matches badged LIVE days
/// after they finished, which is the same report as Bug #15.
///
/// The rule these pin: a match is Live only when its scoreboard is warm.
void main() {
  final now = DateTime(2026, 8, 5, 18, 0);

  Fixture fixture({
    required FixtureStatus status,
    int lastSeq = 12,
    DateTime? lastEventAt,
    DateTime? startedAt,
  }) =>
      Fixture(
        id: 'f1',
        orgId: 'o1',
        compId: 'c1',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'Ravi',
        entrantBName: 'Kiran',
        status: status,
        lastSeq: lastSeq,
        startedAt: startedAt,
        lastEventAt: lastEventAt,
      );

  group('a match is live only while it is being scored', () {
    test('a scoreboard touched moments ago is live', () {
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: now.subtract(const Duration(minutes: 2)),
      );

      expect(f.isLiveAt(now), isTrue);
      expect(f.isStaleLiveAt(now), isFalse);
    });

    test('a scoreboard nobody has touched for days is not live', () {
      // The exact shape of the reported bug: scored on Saturday, still
      // wearing a LIVE badge on Wednesday.
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: now.subtract(const Duration(days: 4)),
      );

      expect(f.isLiveAt(now), isFalse);
      expect(f.isStaleLiveAt(now), isTrue);
    });

    test('a long lunch break does not end a match', () {
      // A full-day cricket match pauses for an hour and is still live. The
      // staleness window has to clear an ordinary interval or the badge
      // flickers off mid-match, which is its own bug.
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: now.subtract(const Duration(hours: 1, minutes: 30)),
      );

      expect(f.isLiveAt(now), isTrue);
    });

    test('the boundary sits exactly at the staleness window', () {
      final justInside = fixture(
        status: FixtureStatus.live,
        lastEventAt: now
            .subtract(Fixture.liveStaleAfter)
            .add(const Duration(minutes: 1)),
      );
      final justOutside = fixture(
        status: FixtureStatus.live,
        lastEventAt: now.subtract(Fixture.liveStaleAfter),
      );

      expect(justInside.isLiveAt(now), isTrue);
      expect(justOutside.isLiveAt(now), isFalse);
    });
  });

  group('not started and finished matches are never live', () {
    test('a scheduled match is not live however warm its clock', () {
      final f = fixture(
        status: FixtureStatus.scheduled,
        lastEventAt: now,
      );

      expect(f.isLiveAt(now), isFalse);
      expect(f.isStaleLiveAt(now), isFalse);
    });

    test('a match with no events yet has not started', () {
      // Belt and braces against a fixture whose status was set to live by
      // some path other than a scoring action. No events means no scoreboard,
      // whatever the status field claims.
      final f = fixture(
        status: FixtureStatus.live,
        lastSeq: 0,
        lastEventAt: now,
      );

      expect(f.isLiveAt(now), isFalse);
    });

    test('a completed match is not live', () {
      final f = fixture(
        status: FixtureStatus.completed,
        lastEventAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(f.isLiveAt(now), isFalse);
      expect(f.isStaleLiveAt(now), isFalse);
    });

    test('walkovers and abandonments are not live', () {
      for (final s in [
        FixtureStatus.walkover,
        FixtureStatus.abandoned,
        FixtureStatus.disputed,
      ]) {
        expect(
          fixture(status: s, lastEventAt: now).isLiveAt(now),
          isFalse,
          reason: '$s must never read as live',
        );
      }
    });
  });

  group('fixtures written before the heartbeat existed', () {
    test('fall back to startedAt rather than claiming to be live', () {
      // Every match already in Firestore predates `lastEventAt`. An old match
      // that started days ago must read as stale, not as live — that IS the
      // backlog of matches users are complaining about.
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: null,
        startedAt: now.subtract(const Duration(days: 12)),
      );

      expect(f.isLiveAt(now), isFalse);
      expect(f.isStaleLiveAt(now), isTrue);
    });

    test('an old match started minutes ago is still live', () {
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: null,
        startedAt: now.subtract(const Duration(minutes: 5)),
      );

      expect(f.isLiveAt(now), isTrue);
    });

    test('no timestamps at all reads as not live, never as live', () {
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: null,
        startedAt: null,
      );

      expect(f.isLiveAt(now), isFalse);
      expect(f.isStaleLiveAt(now), isTrue);
    });
  });

  group('clock skew', () {
    test('a heartbeat from the future does not read as stale', () {
      // Server timestamps can land slightly ahead of a device clock. That
      // must not knock a genuinely live match off the list.
      final f = fixture(
        status: FixtureStatus.live,
        lastEventAt: now.add(const Duration(seconds: 30)),
      );

      expect(f.isLiveAt(now), isTrue);
    });
  });

  group('the stored status is still readable on its own', () {
    test('isLive reports the record, isLiveAt reports reality', () {
      final abandoned = fixture(
        status: FixtureStatus.live,
        lastEventAt: now.subtract(const Duration(days: 3)),
      );

      // Scoring permissions and state transitions still key off the stored
      // status — a scorer must be able to resume an abandoned match.
      expect(abandoned.isLive, isTrue);
      expect(abandoned.status.acceptsScoring, isTrue);
      // But nothing a spectator reads calls it live.
      expect(abandoned.isLiveAt(now), isFalse);
    });
  });
}
