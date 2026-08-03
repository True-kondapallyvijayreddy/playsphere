import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/enums.dart';
import 'package:playsphere/core/models/squad_entry.dart';

/// Step 6, second half: "the first eleven of OUR members who register are
/// playing ABC on Sunday."
///
/// The per-side mirror of the participation model. Its arithmetic is asserted
/// separately because it is enforced in three places that must agree — this
/// model, the transaction in `CompetitionRepository`, and `firestore.rules`.
void main() {
  group('filling one club side', () {
    test('the first eleven are in', () {
      for (var taken = 0; taken < 11; taken++) {
        final call = SquadCall(capacity: 11, confirmed: taken, open: true);
        expect(call.outcomeOfJoiningNow, RegistrationStatus.confirmed);
        expect(call.slotsRemaining, 11 - taken);
        expect(call.acceptsEntries, isTrue);
      }
    });

    test('the twelfth becomes a reserve', () {
      const call = SquadCall(capacity: 11, confirmed: 11, open: true);
      expect(call.isFull, isTrue);
      expect(call.outcomeOfJoiningNow, RegistrationStatus.waitlisted);
      expect(call.acceptsEntries, isTrue);
    });

    test('a full side with no reserves stops accepting', () {
      const call = SquadCall(
        capacity: 11,
        confirmed: 11,
        open: true,
        waitlistEnabled: false,
      );
      expect(call.acceptsEntries, isFalse);
    });

    test('a side the club has not opened accepts nobody', () {
      const call = SquadCall(capacity: 11, open: false);
      expect(call.acceptsEntries, isFalse);
    });

    test('a side with no limit never fills', () {
      const call = SquadCall(open: true, confirmed: 40);
      expect(call.slotsRemaining, isNull);
      expect(call.isFull, isFalse);
      expect(call.outcomeOfJoiningNow, RegistrationStatus.confirmed);
    });

    test('over-admitting past capacity clamps rather than going negative', () {
      const call = SquadCall(capacity: 11, confirmed: 14, open: true);
      expect(call.slotsRemaining, 0);
      expect(call.isFull, isTrue);
    });
  });

  group('the wire format', () {
    test('a fixture with no squad call reads as closed', () {
      // Every challenge already in the database predates this field. A
      // default of "open" would throw those matches open to registration
      // without either club asking for it.
      final call = SquadCall.fromMap(null);
      expect(call.open, isFalse);
      expect(call.capacity, isNull);
      expect(call.confirmed, 0);
    });

    test('a call round-trips', () {
      const call = SquadCall(
        open: true,
        capacity: 11,
        confirmed: 4,
        waitlisted: 2,
        waitlistEnabled: false,
      );
      final back = SquadCall.fromMap(
        Map<String, dynamic>.from(call.toMap()),
      );
      expect(back.open, isTrue);
      expect(back.capacity, 11);
      expect(back.confirmed, 4);
      expect(back.waitlisted, 2);
      expect(back.waitlistEnabled, isFalse);
    });

    test('reserves default to on when the field is absent', () {
      // Absent must not mean "turn people away" — that is the surprising
      // direction for a club that never made a choice.
      expect(SquadCall.fromMap(<String, dynamic>{}).waitlistEnabled, isTrue);
    });
  });

  group('a squad entry', () {
    test('only a confirmed entry is actually playing', () {
      SquadEntry entry(RegistrationStatus s) => SquadEntry(
            uid: 'u1',
            displayName: 'Ravi',
            side: 'a',
            orgId: 'abc',
            status: s,
          );
      expect(entry(RegistrationStatus.confirmed).isPlaying, isTrue);
      expect(entry(RegistrationStatus.waitlisted).isPlaying, isFalse);
      expect(entry(RegistrationStatus.withdrawn).isPlaying, isFalse);
    });

    test('a withdrawn entry stops occupying a place', () {
      expect(RegistrationStatus.withdrawn.occupiesSlot, isFalse);
      expect(RegistrationStatus.confirmed.occupiesSlot, isTrue);
      expect(RegistrationStatus.waitlisted.occupiesSlot, isTrue);
    });
  });
}
