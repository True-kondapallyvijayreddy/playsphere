import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/competition.dart';
import 'package:playsphere/core/models/enums.dart';

/// The participation models of the Sports OS flow, step 5.
///
/// The scenarios below are the ones drawn in the flow: a 13-a-side cricket
/// event that fills first-come, and the same event run as "the captain names
/// 8, the other 5 are open". These assert the arithmetic that decides what
/// tapping Register does — the repository re-decides it inside a transaction
/// and `firestore.rules` re-checks it again, but all three read the same
/// numbers, so getting these wrong gets all three wrong.
Competition event({
  required ParticipationModel model,
  int? maxEntrants,
  int preselectedSlots = 0,
  bool waitlistEnabled = false,
  int confirmedCount = 0,
  int waitlistCount = 0,
  CompetitionStatus status = CompetitionStatus.registrationOpen,
}) =>
    Competition(
      id: 'c1',
      orgId: 'o1',
      name: 'Sunday Cricket',
      sportId: 'cricket',
      sportName: 'Cricket',
      archetype: CompetitionArchetype.versus,
      entrantType: EntrantType.individual,
      format: CompetitionFormat.knockout,
      status: status,
      category: const CompetitionCategory(label: 'Open'),
      scoringPluginKey: 'cricket',
      maxEntrants: maxEntrants,
      participationModel: model,
      preselectedSlots: preselectedSlots,
      waitlistEnabled: waitlistEnabled,
      confirmedCount: confirmedCount,
      waitlistCount: waitlistCount,
    );

void main() {
  group('open registration — first come, first served', () {
    test('the first thirteen are confirmed on the spot', () {
      for (var taken = 0; taken < 13; taken++) {
        final e = event(
          model: ParticipationModel.open,
          maxEntrants: 13,
          confirmedCount: taken,
        );
        expect(
          e.outcomeOfRegisteringNow,
          RegistrationStatus.confirmed,
          reason: 'registrant ${taken + 1} of 13 should be in the team',
        );
        expect(e.slotsRemaining, 13 - taken);
      }
    });

    test('the fourteenth is refused when there is no waitlist', () {
      final full = event(
        model: ParticipationModel.open,
        maxEntrants: 13,
        confirmedCount: 13,
      );
      expect(full.openSlotsFull, isTrue);
      expect(full.slotsRemaining, 0);
      expect(full.registrationIsOpen, isFalse);
    });

    test('the fourteenth is queued when the organizer allowed a waitlist', () {
      final full = event(
        model: ParticipationModel.open,
        maxEntrants: 13,
        confirmedCount: 13,
        waitlistEnabled: true,
      );
      expect(full.registrationIsOpen, isTrue);
      expect(full.outcomeOfRegisteringNow, RegistrationStatus.waitlisted);
    });

    test('an uncapped event never fills', () {
      final e = event(model: ParticipationModel.open, confirmedCount: 400);
      expect(e.openSlots, isNull);
      expect(e.slotsRemaining, isNull);
      expect(e.openSlotsFull, isFalse);
      expect(e.outcomeOfRegisteringNow, RegistrationStatus.confirmed);
    });

    test('registration is shut once the event is past registration_open', () {
      for (final status in [
        CompetitionStatus.draft,
        CompetitionStatus.registrationClosed,
        CompetitionStatus.scheduled,
        CompetitionStatus.inProgress,
        CompetitionStatus.completed,
        CompetitionStatus.cancelled,
      ]) {
        expect(
          event(model: ParticipationModel.open, status: status)
              .registrationIsOpen,
          isFalse,
          reason: 'a ${status.wire} event must not accept entries',
        );
      }
    });
  });

  group('hybrid selection — organizer picks 8, five stay open', () {
    Competition hybrid({int confirmedCount = 0, bool waitlist = false}) => event(
          model: ParticipationModel.hybrid,
          maxEntrants: 13,
          preselectedSlots: 8,
          confirmedCount: confirmedCount,
          waitlistEnabled: waitlist,
        );

    test('only the five unreserved slots are open to registration', () {
      expect(hybrid().openSlots, 5);
      expect(hybrid().slotsRemaining, 5);
    });

    test('the fifth open registrant still gets in', () {
      expect(
        hybrid(confirmedCount: 4).outcomeOfRegisteringNow,
        RegistrationStatus.confirmed,
      );
      expect(hybrid(confirmedCount: 4).slotsRemaining, 1);
    });

    test('the sixth does not eat into the reserved eight', () {
      final e = hybrid(confirmedCount: 5);
      expect(e.slotsRemaining, 0);
      expect(e.openSlotsFull, isTrue);
      expect(e.registrationIsOpen, isFalse);
    });

    test('the sixth is queued when a waitlist is enabled', () {
      final e = hybrid(confirmedCount: 5, waitlist: true);
      expect(e.outcomeOfRegisteringNow, RegistrationStatus.waitlisted);
    });

    test('reserving every slot leaves nothing open', () {
      final e = event(
        model: ParticipationModel.hybrid,
        maxEntrants: 13,
        preselectedSlots: 13,
      );
      expect(e.openSlots, 0);
      expect(e.registrationIsOpen, isFalse);
    });

    test('over-reserving is clamped rather than going negative', () {
      final e = event(
        model: ParticipationModel.hybrid,
        maxEntrants: 13,
        preselectedSlots: 20,
      );
      expect(e.openSlots, 0);
      expect(e.slotsRemaining, 0);
    });
  });

  group('approval — every entry is an application', () {
    test('registering produces a pending application, never a place', () {
      final e = event(model: ParticipationModel.approval, maxEntrants: 13);
      expect(e.outcomeOfRegisteringNow, RegistrationStatus.pending);
    });

    test('an approval event ignores the reserved-slot arithmetic', () {
      // preselectedSlots only means anything for a hybrid event; an approval
      // event's whole field is at the organizer's discretion.
      final e = event(
        model: ParticipationModel.approval,
        maxEntrants: 13,
        preselectedSlots: 8,
      );
      expect(e.openSlots, 13);
    });
  });

  group('wire compatibility', () {
    test('an event saved before participation models existed is approval', () {
      // The only behaviour the app had was approval-gated. Defaulting an
      // absent field to anything else would retroactively admit an untouched
      // application queue into a live event.
      expect(ParticipationModel.fromWire(null), ParticipationModel.approval);
      expect(ParticipationModel.fromWire('nonsense'),
          ParticipationModel.approval);
    });

    test('every model round-trips through its wire name', () {
      for (final m in ParticipationModel.values) {
        expect(ParticipationModel.fromWire(m.wire), m);
      }
    });

    test('only approval withholds the decision from the registrant', () {
      expect(ParticipationModel.open.autoConfirms, isTrue);
      expect(ParticipationModel.hybrid.autoConfirms, isTrue);
      expect(ParticipationModel.approval.autoConfirms, isFalse);
    });
  });

  group('registration counters survive a round trip', () {
    test('a created competition seeds both counters at zero', () {
      final data = event(model: ParticipationModel.open, maxEntrants: 13)
          .toCreate();
      expect(data['confirmedCount'], 0);
      expect(data['waitlistCount'], 0);
      expect(data['participationModel'], 'open');
      expect(data['preselectedSlots'], 0);
    });

    test('an update cannot carry the model, the reserved block or the counts',
        () {
      final data = event(
        model: ParticipationModel.hybrid,
        maxEntrants: 13,
        preselectedSlots: 8,
        confirmedCount: 9,
      ).toUpdate();

      // Changing these under people who have already registered would move
      // them between the team and the queue; the counters belong to the
      // registration transaction alone.
      expect(data.containsKey('participationModel'), isFalse);
      expect(data.containsKey('preselectedSlots'), isFalse);
      expect(data.containsKey('confirmedCount'), isFalse);
      expect(data.containsKey('waitlistCount'), isFalse);
    });
  });
}
