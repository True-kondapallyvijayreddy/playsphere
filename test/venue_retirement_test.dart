import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/fixture.dart';
import 'package:playsphere/domain/tournament/venue_retirement.dart';

/// TC-ADM-040: unticking a venue in the season's venue list saved at once even
/// with a match still booked on one of its courts, which was left pointing at a
/// court the season no longer had.
void main() {
  Fixture fx(
    String id, {
    String compId = 'chess',
    String? venueId = 'ground1',
    FixtureStatus status = FixtureStatus.scheduled,
    String? roundLabel = 'Final',
    DateTime? at,
  }) =>
      Fixture(
        id: id,
        orgId: 'o1',
        compId: compId,
        entrantAId: 'a',
        entrantBId: 'b',
        entrantAName: 'Priyanka',
        entrantBName: 'Vijay',
        status: status,
        roundLabel: roundLabel,
        venueId: venueId,
        scheduledAt: at,
      );

  String? block(
    Iterable<Fixture> fixtures, {
    Set<String> removed = const {'ground1'},
    Map<String, Set<String>> eventVenues = const {},
  }) =>
      venueRetirementBlock(
        removedVenueIds: removed,
        fixtures: fixtures,
        eventVenueIds: eventVenues,
        venueNames: const {'ground1': 'PS Test Ground'},
      );

  test('refuses removing a venue with an unplayed match on it, naming it', () {
    final message = block([fx('f1')]);
    expect(message, isNotNull);
    expect(message, contains('PS Test Ground still has 1 match booked'));
    expect(message, contains('Final Priyanka v Vijay'));
  });

  test('a match under way counts — it is still on that court', () {
    expect(block([fx('f1', status: FixtureStatus.live)]), isNotNull);
  });

  test('played and called-off matches do not hold the venue', () {
    expect(
      block([
        fx('f1', status: FixtureStatus.completed),
        fx('f2', status: FixtureStatus.walkover),
        fx('f3', status: FixtureStatus.abandoned),
      ]),
      isNull,
    );
  });

  test('a match on another venue is not affected', () {
    expect(block([fx('f1', venueId: 'ground2')]), isNull);
  });

  test('an event that names the venue itself still has it', () {
    // The season dropping a ground does not take it from an event that names
    // it in its own settings, so that event's matches are not stranded.
    expect(
      block([
        fx('f1')
      ], eventVenues: {
        'chess': {'ground1'},
      }),
      isNull,
    );
  });

  test('only adding venues is never refused', () {
    expect(block([fx('f1')], removed: const {}), isNull);
  });

  test('lists the first few in time order and counts the rest', () {
    final day = DateTime(2026, 10, 10, 9);
    final message = block([
      for (var i = 4; i >= 0; i--)
        fx('f$i', roundLabel: 'Round $i', at: day.add(Duration(hours: i))),
    ])!;
    expect(message, contains('5 matches booked'));
    expect(message.indexOf('Round 0'), lessThan(message.indexOf('Round 1')));
    expect(message, contains('and 2 more'));
    expect(message, isNot(contains('Round 4')));
  });
}
