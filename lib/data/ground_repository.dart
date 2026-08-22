import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';

import '../core/models/ground.dart';
import '../domain/geo/geohash.dart';
import 'media_uploader.dart';
import 'org_repository.dart' show guard, guardStream;

/// One search hit with the distance that earned it a place in the list —
/// what a "near me" result needs that a plain [Ground] doesn't.
class GroundNearby {
  const GroundNearby({required this.ground, required this.distanceKm});

  final Ground ground;
  final double distanceKm;

  String get distanceLabel => distanceKm < 1
      ? '${(distanceKm * 1000).round()} m away'
      : '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km away';
}

/// Listing grounds, finding them, and holding an hour on one.
class GroundRepository {
  const GroundRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the photo upload against a fake bucket.
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

  // --- Photo ------------------------------------------------------------

  /// Gives a ground its picture.
  ///
  /// `Ground.photoUrl` has existed on the model since grounds were added and
  /// was read by nothing and written by nothing. It matters more here than
  /// anywhere else in the app: somebody choosing between two grounds an hour
  /// apart is choosing on the strength of a photo, and a list of names tells
  /// them nothing about which one has a covered pitch.
  Future<String> uploadGroundPhoto({
    required String groundId,
    required String uid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'grounds/$groundId/photo',
          uid: uid,
          bytes: bytes,
          contentType: contentType,
          maxMegabytes: 6,
        );
        await Refs.ground(groundId).update({'photoUrl': url});
        return url;
      });

  /// Goes back to no photo.
  Future<void> removeGroundPhoto(String groundId) =>
      guard(() => Refs.ground(groundId).update({'photoUrl': null}));

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
  /// Finds grounds by any words somebody might type — a ground's name, an
  /// area, a city, a sport — narrowed by sport and by the hour they want.
  ///
  /// ## Why this is not "search by city" any more
  ///
  /// It was, and that made the only findable ground one whose city you had
  /// already typed correctly and in full. Nobody looks for a pitch that way:
  /// they know a name, or an area, or only the sport. "Gachibowli" returned
  /// nothing, because Gachibowli is not a city.
  ///
  /// ## How the words are matched
  ///
  /// Firestore has no full-text index, so the words live on the document —
  /// see [Ground.searchTokens]. One `array-contains` on the LONGEST word
  /// typed does the narrowing, and every other word is checked in Dart
  /// against whatever that returned. Longest as a proxy for rarest: "turf"
  /// is on half the listings in a city and "gachibowli" on a handful, and
  /// picking the wrong one of those two costs a read of every turf in
  /// Telangana. It is a heuristic, and it is wrong occasionally and cheaply.
  ///
  /// ## Why the old city query still runs
  ///
  /// `searchTokens` is written on save, so a ground listed before this
  /// existed does not carry one and cannot be found by the token query at
  /// all. The `cityKey` equality it used to rely on runs alongside and its
  /// results are merged in, which keeps every existing listing findable by
  /// its city while the tokens fill in as owners edit. New listings are
  /// findable by everything from the moment they are saved.
  ///
  /// A [Future] rather than a [Stream]: this is a merge of two queries, and
  /// searching is something a person does once by pressing a button, not
  /// something they sit watching. The availability grid behind a chosen
  /// ground is the part that has to be live, and that still is.
  Future<List<Ground>> searchGrounds({
    String keywords = '',
    String? sportId,

    /// Only grounds whose gates are open then. A ground that shuts at 18:00
    /// is not an answer to "somewhere to play at 19:00", and offering it
    /// means the person picks it and finds no slots.
    int? openAtHour,
    int limit = 100,
  }) =>
      guard(() async {
        final words = Ground.tokenize([keywords]);

        final results = <String, Ground>{};

        if (words.isEmpty) {
          // No words, but a sport — "show me the cricket grounds", which is
          // where the flow now lands after asking which sport. Without this
          // the search would open on an empty list and make the sport
          // question look pointless.
          if (sportId != null) {
            final snap = await Refs.grounds
                .where('isActive', isEqualTo: true)
                .where('sportIds', arrayContains: sportId)
                .limit(limit)
                .get();
            for (final doc in snap.docs) {
              results[doc.id] = Ground.fromDoc(doc);
            }
          }
        } else {
          final anchor =
              words.reduce((a, b) => b.length > a.length ? b : a);

          final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
            Refs.grounds
                .where('isActive', isEqualTo: true)
                .where('searchTokens', arrayContains: anchor)
                .limit(limit)
                .get(),
            // The legacy path, for listings written before searchTokens.
            Refs.grounds
                .where('isActive', isEqualTo: true)
                .where('cityKey', isEqualTo: keywords.trim().toLowerCase())
                .limit(limit)
                .get(),
          ];

          for (final snap in await Future.wait(futures)) {
            for (final doc in snap.docs) {
              results[doc.id] = Ground.fromDoc(doc);
            }
          }
        }

        // Every word has to match, not just the anchor. `searchTokens` is
        // recomputed here rather than read back from the document so a
        // legacy listing — which has none stored — is still filtered on the
        // same terms as a fresh one.
        final matching = <Ground>[];
        for (final g in results.values) {
          final tokens = g.searchTokens.toSet();
          // Whole words, the same test the `array-contains` anchor applies.
          // A prefix match here would find grounds the anchor query could
          // never have returned, so which half-typed words worked would
          // depend on which one happened to be longest.
          if (!words.every(tokens.contains)) continue;
          if (sportId != null && !g.servesSport(sportId)) continue;
          if (openAtHour != null && !g.isWithinHours(openAtHour, openAtHour + 1)) {
            continue;
          }
          matching.add(g);
        }

        // Verified first, then the better-used grounds: a club picking a
        // ground sight-unseen is relying on somebody else having been there
        // before them.
        matching.sort((a, b) {
          if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
          return b.bookingCount.compareTo(a.bookingCount);
        });
        return matching;
      });

  /// Grounds within [radiusKm] of a point, nearest first.
  ///
  /// A one-shot fetch, not a stream — "near me" is something a person asks
  /// for once by tapping a button, standing at a fixed spot, unlike the city
  /// search someone might sit refreshing while a club fills up. See
  /// [Geohash] for why nine range queries, not one.
  ///
  /// The nine queries run concurrently and get merged and deduplicated by
  /// document id before the real-distance filter runs — a ground can appear
  /// in more than one cell's query near a cell boundary, and would otherwise
  /// be double-counted.
  Future<List<GroundNearby>> nearby({
    required double latitude,
    required double longitude,
    double radiusKm = 15,
    String? sportId,
  }) =>
      guard(() async {
        final precision = Geohash.precisionForRadiusKm(radiusKm);
        final cells = Geohash.neighborsOf(latitude, longitude, precision);

        final snapshots = await Future.wait(cells.map((cell) {
          final (start, end) = Geohash.queryBoundsFor(cell);
          return Refs.grounds
              .where('isActive', isEqualTo: true)
              .where('geohash', isGreaterThanOrEqualTo: start)
              .where('geohash', isLessThan: end)
              .get();
        }));

        final byId = <String, Ground>{};
        for (final snap in snapshots) {
          for (final doc in snap.docs) {
            byId[doc.id] = Ground.fromDoc(doc);
          }
        }

        final hits = <GroundNearby>[];
        for (final g in byId.values) {
          if (g.latitude == null || g.longitude == null) continue;
          if (sportId != null && !g.servesSport(sportId)) continue;
          final d = Geohash.distanceKm(
            latitude,
            longitude,
            g.latitude!,
            g.longitude!,
          );
          if (d <= radiusKm) hits.add(GroundNearby(ground: g, distanceKm: d));
        }

        hits.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        return hits;
      });

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
  /// ## Why this is a transaction, and why a query cannot be the guard
  ///
  /// Two clubs looking for a pitch on Sunday evening will check availability
  /// at the same time, both be told 18:00 is free, and both book it. That is
  /// not a rare race — it is the *expected* traffic pattern for a popular
  /// ground, and its consequence is two teams arriving at one pitch.
  ///
  /// A transaction only closes that window for documents it reads BY
  /// REFERENCE — `Transaction.get(docRef)`. A `Query.get()` run inside a
  /// transaction (what this method used to do: re-read the day's bookings
  /// with a `where` clause) is an ordinary, untracked read; Firestore has
  /// nothing to compare it against at commit time, so two transactions could
  /// both run that query, both see the hour free, and both commit. The
  /// double-booking this method exists to prevent was still possible.
  ///
  /// So the guard is [Refs.groundHourHold]: one document per hour the
  /// booking covers, at a deterministic id, read by reference before being
  /// created. Two bookings racing for hour 18 both `tx.get` the same
  /// `2026-08-10_18` document; whichever commits second finds Firestore
  /// retrying it because the document it read has changed, and the retry's
  /// own read finds the hold already there and fails outright — a real
  /// guarantee, not a hope. See `firestore.rules` on `hourHolds` for the
  /// write-side half of this.
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

        // hour -> the hold document that has to be free for that hour to be
        // bookable. A map rather than a plain list so the write loop below
        // can stamp each hold with the hour it actually covers.
        final holdRefs = {
          for (var h = startHour; h < endHour; h++)
            h: Refs.groundHourHold(ground.id, dayKey, h),
        };

        await Refs.db.runTransaction((tx) async {
          // Every read in a Firestore transaction must happen before any
          // write. This loop is what makes exclusivity real — see the class
          // doc above for why a query could never do this job.
          for (final ref in holdRefs.values) {
            final snap = await tx.get(ref);
            if (snap.exists) {
              throw const ValidationException(
                'That time was just taken by someone else. Pick another '
                'slot.',
              );
            }
          }

          for (final entry in holdRefs.entries) {
            tx.set(entry.value, {
              'bookingId': bookingRef.id,
              'bookedByUid': bookedBy.uid,
              'dayKey': dayKey,
              'hour': entry.key,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          tx.set(bookingRef, booking.toCreate());

          tx.update(Refs.ground(ground.id), {
            'bookingCount': FieldValue.increment(1),
          });
        });

        return booking;
      });

  /// Releases a slot. The booking document stays as a record — see
  /// [GroundBookingStatus.cancelled] — but the hour holds behind it (see
  /// [book]) are deleted in the same batch, which is what actually frees the
  /// hour for somebody else to take. Forgetting this half would leave a
  /// cancelled booking's hours permanently unbookable.
  Future<void> cancelBooking({
    required String groundId,
    required String bookingId,
  }) =>
      guard(() async {
        final snap = await Refs.groundBooking(groundId, bookingId).get();
        if (!snap.exists) {
          throw const ValidationException('That booking no longer exists.');
        }
        final booking = GroundBooking.fromDoc(snap);

        final batch = Refs.db.batch();
        batch.update(Refs.groundBooking(groundId, bookingId), {
          'status': GroundBookingStatus.cancelled.wire,
          'cancelledAt': FieldValue.serverTimestamp(),
        });
        for (var h = booking.startHour; h < booking.endHour; h++) {
          batch.delete(Refs.groundHourHold(groundId, booking.dayKey, h));
        }
        await batch.commit();
      });

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
