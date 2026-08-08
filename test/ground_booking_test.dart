import 'package:flutter_test/flutter_test.dart';
import 'package:playsphere/core/models/ground.dart';

/// The arithmetic that decides whether two teams turn up to the same pitch.
///
/// `GroundRepository.book` re-runs this check inside a Firestore transaction
/// and `firestore.rules` validates the shape independently, but all three
/// read the same overlap rule — so getting it wrong here gets it wrong
/// everywhere, and the failure is two clubs on one ground on a Sunday.
Ground ground({
  int openHour = 6,
  int closeHour = 22,
  int hourlyRatePaise = 150000,
  List<String> sportIds = const ['cricket'],
  bool isActive = true,
}) =>
    Ground(
      id: 'g1',
      ownerUid: 'owner',
      name: 'Gachibowli Turf',
      city: 'Hyderabad',
      openHour: openHour,
      closeHour: closeHour,
      hourlyRatePaise: hourlyRatePaise,
      sportIds: sportIds,
      isActive: isActive,
    );

GroundBooking booking({
  required int startHour,
  required int endHour,
  GroundBookingStatus status = GroundBookingStatus.confirmed,
  String dayKey = '2026-08-09',
}) =>
    GroundBooking(
      id: 'b${startHour}_$endHour',
      groundId: 'g1',
      groundName: 'Gachibowli Turf',
      dayKey: dayKey,
      startHour: startHour,
      endHour: endHour,
      bookedByUid: 'u1',
      bookedByName: 'Ravi',
      status: status,
    );

void main() {
  group('slot overlap', () {
    test('a booking does not overlap one that starts when it ends', () {
      // 18–20 and 20–22 are back to back, not a clash. The half-open
      // interval is the whole reason: if the end were inclusive, every
      // consecutive pair of bookings on a busy ground would be rejected and
      // the ground could only ever be booked once an evening.
      expect(booking(startHour: 18, endHour: 20).overlaps(20, 22), isFalse);
      expect(booking(startHour: 20, endHour: 22).overlaps(18, 20), isFalse);
    });

    test('a booking overlaps one that starts inside it', () {
      expect(booking(startHour: 18, endHour: 20).overlaps(19, 21), isTrue);
    });

    test('a booking overlaps one that fully contains it', () {
      expect(booking(startHour: 18, endHour: 19).overlaps(17, 22), isTrue);
    });

    test('a booking overlaps an identical slot', () {
      expect(booking(startHour: 18, endHour: 20).overlaps(18, 20), isTrue);
    });

    test('a booking does not overlap an earlier, separate slot', () {
      expect(booking(startHour: 18, endHour: 20).overlaps(6, 8), isFalse);
    });
  });

  group('opening hours', () {
    test('a slot inside the hours is bookable', () {
      expect(ground().isWithinHours(18, 20), isTrue);
    });

    test('a slot ending exactly at closing time is bookable', () {
      // A ground that shuts at 22 can be booked 21–22. Rejecting this would
      // make the last hour of every day permanently unsellable.
      expect(ground(closeHour: 22).isWithinHours(21, 22), isTrue);
    });

    test('a slot starting before opening is not', () {
      expect(ground(openHour: 6).isWithinHours(5, 8), isFalse);
    });

    test('a slot running past closing is not', () {
      expect(ground(closeHour: 22).isWithinHours(21, 23), isFalse);
    });

    test('a zero-length or reversed slot is not', () {
      expect(ground().isWithinHours(18, 18), isFalse);
      expect(ground().isWithinHours(20, 18), isFalse);
    });
  });

  group('day availability', () {
    test('hours covered by a confirmed booking are taken', () {
      final a = DayAvailability(ground(), [booking(startHour: 18, endHour: 20)]);
      expect(a.isHourTaken(18), isTrue);
      expect(a.isHourTaken(19), isTrue);
      // 20 is the exclusive end — free for the next booking.
      expect(a.isHourTaken(20), isFalse);
    });

    test('a cancelled booking does not hold its slot', () {
      // The document stays as a record. If it kept blocking the hour, every
      // cancellation would permanently retire a slot.
      final a = DayAvailability(ground(), [
        booking(
          startHour: 18,
          endHour: 20,
          status: GroundBookingStatus.cancelled,
        ),
      ]);
      expect(a.isHourTaken(18), isFalse);
      expect(a.isFree(18, 20), isTrue);
    });

    test('a slot straddling a booked hour is not free', () {
      final a = DayAvailability(ground(), [booking(startHour: 19, endHour: 20)]);
      expect(a.isFree(18, 21), isFalse);
      expect(a.isFree(20, 22), isTrue);
    });

    test('startsFitting offers only slots that actually fit', () {
      // Open 6–22, with 18–20 taken. A 2-hour slot can start at 6..16 and at
      // 20 — but not 17 (would run into 18) and not 19 (inside the booking).
      final a = DayAvailability(ground(), [booking(startHour: 18, endHour: 20)]);
      final starts = a.startsFitting(2);

      expect(starts, contains(6));
      expect(starts, contains(16));
      expect(starts, contains(20));
      expect(starts, isNot(contains(17)));
      expect(starts, isNot(contains(18)));
      expect(starts, isNot(contains(19)));
      // 21 would end at 23, past closing.
      expect(starts, isNot(contains(21)));
    });

    test('a fully booked day offers nothing', () {
      final a = DayAvailability(
        ground(openHour: 18, closeHour: 20),
        [booking(startHour: 18, endHour: 20)],
      );
      expect(a.startsFitting(1), isEmpty);
    });

    test('a longer slot has fewer starts than a shorter one', () {
      final a = DayAvailability(ground(), [booking(startHour: 18, endHour: 20)]);
      expect(
        a.startsFitting(4).length,
        lessThan(a.startsFitting(1).length),
      );
    });
  });

  group('pricing', () {
    test('cost is the hourly rate times the hours', () {
      expect(ground(hourlyRatePaise: 150000).priceForPaise(2), 300000);
    });

    test('a free ground stays free however long it is booked', () {
      expect(ground(hourlyRatePaise: 0).priceForPaise(8), 0);
      expect(ground(hourlyRatePaise: 0).isFree, isTrue);
    });
  });

  group('sport matching', () {
    test('a ground with no sports listed serves every sport', () {
      // A bare maidan. This is why the sport filter is applied on the client
      // rather than as an `array-contains` query — the query would hide
      // exactly these grounds.
      expect(ground(sportIds: const []).servesSport('kabaddi'), isTrue);
    });

    test('a ground listing sports serves only those', () {
      final g = ground(sportIds: const ['cricket', 'football']);
      expect(g.servesSport('cricket'), isTrue);
      expect(g.servesSport('badminton'), isFalse);
    });
  });

  group('day keys', () {
    test('a day key is zero-padded so it sorts lexicographically', () {
      expect(GroundBooking.dayKeyOf(DateTime(2026, 8, 9)), '2026-08-09');
      expect(GroundBooking.dayKeyOf(DateTime(2026, 12, 25)), '2026-12-25');
    });

    test('startsAt reconstructs the instant from the key and the hour', () {
      final b = booking(startHour: 18, endHour: 20, dayKey: '2026-08-09');
      expect(b.startsAt, DateTime(2026, 8, 9, 18));
    });

    test('hours is the length of the slot', () {
      expect(booking(startHour: 18, endHour: 20).hours, 2);
    });
  });

  group('city key', () {
    test('the search key is case- and space-insensitive', () {
      // Firestore has no case-insensitive matching, so "Hyderabad" typed by
      // an owner and "hyderabad" typed by a searcher have to converge on one
      // stored value or the ground is unfindable.
      const a = Ground(
        id: 'g',
        ownerUid: 'o',
        name: 'A',
        city: '  Hyderabad ',
      );
      expect(a.cityKey, 'hyderabad');
    });
  });
}
