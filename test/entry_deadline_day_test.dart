import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/firestore_codec.dart';
import 'package:playsphere/core/models/tournament.dart';

/// "Home says 0 active seasons on day one."
///
/// On 19 Sep, the first day of two seasons whose entries were still open and
/// still showing Register buttons, the home tile read "Active seasons 0". The
/// day before it read 2. Both seasons closed entries "19 Sep", and a date
/// picker means midnight — so entries closed before the day they named began.
void main() {
  group('a deadline picked as a day', () {
    test('midnight is read as the end of that day', () {
      final closes = endOfDeadlineDay(DateTime(2026, 9, 19));
      expect(closes, DateTime(2026, 9, 19, 23, 59, 59, 999));
    });

    test('a real time of day is left exactly as the organizer set it', () {
      // "Entries close at 6pm" means 6pm, and rounding it up to midnight would
      // keep a field open for six hours the organizer had closed.
      final at6 = DateTime(2026, 9, 19, 18);
      expect(endOfDeadlineDay(at6), at6);
    });

    test('no deadline stays no deadline', () {
      expect(endOfDeadlineDay(null), isNull);
    });
  });

  group('a season on its first morning', () {
    Tournament season({DateTime? deadline}) => Tournament(
          id: 't1',
          orgId: 'o1',
          name: 'PS House Games 2026',
          startDate: DateTime(2026, 9, 19),
          endDate: DateTime(2026, 9, 21),
          entryDeadline: deadline,
          status: TournamentStatus.entriesOpen,
        );

    test('is still taking entries at 9am on the closing day', () {
      final s = season(deadline: DateTime(2026, 9, 19));
      expect(s.entryDeadlinePassed(DateTime(2026, 9, 19, 9)), isFalse);
    });

    test('is closed the next morning', () {
      final s = season(deadline: DateTime(2026, 9, 19));
      expect(s.entryDeadlinePassed(DateTime(2026, 9, 20, 9)), isTrue);
    });

    test('never closes when no deadline was set', () {
      expect(season().entryDeadlinePassed(DateTime(2030, 1, 1)), isFalse);
    });
  });

  group('an event on its closing day', () {
    Competition event({DateTime? closes}) => Competition(
          id: 'c1',
          orgId: 'o1',
          name: 'Badminton Singles',
          sportId: 'badminton',
          sportName: 'Badminton',
          archetype: CompetitionArchetype.versus,
          entrantType: EntrantType.individual,
          format: CompetitionFormat.knockout,
          status: CompetitionStatus.registrationOpen,
          category: const CompetitionCategory(label: 'Open'),
          scoringPluginKey: 'rally_based',
          startDate: DateTime(2026, 9, 19),
          registrationClosesAt: closes,
        );

    test('still takes entries during the day it closes', () {
      final c = event(closes: DateTime(2026, 9, 19));
      expect(c.registrationDeadlinePassed(DateTime(2026, 9, 19, 10)), isFalse);
      expect(
        c.displayStatus(DateTime(2026, 9, 19, 10)),
        CompetitionStatus.registrationOpen,
      );
    });

    test('reads as closed once that day is over', () {
      final c = event(closes: DateTime(2026, 9, 19));
      expect(c.registrationDeadlinePassed(DateTime(2026, 9, 20)), isTrue);
      expect(
        c.displayStatus(DateTime(2026, 9, 20)),
        CompetitionStatus.registrationClosed,
      );
    });
  });
}
