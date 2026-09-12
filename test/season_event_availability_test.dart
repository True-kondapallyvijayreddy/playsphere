import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/draw_config.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/tournament.dart';
import 'package:playsphere/domain/draw/tournament_scheduler.dart';
import 'package:playsphere/data/tournament_repository.dart';

/// Turning two stored documents into "where and when may this sport play".
///
/// Everything the per-sport scheduling feature promises rests on this
/// translation, and a wrong answer here produces a timetable that is wrong in
/// a way nobody can see by reading it — a cricket match on a badminton court
/// looks exactly like a cricket match.
///
/// The other half of the job is that it must be silent. Every season created
/// before per-sport grounds existed stores the season's own venue list, the
/// season's own start date and the schedule config's default hours on every
/// one of its events; read as restrictions, those would pin the whole back
/// catalogue to day one on a subset of its grounds.
void main() {
  final seasonStart = DateTime(2026, 9, 12);
  final seasonEnd = DateTime(2026, 9, 20);

  Tournament season({
    List<String> venueIds = const ['hall', 'field'],
    DateTime? start,
    DateTime? end,
  }) =>
      Tournament(
        id: 't1',
        orgId: 'org1',
        name: 'Annual Meet',
        status: TournamentStatus.entriesOpen,
        venueIds: venueIds,
        startDate: start ?? seasonStart,
        endDate: end ?? seasonEnd,
      );

  Competition event({
    List<String> venueIds = const ['hall', 'field'],
    DateTime? start,
    DateTime? end,
    int dayStartHour = 9,
    int dayEndHour = 19,
  }) =>
      Competition(
        id: 'c1',
        orgId: 'org1',
        tournamentId: 't1',
        name: 'Annual Meet — Badminton',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.draft,
        category: CompetitionCategory.presets().first,
        scoringPluginKey: 'badminton',
        startDate: start ?? seasonStart,
        endDate: end,
        scheduleConfig: ScheduleConfig(
          venueIds: venueIds,
          dayStartHour: dayStartHour,
          dayEndHour: dayEndHour,
        ),
      );

  group('a sport that said nothing restricts nothing', () {
    test('an event holding the season’s own grounds is not confined to them',
        () {
      final a = TournamentRepository.availabilityOf(event(), season());
      expect(a.venueIds, isEmpty);
    });

    test('an event starting on the season’s own first day is not pinned to it',
        () {
      final a = TournamentRepository.availabilityOf(event(), season());
      expect(a.firstDay, isNull);
    });

    test('an event with no end date is not confined to one', () {
      final a = TournamentRepository.availabilityOf(event(), season());
      expect(a.lastDay, isNull);
    });

    test('an event ending exactly when the season does is not a restriction',
        () {
      final a = TournamentRepository.availabilityOf(
        event(end: seasonEnd),
        season(),
      );
      expect(a.lastDay, isNull);
    });
  });

  group('a sport that said something is held to it', () {
    test('one ground out of two is a real restriction', () {
      final a = TournamentRepository.availabilityOf(
        event(venueIds: ['hall']),
        season(),
      );
      expect(a.venueIds, {'hall'});
      expect(a.isUnrestricted, isFalse);
    });

    test('a later start day is kept', () {
      final later = DateTime(2026, 9, 14);
      final a = TournamentRepository.availabilityOf(
        event(start: later),
        season(),
      );
      expect(a.firstDay, later);
    });

    test('an earlier finish is kept', () {
      final earlier = DateTime(2026, 9, 15);
      final a = TournamentRepository.availabilityOf(
        event(end: earlier),
        season(),
      );
      expect(a.lastDay, earlier);
    });

    test('the hours are taken as written, defaults included', () {
      // Not conditioned on "is this the default": the single-event scheduler
      // has always built its grid straight from these two numbers, and a
      // tournament that instead used its buildings' opening hours is why a
      // season whose form said 09:00–19:00 could still schedule at seven in
      // the morning.
      final a = TournamentRepository.availabilityOf(event(), season());
      expect(a.dayStartHour, 9);
      expect(a.dayEndHour, 19);

      final evening = TournamentRepository.availabilityOf(
        event(dayStartHour: 16, dayEndHour: 20),
        season(),
      );
      expect(evening.dayStartHour, 16);
      expect(evening.dayEndHour, 20);
    });
  });

  group('the restriction answers the questions the scheduler asks', () {
    test('a hall-only sport rejects the field and accepts the hall', () {
      final a = TournamentRepository.availabilityOf(
        event(venueIds: ['hall']),
        season(),
      );
      expect(
        a.allowsCourt(const CourtRefLike(venueId: 'hall').ref),
        isTrue,
      );
      expect(
        a.allowsCourt(const CourtRefLike(venueId: 'field').ref),
        isFalse,
      );
    });

    test('an afternoon sport rejects a morning window', () {
      final a = TournamentRepository.availabilityOf(
        event(dayStartHour: 16, dayEndHour: 20),
        season(),
      );
      expect(
        a.allowsWindow(ScheduleWindow(
          start: DateTime(2026, 9, 12, 10),
          end: DateTime(2026, 9, 12, 10, 30),
        )),
        isFalse,
      );
      expect(
        a.allowsWindow(ScheduleWindow(
          start: DateTime(2026, 9, 12, 17),
          end: DateTime(2026, 9, 12, 17, 30),
        )),
        isTrue,
      );
    });

    test('a two-day sport rejects a day outside its own window', () {
      final a = TournamentRepository.availabilityOf(
        event(start: DateTime(2026, 9, 14), end: DateTime(2026, 9, 15)),
        season(),
      );
      bool allowsDay(int d) => a.allowsWindow(ScheduleWindow(
            start: DateTime(2026, 9, d, 10),
            end: DateTime(2026, 9, d, 10, 30),
          ));
      expect(allowsDay(13), isFalse);
      expect(allowsDay(14), isTrue);
      expect(allowsDay(15), isTrue);
      expect(allowsDay(16), isFalse);
    });
  });
}

/// A one-field stand-in so these cases read as "a court at this ground"
/// rather than as four strings of scheduler bookkeeping.
class CourtRefLike {
  const CourtRefLike({required this.venueId});

  final String venueId;

  CourtRef get ref => CourtRef(
        venueId: venueId,
        venueName: venueId,
        courtId: 'c1',
        courtName: 'Court 1',
      );
}
