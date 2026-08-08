import 'package:flutter_test/flutter_test.dart';

import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';

/// Bug #6 — once the registration date passes, the event should show
/// "Registration Closed" by itself.
///
/// It did not, because `status` is a stored field and nothing writes it when
/// a deadline passes: there is no scheduled job over every event, and the
/// organizer is not going to open the app at midnight to flip it. So a
/// competition whose entries shut on Friday still advertised "Registration
/// Open" the next week, while [Competition.registrationIsOpen] had already
/// correctly disabled the button — the label and the button disagreed.
///
/// The fix derives the displayed status on read. These pin what it derives,
/// and just as importantly what it refuses to derive.
void main() {
  final now = DateTime(2026, 8, 5, 12, 0);

  Competition competition({
    required CompetitionStatus status,
    DateTime? closesAt,
  }) =>
      Competition(
        id: 'c1',
        orgId: 'o1',
        name: 'Nizampet Summer Cup',
        sportId: 'badminton',
        sportName: 'Badminton',
        archetype: CompetitionArchetype.versus,
        entrantType: EntrantType.individual,
        format: CompetitionFormat.knockout,
        status: status,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: 'goal_based',
        registrationClosesAt: closesAt,
      );

  group('the deadline closes registration on its own', () {
    test('an event past its deadline shows Registration Closed', () {
      final c = competition(
        status: CompetitionStatus.registrationOpen,
        closesAt: now.subtract(const Duration(days: 3)),
      );

      expect(c.displayStatus(now), CompetitionStatus.registrationClosed);
      expect(c.displayStatus(now).label, 'Registration Closed');
      // The stored field is untouched — this is a read-time derivation, not
      // a write, so it works on every event already in the database.
      expect(c.status, CompetitionStatus.registrationOpen);
    });

    test('an event before its deadline still shows Registration Open', () {
      final c = competition(
        status: CompetitionStatus.registrationOpen,
        closesAt: now.add(const Duration(days: 2)),
      );

      expect(c.displayStatus(now), CompetitionStatus.registrationOpen);
    });

    test('the boundary is the deadline itself', () {
      final atDeadline = competition(
        status: CompetitionStatus.registrationOpen,
        closesAt: now,
      );
      final aMinuteLater = competition(
        status: CompetitionStatus.registrationOpen,
        closesAt: now.subtract(const Duration(minutes: 1)),
      );

      // Registration is open right up to the stated moment.
      expect(atDeadline.displayStatus(now), CompetitionStatus.registrationOpen);
      expect(
        aMinuteLater.displayStatus(now),
        CompetitionStatus.registrationClosed,
      );
    });

    test('an event with no deadline never closes itself', () {
      // Plenty of club events run "until we say stop". Inventing a cut-off
      // for them would close registration nobody asked to close.
      final c = competition(status: CompetitionStatus.registrationOpen);

      expect(c.displayStatus(now), CompetitionStatus.registrationOpen);
      expect(c.registrationDeadlinePassed(now), isFalse);
    });
  });

  group('what the deadline must NOT override', () {
    test('a running event is not dragged back to Registration Closed', () {
      // The deadline says nothing about an event that has already started.
      final c = competition(
        status: CompetitionStatus.inProgress,
        closesAt: now.subtract(const Duration(days: 5)),
      );

      expect(c.displayStatus(now), CompetitionStatus.inProgress);
    });

    test('a completed or cancelled event keeps its real status', () {
      for (final s in [
        CompetitionStatus.completed,
        CompetitionStatus.cancelled,
        CompetitionStatus.scheduled,
        CompetitionStatus.registrationClosed,
      ]) {
        final c = competition(
          status: s,
          closesAt: now.subtract(const Duration(days: 5)),
        );
        expect(
          c.displayStatus(now),
          s,
          reason: '$s is a decision somebody made and must not be overwritten',
        );
      }
    });
  });

  group('the label and the button now agree', () {
    test('a passed deadline shows closed AND refuses registration', () {
      // The two used to disagree, which is what made it read as a bug rather
      // than as a closed event.
      final c = competition(
        status: CompetitionStatus.registrationOpen,
        closesAt: now.subtract(const Duration(hours: 1)),
      );

      expect(c.displayStatus(now), CompetitionStatus.registrationClosed);
      expect(c.registrationIsOpen, isFalse);
    });

    test('an open event shows open AND accepts registration', () {
      final c = competition(
        status: CompetitionStatus.registrationOpen,
        closesAt: DateTime.now().add(const Duration(days: 30)),
      );

      expect(
        c.displayStatus(DateTime.now()),
        CompetitionStatus.registrationOpen,
      );
      expect(c.registrationIsOpen, isTrue);
    });
  });
}
