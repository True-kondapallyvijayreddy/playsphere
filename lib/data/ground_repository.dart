import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';

import '../core/models/ground.dart';
import '../core/models/ground_verification.dart';
import '../domain/geo/geohash.dart';
import '../domain/geo/site_presence.dart';
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
          // Suspending a listing also switches `isActive` off, so the query
          // above already drops most of these. Checked again here because the
          // two fields are written by different code paths — the trigger sets
          // both, an admin acting by hand might set one — and a suspended
          // ground appearing in search is the one bug this whole feature
          // exists to prevent.
          if (!g.verificationStatus.isDiscoverable) continue;
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
        // Verified first, then grounds people have actually turned up at,
        // then the better-used ones. Arrivals rank above raw booking count on
        // purpose: bookings are a number the listing's own owner can inflate
        // from a second account, arrivals are not.
        matching.sort((a, b) {
          if (a.isVerified != b.isVerified) return a.isVerified ? -1 : 1;
          if (a.checkInCount != b.checkInCount) {
            return b.checkInCount.compareTo(a.checkInCount);
          }
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
          if (!g.verificationStatus.isDiscoverable) continue;
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
        return DayAvailability(
          ground,
          snap.docs.map(GroundBooking.fromDoc),
          day: day,
        );
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
        if (!ground.verificationStatus.isBookable) {
          throw const ValidationException(
            'This listing has been taken down by PlaySphere and cannot be '
            'booked.',
          );
        }
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

          // `bookingCount` is deliberately NOT written here any more.
          //
          // It used to be incremented in this transaction, under a rule that
          // let any signed-in caller bump it by one with nothing limiting
          // repetition — so the one number on a public listing that a customer
          // reads as social proof was the one number anybody could run up
          // without booking anything. `onGroundBooked`
          // (functions/grounds.js) recomputes it from the bookings themselves,
          // which also means a cancelled booking takes its contribution back
          // instead of leaving the count permanently high.
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

// ---------------------------------------------------------------------------
// Verification, reports and arrivals
// ---------------------------------------------------------------------------

/// One photograph the owner has just taken, before it has been uploaded.
///
/// The wizard collects these in memory and hands the whole set over at the
/// end, rather than uploading each one as it is taken. That is deliberate: a
/// submission is only meaningful as a set — the presence checks are about how
/// the fixes relate to *each other* — and uploading photo one before photo
/// three has failed its check would leave orphaned evidence in the bucket for
/// listings that were never created.
class CapturedProof {
  const CapturedProof({
    required this.kind,
    required this.bytes,
    required this.contentType,
    required this.fix,
  });

  final GroundProofKind kind;
  final Uint8List bytes;
  final String contentType;

  /// Where the phone was when the shutter fired. Not where it was when the
  /// wizard opened — see `SitePresence` for why that distinction is the whole
  /// point.
  final SiteFix fix;
}

/// Listing a ground with proof, reporting one, and confirming you arrived.
///
/// An extension rather than more methods on [GroundRepository] itself: these
/// are all about whether a listing is *trustworthy*, which is a different
/// concern from finding one and holding an hour on it, and keeping them
/// apart means the booking transaction's file does not grow a second reason
/// to be edited.
extension GroundTrustRepository on GroundRepository {
  // --- Listing with proof -------------------------------------------------

  /// Publishes a ground together with the evidence that somebody stood at it.
  ///
  /// ## Why this is not a transaction
  ///
  /// It cannot be. The photographs have to reach Cloud Storage before their
  /// URLs can be written to Firestore, and Storage is not part of a Firestore
  /// transaction. So the order is chosen for which failure is survivable:
  /// uploads first, then the ground, then the proofs and the claim in one
  /// batch.
  ///
  /// A crash between the uploads and the ground leaves unreferenced objects
  /// in the bucket, which costs pennies and is a lifecycle rule's problem. A
  /// crash between the ground and the proofs leaves a listing in `pending`
  /// with no evidence behind it — which a reviewer sees as exactly that, an
  /// empty submission, and rejects. Both failures are visible and neither
  /// publishes a *verified* listing, which is the only outcome that would
  /// actually matter.
  ///
  /// The presence checks have already run in the wizard by the time this is
  /// called. They run again here anyway: the wizard is a UI, and a UI is a
  /// convenience for the honest, not a control on the dishonest.
  Future<String> listGroundWithProof({
    required Ground ground,
    required List<CapturedProof> proofs,
    required GroundClaimType claimType,
    required String holderName,
    required GroundDocumentKind documentKind,
    required Uint8List documentBytes,
    required String documentContentType,
    required String uid,
    DateTime? now,
  }) =>
      guard(() async {
        final at = now ?? DateTime.now();

        final missing = GroundProofKind.values
            .where((k) => k.isRequired && k != GroundProofKind.ownershipDocument)
            .where((k) => !proofs.any((p) => p.kind == k))
            .toList();
        if (missing.isNotEmpty) {
          throw ValidationException(
            'Still needed: ${missing.map((k) => k.label.toLowerCase()).join(', ')}.',
          );
        }

        final verdict = SitePresence.checkSet(
          proofs.map((p) => p.fix).toList(),
          now: at,
          pinLatitude: ground.latitude,
          pinLongitude: ground.longitude,
        );
        if (!verdict.isOk) {
          throw ValidationException(verdict.problem!.message);
        }

        // The ground document first, because every storage path and every
        // proof document is keyed on its id. Written as `pending` — see
        // `Ground.toCreate`, which will not let any other status through.
        final groundRef = Refs.grounds.doc();
        final pinned = ground.copyWith();
        await groundRef.set({
          ...pinned.toCreate(),
          'verificationStatus': GroundVerificationStatus.pending.wire,
        });

        // Uploads run concurrently. On rural 4G this is the slow part of the
        // whole flow by an order of magnitude, and doing four in series is
        // the difference between an owner finishing and an owner giving up.
        final uploads = await Future.wait([
          for (final proof in proofs)
            _media.putImage(
              folder: 'groundProofs/${groundRef.id}/${proof.kind.wire}',
              uid: uid,
              bytes: proof.bytes,
              contentType: proof.contentType,
              maxMegabytes: 6,
            ),
          _media.putImage(
            folder: 'groundDocs/${groundRef.id}',
            uid: uid,
            bytes: documentBytes,
            contentType: documentContentType,
            maxMegabytes: 6,
          ),
        ]);
        final documentUrl = uploads.last;

        final batch = Refs.db.batch();
        for (var i = 0; i < proofs.length; i++) {
          final proof = proofs[i];
          batch.set(
            Refs.groundVerification(groundRef.id).doc(),
            GroundProof(
              id: '',
              kind: proof.kind,
              imageUrl: uploads[i],
              latitude: proof.fix.latitude,
              longitude: proof.fix.longitude,
              accuracyMetres: proof.fix.accuracyMetres,
              capturedAt: proof.fix.at,
              capturedByUid: uid,
              isMocked: proof.fix.isMocked,
            ).toCreate(),
          );
        }
        batch.set(
          Refs.groundClaim(groundRef.id),
          GroundOwnershipClaim(
            claimType: claimType,
            holderName: holderName,
            documentKind: documentKind,
            documentUrl: documentUrl,
            declaredByUid: uid,
            contactPhone: ground.contactPhone,
          ).toCreate(),
        );

        // The advertising photo, so a listing made this way is not blank in
        // search. The playing-area shot is the one people are choosing on.
        final hero = uploads.isNotEmpty ? uploads.first : null;
        if (hero != null) {
          batch.update(groundRef, {'photoUrl': hero});
        }

        await batch.commit();
        return groundRef.id;
      });

  /// The evidence behind one listing. Readable by its owner and by an admin;
  /// for everyone else this stream closes with a permission error, which is
  /// the intended behaviour and not a bug to be papered over.
  Stream<List<GroundProof>> watchGroundProofs(String groundId) => guardStream(
        () => Refs.groundVerification(groundId)
            .orderBy('capturedAt')
            .snapshots()
            .map((s) => s.docs
                .where((d) => d.id != 'claim')
                .map(GroundProof.fromDoc)
                .toList(growable: false)),
      );

  Future<GroundOwnershipClaim?> groundClaim(String groundId) =>
      guard(() async {
        final snap = await Refs.groundClaim(groundId).get();
        return snap.exists ? GroundOwnershipClaim.fromDoc(snap) : null;
      });

  // --- Reporting ----------------------------------------------------------

  /// Files one person's complaint about one listing.
  ///
  /// Deliberately a plain `set` at a deterministic id rather than a create:
  /// somebody who reported a wrong address and then discovered the owner was
  /// asking for advances should be able to say so, and the id keeps that a
  /// correction rather than a second vote. The auto-suspend trigger recomputes
  /// the score from the whole collection for exactly this reason — it cannot
  /// just add the new report's weight to a running total.
  Future<void> reportGround({
    required Ground ground,
    required AppUser reporter,
    required GroundReportReason reason,
    String? note,
    String? bookingId,
  }) =>
      guard(() async {
        if (ground.ownerUid == reporter.uid) {
          throw const ValidationException(
            'This is your own listing. Edit it instead.',
          );
        }
        final id = GroundReport.idFor(
          reporterUid: reporter.uid,
          groundId: ground.id,
        );
        await Refs.groundReport(id).set(
          GroundReport(
            id: id,
            groundId: ground.id,
            groundName: ground.name,
            groundOwnerUid: ground.ownerUid,
            reporterUid: reporter.uid,
            reporterName: reporter.displayName,
            reason: reason,
            note: note,
            bookingId: bookingId,
          ).toCreate(),
        );
      });

  /// Whether this person has already reported this ground, so the button can
  /// say "Reported" instead of inviting them to do it again.
  Stream<GroundReport?> watchMyReport({
    required String groundId,
    required String uid,
  }) =>
      guardStream(
        () => Refs.groundReport(
          GroundReport.idFor(reporterUid: uid, groundId: groundId),
        ).snapshots().map((d) => d.exists ? GroundReport.fromDoc(d) : null),
      );

  // --- Arrivals -----------------------------------------------------------

  /// Records that the person who booked this slot is standing at the ground.
  ///
  /// The distance is computed here for the message the person sees, and
  /// recomputed by the trigger from the ground's own pin before it is allowed
  /// to move `checkInCount`. A client that lies about `distanceMetres` gets a
  /// check-in document that the server declines to count — which is the
  /// correct division: the client may assert, only the server may conclude.
  ///
  /// An out-of-range arrival is still written. It is the single most useful
  /// record in the system when a booker turns up and finds no ground: it is
  /// timestamped, positioned, and tied to a booking, which is exactly what a
  /// reviewer needs and exactly what a screenshot of a WhatsApp argument is
  /// not.
  Future<GroundCheckIn> checkInToBooking({
    required Ground ground,
    required GroundBooking booking,
    required SiteFix fix,
    required String uid,
  }) =>
      guard(() async {
        if (booking.bookedByUid != uid) {
          throw const ValidationException(
            'Only the person who booked this slot can check in on it.',
          );
        }
        if (ground.latitude == null || ground.longitude == null) {
          throw const ValidationException(
            'This ground has no location saved, so arriving cannot be '
            'confirmed. Report the listing if the details are wrong.',
          );
        }

        final checkIn = GroundCheckIn(
          bookingId: booking.id,
          uid: uid,
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyMetres: fix.accuracyMetres,
          distanceMetres:
              fix.distanceMetresToPoint(ground.latitude!, ground.longitude!),
          capturedAt: fix.at,
          isMocked: fix.isMocked,
        );

        final batch = Refs.db.batch();
        batch.set(
          Refs.groundCheckIn(ground.id, booking.id),
          checkIn.toCreate(),
        );
        // Denormalized onto the booking so "my bookings" can render the badge
        // without reading the subcollection once per row.
        batch.update(Refs.groundBooking(ground.id, booking.id), {
          'checkedInAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();

        return checkIn;
      });
}

/// The reviewer's side: what is waiting, and settling it.
///
/// Separate from [GroundTrustRepository] because every method here is gated
/// on the `admin` custom claim in `firestore.rules`, and a reader of this
/// file should be able to see at a glance which calls a normal account can
/// make and which will simply be denied.
extension GroundReviewRepository on GroundRepository {
  /// Listings that need a human: submitted and unreviewed, or complained
  /// about.
  ///
  /// ## Why two queries merged rather than one
  ///
  /// Firestore cannot express "status is pending OR reportScore is above
  /// zero" — a disjunction across two fields is not a query it has. A single
  /// composite field encoding "needs review" would have to be maintained by
  /// every writer that touches either half, and would be wrong for exactly as
  /// long as any one of them forgot.
  ///
  /// Two narrow reads merged in memory costs nothing at review volumes and
  /// cannot drift. A verified ground that starts collecting reports shows up
  /// through the second query, which is the case a naive `status == pending`
  /// queue would miss entirely — and it is the most urgent case there is.
  Future<List<Ground>> reviewQueue({int limit = 100}) => guard(() async {
        final results = await Future.wait([
          Refs.grounds
              .where('verificationStatus', isEqualTo: 'pending')
              .limit(limit)
              .get(),
          Refs.grounds
              .where('reportScore', isGreaterThan: 0)
              .orderBy('reportScore', descending: true)
              .limit(limit)
              .get(),
        ]);

        final byId = <String, Ground>{};
        for (final snap in results) {
          for (final doc in snap.docs) {
            byId[doc.id] = Ground.fromDoc(doc);
          }
        }

        // Complaints first, then the riskiest submissions, then oldest. The
        // ordering is the whole value of a queue: one person reviewing has to
        // spend their attention where a fraud is already in progress rather
        // than working through arrivals in the order they landed.
        final list = byId.values.toList();
        list.sort((a, b) {
          if (a.reportScore != b.reportScore) {
            return b.reportScore.compareTo(a.reportScore);
          }
          if (a.riskFlags.length != b.riskFlags.length) {
            return b.riskFlags.length.compareTo(a.riskFlags.length);
          }
          final at = a.createdAt, bt = b.createdAt;
          if (at == null || bt == null) return 0;
          return at.compareTo(bt);
        });
        return list;
      });

  /// Every complaint filed against one listing.
  Stream<List<GroundReport>> watchReportsFor(String groundId) => guardStream(
        () => Refs.groundReports
            .where('groundId', isEqualTo: groundId)
            .snapshots()
            .map((s) => s.docs.map(GroundReport.fromDoc).toList(growable: false)),
      );

  /// Settles a listing.
  ///
  /// Writes `isActive` alongside the status for anything that takes a listing
  /// down, because search filters on `isActive` in the Firestore query — so
  /// clearing it is what actually removes the listing from results, including
  /// for clients on an older build that has never heard of
  /// `verificationStatus`. The mirrored `isVerified` boolean is kept in step
  /// for the same reason: exports, BigQuery views and bookmarked console
  /// queries still read it.
  Future<void> setVerificationStatus({
    required String groundId,
    required GroundVerificationStatus status,
    String? note,
  }) =>
      guard(() async {
        await Refs.ground(groundId).update({
          'verificationStatus': status.wire,
          'isVerified': status == GroundVerificationStatus.verified,
          if (!status.isBookable) 'isActive': false,
          // Approving something that was suspended puts it back on the
          // market. Left out of the `if` above rather than folded into it so
          // the asymmetry is deliberate and visible: taking a listing down
          // always deactivates it, putting one back always reactivates it.
          if (status == GroundVerificationStatus.verified) 'isActive': true,
          'reviewNote': note,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
      });
}
