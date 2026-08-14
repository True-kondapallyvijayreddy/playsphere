import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/club_standing.dart';

/// The club ladder as the client reads it.
///
/// The stored order is all-time, because one document can carry one order.
/// Everything worth protecting here is what happens when the screen asks for
/// a narrower window: the list has to be re-ranked, not filtered, or a club
/// that played nothing this month sits above one that won four.
void main() {
  Map<String, dynamic> tally({
    int played = 0,
    int won = 0,
    int drawn = 0,
    int lost = 0,
    int points = 0,
  }) =>
      {
        'played': played,
        'won': won,
        'drawn': drawn,
        'lost': lost,
        'points': points,
      };

  Map<String, dynamic> club(
    String name, {
    required Map<String, dynamic> all,
    Map<String, dynamic>? d30,
  }) =>
      {
        'clubId': name.toLowerCase(),
        'name': name,
        'all': all,
        'd30': d30 ?? tally(),
      };

  test('reads a published ladder', () {
    final standings = ClubStandings.fromMap({
      'clubs': [
        club('Warriors', all: tally(played: 6, won: 4, drawn: 0, lost: 2, points: 12)),
      ],
    }, 'cricket');

    expect(standings.sportId, 'cricket');
    final row = standings.clubs.single;
    expect(row.name, 'Warriors');
    expect(row.tallyFor('all').points, 12);
    expect(row.tallyFor('d90').isEmpty, isTrue);
  });

  test('a narrower window re-ranks rather than filtering', () {
    final standings = ClubStandings.fromMap({
      'clubs': [
        // Top all-time, but played nothing recently.
        club('Warriors',
            all: tally(played: 20, won: 18, points: 54), d30: tally()),
        club('Titans',
            all: tally(played: 6, won: 2, points: 6),
            d30: tally(played: 3, won: 3, points: 9)),
      ],
    }, 'cricket');

    expect(standings.ranked('all').map((c) => c.name), ['Warriors', 'Titans']);
    // Over 30 days only Titans has played, so they lead and Warriors is gone
    // entirely — not shown at rank 1 with a blank record.
    expect(standings.ranked('d30').map((c) => c.name), ['Titans']);
  });

  test('ties break on wins, then name, so the order is stable', () {
    final standings = ClubStandings.fromMap({
      'clubs': [
        club('Zephyr', all: tally(played: 4, won: 2, points: 6)),
        club('Alpha', all: tally(played: 4, won: 2, points: 6)),
        club('Mid', all: tally(played: 5, won: 3, points: 6)),
      ],
    }, 'cricket');

    expect(standings.ranked('all').map((c) => c.name), ['Mid', 'Alpha', 'Zephyr']);
  });

  test('win rate is withheld below three matches', () {
    // One win is not a record, and a ladder claiming 100% on it is one nobody
    // believes twice.
    expect(const ClubTally(played: 1, won: 1).winRate, isNull);
    expect(const ClubTally(played: 2, won: 2).winRate, isNull);
    expect(const ClubTally(played: 4, won: 3).winRate, 0.75);
  });

  test('a malformed row does not take the ladder down', () {
    final standings = ClubStandings.fromMap({
      'clubs': [
        'not a map',
        club('Warriors', all: tally(played: 2, won: 2, points: 6)),
      ],
    }, 'cricket');

    expect(standings.clubs, hasLength(1));
    expect(standings.clubs.single.name, 'Warriors');
  });

  test('an absent document is an empty ladder, not an error', () {
    final standings = ClubStandings.fromMap(null, 'cricket');
    expect(standings.isEmpty, isTrue);
    expect(standings.ranked('all'), isEmpty);
  });
}
