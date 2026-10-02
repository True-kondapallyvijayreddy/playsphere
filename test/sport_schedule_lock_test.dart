import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/core/notifications/notification_model.dart';

/// Which sports' timetables read as published, and so which get the Draw &
/// schedule and Lock buttons.
void main() {
  Tournament season({
    TournamentStatus status = TournamentStatus.entriesOpen,
    bool locked = false,
    Map<String, DateTime> released = const {},
  }) =>
      Tournament(
        id: 's1',
        orgId: 'org1',
        name: 'Sports Week 2026',
        status: status,
        isScheduleLocked: locked,
        sportSchedulesReleasedAt: released,
      );

  final at = DateTime(2026, 9, 1);

  test('a sport added after every sport was published is a draft', () {
    // Cricket and badminton published, which locked the season; kho-kho
    // added since. The flag must not make kho-kho read as published.
    final t = season(
      status: TournamentStatus.scheduled,
      locked: true,
      released: {'cricket': at, 'badminton': at},
    );
    expect(t.isSportScheduleLocked('cricket'), isTrue);
    expect(t.isSportScheduleLocked('kho_kho'), isFalse);
    expect(t.isWholeScheduleLocked({'cricket', 'badminton', 'kho_kho'}),
        isFalse);
    expect(t.isWholeScheduleLocked({'cricket', 'badminton'}), isTrue);
  });

  test('a season published season-wide keeps every sport published', () {
    for (final t in [
      season(locked: true),
      // Locked before the flag existed: only the status says so.
      season(status: TournamentStatus.inProgress),
    ]) {
      expect(t.publishedSeasonWide, isTrue);
      expect(t.isSportScheduleLocked('cricket'), isTrue);
      expect(t.isWholeScheduleLocked({'cricket'}), isTrue);
    }
  });

  test('a new season with nothing published is a draft everywhere', () {
    final t = season();
    expect(t.publishedSeasonWide, isFalse);
    expect(t.isSportScheduleLocked('cricket'), isFalse);
    expect(t.isWholeScheduleLocked({'cricket'}), isFalse);
  });

  test('a completed season is never reopened', () {
    final t = season(
      status: TournamentStatus.completed,
      released: {'cricket': at},
    );
    expect(t.isSportScheduleLocked('kho_kho'), isTrue);
  });

  group('invitation deep link', () {
    test('a build with the invitations space follows the V2 route', () {
      final link = DeepLink.fromDataPayload({
        'deepLinkRoute': '/org/:orgId/live-tournament/:tournamentId',
        'deepLinkRouteV2': '/invitations?club=:clubId',
        'deepLinkParam_clubId': 'clubB',
        'deepLinkParam_orgId': 'clubA',
        'deepLinkParam_tournamentId': 't1',
      })!;
      expect(link.resolve(), '/invitations?club=clubB');
    });

    test('a payload without V2 still opens its route', () {
      final link = DeepLink.fromDataPayload({
        'deepLinkRoute': '/org/:orgId/event/:compId',
        'deepLinkParam_orgId': 'o',
        'deepLinkParam_compId': 'c',
      })!;
      expect(link.resolve(), '/org/o/event/c');
    });
  });
}
