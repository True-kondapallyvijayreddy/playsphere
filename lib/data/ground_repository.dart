import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';

import '../core/models/ground.dart';
import 'org_repository.dart' show guard, guardStream;

/// Listing grounds, finding them, and holding an hour on one.
class GroundRepository {
  const GroundRepository();

  // --- Owner side -------------------------------------------------------

  Future<String> registerGround(Ground ground) => guard(() async {
        final ref = Refs.grounds.doc();
        await ref.set(ground.toCreate());
        return ref.id;
      });

  Future<void> updateGround(Ground ground) =>
      guard(() => Refs.ground(ground.id).update(ground.toUpdate()));

  /// The grounds this person owns.
  Stream<List<Ground>> watchMyGrounds(String ownerUid) => guardStream(
        () => Refs.grounds
            .where('ownerUid', isEqualTo: ownerUid)
            .snapshots()
            .map((s) => s.docs.map(Ground.fromDoc).toList(growable: false)),
      );

  Stream<Ground?> watchGround(String groundId) => guardStream(
        () => Refs.ground(groundId).snapshots().map(
              (d) => d.exists ? Ground.fromDoc(d) : null,
            ),
      );

  // --- Player / club side -----------------------------------------------

  /// Grounds in a city, optionally for one sport.
  ///
  /// The sport is filtered on the client rather than in the query, on purpose.
  /// A ground with no `sportIds` means "any sport" (a bare maidan), and
  /// Firestore's `array-contains` cannot express "contains this value OR is
  /// empty" — so a server-side sport filter would silently hide exactly the
  /// general-purpose grounds a village club is most likely to want. The city
  /// clause already bounds the result to something a client can filter.
  Stream<List<Ground>> searchGrounds({
    required String city,
    String? sportId,
  }) =>
      guardStream(
        () => Refs.grounds
            .where('cityKey', isEqualTo: city.trim().toLowerCase())
            .where('isActive', isEqualTo: true)
            .limit(100)
            .snapshots()
            .map((s) {
          final all = s.docs.map(Ground.fromDoc);
          final matching =
              sportId == null ? all : all.where((g) => g.servesSport(sportId));
          final list = matching.toList()
            // Verified first, then the better-used grounds: a club picking a
            // ground sight-unseen is relying on somebody else having been
            // there before them.
            ..sort((a, b) {
              if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
              return b.bookingCount.compareTo(a.bookingCount);
            });
          return list;
        }),
      );

  /// One ground's bookings for one day — what the availability check reads.
  Stream<List<GroundBooking>> watchDayBookings({
    required String groundId,
    required DateTime day,
  }) =>
      guardStream(
        () => Refs.groundBookings(groundId)
            .where('dayKey', isEqualTo: GroundBooking.dayKeyOf(day))
            .snapshots()
            .map(
              (s) => s.docs.map(GroundBooking.fromDoc).toList(growable: false),
            ),
      );

  /// Availability for one ground on one day, ready to be asked about slots.
  Future<DayAvailability> availabilityFor({
    required Ground ground,
    required DateTime day,
  }) =>
      guard(() async {
        final snap = await Refs.groundBookings(ground.id)
            .where('dayKey', isEqualTo: GroundBooking.dayKeyOf(day))
            .get();
        return DayAvailability(ground, snap.docs.map(GroundBooking.fromDoc));
      });

  /// Books `[startHour, endHour)` on [ground], or fails because someone else
  /// has it.
  ///
  /// ## Why this is a transaction and not a write
  ///
  /// Two clubs looking for a pitch on Sunday evening will check availability
  /// at the same time, both be told 18:00 is free, and both book it. That is
  /// not a rare race — it is the *expected* traffic pattern for a popular
  /// ground, and its consequence is two teams arriving at one pitch.
  ///
  /// So the conflict check is re-run inside the transaction, against the same
  /// documents the write will land next to. Firestore aborts and retries the
  /// whole transaction if any document it read changed underneath it, which
  /// makes "nobody else took this hour between my check and my write" an
  /// actual guarantee rather than a hope.
  ///
  /// The read is bounded to one ground on one day, which is what makes it
  /// affordable to do inside a transaction at all — see [GroundBooking] for
  /// why the slot is modelled as a day key plus two integers.
  Future<GroundBooking> book({
    required Ground ground,
    required DateTime day,
    required int startHour,
    required int endHour,
    required AppUser bookedBy,
    String? orgId,
    String? competitionId,
    String? sportId,
    String? notes,
  }) =>
      guard(() async {
        if (!ground.isActive) {
          throw const ValidationException(
            'This ground is not taking bookings at the moment.',
          );
        }
        if (!ground.isWithinHours(startHour, endHour)) {
          throw ValidationException(
            '${ground.name} is open ${_hourLabel(ground.openHour)} to '
            '${_hourLabel(ground.closeHour)}. Pick a time inside that.',
          );
        }

        final dayKey = GroundBooking.dayKeyOf(day);
        final hours = endHour - startHour;
        final amount = ground.priceForPaise(hours);

        final bookingRef = Refs.groundBookings(ground.id).doc();

        final booking = GroundBooking(
          id: bookingRef.id,
          groundId: ground.id,
          groundName: ground.name,
          dayKey: dayKey,
          startHour: startHour,
          endHour: endHour,
          bookedByUid: bookedBy.uid,
          bookedByName: bookedBy.displayName,
          bookedForOrgId: orgId,
          competitionId: competitionId,
          sportId: sportId,
          // What is OWED, not what was collected.
          //
          // There is no payment processor in the loop yet, so a ground with
          // an hourly rate is settled at the ground — which is how almost
          // every turf and maidan in India already works. Writing a
          // `payments/` row here would be recording money that nobody
          // received, and a ledger that logs imaginary income is worse than
          // no ledger. The row gets written by the gateway's webhook once
          // there is a gateway; `paymentId` is where it will be linked.
          amountPaise: amount,
          paymentId: null,
          notes: notes,
          status: GroundBookingStatus.confirmed,
        );

        await Refs.db.runTransaction((tx) async {
          // Re-read inside the transaction. The availability the person was
          // shown is now old news, and this is the read that counts.
          final clashes = await Refs.groundBookings(ground.id)
              .where('dayKey', isEqualTo: dayKey)
              .get();

          for (final doc in clashes.docs) {
            final other = GroundBooking.fromDoc(doc);
            if (!other.holdsSlot) continue;
            if (other.overlaps(startHour, endHour)) {
              throw ValidationException(
                '${_hourLabel(other.startHour)}–${_hourLabel(other.endHour)} '
                'was just taken by someone else. Pick another slot.',
              );
            }
          }

          tx.set(bookingRef, booking.toCreate());

          tx.update(Refs.ground(ground.id), {
            'bookingCount': FieldValue.increment(1),
          });
        });

        return booking;
      });

  /// Releases a slot. The document stays as a record — see
  /// [GroundBookingStatus.cancelled].
  Future<void> cancelBooking({
    required String groundId,
    required String bookingId,
  }) =>
      guard(() => Refs.groundBooking(groundId, bookingId).update({
            'status': GroundBookingStatus.cancelled.wire,
            'cancelledAt': FieldValue.serverTimestamp(),
          }));

  /// Every booking this person made, soonest first.
  Stream<List<GroundBooking>> watchMyBookings(String uid) => guardStream(
        () => Refs.allGroundBookingsQuery
            .where('bookedByUid', isEqualTo: uid)
            .orderBy('startsAt', descending: true)
            .limit(50)
            .snapshots()
            .map(
              (s) => s.docs.map(GroundBooking.fromDoc).toList(growable: false),
            ),
      );

  /// Every booking against one ground, for the owner's calendar.
  Stream<List<GroundBooking>> watchGroundBookings(String groundId) =>
      guardStream(
        () => Refs.groundBookings(groundId)
            .orderBy('startsAt', descending: true)
            .limit(100)
            .snapshots()
            .map(
              (s) => s.docs.map(GroundBooking.fromDoc).toList(growable: false),
            ),
      );
}

/// `18` → `6pm`. Hours are shown to people who are agreeing to meet at one,
/// and 24-hour time is not how that conversation happens in India.
String _hourLabel(int hour) {
  if (hour == 0) return '12am';
  if (hour == 12) return '12pm';
  return hour < 12 ? '${hour}am' : '${hour - 12}pm';
}

/// Exposed for the UI, which labels the same hours on the slot picker.
String groundHourLabel(int hour) => _hourLabel(hour);
