import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/chunked_batch.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/competition.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/models/match_player.dart';
import '../core/models/scoring_request.dart';
import '../core/models/squad_entry.dart';
import '../core/sync/uuid_v7.dart';
import '../domain/draw/fixture_generator.dart';
import '../domain/draw/match_scheduler.dart';
import '../domain/standings/standings_calculator.dart';
import '../domain/scoring/scoring_plugin.dart';
import '../domain/scoring/scoring_registry.dart';
import 'org_repository.dart' show guard, guardStream;

class CompetitionRepository {
  const CompetitionRepository();

  /// Failures from a write that was applied to the local cache and returned
  /// to the caller *before* the server acknowledged it — every method below
  /// marked "not awaited". Mirrors `ScoringService.writeFailures`: with
  /// offline persistence on, awaiting a Firestore write never completes
  /// while offline, so match-day setup screens cannot afford to await these
  /// the way the rest of this repository still awaits reads and simple
  /// admin writes. A screen that wants to tell an organizer "that didn't
  /// save" listens here instead of relying on a thrown exception.
  ///
  /// Static, not an instance field, so the class can stay `const` — every
  /// call site constructs a fresh `CompetitionRepository()` and they must
  /// all observe the same failures.
  static final StreamController<AppException> _writeFailures =
      StreamController<AppException>.broadcast();

  static Stream<AppException> get writeFailures => _writeFailures.stream;

  /// Same translation `ScoringService._translateWriteFailure` applies —
  /// duplicated rather than shared because the two repositories have no
  /// common base and the mapping is a handful of lines, not a reason to
  /// invent one.
  static AppException _translateWriteFailure(Object error) {
    if (error is! FirebaseException) {
      return const ValidationException('That could not be saved.');
    }
    return switch (error.code) {
      'permission-denied' => const PermissionDeniedException(),
      'already-exists' => const ConflictException(),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      _ => ValidationException(error.message ?? 'That could not be saved.'),
    };
  }

  // --- Reads ------------------------------------------------------------

  Stream<List<Competition>> watchCompetitions(
    String orgId, {
    CompetitionStatus? status,
  }) {
    Query<Map<String, dynamic>> q = Refs.competitions(orgId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    return q.snapshots().map(
          (snap) => snap.docs.map(Competition.fromDoc).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0))),
        );
  }

  Stream<Competition?> watchCompetition(String orgId, String compId) =>
      Refs.competition(orgId, compId).snapshots().map(
            (doc) => doc.exists ? Competition.fromDoc(doc) : null,
          );

  Stream<List<Registration>> watchRegistrations(
    String orgId,
    String compId, {
    RegistrationStatus? status,
  }) {
    Query<Map<String, dynamic>> q = Refs.registrations(orgId, compId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    return q.snapshots().map(
          (snap) => snap.docs.map(Registration.fromDoc).toList(),
        );
  }

  Stream<List<Entrant>> watchEntrants(String orgId, String compId) =>
      Refs.entrants(orgId, compId).snapshots().map(
            (snap) => snap.docs.map(Entrant.fromDoc).toList(),
          );

  Stream<List<Fixture>> watchFixtures(String orgId, String compId) =>
      Refs.fixtures(orgId, compId).snapshots().map(
            (snap) => snap.docs.map(Fixture.fromDoc).toList()
              ..sort((a, b) {
                final r = a.round.compareTo(b.round);
                return r != 0 ? r : a.matchIndex.compareTo(b.matchIndex);
              }),
          );

  /// Live matches across an entire organization — powers the spectator
  /// "what's on right now" screen that remote viewers land on.
  Stream<List<Fixture>> watchLiveFixtures(String orgId) {
    return Refs.allFixturesQuery
        .where('orgId', isEqualTo: orgId)
        .where('status', isEqualTo: FixtureStatus.live.wire)
        .snapshots()
        .map((snap) => snap.docs.map(Fixture.fromDoc).toList());
  }

  /// Fixtures a specific person is assigned to score.
  Stream<List<Fixture>> watchMyScoringAssignments(String uid) {
    return Refs.allFixturesQuery
        .where('scorerUids', arrayContains: uid)
        .where('status', whereIn: [
          FixtureStatus.scheduled.wire,
          FixtureStatus.live.wire,
        ])
        .snapshots()
        .map((snap) => snap.docs.map(Fixture.fromDoc).toList());
  }

  // --- Competition lifecycle -------------------------------------------

  /// Creates a competition, offline included.
  ///
  /// Genuinely fully possible offline: `.doc()` generates the id
  /// client-side with no network round trip, and a fresh `.set()` needs no
  /// prior read. The write is deliberately NOT awaited — see
  /// `ScoringService.submit`'s comment for why: with offline persistence
  /// enabled, an awaited Firestore write does not complete until the server
  /// acknowledges it, and offline that is never, which would hang
  /// "Saving..." for the rest of the time the organizer has no signal. The
  /// local cache write lands at once, so `watchCompetition`/
  /// `watchCompetitions` show the new competition immediately; a failure
  /// once connectivity returns is reported on [writeFailures] instead of by
  /// throwing here.
  Future<String> createCompetition(Competition competition) => guard(() async {
        final ref = Refs.competitions(competition.orgId).doc();
        unawaited(
          ref.set(competition.toCreate()).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
        return ref.id;
      });

  Future<void> updateCompetition(Competition competition) => guard(
        () => Refs.competition(competition.orgId, competition.id)
            .update(competition.toUpdate()),
      );

  Future<void> setStatus({
    required String orgId,
    required String compId,
    required CompetitionStatus status,
  }) =>
      guard(() => Refs.competition(orgId, compId).update({
            'status': status.wire,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  // --- Registration -----------------------------------------------------

  /// Registers [user], refusing when they do not meet the category rules.
  ///
  /// The eligibility check runs before the write and returns the specific
  /// reason. Silently accepting an ineligible entry and discovering it at
  /// medal time is how school meets end in arguments.
  /// Registers [user] and returns what actually happened to them.
  ///
  /// ## Why this is a transaction and not a `set`
  ///
  /// "The first thirteen people who register are the team" is a promise about
  /// a count, and a count is exactly what a client cannot be trusted with.
  /// Two people tapping Register at the same moment on the thirteenth slot
  /// both read "12 confirmed" and both write themselves in, and the organizer
  /// arrives at the ground with fourteen players and no way to say which one
  /// was late.
  ///
  /// So the decision — confirmed, waitlisted, or an application — is made
  /// inside a Firestore transaction that reads the competition's counters and
  /// writes the registration and the incremented counter together. Firestore
  /// aborts and retries the transaction if the competition document changed
  /// underneath it, which is what turns first-come into a real ordering
  /// rather than a race. `firestore.rules` enforces the same arithmetic
  /// independently, so a client bypassing this method entirely still cannot
  /// confirm itself into a full or approval-gated event.
  ///
  /// ## What this costs
  ///
  /// Transactions do not work offline — they need a round trip to see a
  /// consistent read. Registering therefore requires signal, unlike scoring,
  /// which must not. That trade is deliberate and the right way round:
  /// registration happens on a phone at home in the days before the match,
  /// scoring happens on a ground with no bars. A caller offline gets a
  /// [NetworkException] telling them to try when they have signal, which is
  /// honest, rather than a local write that silently invents a slot that was
  /// taken hours ago.
  Future<RegistrationStatus> register({
    required Competition competition,
    required AppUser user,
  }) =>
      guard(() async {
        if (!competition.registrationIsOpen) {
          throw const ValidationException(
            'Entries are closed for this competition.',
          );
        }

        final eligibility = competition.category.check(
          user,
          competitionStart: competition.startDate,
        );
        if (!eligibility.isEligible) {
          throw ValidationException(
            'Not eligible for ${competition.category.label}. '
            '${eligibility.reason}',
          );
        }

        final compRef = Refs.competition(competition.orgId, competition.id);
        final regRef =
            Refs.registration(competition.orgId, competition.id, user.uid);

        return Refs.db.runTransaction<RegistrationStatus>(
          (tx) async {
            // Re-read rather than trusting the [competition] argument: it came
            // from a snapshot listener and may be seconds stale, which on a
            // last-slot race is the whole question.
            final compSnap = await tx.get(compRef);
            if (!compSnap.exists) {
              throw const ValidationException('That event no longer exists.');
            }
            final fresh = Competition.fromDoc(compSnap);

            if (!fresh.registrationIsOpen) {
              throw const ValidationException(
                'Entries closed while you were registering.',
              );
            }

            // Re-registering after withdrawing is allowed and lands at the
            // back of whatever queue now exists — but a live registration
            // must not be able to double-count itself into two slots.
            final existing = await tx.get(regRef);
            if (existing.exists) {
              final current = Registration.fromDoc(existing);
              if (current.status.occupiesSlot) {
                throw const ValidationException(
                  'You have already registered for this event.',
                );
              }
            }

            final outcome = fresh.outcomeOfRegisteringNow;

            if (outcome == RegistrationStatus.waitlisted &&
                !fresh.waitlistEnabled) {
              throw const ValidationException('This event is full.');
            }

            final position = outcome == RegistrationStatus.waitlisted
                ? fresh.waitlistCount + 1
                : null;

            tx.set(
              regRef,
              Registration(
                uid: user.uid,
                displayName: user.displayName,
                photoUrl: user.photoUrl,
                status: outcome,
              ).toCreate(status: outcome, waitlistPosition: position),
            );

            // Only the counter that the outcome belongs to moves, and only by
            // one. An approval-model registration moves neither: it does not
            // hold a slot until an organizer confirms it, and counting it
            // would let a queue of applications close a field nobody was
            // admitted to.
            if (outcome == RegistrationStatus.confirmed) {
              tx.update(compRef, {
                'confirmedCount': FieldValue.increment(1),
              });
            } else if (outcome == RegistrationStatus.waitlisted) {
              tx.update(compRef, {
                'waitlistCount': FieldValue.increment(1),
              });
            }

            return outcome;
          },
        );
      });

  /// Puts members into the field directly — the organizer's picks in a hybrid
  /// event, and the "final changes" an admin makes at the ground.
  ///
  /// These are confirmed on creation and marked [Registration.preselected],
  /// and they consume the reserved slots rather than the open ones: an
  /// organizer filling their 8 must not eat into the 5 that were advertised
  /// as open. That is why this increments nothing — [Competition.openSlots]
  /// already excludes the reserved block, so a preselected entrant is outside
  /// the count that first-come registration competes over.
  Future<void> preselect({
    required Competition competition,
    required List<AppUser> players,
    required String byUid,
  }) =>
      guard(() async {
        if (players.isEmpty) return;

        final ineligible = <String>[];
        for (final p in players) {
          final check = competition.category.check(
            p,
            competitionStart: competition.startDate,
          );
          if (!check.isEligible) {
            ineligible.add('${p.displayName}: ${check.reason}');
          }
        }
        if (ineligible.isNotEmpty) {
          throw ValidationException(
            'Not eligible for ${competition.category.label} — '
            '${ineligible.join('; ')}',
          );
        }

        final batch = Refs.db.batch();
        for (final p in players) {
          final data = Registration(
            uid: p.uid,
            displayName: p.displayName,
            photoUrl: p.photoUrl,
            status: RegistrationStatus.confirmed,
          ).toCreate(
            status: RegistrationStatus.confirmed,
            preselected: true,
          );
          data['decidedBy'] = byUid;
          batch.set(
            Refs.registration(competition.orgId, competition.id, p.uid),
            data,
          );
        }

        // Every id is known client-side, so this is applied to the local cache
        // immediately and not awaited — an organizer naming a squad at the
        // ground gets an instant list. Failures surface on [writeFailures].
        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
      });

  /// An organizer's verdict on a registration.
  ///
  /// Moves the confirmed counter with the decision, because the counter is
  /// what capacity is enforced against: confirming an application without
  /// incrementing it would let an organizer admit twenty people into a
  /// thirteen-slot event and never be told.
  /// An organizer's verdict on a registration.
  ///
  /// Moves the confirmed counter with the decision, because the counter is
  /// what capacity is enforced against: confirming an application without
  /// incrementing it would let an organizer admit twenty people into a
  /// thirteen-slot event and never be told.
  Future<void> decideRegistration({
    required String orgId,
    required String compId,
    required String uid,
    required RegistrationStatus status,
    required String decidedByUid,
    String? note,
  }) =>
      guard(() => _moveRegistration(
            orgId: orgId,
            compId: compId,
            uid: uid,
            after: status,
            extraFields: {
              'decidedBy': decidedByUid,
              'eligibilityNote': note,
              'decidedAt': FieldValue.serverTimestamp(),
            },
          ));

  /// A player pulling out.
  ///
  /// The interesting case is a *confirmed* player pulling out, because that
  /// re-opens a slot — and the flow says the waitlist exists precisely for
  /// this moment. The first reserve is promoted in the same transaction, so
  /// there is never a window where the event is a player short and nobody has
  /// been told they are in.
  Future<void> withdraw({
    required String orgId,
    required String compId,
    required String uid,
  }) =>
      guard(() => _moveRegistration(
            orgId: orgId,
            compId: compId,
            uid: uid,
            after: RegistrationStatus.withdrawn,
          ));

  /// The one path that changes a registration's status.
  ///
  /// Every such change has to move the competition's counters in step with
  /// it, because those counters are what capacity is enforced against — in
  /// the client here, and independently in `firestore.rules`. Three
  /// near-copies of this arithmetic would drift until the counters stopped
  /// meaning anything.
  ///
  /// ## Reads first, then writes
  ///
  /// Firestore transactions require every read to happen before the first
  /// write, so the read phase below is unconditional. That is the API's
  /// shape, not caution.
  ///
  /// ## Why promotion is a second transaction
  ///
  /// When a confirmed player drops out, the first reserve takes their slot.
  /// It is tempting to do both in one transaction, and it does not work:
  /// security rules evaluate a write against the state *before* the
  /// transaction, so at the moment the promotion is checked the event is
  /// still full — the very condition the rule refuses to promote into. The
  /// withdrawal has to commit first for the slot to become provably free.
  ///
  /// The gap between the two is milliseconds, and if the app dies inside it
  /// the result is an event one player short with a reserve still queued —
  /// visible, and fixable by an organizer in one tap. The failure mode of
  /// the alternative is a double-booked slot, which is not.
  Future<void> _moveRegistration({
    required String orgId,
    required String compId,
    required String uid,
    required RegistrationStatus after,
    Map<String, Object?> extraFields = const {},
  }) async {
    final compRef = Refs.competition(orgId, compId);
    final regRef = Refs.registration(orgId, compId, uid);

    final freedASlot = await Refs.db.runTransaction<bool>((tx) async {
      // ---- reads -------------------------------------------------------
      final regSnap = await tx.get(regRef);
      if (!regSnap.exists) {
        throw const ValidationException('That registration is gone.');
      }

      final before = Registration.fromDoc(regSnap).status;
      if (before == after) return false;

      // ---- decide ------------------------------------------------------
      var confirmedDelta = 0;
      var waitlistDelta = 0;
      if (before == RegistrationStatus.confirmed) confirmedDelta -= 1;
      if (after == RegistrationStatus.confirmed) confirmedDelta += 1;
      if (before == RegistrationStatus.waitlisted) waitlistDelta -= 1;
      if (after == RegistrationStatus.waitlisted) waitlistDelta += 1;

      // ---- writes ------------------------------------------------------
      tx.update(regRef, {
        ...extraFields,
        'status': after.wire,
        // Leaving the queue by any route makes the position meaningless, and
        // a stale "3rd reserve" on a confirmed player is how a scorer ends up
        // reading the wrong list at the ground.
        if (after != RegistrationStatus.waitlisted) 'waitlistPosition': null,
      });

      if (confirmedDelta != 0 || waitlistDelta != 0) {
        tx.update(compRef, {
          if (confirmedDelta != 0)
            'confirmedCount': FieldValue.increment(confirmedDelta),
          if (waitlistDelta != 0)
            'waitlistCount': FieldValue.increment(waitlistDelta),
        });
      }

      return confirmedDelta < 0;
    });

    if (freedASlot) {
      await _promoteFirstReserve(orgId, compId, justLeft: uid);
    }
  }

  /// Pulls the first reserve into a slot that has just been freed.
  ///
  /// Deliberately forgiving: a promotion that cannot happen — because the
  /// queue is empty, because the reserve withdrew in the meantime, or
  /// because an organizer refilled the slot first — is not an error in the
  /// withdrawal that triggered it. The player who pulled out has pulled out
  /// either way, and failing their action because someone else's row moved
  /// would be the wrong thing to tell them.
  Future<void> _promoteFirstReserve(
    String orgId,
    String compId, {
    required String justLeft,
  }) async {
    try {
      final next = await _firstWaitlisted(orgId, compId, exclude: justLeft);
      if (next == null) return;

      final compRef = Refs.competition(orgId, compId);
      final nextRef = Refs.registration(orgId, compId, next.uid);

      await Refs.db.runTransaction((tx) async {
        final nextSnap = await tx.get(nextRef);
        final compSnap = await tx.get(compRef);
        if (!nextSnap.exists || !compSnap.exists) return;

        // Re-verified inside the transaction: the query that chose this
        // candidate ran before it, and they may have withdrawn since.
        if (Registration.fromDoc(nextSnap).status !=
            RegistrationStatus.waitlisted) {
          return;
        }

        final comp = Competition.fromDoc(compSnap);
        final open = comp.openSlots;
        // The slot has to genuinely exist. An organizer who over-admitted
        // past capacity should not have the overflow topped back up by the
        // waitlist.
        if (open != null && comp.confirmedCount >= open) return;

        tx.update(nextRef, {
          'status': RegistrationStatus.confirmed.wire,
          'waitlistPosition': null,
          'promotedFromWaitlistAt': FieldValue.serverTimestamp(),
        });
        tx.update(compRef, {
          'confirmedCount': FieldValue.increment(1),
          'waitlistCount': FieldValue.increment(-1),
        });
      });
    } catch (error) {
      _writeFailures.add(_translateWriteFailure(error));
    }
  }


  /// The registration at the front of the waitlist, if there is one.
  ///
  /// Ordered by [Registration.waitlistPosition] rather than creation time so
  /// that the queue an entrant was shown — "you are 2nd reserve" — is the
  /// queue that is actually honoured.
  Future<Registration?> _firstWaitlisted(
    String orgId,
    String compId, {
    String? exclude,
  }) async {
    final snap = await Refs.registrations(orgId, compId)
        .where('status', isEqualTo: RegistrationStatus.waitlisted.wire)
        .orderBy('waitlistPosition')
        .limit(2)
        .get();

    for (final doc in snap.docs) {
      if (doc.id == exclude) continue;
      return Registration.fromDoc(doc);
    }
    return null;
  }


  /// Freezes the confirmed field into entrants and closes registration.
  ///
  /// Registration and entrant are separate on purpose: this is the moment the
  /// starting field is fixed, so a late application cannot appear inside a
  /// bracket that is already being played.
  /// Freezes the confirmed field into entrants and closes registration —
  /// what still requires connectivity, and what does not.
  ///
  /// The read below is the part that cannot be made fully offline-honest.
  /// When offline, Firestore serves this query from whatever this device
  /// has already cached — typically populated by the registrations list
  /// screen's own listener before an organizer ever reaches this button, so
  /// the common case (one organizer, one phone, reviewing then locking the
  /// field at the ground) works. But it is not the same guarantee being
  /// online gives: a registration confirmed moments ago on a *different*
  /// device, never synced to this one, is invisible to this read and will
  /// be silently excluded from the field. There is no way to close that gap
  /// without a connection — a device cannot learn about a write it has
  /// never seen. If completeness across every device matters more than
  /// being able to lock the field right now, this action should wait for
  /// signal.
  ///
  /// The write, once the entrant list is decided, has no such limitation:
  /// every entrant id (`doc(reg.uid)`) is already known client-side, so it
  /// is applied to the local cache and NOT awaited — the count this method
  /// returns is correct the instant the batch is built, regardless of when
  /// the server acknowledges it. A failure is reported on [writeFailures].
  Future<int> lockFieldAndCreateEntrants({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final snap = await Refs.registrations(orgId, compId)
            .where('status', isEqualTo: RegistrationStatus.confirmed.wire)
            .get();

        if (snap.docs.length < 2) {
          throw const ValidationException(
            'At least two confirmed entries are needed before you can close '
            'entries and make a draw.',
          );
        }

        final batch = Refs.db.batch();
        for (final doc in snap.docs) {
          final reg = Registration.fromDoc(doc);
          batch.set(
            Refs.entrants(orgId, compId).doc(reg.uid),
            Entrant(
              id: reg.uid,
              displayName: reg.displayName,
              entrantType: EntrantType.individual,
              uid: reg.uid,
              photoUrl: reg.photoUrl,
            ).toMap(),
          );
        }
        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.registrationClosed.wire,
          'entrantCount': snap.docs.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));
        return snap.docs.length;
      });

  // --- Draw -------------------------------------------------------------

  /// Generates and persists the fixture list.
  ///
  /// Refuses to run once a match has been scored: regenerating a draw
  /// underneath results already entered would orphan them, and there is no
  /// safe automatic reconciliation.
  ///
  /// The `anyScored` guard just below is a genuine safety check — a
  /// regenerate deletes every existing fixture, scored or not — and offline
  /// it is only as complete as what this device has cached, exactly like
  /// the read in [lockFieldAndCreateEntrants] above. On the device that has
  /// been scoring the competition throughout (the realistic case this
  /// offline mode is built for) that is everything relevant. Against a
  /// result entered from a second device that never synced to this one
  /// before going offline, it is not, and there is no local fix for that —
  /// only a connection closes the gap. This method does not attempt to
  /// detect that case and refuse; it trusts the same cache the rest of the
  /// screen is already showing the organizer.
  ///
  /// The write that follows has no such limitation — every fixture id comes
  /// from a client-side `.doc()` — so it is applied to the local cache and
  /// NOT awaited; the count returned is final the moment the batch is
  /// built, and a failure is reported on [writeFailures].
  Future<DrawOutcome> generateDraw({
    required Competition competition,
    required List<Entrant> entrants,
    required List<String> defaultScorerUids,
  }) =>
      guard(() async {
        final orgId = competition.orgId;
        final compId = competition.id;

        final existing = await Refs.fixtures(orgId, compId).get();
        final anyScored = existing.docs
            .map(Fixture.fromDoc)
            .any((f) => f.lastSeq > 0 || f.hasResult);
        if (anyScored) {
          throw const ValidationException(
            'Some matches already have scores. Clear those results before '
            'regenerating the draw.',
          );
        }

        // Every parameter the generator accepts is passed. Until this call
        // carried them, a groups+knockout draw silently took the fallback of
        // roughly four per group with two qualifiers each no matter what the
        // organizer chose, because there was no way to say otherwise and no
        // field to say it in.
        final draw = competition.drawConfig;
        final planned = const FixtureGenerator().generate(
          format: competition.format,
          entrants: entrants,
          shuffleSeed: draw.shuffleSeed,
          doubleRoundRobin: draw.doubleRoundRobin,
          bracketReset: draw.bracketReset,
          groupSize: draw.groupSize,
          numGroups: draw.numGroups,
          qualifiersPerGroup: draw.qualifiersPerGroup,
        );
        if (planned.isEmpty) {
          throw const ValidationException(
            'Not enough entrants to make a draw.',
          );
        }

        final sport = SportCatalog.byId(competition.sportId);

        // ---- Pass 1: decide what is actually being written. ----
        //
        // Byes and dead branches are not matches. Everything else is,
        // INCLUDING placeholders whose entrants are still unknown — a
        // quarter-final exists as soon as the draw does, and dropping it is
        // what previously left groups+knockout with no knockout stage. See
        // `SlotFill` for the full history of that bug.
        final kept = <PlannedFixture>[
          for (final p in planned)
            if (p.isPlayable) p,
        ];
        if (kept.isEmpty) {
          throw const ValidationException(
            'Not enough entrants to make a draw.',
          );
        }

        // ---- Pass 2: allocate ids only for what survives. ----
        //
        // Allocating for every planned fixture and writing only some is what
        // produced dangling `feedsWinnerToFixtureId` values pointing at
        // documents that were never created. When one of those matches
        // finished, the advancement `batch.update()` hit a missing document,
        // Firestore rejected the batch, and the SCORE was lost with it. Ids
        // now exist only for documents that will exist, and a pointer at
        // anything else resolves to null rather than to a lie.
        final refByPlannedIndex = <int, DocumentReference<Map<String, dynamic>>>{
          for (final p in kept) p.matchIndex: Refs.fixtures(orgId, compId).doc(),
        };
        String? idFor(int? plannedIndex) =>
            plannedIndex == null ? null : refByPlannedIndex[plannedIndex]?.id;

        // Identifies this draw, so a partial write is detectable and
        // repairable — see `ChunkedBatch` for why atomicity cannot be
        // promised across chunks.
        final drawId = UuidV7.generate();

        // Turn the draw into a timetable before writing it. Every fixture used
        // to be stamped with `competition.startDate`, so a 38-entrant draw
        // told all 38 entrants to arrive at the same minute — which is not a
        // schedule, and is why tournaments that start at ten finish at eleven.
        final timetable = _planSchedule(kept, competition);

        final batch = ChunkedBatch(Refs.db);

        // Clear any previous unscored draw so regenerating does not leave
        // stale fixtures behind alongside the new ones.
        for (final doc in existing.docs) {
          batch.delete(doc.reference);
        }

        for (final p in kept) {
          final ref = refByPlannedIndex[p.matchIndex]!;
          final fixture = Fixture(
            id: ref.id,
            orgId: orgId,
            compId: compId,
            entrantAId: p.entrantA?.id ?? '',
            entrantBId: p.entrantB?.id ?? '',
            entrantAName: p.entrantA?.displayName ?? 'To be decided',
            entrantBName: p.entrantB?.displayName ?? 'To be decided',
            status: FixtureStatus.scheduled,
            round: p.round,
            matchIndex: p.matchIndex,
            roundLabel: p.roundLabel,
            venue: competition.venue,
            scheduledAt: timetable.startAt[p.matchIndex] ?? competition.startDate,
            courtId: timetable.courtId[p.matchIndex],
            scorerUids: defaultScorerUids,
            scoringPluginKey: competition.scoringPluginKey,
            sportId: competition.sportId,
            rulesetVersion: competition.rulesetVersion,
            // Frozen here so every surface that renders this match reads the
            // rules it was actually played under, without a second read.
            scoringConfig: sport.config,
            scoreState: ScoringRegistry.resolve(competition.scoringPluginKey)
                .initialState(_contextFor(p, sport)),
            feedsWinnerToFixtureId: idFor(p.feedsWinnerToIndex),
            feedsWinnerToSlot: p.feedsWinnerToSlot,
            // The rest of the draw's wiring, which the generator has always
            // produced and this method used to drop on the floor. Without
            // `groupId` no group table can be computed, so no qualifier can
            // ever be resolved and a groups+knockout draw sits at "To be
            // decided" forever; without `feedsLoserTo*` the losers bracket is
            // written and nobody arrives in it.
            feedsLoserToFixtureId: idFor(p.feedsLoserToIndex),
            feedsLoserToSlot: p.feedsLoserToSlot,
            bracket: p.bracket,
            groupId: p.groupId,
            qualifierA: p.qualifierA,
            qualifierB: p.qualifierB,
          );

          batch.set(ref, fixture.toCreate());
        }

        batch.update(Refs.competition(orgId, compId), {
          'status': CompetitionStatus.scheduled.wire,
          'fixtureCount': kept.length,
          'drawId': drawId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Not awaited, for the same reason every match-day write here is not:
        // the local cache already holds all of it, and awaiting would hang
        // until a server answered. A rejection surfaces on [writeFailures].
        unawaited(batch.commitAll().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return DrawOutcome(
          planned: planned.length,
          written: kept.length,
          chunks: batch.chunkCount,
          drawId: drawId,
        );
      });

  /// Counts how much of a draw actually reached the server.
  ///
  /// Exists because [ChunkedBatch] gives up cross-chunk atomicity, and the
  /// honest response to that is a way to detect a partial write rather than a
  /// comment asserting it will not happen. Compares the fixtures carrying
  /// [drawId] against the count recorded on the competition.
  Future<({int expected, int found, bool complete})> verifyDraw({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final comp = await Refs.competition(orgId, compId).get();
        final expected = (comp.data()?['fixtureCount'] as num?)?.toInt() ?? 0;
        final drawId = comp.data()?['drawId'] as String?;
        if (drawId == null) {
          return (expected: expected, found: expected, complete: true);
        }
        final snap = await Refs.fixtures(orgId, compId)
            .where('drawId', isEqualTo: drawId)
            .count()
            .get();
        final found = snap.count ?? 0;
        return (
          expected: expected,
          found: found,
          complete: found >= expected,
        );
      });

  /// Creates a one-off match and the competition that holds it, together.
  ///
  /// The club's own internal game, and one player against another. Both were
  /// impossible to express before: a fixture lives under a competition, and
  /// the only route to a competition ran through registration and a draw. So
  /// a Sunday side-versus-side, or two friends on a badminton court, had to
  /// be staged as a tournament of two — six screens before the first serve,
  /// which on a ground is the same as not being possible.
  ///
  /// One batch, so a competition can never exist without its match. The
  /// fixture is created `live` rather than `scheduled` and the creator is its
  /// scorer, because the entire point of the path is that the next tap after
  /// this one is a score.
  ///
  /// Returns the new fixture's ids so the caller can open the pad on it.
  Future<({String compId, String fixtureId})> createQuickMatch({
    required String orgId,
    required String name,
    required SportSpec sport,
    required CompetitionCategory category,
    required String sideAName,
    required String sideBName,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
    required String createdByUid,
    String? venue,
    DateTime? startsAt,
    Map<String, dynamic>? scoringConfig,
  }) =>
      guard(() async {
        if (lineupA.isEmpty || lineupB.isEmpty) {
          throw const ValidationException(
            'Both sides need at least one player before the match can start.',
          );
        }

        final compRef = Refs.competitions(orgId).doc();
        final fixtureRef = Refs.fixtures(orgId, compRef.id).doc();
        final config = scoringConfig ?? sport.config;

        // Entrant ids are the fixture's own two sides rather than references
        // to registration documents, because a quick match has no
        // registrations to point at. They only have to be stable and distinct
        // within the match — the standings calculator and the award both key
        // on them, and neither cares what they spell.
        const entrantAId = 'side_a';
        const entrantBId = 'side_b';

        final competition = Competition(
          id: compRef.id,
          orgId: orgId,
          name: name,
          sportId: sport.id,
          sportName: sport.name,
          archetype: sport.archetype,
          entrantType: lineupA.length > 1 || lineupB.length > 1
              ? EntrantType.team
              : EntrantType.individual,
          format: CompetitionFormat.singleMatch,
          // Overwritten by `toCreate`, which is the single place a starting
          // status is decided. Passed here only because the field is required.
          status: CompetitionStatus.inProgress,
          category: category,
          scoringPluginKey: sport.pluginKey,
          venue: venue,
          startDate: startsAt ?? DateTime.now(),
          // Nobody registers for a match that already has both team sheets.
          participationModel: ParticipationModel.approval,
          entrantCount: 2,
          fixtureCount: 1,
          createdBy: createdByUid,
        );

        final fixture = Fixture(
          id: fixtureRef.id,
          orgId: orgId,
          compId: compRef.id,
          entrantAId: entrantAId,
          entrantBId: entrantBId,
          entrantAName: sideAName,
          entrantBName: sideBName,
          // Live from the first moment. A quick match that opened
          // `scheduled` would need somebody to remember to start it, and the
          // person who set it up is already standing on the court.
          status: FixtureStatus.live,
          roundLabel: 'Match',
          venue: venue,
          scheduledAt: startsAt ?? DateTime.now(),
          scorerUids: [createdByUid],
          scoringPluginKey: sport.pluginKey,
          sportId: sport.id,
          scoringConfig: config,
          lineupA: lineupA,
          lineupB: lineupB,
          scoreState: ScoringRegistry.resolve(sport.pluginKey).initialState(
            ScoringContext(
              entrantAName: sideAName,
              entrantBName: sideBName,
              config: config,
              lineupA: lineupA,
              lineupB: lineupB,
            ),
          ),
          startedAt: DateTime.now(),
        );

        final batch = Refs.db.batch();
        batch.set(compRef, competition.toCreate());
        batch.set(fixtureRef, fixture.toCreate());

        // Not awaited, for the same reason every other match-day write in
        // this file is not: with offline persistence on, a Firestore commit
        // does not complete until the server acknowledges it, and a club
        // ground has no signal. The local cache takes the write immediately,
        // so the pad opens on a real fixture either way; a rejection once
        // connectivity returns arrives on [writeFailures].
        unawaited(batch.commit().catchError((Object error) {
          _writeFailures.add(_translateWriteFailure(error));
        }));

        return (compId: compRef.id, fixtureId: fixtureRef.id);
      });

  /// Fills the knockout phase of a groups+knockout draw from the group tables.
  ///
  /// This is the step that was missing entirely. The generator has always
  /// produced a fully-shaped knockout bracket alongside the groups, with each
  /// slot tagged by the table position that will fill it ("winner of Group B"),
  /// and nothing has ever read those tags — so the quarter-finals of every
  /// groups+knockout tournament ever drawn in this app read "To be decided"
  /// permanently, and organizers did the promotion on paper.
  ///
  /// ## Only complete groups promote
  ///
  /// A group is resolved only once every one of its matches has a result. Half
  /// a group has a leader, not a winner, and writing that leader into a
  /// quarter-final would stick: nothing downstream would move them back out
  /// when the last group match reversed the table.
  ///
  /// ## Safe to call repeatedly
  ///
  /// Idempotent by construction — a slot that already holds a real entrant is
  /// skipped, so this can run on every result without needing to know whether
  /// it has run before. That matters because the natural trigger is "a group
  /// match finished", which fires many times for the same group.
  Future<QualifierOutcome> resolveQualifiers({
    required String orgId,
    required String compId,
  }) =>
      guard(() async {
        final compDoc = await Refs.competition(orgId, compId).get();
        if (!compDoc.exists) {
          throw const NotFoundException('That competition no longer exists.');
        }
        final competition = Competition.fromDoc(compDoc);

        final fixtureSnap = await Refs.fixtures(orgId, compId).get();
        final fixtures = fixtureSnap.docs.map(Fixture.fromDoc).toList();

        final entrantSnap = await Refs.entrants(orgId, compId).get();
        final entrants = entrantSnap.docs.map(Entrant.fromDoc).toList();

        const calculator = StandingsCalculator();
        final tables = calculator.computeGroups(
          competition: competition,
          entrants: entrants,
          fixtures: fixtures,
        );

        final complete = <String, List<Standing>>{
          for (final entry in tables.entries)
            if (calculator.isGroupComplete(entry.key, fixtures))
              entry.key: entry.value,
        };

        final batch = Refs.db.batch();
        var resolved = 0;
        final waiting = <String>{};

        for (final fixture in fixtures) {
          final updates = <String, Object?>{};

          void fill(String slot, QualifierSource? source, String existingId) {
            if (source == null || existingId.isNotEmpty) return;
            final table = complete[source.groupId];
            if (table == null) {
              waiting.add(source.groupId);
              return;
            }
            // A group with fewer finishers than the draw expects to promote
            // — an entrant withdrew before a ball was played. Leaving the
            // slot unresolved is right: the organizer has to decide whether
            // to give a bye or reshape the bracket, and a silent wrong name
            // in a quarter-final is worse than an empty one.
            if (source.position > table.length) return;
            final standing = table[source.position - 1];
            updates['entrant${slot}Id'] = standing.entrantId;
            updates['entrant${slot}Name'] = standing.displayName;
          }

          fill('A', fixture.qualifierA, fixture.entrantAId);
          fill('B', fixture.qualifierB, fixture.entrantBId);

          if (updates.isEmpty) continue;
          batch.update(Refs.fixture(orgId, compId, fixture.id), updates);
          resolved++;
        }

        if (resolved > 0) {
          // Not awaited, for the reason every match-day write here is not:
          // the local cache has it already and awaiting would hang offline.
          unawaited(batch.commit().catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }));
        }

        return QualifierOutcome(
          slotsResolved: resolved,
          groupsComplete: complete.keys.toList()..sort(),
          groupsPending: waiting.toList()..sort(),
        );
      });

  /// Turns a generated draw into "which court, what time" for every fixture.
  ///
  /// ## Why placeholders get a time too
  ///
  /// [MatchScheduler] deliberately skips a fixture whose entrants are not both
  /// known — you cannot check a rest gap for a player you cannot name, and a
  /// semi-final has no players until the quarter-finals are played. But an
  /// organizer publishing a schedule still has to tell people roughly when to
  /// come back, and every federation solves this the same way: a placeholder
  /// carries a **"not before" time**, derived from when its feeder round is
  /// expected to finish. So this method schedules what it can properly, then
  /// gives every remaining round a provisional start one slot after the
  /// latest match of the round before it.
  ///
  /// Group matches are scheduled ahead of knockout matches regardless of round
  /// number, because a groups+knockout draw numbers both from 1 and the
  /// knockout phase cannot begin until every group has finished.
  ({Map<int, DateTime> startAt, Map<int, String> courtId, List<String> problems})
      _planSchedule(List<PlannedFixture> kept, Competition competition) {
    final cfg = competition.scheduleConfig;
    final start = competition.startDate;

    // Without courts or a start date there is nothing to lay out against, so
    // every fixture keeps the competition's own start time — the old
    // behaviour, which is the honest answer when the organizer has not told
    // us how many courts they have.
    if (!cfg.hasCourts || start == null) {
      return (startAt: {}, courtId: {}, problems: const []);
    }

    final venues = [
      for (final name in cfg.courts) Venue(id: name, name: name, capacity: 1),
    ];

    // Enough slots that the draw fits even if every match needs its own,
    // spilling onto later days at the configured day boundaries. Capped so a
    // misconfiguration (one court, thousand-entrant field) cannot spin here.
    final perDay =
        ((cfg.dayEndHour - cfg.dayStartHour) * 60) ~/ cfg.slotMinutes;
    final slots = <TimeSlot>[];
    if (perDay > 0) {
      final daysNeeded =
          ((kept.length / (venues.length * perDay)).ceil()).clamp(1, 30);
      for (var day = 0; day < daysNeeded; day++) {
        var cursor = DateTime(
          start.year,
          start.month,
          start.day + day,
          cfg.dayStartHour,
        );
        for (var i = 0; i < perDay; i++) {
          final end = cursor.add(Duration(minutes: cfg.matchMinutes));
          slots.add(TimeSlot(start: cursor, end: end));
          cursor = cursor.add(Duration(minutes: cfg.slotMinutes));
        }
      }
    }

    // Group matches first, then by round, then by draw position — the order
    // the scheduler fills slots in, and therefore the order matches are
    // played. A later round must never take an earlier court than the round
    // that feeds it.
    final ordered = [...kept]..sort((a, b) {
        final phase = (a.bracket == Bracket.group ? 0 : 1)
            .compareTo(b.bracket == Bracket.group ? 0 : 1);
        if (phase != 0) return phase;
        final round = a.round.compareTo(b.round);
        if (round != 0) return round;
        return a.matchIndex.compareTo(b.matchIndex);
      });

    final result = const MatchScheduler().schedule(
      fixtures: ordered,
      venues: venues,
      slots: slots,
      minRestBetweenMatches: Duration(minutes: cfg.restGapMinutes),
    );

    final startAt = <int, DateTime>{};
    final courtId = <int, String>{};
    for (final s in result.scheduled) {
      startAt[s.fixture.matchIndex] = s.slot.start;
      courtId[s.fixture.matchIndex] = s.venue.id;
    }

    // "Not before" times for everything still unplaced. Walk the rounds in
    // playing order; each round with no real placement starts one slot after
    // the latest time anything before it is due to finish.
    var watermark = startAt.values.isEmpty
        ? DateTime(start.year, start.month, start.day, cfg.dayStartHour)
        : startAt.values.reduce((a, b) => a.isAfter(b) ? a : b);

    for (final p in ordered) {
      if (startAt.containsKey(p.matchIndex)) {
        final placed = startAt[p.matchIndex]!;
        if (placed.isAfter(watermark)) watermark = placed;
        continue;
      }
      watermark = watermark.add(Duration(minutes: cfg.slotMinutes));
      startAt[p.matchIndex] = watermark;
      // No court: a provisional match has not been given one, and inventing
      // one would have an organizer holding a court empty for a match that
      // might be an hour late.
    }

    return (
      startAt: startAt,
      courtId: courtId,
      problems: [
        for (final u in result.unscheduled) '${u.fixture.roundLabel}: ${u.reason}',
      ],
    );
  }

  ScoringContext _contextFor(PlannedFixture p, SportSpec sport) =>
      ScoringContext(
        entrantAName: p.entrantA?.displayName ?? 'A',
        entrantBName: p.entrantB?.displayName ?? 'B',
        config: sport.config,
      );

  Future<void> assignScorers({
    required String orgId,
    required String compId,
    required String fixtureId,
    required List<String> scorerUids,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            'scorerUids': scorerUids,
          }));

  // --- Asking to score --------------------------------------------------

  /// Raises a hand to score [fixture].
  ///
  /// Awaited, unlike the scoring writes in this file: this one is not part of
  /// a match in progress, the person is standing still looking at a button,
  /// and "your request has been sent" is a claim we should only make once the
  /// server has it. Re-requesting overwrites the caller's own document —
  /// `scoringRequests/{uid}` — so a double tap cannot produce two rows in
  /// somebody's approval queue.
  Future<void> requestToScore({
    required Fixture fixture,
    required String uid,
    required String displayName,
    String? note,
  }) =>
      guard(() => Refs.scoringRequest(
            fixture.orgId,
            fixture.compId,
            fixture.id,
            uid,
          ).set(
            ScoringRequest(
              uid: uid,
              orgId: fixture.orgId,
              compId: fixture.compId,
              fixtureId: fixture.id,
              displayName: displayName,
              matchLabel: '${fixture.entrantAName} v ${fixture.entrantBName}',
              status: ScoringRequestStatus.pending,
              note: note,
            ).toCreate(),
          ));

  /// Grants the request and adds the person to the match's scorers, in one
  /// batch.
  ///
  /// Atomic on purpose. Split into two writes, a failure between them leaves
  /// either an approved request by someone the fixture will still reject, or
  /// a scorer with no record of who let them in — and the second is the one
  /// that matters when a result is disputed months later.
  Future<void> approveScoringRequest({
    required ScoringRequest request,
    required String decidedByUid,
  }) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.update(
          Refs.fixture(request.orgId, request.compId, request.fixtureId),
          {'scorerUids': FieldValue.arrayUnion([request.uid])},
        );
        batch.update(
          Refs.scoringRequest(
            request.orgId,
            request.compId,
            request.fixtureId,
            request.uid,
          ),
          {
            'status': ScoringRequestStatus.approved.wire,
            'decidedBy': decidedByUid,
            'decidedAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
      });

  Future<void> declineScoringRequest({
    required ScoringRequest request,
    required String decidedByUid,
  }) =>
      guard(() => Refs.scoringRequest(
            request.orgId,
            request.compId,
            request.fixtureId,
            request.uid,
          ).update({
            'status': ScoringRequestStatus.declined.wire,
            'decidedBy': decidedByUid,
            'decidedAt': FieldValue.serverTimestamp(),
          }));

  /// This person's own request for one match, so the button can say "asked"
  /// rather than offering to ask again.
  Stream<ScoringRequest?> watchMyScoringRequest({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String uid,
  }) =>
      guardStream(
        () => Refs.scoringRequest(orgId, compId, fixtureId, uid)
            .snapshots()
            .map((d) => d.exists ? ScoringRequest.fromDoc(d) : null),
      );

  /// Everyone waiting on an answer from [orgId].
  Stream<List<ScoringRequest>> watchPendingScoringRequests(String orgId) =>
      guardStream(
        () => Refs.allScoringRequestsQuery
            .where('orgId', isEqualTo: orgId)
            .where('status', isEqualTo: ScoringRequestStatus.pending.wire)
            .snapshots()
            .map((s) => s.docs.map(ScoringRequest.fromDoc).toList()),
      );

  /// Records who is playing, per side.
  ///
  /// Set before the first ball. The scoring engines refuse a delivery that
  /// names nobody, so this is what makes a match scorable at all for any sport
  /// that tracks players — including the very first match of a competition,
  /// created and started without ever having had signal.
  ///
  /// Genuinely fully possible offline: unlike the two methods above, this
  /// needs no prior read and no server-derived value — the line-up is
  /// exactly what the scorer just entered. Deliberately NOT awaited, for the
  /// same reason as everywhere else in this file: an awaited Firestore write
  /// does not complete until the server acknowledges it, and awaiting this
  /// one is what used to hang "Saving..." on a ground with no signal and
  /// make it impossible to ever record who's playing, which in turn made it
  /// impossible to score anything at all offline. The local cache write
  /// lands immediately, so this device's own fixture listener shows the
  /// line-up at once; a failure is reported on [writeFailures].
  // --- Squad calls: a club opening its own side to its own members -------

  /// Everyone who has put their hand up for a side.
  Stream<List<SquadEntry>> watchSquadEntries(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      guardStream(
        () => Refs.squadEntries(orgId, compId, fixtureId)
            .orderBy('createdAt')
            .snapshots()
            .map((s) => s.docs.map(SquadEntry.fromDoc).toList()),
      );

  /// A club opening (or closing) its own side to its own members.
  ///
  /// This is the half of the flow's step 6 that was missing: "XYZ Club selects
  /// players **or opens registration**". Until now the challenged club's admin
  /// had to name every player by hand, which is the same chasing-people-over-
  /// WhatsApp problem that participation models solved at the event level —
  /// just one level down, where a challenge actually lives.
  Future<void> setSquadCall({
    required Fixture fixture,
    required String forOrgId,
    required bool open,
    int? capacity,
    bool waitlistEnabled = true,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }
        if (fixture.squadLockedFor(
          side == 'a' ? fixture.entrantAId : fixture.entrantBId,
        )) {
          throw const ValidationException(
            'That squad is locked. Reopen it before changing the call.',
          );
        }

        final existing = fixture.squadCallFor(side);
        final call = SquadCall(
          open: open,
          capacity: capacity,
          // Counters are carried across rather than reset: closing and
          // reopening a call must not forget who already has a place.
          confirmed: existing.confirmed,
          waitlisted: existing.waitlisted,
          waitlistEnabled: waitlistEnabled,
        );

        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id).update({
            side == 'a' ? 'squadCallA' : 'squadCallB': call.toMap(),
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// A member registering for their own club's side.
  ///
  /// Transactional for the same reason competition registration is: "the first
  /// eleven of our members who register are playing" is a promise about a
  /// count, and two people tapping at once on the last place both read ten.
  /// `firestore.rules` enforces the same arithmetic independently.
  ///
  /// Which side the member joins is derived from the club they belong to, not
  /// passed in — a member of ABC cannot register for XYZ's eleven.
  Future<RegistrationStatus> joinSquad({
    required Fixture fixture,
    required String forOrgId,
    required AppUser user,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'You are not in either club playing this match.',
          );
        }

        final fixRef =
            Refs.fixture(fixture.orgId, fixture.compId, fixture.id);
        final entryRef = Refs.squadEntry(
          fixture.orgId,
          fixture.compId,
          fixture.id,
          user.uid,
        );

        return Refs.db.runTransaction<RegistrationStatus>((tx) async {
          final fixSnap = await tx.get(fixRef);
          if (!fixSnap.exists) {
            throw const ValidationException('That match no longer exists.');
          }
          final fresh = Fixture.fromDoc(fixSnap);
          final call = fresh.squadCallFor(side);

          if (fresh.squadLockedFor(
            side == 'a' ? fresh.entrantAId : fresh.entrantBId,
          )) {
            throw const ValidationException(
              'That squad has been locked in already.',
            );
          }
          if (!call.acceptsEntries) {
            throw const ValidationException(
              'Registration is not open for this side.',
            );
          }

          final existing = await tx.get(entryRef);
          if (existing.exists &&
              SquadEntry.fromDoc(existing).status.occupiesSlot) {
            throw const ValidationException(
              'You have already put your name down.',
            );
          }

          final outcome = call.outcomeOfJoiningNow;
          if (outcome == RegistrationStatus.waitlisted &&
              !call.waitlistEnabled) {
            throw const ValidationException('This side is full.');
          }

          tx.set(
            entryRef,
            SquadEntry(
              uid: user.uid,
              displayName: user.displayName,
              photoUrl: user.photoUrl,
              side: side,
              orgId: forOrgId,
              status: outcome,
              waitlistPosition: outcome == RegistrationStatus.waitlisted
                  ? call.waitlisted + 1
                  : null,
            ).toCreate(),
          );

          final field = side == 'a' ? 'squadCallA' : 'squadCallB';
          tx.update(fixRef, {
            if (outcome == RegistrationStatus.confirmed)
              '$field.confirmed': FieldValue.increment(1)
            else
              '$field.waitlisted': FieldValue.increment(1),
          });

          return outcome;
        });
      });

  /// A member pulling out of a squad they had registered for.
  ///
  /// Frees the place, then promotes the first reserve in a second
  /// transaction — for exactly the reason competition withdrawal does: the
  /// rules evaluate a write against pre-transaction state, so the slot is only
  /// provably free once the withdrawal has committed.
  Future<void> leaveSquad({
    required Fixture fixture,
    required String uid,
  }) =>
      guard(() async {
        final fixRef =
            Refs.fixture(fixture.orgId, fixture.compId, fixture.id);
        final entryRef = Refs.squadEntry(
          fixture.orgId,
          fixture.compId,
          fixture.id,
          uid,
        );

        final freedAPlace = await Refs.db.runTransaction<String?>((tx) async {
          final snap = await tx.get(entryRef);
          if (!snap.exists) return null;
          final entry = SquadEntry.fromDoc(snap);
          if (entry.status == RegistrationStatus.withdrawn) return null;

          final field = entry.side == 'a' ? 'squadCallA' : 'squadCallB';

          tx.update(entryRef, {
            'status': RegistrationStatus.withdrawn.wire,
            'waitlistPosition': null,
          });
          tx.update(fixRef, {
            if (entry.status == RegistrationStatus.confirmed)
              '$field.confirmed': FieldValue.increment(-1)
            else if (entry.status == RegistrationStatus.waitlisted)
              '$field.waitlisted': FieldValue.increment(-1),
          });

          return entry.status == RegistrationStatus.confirmed
              ? entry.side
              : null;
        });

        if (freedAPlace != null) {
          await _promoteFirstReserveIntoSquad(
            fixture: fixture,
            side: freedAPlace,
            justLeft: uid,
          );
        }
      });

  /// Pulls the first reserve into a squad place that has just been freed.
  ///
  /// Forgiving by design: a promotion that cannot happen is not a failure of
  /// the withdrawal that triggered it. The member who pulled out has pulled
  /// out either way.
  Future<void> _promoteFirstReserveIntoSquad({
    required Fixture fixture,
    required String side,
    required String justLeft,
  }) async {
    try {
      final snap = await Refs.squadEntries(
        fixture.orgId,
        fixture.compId,
        fixture.id,
      )
          .where('side', isEqualTo: side)
          .where('status', isEqualTo: RegistrationStatus.waitlisted.wire)
          .orderBy('waitlistPosition')
          .limit(2)
          .get();

      SquadEntry? next;
      for (final doc in snap.docs) {
        if (doc.id == justLeft) continue;
        next = SquadEntry.fromDoc(doc);
        break;
      }
      if (next == null) return;

      final fixRef = Refs.fixture(fixture.orgId, fixture.compId, fixture.id);
      final nextRef = Refs.squadEntry(
        fixture.orgId,
        fixture.compId,
        fixture.id,
        next.uid,
      );

      await Refs.db.runTransaction((tx) async {
        final nextSnap = await tx.get(nextRef);
        final fixSnap = await tx.get(fixRef);
        if (!nextSnap.exists || !fixSnap.exists) return;
        if (SquadEntry.fromDoc(nextSnap).status !=
            RegistrationStatus.waitlisted) {
          return;
        }

        final call = Fixture.fromDoc(fixSnap).squadCallFor(side);
        if (call.isFull) return;

        final field = side == 'a' ? 'squadCallA' : 'squadCallB';
        tx.update(nextRef, {
          'status': RegistrationStatus.confirmed.wire,
          'waitlistPosition': null,
          'promotedFromWaitlistAt': FieldValue.serverTimestamp(),
        });
        tx.update(fixRef, {
          '$field.confirmed': FieldValue.increment(1),
          '$field.waitlisted': FieldValue.increment(-1),
        });
      });
    } catch (error) {
      _writeFailures.add(_translateWriteFailure(error));
    }
  }

  /// Turns the members who registered into the actual team sheet, and locks it.
  ///
  /// The moment a squad call becomes a squad. Everyone confirmed becomes a
  /// [MatchPlayer] on that side, in the order they registered, which is the
  /// order they were promised places in.
  Future<void> lockSquadFromEntries({
    required Fixture fixture,
    required String forOrgId,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }

        final snap = await Refs.squadEntries(
          fixture.orgId,
          fixture.compId,
          fixture.id,
        )
            .where('side', isEqualTo: side)
            .where('status', isEqualTo: RegistrationStatus.confirmed.wire)
            .get();

        final entries = snap.docs.map(SquadEntry.fromDoc).toList()
          ..sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null || bt == null) return 0;
            return at.compareTo(bt);
          });

        if (entries.isEmpty) {
          throw const ValidationException(
            'Nobody has registered for this side yet.',
          );
        }

        await setSideLineup(
          fixture: fixture,
          forOrgId: forOrgId,
          lineup: [
            for (final e in entries)
              MatchPlayer(id: e.uid, name: e.displayName, uid: e.uid),
          ],
          lock: true,
        );
      });

  /// One club naming its own players in an inter-club match.
  ///
  /// ## Why this exists next to [setLineups]
  ///
  /// [setLineups] writes both squads at once, which is right for an internal
  /// competition where one club's organizers run everything. It is wrong for
  /// a challenge match, where two clubs that do not answer to each other each
  /// pick their own side — and until now the visiting club could not name a
  /// single player, because the fixture lives under the *hosting* club and
  /// every write path required authority there. "ABC challenges XYZ, XYZ
  /// picks its team" simply did not work.
  ///
  /// A challenge fixture stores the two clubs' own ids as its entrant ids
  /// (see `CommunityRepository.acceptChallenge`), so which side a club may
  /// touch is answerable from the fixture alone — here, and independently in
  /// `firestore.rules`, which is what stops one club from picking the other's
  /// team.
  ///
  /// [lock] is the flow's "lock its final squad": the club declaring it has
  /// finished picking. A locked side can only be reopened by the club that
  /// locked it.
  ///
  /// Not awaited, for the same reason as [setLineups] — an admin naming a
  /// squad at the ground gets an instant list, and a failure arrives on
  /// [writeFailures].
  Future<void> setSideLineup({
    required Fixture fixture,
    required String forOrgId,
    required List<MatchPlayer> lineup,
    bool? lock,
  }) =>
      guard(() async {
        final side = fixture.sideForOrg(forOrgId);
        if (side == null) {
          throw const ValidationException(
            'This club is not one of the two contesting this match.',
          );
        }

        final isA = side == 'a';
        if (fixture.squadLockedFor(isA ? fixture.entrantAId : fixture.entrantBId) &&
            lock != false) {
          throw const ValidationException(
            'That squad is locked. Reopen it before making changes.',
          );
        }

        // `playerUids` summarises BOTH sides and is what the rules consult
        // when a scorer settles ratings onto a player's profile, so it has to
        // be recomputed from this side's new list plus the other side's
        // existing one — writing only this side's uids would strip the
        // opponent's players out of the match they played in.
        final other = isA ? fixture.lineupB : fixture.lineupA;
        final playerUids = <String>{
          for (final p in [...lineup, ...other])
            if (p.uid != null) p.uid!,
        }.toList();

        final update = <String, Object?>{
          isA ? 'lineupA' : 'lineupB': MatchPlayer.listTo(lineup),
          'playerUids': playerUids,
        };
        if (lock != null) {
          update[isA ? 'squadLockedA' : 'squadLockedB'] = lock;
        }

        unawaited(
          Refs.fixture(fixture.orgId, fixture.compId, fixture.id)
              .update(update)
              .catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  Future<void> setLineups({
    required String orgId,
    required String compId,
    required String fixtureId,
    required List<MatchPlayer> lineupA,
    required List<MatchPlayer> lineupB,
  }) =>
      guard(() async {
        unawaited(
          Refs.fixture(orgId, compId, fixtureId).update({
            'lineupA': MatchPlayer.listTo(lineupA),
            'lineupB': MatchPlayer.listTo(lineupB),
            // Written in the same update as the line-ups it summarises.
            // `firestore.rules` reads it to decide whether a scorer settling
            // a match may write ratings and career stats onto a given
            // player's profile — see the ratings/career_stats rules — and it
            // cannot reach inside the lineup maps to work that out itself.
            'playerUids': <String>{
              for (final p in [...lineupA, ...lineupB])
                if (p.uid != null) p.uid!,
            }.toList(),
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  /// Records the toss, and who chose what.
  ///
  /// Cricket needs it to know which side bats first; every other sport uses it
  /// to decide who starts. It is written onto the fixture and into the frozen
  /// scoring config, because "who batted first" is part of how the match reads
  /// forever after and must not be recomputed later from anything mutable.
  ///
  /// Genuinely fully possible offline, for the same reason as [setLineups]:
  /// no prior read, nothing server-derived. Not awaited, for the same
  /// reason — see that method's comment.
  /// Records the toss and what the winner took.
  ///
  /// [startingSide] is who plays first, worked out from the choice rather
  /// than assumed — see `TossDialog._startingSide`. It is written for every
  /// sport, because "who served first" and "who raided first" are as much a
  /// part of a scorecard as "who batted first".
  ///
  /// [decidesBatting] gates the one key that is cricket's alone. The dialog
  /// used to write `battingFirst` for all thirteen sports, so a badminton
  /// fixture carried a frozen ruleset asserting which side batted.
  Future<void> recordToss({
    required String orgId,
    required String compId,
    required String fixtureId,
    required String wonByEntrantId,
    required String decision,
    required String startingSide,
    required bool decidesBatting,
    required Map<String, dynamic> scoringConfig,
  }) =>
      guard(() async {
        unawaited(
          Refs.fixture(orgId, compId, fixtureId).update({
            'tossWonByEntrantId': wonByEntrantId,
            'tossDecision': decision,
            'scoringConfig': {
              ...scoringConfig,
              'startingSide': startingSide,
              if (decidesBatting) 'battingFirst': startingSide,
            },
          }).catchError((Object error) {
            _writeFailures.add(_translateWriteFailure(error));
          }),
        );
      });

  Future<void> rescheduleFixture({
    required String orgId,
    required String compId,
    required String fixtureId,
    DateTime? scheduledAt,
    String? venue,
  }) =>
      guard(() => Refs.fixture(orgId, compId, fixtureId).update({
            if (scheduledAt != null)
              'scheduledAt': Timestamp.fromDate(scheduledAt),
            if (venue != null) 'venue': venue,
          }));
}

/// What a draw generation actually did.
///
/// Replaces a bare `int`, which could not distinguish "703 matches created"
/// from "703 matches planned, an unknown number written, and the batch may
/// have been rejected on the way". The organizer is shown a number that was
/// true at the moment it was produced; these fields are what make it true.
class DrawOutcome {
  const DrawOutcome({
    required this.planned,
    required this.written,
    required this.chunks,
    required this.drawId,
  });

  /// Fixtures the generator produced, including byes and dead branches.
  final int planned;

  /// Fixtures handed to Firestore — the number of real matches.
  final int written;

  /// How many batches it took. More than one means the write is not atomic
  /// and `verifyDraw` is worth running.
  final int chunks;

  final String drawId;

  bool get isAtomic => chunks <= 1;

  /// How many planned fixtures were byes or dead branches. Worth surfacing:
  /// a large number on a non-knockout format usually means the field size is
  /// awkward rather than that anything went wrong.
  int get skipped => planned - written;
}

/// What one pass of [CompetitionRepository.resolveQualifiers] achieved.
///
/// Reports pending groups as well as resolved slots because "nothing happened"
/// has two very different meanings to an organizer — every qualifier is
/// already in place, or Group C still has two matches to play — and a bare
/// count cannot tell them apart.
class QualifierOutcome {
  const QualifierOutcome({
    required this.slotsResolved,
    required this.groupsComplete,
    required this.groupsPending,
  });

  /// Knockout fixtures that gained at least one entrant on this pass.
  final int slotsResolved;

  final List<String> groupsComplete;

  /// Groups a knockout slot is still waiting on.
  final List<String> groupsPending;

  bool get isFullyResolved => groupsPending.isEmpty;
}
