import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/draw/court_delay.dart';

/// TC-ADM-024: one court overrunning used to mean shifting the whole season.
void main() {
  final day = DateTime(2026, 10, 10);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 10, h, m);

  Fixture fx(
    String id,
    DateTime? when, {
    String court = 'c1',
    String venue = 'v1',
    FixtureStatus status = FixtureStatus.scheduled,
    int lastSeq = 0,
  }) =>
      Fixture(
        id: id,
        orgId: 'o1',
        compId: 'e1',
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'A',
        entrantBName: 'B',
        status: status,
        lastSeq: lastSeq,
        scheduledAt: when,
        venueId: venue,
        courtRefId: court,
      );

  test('moves this match and the later ones on the same court', () {
    final target = fx('t', at(10));
    final moves = courtDelayMoves(
      target: target,
      by: const Duration(minutes: 30),
      fixtures: [
        fx('earlier', at(9)),
        target,
        fx('later', at(11)),
        fx('other-court', at(11), court: 'c2'),
        fx('other-venue', at(11), venue: 'v2'),
      ],
    );
    expect(moves, {'t': at(10, 30), 'later': at(11, 30)});
  });

  test('never moves a match under way or played', () {
    final target = fx('t', at(10));
    final moves = courtDelayMoves(
      target: target,
      by: const Duration(minutes: 15),
      fixtures: [
        target,
        fx('live', at(11), status: FixtureStatus.live),
        fx('started', at(12), lastSeq: 3),
        fx('done', at(13), status: FixtureStatus.completed),
      ],
    );
    expect(moves.keys, ['t']);
  });

  test('stays within the day', () {
    final target = fx('t', at(17));
    final tomorrow = fx('tomorrow', day.add(const Duration(days: 1, hours: 9)));
    final moves = courtDelayMoves(
      target: target,
      by: const Duration(minutes: 30),
      fixtures: [target, tomorrow],
    );
    expect(moves.keys, ['t']);
  });

  test('a match with no court or time moves nothing', () {
    expect(
      courtDelayMoves(
        target: fx('t', null),
        by: const Duration(minutes: 30),
        fixtures: const [],
      ),
      isEmpty,
    );
  });
}
