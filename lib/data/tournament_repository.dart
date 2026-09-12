import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/chunked_batch.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/competition.dart';
import '../core/models/draw_slot.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/models/match_official.dart';
import '../core/models/club_standing.dart';
import '../core/models/ranking_entry.dart';
import '../core/models/tournament.dart';
import '../core/models/season_interest.dart';
import '../core/models/tournament_invite.dart';
import '../core/models/tournament_official.dart';
import '../core/models/venue.dart';
import '../core/models/venue_plan.dart';
import '../domain/draw/match_count.dart';
import '../domain/draw/officials_roster.dart';
import '../domain/draw/schedule_guarantees.dart';
import '../domain/draw/schedule_shift.dart';
import '../domain/draw/season_capacity.dart';
import '../domain/draw/tournament_scheduler.dart';
import 'competition_repository.dart';
import 'media_uploader.dart';
import 'org_repository.dart' show guard, guardStream;

/// One season, read once, in the shape every scheduling operation needs.
typedef _SeasonPlan = ({
  Tournament tournament,
  List<Competition> events,
  List<SchedulableMatch> matches,

  /// Keyed `compId#matchIndex`, matching [SchedulableMatch.key].
  Map<String, Fixture> fixturesByKey,
  List<CourtCalendar> calendars,
  Duration minRest,
  Duration transition,
});

/// Venues, tournaments, and the one operation that needs both: laying out
/// every match of every event across one shared pool of courts.
class TournamentRepository {
  const TournamentRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the banner upload against a fake bucket.
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

  // --- Branding ---------------------------------------------------------

  /// Puts artwork across the top of a season, including on its public link.
  ///
  /// This is the highest-value image in the product. The public tournament
  /// page is the one thing a club sends to people who do not have PlaySphere
  /// — the page that replaces the Telegram channel — and until now it opened
  /// with an app bar reading "Tournament".
  ///
  /// Deliberately a one-field write. `Tournament.toUpdate` is what the edit
  /// sheet calls and it does not carry `bannerUrl`, so the two can never
  /// clobber each other.
  Future<String> uploadSeasonBanner({
    required String orgId,
    required String tournamentId,
    required String uid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'tournaments/$tournamentId/banner',
          uid: uid,
          bytes: bytes,
          contentType: contentType,
          maxMegabytes: 6,
        );
        await Refs.tournament(orgId, tournamentId)
            .update({'bannerUrl': url});
        return url;
      });

  /// Goes back to the generated banner.
  Future<void> removeSeasonBanner({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(
        () => Refs.tournament(orgId, tournamentId).update({'bannerUrl': null}),
      );

  /// Puts the season's badge on it — the crest on the banner, in the season
  /// list, and on the public link.
  ///
  /// A separate object and a separate field from the banner, not a second use
  /// of one upload, because the two are different pictures at different
  /// aspect ratios: a badge is squared and drawn `contain` at 56pt, a banner
  /// is a full-bleed 1600px photograph. Shrunk harder on the way in for the
  /// same reason — nothing in the app draws this above 96pt.
  ///
  /// A one-field write, like the banner above, so the edit sheet's
  /// `Tournament.toUpdate` can never clobber it.
  Future<String> uploadSeasonLogo({
    required String orgId,
    required String tournamentId,
    required String uid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'tournaments/$tournamentId/logo',
          uid: uid,
          bytes: bytes,
          contentType: contentType,
        );
        await Refs.tournament(orgId, tournamentId).update({'logoUrl': url});
        return url;
      });

  /// Goes back to no crest at all, which is the normal state.
  Future<void> removeSeasonLogo({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(
        () => Refs.tournament(orgId, tournamentId).update({'logoUrl': null}),
      );

  static final StreamController<AppException> _writeFailures =
      StreamController<AppException>.broadcast();

  static Stream<AppException> get writeFailures => _writeFailures.stream;

  static AppException _translate(Object error) {
    if (error is! FirebaseException) {
      return const ValidationException('That could not be saved.');
    }
    return switch (error.code) {
      'permission-denied' => const PermissionDeniedException(),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      _ => ValidationException(error.message ?? 'That could not be saved.'),
    };
  }

  // --- Venues -----------------------------------------------------------

  Stream<List<Venue>> watchVenues(String orgId, {bool includeArchived = false}) {
    return Refs.venues(orgId).snapshots().map((snap) {
      final all = snap.docs.map(Venue.fromDoc).toList();
      final visible = includeArchived
          ? all
          : [for (final v in all) if (!v.isArchived) v];
      return visible..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  Stream<Venue?> watchVenue(String orgId, String venueId) =>
      Refs.venue(orgId, venueId)
          .snapshots()
          .map((d) => d.exists ? Venue.fromDoc(d) : null);

  Future<String> createVenue(Venue venue) => guard(() async {
        if (venue.name.trim().isEmpty) {
          throw const ValidationException('A venue needs a name.');
        }
        final ref = Refs.venues(venue.orgId).doc();
        unawaited(ref.set(venue.toCreate()).catchError((Object e) {
          _writeFailures.add(_translate(e));
        }));
        return ref.id;
      });

  Future<void> updateVenue(Venue venue) =>
      guard(() => Refs.venue(venue.orgId, venue.id).update(venue.toUpdate()));

  /// Retires a venue without deleting it.
  ///
  /// A venue that has hosted a match is part of the record: fixtures name it,
  /// and a career profile that says "played at" needs somewhere to point. So
  /// this hides it from pickers rather than removing it.
  Future<void> archiveVenue(String orgId, String venueId) =>
      guard(() => Refs.venue(orgId, venueId).update({
            'isArchived': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  // --- Tournaments ------------------------------------------------------

  Stream<List<Tournament>> watchTournaments(String orgId) =>
      Refs.tournaments(orgId).snapshots().map(
            (snap) => snap.docs.map(Tournament.fromDoc).toList()
              ..sort((a, b) => (b.startDate ?? DateTime(0))
                  .compareTo(a.startDate ?? DateTime(0))),
          );

  Stream<Tournament?> watchTournament(String orgId, String tournamentId) =>
      Refs.tournament(orgId, tournamentId)
          .snapshots()
          .map((d) => d.exists ? Tournament.fromDoc(d) : null);

  /// Every draw belonging to one tournament.
  Stream<List<Competition>> watchEvents(String orgId, String tournamentId) =>
      Refs.competitions(orgId)
          .where('tournamentId', isEqualTo: tournamentId)
          .snapshots()
          .map((snap) => snap.docs.map(Competition.fromDoc).toList()
            ..sort((a, b) => a.name.compareTo(b.name)));

  /// Every match in a tournament, across all its events, as one stream.
  ///
  /// A collection-group query constrained by orgId and tournamentId so
  /// Firestore security rules can evaluate organization read access.
  Stream<List<Fixture>> watchFixtures(String orgId, String tournamentId) {
    return Refs.allFixturesQuery
        .where('orgId', isEqualTo: orgId)
        .where('tournamentId', isEqualTo: tournamentId)
        .snapshots()
        .map((snap) => snap.docs.map(Fixture.fromDoc).toList()
          ..sort((a, b) {
            final at = a.scheduledAt;
            final bt = b.scheduledAt;
            if (at == null && bt == null) {
              return a.matchIndex.compareTo(b.matchIndex);
            }
            if (at == null) return 1;
            if (bt == null) return -1;
            return at.compareTo(bt);
          }));
  }

  Future<String> createTournament(Tournament tournament) => guard(() async {
        if (tournament.name.trim().isEmpty) {
          throw const ValidationException('A tournament needs a name.');
        }
        final ref = Refs.tournaments(tournament.orgId).doc();
        unawaited(ref.set(tournament.toCreate()).catchError((Object e) {
          _writeFailures.add(_translate(e));
        }));
        return ref.id;
      });

  Future<void> updateTournament(Tournament tournament) => guard(
        () => Refs.tournament(tournament.orgId, tournament.id)
            .update(tournament.toUpdate()),
      );

  /// Updates the list of assigned venue IDs for this tournament.
  Future<void> updateTournamentVenues({
    required String orgId,
    required String tournamentId,
    required List<String> venueIds,
  }) =>
      guard(() => Refs.tournament(orgId, tournamentId).update({
            'venueIds': venueIds,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

  /// Puts a season on hold, reversibly, and says why.
  ///
  /// ## Why this is not cancellation
  ///
  /// The only stop button a season had was `status: cancelled`, which is
  /// one-way by design — every entrant is told the season is off, and a
  /// season that could be un-cancelled would make that message worthless. But
  /// the thing that actually happens to a grassroots season is not it being
  /// called off, it is a monsoon week, an exam fortnight, a ground the
  /// municipality has taken back for a fair. The season resumes; it just is
  /// not running right now.
  ///
  /// With only the permanent button available, organizers used it — and then
  /// re-created the season, losing the draws, the standings and everyone's
  /// registrations with it. This is the reversible one.
  ///
  /// What it changes: no new entries anywhere under it (every event goes on
  /// hold with it), and the season reads as paused everywhere it appears.
  /// What it does not change: [Tournament.status], the draws, the schedule,
  /// or anything already played. See [Tournament.isSuspended].
  ///
  /// [reason] is required and refused when blank, for the reason
  /// `CompetitionRepository.cancelCompetition` documents: a season that goes
  /// quiet without one is indistinguishable from the app being broken.
  Future<void> suspendTournament({
    required String orgId,
    required String tournamentId,
    required String reason,
    required String byUid,
  }) =>
      guard(() async {
        final text = reason.trim();
        if (text.isEmpty) {
          throw const ValidationException(
            'Give a reason. Everyone who entered will see it, and a season '
            'that stops without one reads as a fault in the app.',
          );
        }
        if (text.length > 500) {
          throw const ValidationException(
            'Keep the reason under 500 characters.',
          );
        }

        final snap = await Refs.tournament(orgId, tournamentId).get();
        if (!snap.exists) {
          throw const NotFoundException('That season no longer exists.');
        }
        final tournament = Tournament.fromDoc(snap);
        if (tournament.isSuspended) {
          throw const ValidationException('This season is already on hold.');
        }
        if (tournament.status == TournamentStatus.completed) {
          throw const ValidationException(
            'This season has finished. There is nothing left to pause.',
          );
        }

        await _setSuspension(
          orgId: orgId,
          tournamentId: tournamentId,
          suspended: true,
          reason: text,
          byUid: byUid,
        );
      });

  /// Brings a suspended season back, exactly where it was.
  ///
  /// The status was never touched on the way down, so there is nothing to
  /// restore and nothing to guess: clearing the flag is the whole operation.
  /// Events paused by the season resume with it — but an event the organizer
  /// paused *individually* stays paused, because that was a separate decision
  /// and this one does not overrule it. See [suspendTournament].
  Future<void> resumeTournament({
    required String orgId,
    required String tournamentId,
    required String byUid,
  }) =>
      guard(() async {
        final snap = await Refs.tournament(orgId, tournamentId).get();
        if (!snap.exists) {
          throw const NotFoundException('That season no longer exists.');
        }
        if (!Tournament.fromDoc(snap).isSuspended) {
          throw const ValidationException('This season is not on hold.');
        }

        await _setSuspension(
          orgId: orgId,
          tournamentId: tournamentId,
          suspended: false,
          reason: null,
          byUid: byUid,
        );
      });

  /// Writes the flag onto the season and onto every event it paused.
  ///
  /// Events carry their own copy rather than reading the season's, because
  /// most of the app holds a `Competition` without the `Tournament` above it —
  /// an event tile in a club's list, a registration form, the scoring screen.
  /// A flag they cannot see is a flag they cannot honour.
  ///
  /// `suspendedBySeason` is what keeps resume honest. Without it, resuming
  /// would have to either leave every event paused (so the organizer un-pauses
  /// fifteen events by hand) or resume all of them (so the one event they had
  /// deliberately pulled out comes back too). With it, the season only ever
  /// resumes what the season paused.
  Future<void> _setSuspension({
    required String orgId,
    required String tournamentId,
    required bool suspended,
    required String? reason,
    required String byUid,
  }) async {
    final eventsSnap = await Refs.competitions(orgId)
        .where('tournamentId', isEqualTo: tournamentId)
        .get();

    final batch = ChunkedBatch(Refs.db);
    batch.update(Refs.tournament(orgId, tournamentId), {
      'isSuspended': suspended,
      'suspendReason': suspended ? reason : null,
      'suspendedAt': suspended ? FieldValue.serverTimestamp() : null,
      'suspendedBy': suspended ? byUid : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in eventsSnap.docs) {
      final event = Competition.fromDoc(doc);
      if (suspended) {
        // Already paused by hand — leave it alone, and do not claim the
        // season paused it, or resuming the season would un-pause it.
        if (event.isSuspended) continue;
        batch.update(doc.reference, {
          'isSuspended': true,
          'suspendReason': reason,
          'suspendedAt': FieldValue.serverTimestamp(),
          'suspendedBy': byUid,
          'suspendedBySeason': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Only what the season paused. An event pulled by hand stays pulled.
        if (!event.isSuspended || !event.suspendedBySeason) continue;
        batch.update(doc.reference, {
          'isSuspended': false,
          'suspendReason': null,
          'suspendedAt': null,
          'suspendedBy': null,
          'suspendedBySeason': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commitAll();
  }

  /// Locks the tournament schedule and releases it to participants.
  ///
  /// ## Why this refuses rather than publishing everything it finds
  ///
  /// `Fixture.isDraft` does NOT mean "a real draw not yet announced" — it
  /// means a PLACEHOLDER, a bracket `generateDraftSchedule` laid out against
  /// synthetic entrants ("Team A", "Team B") so an organizer could see the
  /// shape of an event before registration produced anybody. `generateDraw`
  /// replaces them: it deletes every fixture in the event and writes the real
  /// draw in their place, which is why `Fixture.copyWith` refuses to carry
  /// `isDraft` at all.
  ///
  /// So a draft fixture surviving to this point is not something to publish —
  /// it is an event whose real draw was never generated. Clearing the flag
  /// would announce "Team A vs Team B, Court 3, 9:00" to every registered
  /// player. Naming the events and stopping is the only correct answer, and
  /// it is the check that turns "I thought I'd done that one" into a message
  /// instead of a Sunday morning.
  Future<void> lockSchedule({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(() async {
        final eventsSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();

        // Read every event before writing anything, so a season that cannot
        // legally publish has not already half-published itself.
        final placeholderEvents = <String>[];
        var fixtureCount = 0;
        for (final doc in eventsSnap.docs) {
          final fixtureSnap = await Refs.fixtures(orgId, doc.id).get();
          fixtureCount += fixtureSnap.docs.length;
          final hasPlaceholder =
              fixtureSnap.docs.map(Fixture.fromDoc).any((f) => f.isDraft);
          if (hasPlaceholder) {
            placeholderEvents.add(Competition.fromDoc(doc).name);
          }
        }

        if (fixtureCount == 0) {
          throw const ValidationException(
            'There are no matches to publish yet. Generate the draws first.',
          );
        }

        if (placeholderEvents.isNotEmpty) {
          throw ValidationException(
            'These events still have a placeholder draw, not a real one: '
            '${placeholderEvents.join(', ')}. Generate the draw for each '
            'before publishing, or their entrants go out as "Team A".',
          );
        }

        final batch = ChunkedBatch(Refs.db);
        batch.update(Refs.tournament(orgId, tournamentId), {
          'status': TournamentStatus.scheduled.wire,
          'isScheduleLocked': true,
          'scheduleReleasedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        for (final doc in eventsSnap.docs) {
          batch.update(doc.reference, {
            'status': CompetitionStatus.scheduled.wire,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Telling everybody is `onScheduleReleased`'s job, in
        // functions/index.js, and it fires off the `isScheduleLocked`
        // transition this batch writes.
        //
        // It was done here, as a third write in this batch, and it could not
        // work: the document went to `users/{orgId}/notifications` — an orgId
        // is not a uid, so the path named a user who does not exist — and
        // `firestore.rules` ends that collection with `allow create: if
        // false`, because a notification is the server's to write and a
        // client that could create one could notify anybody about anything.
        // Firestore rejects a batch if ANY write in it is denied, so the
        // rejected notification took the two status updates down with it and
        // "Lock & publish" failed outright. The schedule could not be
        // published at all.
        //
        // Awaited, unlike the draw paths: an organizer pressing "publish" is
        // entitled to know it landed.
        await batch.commitAll();
      });

  /// Regenerates the tournament schedule draft with non-overlapping timings
  /// across available courts and rest intervals.
  ///
  /// The timing arguments are the organizer's answers to "how long is a match
  /// and how much time do we need between them", and they are **persisted on
  /// the tournament before the solve runs**, not merely passed through. Until
  /// they were, the dialog that asks collected all three into local variables
  /// and then called a zero-argument callback, so [generateSchedule] re-read
  /// the stored defaults and every answer was silently discarded — the
  /// organizer set a 15-minute changeover, watched a schedule appear, and got
  /// the 5-minute one.
  ///
  /// Persisting also makes the answer stick: the next regeneration, the
  /// per-day shift and the "running late" path all read the same fields, so
  /// the tournament keeps its turnaround rather than reverting to the default
  /// the moment anything else touches the timetable.
  Future<TournamentScheduleReport> regenerateDraftSchedule({
    required String orgId,
    required String tournamentId,
    int? matchMinutes,
    int? changeoverMinutes,
    int? restGapMinutes,
  }) =>
      guard(() async {
        final overrides = <String, Object?>{
          if (matchMinutes != null) 'matchMinutesDefault': matchMinutes,
          if (changeoverMinutes != null) 'changeoverMinutes': changeoverMinutes,
          if (restGapMinutes != null) 'restGapMinutes': restGapMinutes,
        };
        if (overrides.isNotEmpty) {
          // Awaited, unlike most writes here: `generateSchedule` re-reads the
          // tournament document on its first line, so a fire-and-forget write
          // would race the read it is meant to inform.
          await Refs.tournament(orgId, tournamentId).update({
            ...overrides,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return generateSchedule(
          orgId: orgId,
          tournamentId: tournamentId,
          matchMinutesOverride: matchMinutes,
        );
      });

  /// Opens entries on every event of a season at once.
  ///
  /// ## Why this had to exist
  ///
  /// Every competition is created as a `draft` — `Competition.toCreate`
  /// forces it and `firestore.rules` requires it, so that an organizer can
  /// configure an event before anybody can enter it. That is right for one
  /// event and wrong for a season: publishing a twelve-category sports week
  /// produced twelve drafts, and the season page offered no way to open any
  /// of them. The organizer had to open twelve event pages and press "Open
  /// entries" twelve times before a single student could register — and
  /// nothing on the season told them that was the next step, so the ordinary
  /// experience of publishing a season was a season nobody could enter.
  ///
  /// Only drafts are touched. An event whose entries are already open, or
  /// closed, or being played, is left exactly as it is: this opens a season,
  /// it does not reopen one.
  ///
  /// The tournament moves to `entriesOpen` in the same batch, so the season
  /// header and the events under it cannot disagree about whether the season
  /// is taking entries.
  Future<int> openEntriesForSeason({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(() async {
        final eventSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final drafts = [
          for (final doc in eventSnap.docs)
            if (Competition.fromDoc(doc).status == CompetitionStatus.draft)
              Competition.fromDoc(doc),
        ];
        if (drafts.isEmpty) {
          throw const ValidationException(
            'Every event in this season has already been opened.',
          );
        }

        final batch = ChunkedBatch(Refs.db);
        for (final event in drafts) {
          batch.update(Refs.competition(orgId, event.id), {
            'status': CompetitionStatus.registrationOpen.wire,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        batch.update(Refs.tournament(orgId, tournamentId), {
          'status': TournamentStatus.entriesOpen.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Awaited, unlike most writes here. The organizer is watching a
        // button and the next thing they will do is tell people to register;
        // "entries are open" is not something to report optimistically.
        await batch.commitAll();
        return drafts.length;
      });

  /// Draws every event, then lays the whole season out on one timetable.
  ///
  /// The operation the product exists to provide. An organizer running a
  /// fifteen-event meet had to open each event, generate its draw, come back,
  /// and only then ask for a schedule — fifteen trips through a bottom sheet
  /// before anything could be scheduled at all, and no way to tell part-way
  /// through which events were done. Everything below already existed; what
  /// did not was a single call that runs them in the right order.
  ///
  /// Order matters and is the whole point: draws first, because
  /// [generateSchedule] can only place fixtures that exist, and one schedule
  /// pass afterwards over *all* of them, because clash-freedom is a property
  /// of the whole season at once. Scheduling each event as it is drawn would
  /// give every event a conflict-free timetable of its own and still put a
  /// player on two courts at eleven — which is precisely the failure a
  /// multi-category season produces and a per-event scheduler cannot see.
  ///
  /// Events already holding a scored match are left exactly as they are. A
  /// season half-played is the case where regenerating is destructive, and
  /// the honest response is to skip and say so rather than to refuse the
  /// whole run because one event has started.
  Future<SeasonSetupReport> setUpWholeSeason({
    required String orgId,
    required String tournamentId,
    int? matchMinutes,
    int? changeoverMinutes,
    int? restGapMinutes,
  }) =>
      guard(() async {
        final tDoc = await Refs.tournament(orgId, tournamentId).get();
        if (!tDoc.exists) {
          throw const NotFoundException('That tournament no longer exists.');
        }
        final tournament = Tournament.fromDoc(tDoc);
        if (tournament.startDate == null) {
          throw const ValidationException(
            'Set the season dates before laying out a schedule.',
          );
        }
        final eventSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final events = eventSnap.docs.map(Competition.fromDoc).toList();
        if (events.isEmpty) {
          throw const ValidationException('This season has no events yet.');
        }

        // Checked against the same pool `generateSchedule` actually builds
        // from — the season's grounds PLUS any ground a single sport names
        // for itself. Testing only the tournament's own list would refuse a
        // season whose cricket has the main field and whose season-level list
        // was left empty, while the solve it is guarding would have worked.
        if (tournament.venueIds.isEmpty &&
            events.every((e) => e.scheduleConfig.venueIds.isEmpty)) {
          throw const ValidationException(
            'This season has no grounds yet. Add a venue with at least one '
            'court — the schedule is built out of courts.',
          );
        }

        const comps = CompetitionRepository();
        final drawn = <String>[];
        final skipped = <String>[];

        for (final event in events) {
          // Anything already scored is somebody's afternoon. Leave it.
          final fixtureSnap = await Refs.fixtures(orgId, event.id).get();
          final fixtures = fixtureSnap.docs.map(Fixture.fromDoc).toList();
          if (fixtures.any((f) => f.lastSeq > 0 || f.hasResult)) {
            skipped.add('${event.name}: already being played');
            continue;
          }
          // A real draw already stands. Redrawing it would move people who
          // have been told where they are.
          if (fixtures.any((f) => !f.isDraft)) {
            drawn.add(event.name);
            continue;
          }

          final entrantSnap = await Refs.entrants(orgId, event.id).get();
          var entrants = [
            for (final doc in entrantSnap.docs)
              if (!Entrant.fromDoc(doc).withdrawn) Entrant.fromDoc(doc),
          ];

          // Entries still open, and nothing promoted yet.
          //
          // ## Why this closes them rather than skipping
          //
          // An entrant list is not written when somebody registers — it is
          // written when an organizer CLOSES entries, which promotes the
          // confirmed registrations into the field (house squads resolved,
          // pairs joined, waitlist settled). Until that happens the event has
          // registrations and no entrants.
          //
          // Skipping here is what a season with twenty people signed up to
          // every event looked like from the outside: "Set up the whole
          // season" reported "0 entered, needs at least 2" for all twelve of
          // them, while the event pages plainly showed twenty registrations.
          // That reads as a broken schedule, and the fix an organizer needed
          // was twelve trips into twelve event pages to press Close entries.
          //
          // So the one button does the whole thing, which is what it says it
          // does. A failure to close is reported for that event alone and the
          // rest of the season still gets drawn — same policy as a failed
          // draw below.
          if (entrants.isEmpty && event.status.acceptsRegistrations) {
            try {
              entrants = await comps.closeEntriesAndPromote(
                orgId: orgId,
                compId: event.id,
              );
            } on AppException catch (e) {
              skipped.add('${event.name}: ${e.message}');
              continue;
            }
          }

          if (entrants.length < 2) {
            skipped.add(
              '${event.name}: ${entrants.length} entered, needs at least 2',
            );
            continue;
          }

          try {
            await comps.generateDraw(
              competition: event,
              entrants: entrants,
            );
            drawn.add(event.name);
          } on AppException catch (e) {
            // One event's draw failing is not the season's failure. Record it
            // and carry on, so fourteen events still get a timetable.
            skipped.add('${event.name}: ${e.message}');
          }
        }

        if (drawn.isEmpty) {
          throw ValidationException(
            'No event could be drawn. ${skipped.join('; ')}',
          );
        }

        final schedule = await regenerateDraftSchedule(
          orgId: orgId,
          tournamentId: tournamentId,
          matchMinutes: matchMinutes,
          changeoverMinutes: changeoverMinutes,
          restGapMinutes: restGapMinutes,
        );

        return SeasonSetupReport(
          eventsDrawn: drawn.length,
          eventsSkipped: skipped,
          schedule: schedule,
        );
      });

  /// Attaches an existing competition to a tournament, and keeps the
  /// denormalized event count in step.
  Future<void> addEvent({
    required String orgId,
    required String tournamentId,
    required String compId,
  }) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.update(Refs.competition(orgId, compId), {
          'tournamentId': tournamentId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batch.update(Refs.tournament(orgId, tournamentId), {
          'eventCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      });

  /// Records that [count] draws were created directly INTO a tournament.
  ///
  /// [addEvent] handles the attach-an-existing-event path and keeps the count
  /// in step itself. The season form takes the other path — it creates each
  /// sport already carrying `tournamentId`, so nothing ever ran the increment
  /// and a five-sport season sat at `eventCount: 0`.
  ///
  /// That was not merely a wrong chip on a card. `firestore.rules` permits
  /// deleting a tournament only when `eventCount == 0`, which is the guard
  /// that stops somebody removing a season out from under the draws hanging
  /// off it. A season that under-reports its own events is a season that can
  /// be deleted while it still has five.
  /// Fire-and-forget, like the creates it follows. Awaiting a write here means
  /// awaiting the SERVER's acknowledgement, and a season created on a ground
  /// with no signal would hang on this line rather than finishing offline and
  /// syncing later — the one thing §2.1 says must never happen. The increment
  /// is queued in the same ordered mutation queue as the create, so it lands
  /// after it whenever the connection returns; a genuine rejection surfaces
  /// through [writeFailures] rather than blocking the organizer.
  void noteEventsCreated({
    required String orgId,
    required String tournamentId,
    required int count,
  }) {
    unawaited(
      Refs.tournament(orgId, tournamentId).update({
        'eventCount': FieldValue.increment(count),
        'updatedAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) => _writeFailures.add(_translate(e))),
    );
  }

  // --- Cross-club invitations -------------------------------------------

  /// Invites a set of clubs into one tournament, in one batch.
  ///
  /// Batched deliberately. An organizer picks eleven clubs in one sitting and
  /// taps send once; eleven sequential writes on a rural connection means the
  /// fourth can fail while the first three have gone, leaving the host's list
  /// half true with nothing to tell them which half. One commit either invites
  /// everybody or nobody, and the retry is the same tap they already made.
  ///
  /// Clubs already invited are skipped rather than rejected — the caller's
  /// picker excludes them, and re-sending would either duplicate the row or
  /// overwrite an answer somebody has already given.
  Future<void> inviteClubs({
    required Tournament tournament,
    required String hostOrgName,
    required List<({String orgId, String name})> clubs,
    required String invitedByUid,
    String? message,
  }) =>
      guard(() async {
        final targets = [
          for (final c in clubs)
            if (c.orgId != tournament.orgId) c,
        ];
        if (targets.isEmpty) {
          throw const ValidationException('Pick at least one club to invite.');
        }

        final trimmed = message?.trim();
        final batch = Refs.db.batch();
        for (final club in targets) {
          batch.set(
            Refs.tournamentInvite(
              TournamentInvite.idFor(
                fromOrgId: tournament.orgId,
                tournamentId: tournament.id,
                toOrgId: club.orgId,
              ),
            ),
            TournamentInvite(
              id: '',
              tournamentId: tournament.id,
              tournamentName: tournament.name,
              fromOrgId: tournament.orgId,
              fromOrgName: hostOrgName,
              toOrgId: club.orgId,
              toOrgName: club.name,
              status: 'pending',
              message: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
              startDate: tournament.startDate,
              endDate: tournament.endDate,
              invitedBy: invitedByUid,
            ).toCreate(),
          );
        }
        await batch.commit();
      });

  /// Every club invited to one tournament, in the order they were asked.
  Stream<List<TournamentInvite>> watchInvitesForTournament({
    required String orgId,
    required String tournamentId,
  }) {
    return Refs.tournamentInvites
        .where('fromOrgId', isEqualTo: orgId)
        .where('tournamentId', isEqualTo: tournamentId)
        .snapshots()
        .map((snap) => snap.docs.map(TournamentInvite.fromDoc).toList()
          ..sort((a, b) => a.toOrgName.compareTo(b.toOrgName)));
  }

  /// Tournaments other clubs have invited [orgId] into and are still waiting
  /// on an answer for.
  ///
  /// Guarded for the same reason as `watchChallengesForOrg`: this feeds an
  /// error strip on the Notifications screen, and an unguarded rejection
  /// reached it as a raw `FirebaseException` that the UI could only render as
  /// "Something went wrong".
  Stream<List<TournamentInvite>> watchIncomingInvites(String orgId) {
    return guardStream(
      () => Refs.tournamentInvites
          .where('toOrgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) => snap.docs.map(TournamentInvite.fromDoc).toList()
            ..sort((a, b) => (a.startDate ?? DateTime(9999))
                .compareTo(b.startDate ?? DateTime(9999)))),
    );
  }

  /// Every invitation into [orgId] that is still live — asked and unanswered,
  /// or answered yes.
  ///
  /// The wider sibling of [watchIncomingInvites], which is pending-only
  /// because it feeds a "you have been asked, reply" strip and an accepted
  /// invitation is no longer a thing to reply to. This one answers a
  /// different question — "what is my club actually part of?" — and there the
  /// accepted ones are the whole point: a club that said yes in April is
  /// still going in June, and dropping it the moment it was answered is how
  /// the host's season became invisible to everybody it had invited.
  ///
  /// `declined` and `withdrawn` stay out. Both are a closed door, and a
  /// season nobody at this club is going to is not this club's season.
  ///
  /// Guarded like its sibling: this feeds a home-screen count, and one club's
  /// refused read must not surface as a raw exception.
  Stream<List<TournamentInvite>> watchLiveIncomingInvites(String orgId) {
    return guardStream(
      () => Refs.tournamentInvites
          .where('toOrgId', isEqualTo: orgId)
          .where('status', whereIn: const ['pending', 'accepted'])
          .snapshots()
          .map((snap) => snap.docs.map(TournamentInvite.fromDoc).toList()
            ..sort((a, b) => (a.startDate ?? DateTime(9999))
                .compareTo(b.startDate ?? DateTime(9999)))),
    );
  }

  /// Records the invited club's answer, or the host taking the offer back.
  ///
  /// Accepting does NOT enter anybody into anything. The tournament's own
  /// entry rules decide who plays — a club that says yes here is saying it
  /// intends to come, and its players still register through the events. This
  /// is the reply to a question, not a registration, and conflating the two
  /// would let one admin's tap commit a club to a draw nobody has picked a
  /// squad for.
  Future<void> respondToInvite({
    required String inviteId,
    required String status,
  }) =>
      guard(() => Refs.tournamentInvite(inviteId).update({
            'status': status,
            'respondedAt': FieldValue.serverTimestamp(),
          }));

  // --- Interest in an invited season ------------------------------------

  /// Who at [orgId] has put their hand up for the season [hostOrgId] invited
  /// them into.
  ///
  /// Read by the club's own organizers when they pick the side, and by each
  /// member to know whether their own hand is up. One stream for both, rather
  /// than a second single-document read for "am I in this list", because the
  /// rules already let any member of the club read the whole list and a
  /// member seeing who else is available is a feature, not a leak.
  Stream<List<SeasonInterest>> watchSeasonInterest({
    required String orgId,
    required String hostOrgId,
    required String tournamentId,
  }) {
    return guardStream(
      () => Refs.seasonInterest(orgId)
          .where('hostOrgId', isEqualTo: hostOrgId)
          .where('tournamentId', isEqualTo: tournamentId)
          .snapshots()
          .map((snap) => snap.docs.map(SeasonInterest.fromDoc).toList()
            ..sort((a, b) => (a.createdAt ?? DateTime(9999))
                .compareTo(b.createdAt ?? DateTime(9999)))),
    );
  }

  /// Puts a member's hand up, or edits the note on a hand already up.
  ///
  /// A deterministic id and a `set`, so the button is idempotent: pressing it
  /// on a second device updates the one row rather than adding another.
  Future<void> setSeasonInterest(SeasonInterest interest) => guard(
        () => Refs.seasonInterestDoc(interest.orgId, interest.id)
            .set(interest.toCreate(), SetOptions(merge: true)),
      );

  /// Takes a hand back down.
  ///
  /// A delete rather than a status, unlike an invitation's `declined`:
  /// availability is not an answer anybody is owed a record of, and a member
  /// who changes their mind on Tuesday should leave no trace on the owner's
  /// selection list on Wednesday.
  Future<void> clearSeasonInterest({
    required String orgId,
    required String hostOrgId,
    required String tournamentId,
    required String uid,
  }) =>
      guard(
        () => Refs.seasonInterestDoc(
          orgId,
          SeasonInterest.idFor(
            hostOrgId: hostOrgId,
            tournamentId: tournamentId,
            uid: uid,
          ),
        ).delete(),
      );

  // --- Officials (the season's own panel, pre-assigned ICC-style) -------

  Stream<List<TournamentOfficial>> watchOfficials(
    String orgId,
    String tournamentId,
  ) =>
      Refs.tournamentOfficials(orgId, tournamentId).snapshots().map(
            (snap) => snap.docs.map(TournamentOfficial.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  /// Adds someone to this tournament's officiating panel — either picked from
  /// the global `umpires` registry, or entered by hand for the common
  /// grassroots case: the club treasurer's uncle is umpiring, and he has
  /// never opened the app.
  Future<void> addOfficialToRoster({
    required String orgId,
    required String tournamentId,
    required TournamentOfficial official,
    required String addedByUid,
  }) =>
      guard(() => Refs.tournamentOfficial(orgId, tournamentId, official.uid)
          .set(official.toCreate(addedBy: addedByUid)));

  /// Edits a panel entry in place — the sports they cover, the days they can
  /// come, their daily limit.
  ///
  /// A separate call from [addOfficialToRoster] rather than a re-add, because
  /// re-adding would rewrite `addedBy` and `addedAt`, which `firestore.rules`
  /// refuses on update and which record something true: who put this person
  /// on the panel, and when. Editing their availability is not a re-add.
  Future<void> updateOfficialOnRoster({
    required String orgId,
    required String tournamentId,
    required TournamentOfficial official,
  }) =>
      guard(() async {
        if (official.maxMatchesPerDay < 1) {
          throw const ValidationException(
            'An official has to be able to take at least one match a day.',
          );
        }
        await Refs.tournamentOfficial(orgId, tournamentId, official.uid)
            .update(official.toUpdate());
      });

  Future<void> removeOfficialFromRoster({
    required String orgId,
    required String tournamentId,
    required String uid,
  }) =>
      guard(
        () => Refs.tournamentOfficial(orgId, tournamentId, uid).delete(),
      );

  /// Runs [OfficialsAssigner] across every scheduled, not-yet-officiated
  /// fixture in the tournament, using the roster built by
  /// [addOfficialToRoster], and persists whatever it could place.
  ///
  /// Two things are deliberately skipped rather than overridden:
  ///
  /// - A fixture with no `scheduledAt` yet — a venue still marked TBD has no
  ///   time window to check clashes against, and is left for a second run
  ///   once the schedule (or that one match, via the move sheet) is set.
  /// - A fixture that already carries an official — a manual assignment is a
  ///   decision this run must not quietly replace, the same rule the venue
  ///   scheduler follows for a hand-fixed court.
  ///
  /// Returns the [OfficialsRoster] the algorithm produced, `unstaffed`
  /// included, so the caller can show the season owner exactly which matches
  /// still need a name before match day rather than finding out at the gate.
  Future<OfficialsRoster> assignOfficialsAcrossTournament({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(() async {
        final tDoc = await Refs.tournament(orgId, tournamentId).get();
        if (!tDoc.exists) {
          throw const NotFoundException('That tournament no longer exists.');
        }
        final tournament = Tournament.fromDoc(tDoc);

        final rosterSnap =
            await Refs.tournamentOfficials(orgId, tournamentId).get();
        final roster =
            rosterSnap.docs.map(TournamentOfficial.fromDoc).toList();
        if (roster.isEmpty) {
          throw const ValidationException(
            'Add officials to this tournament before assigning them to '
            'matches.',
          );
        }

        final fixSnap = await Refs.allFixturesQuery
            .where('orgId', isEqualTo: orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final fixtures = fixSnap.docs.map(Fixture.fromDoc).toList();

        // The events, for the sport each match is and the name to report an
        // unstaffed one under. A fixture carries `sportId` only when the draw
        // that wrote it recorded one — older ones and quick matches do not —
        // so the event is the authority and the fixture is the fallback.
        final eventsSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final eventById = {
          for (final doc in eventsSnap.docs) doc.id: Competition.fromDoc(doc),
        };

        // Entrant -> club, one lookup per event — the same shape as the
        // uid-by-entrant map `generateSchedule` builds above, for clubs
        // instead of players.
        final clubByEntrant = <String, String?>{};
        for (final compId in {for (final f in fixtures) f.compId}) {
          final entrantSnap = await Refs.entrants(orgId, compId).get();
          for (final doc in entrantSnap.docs) {
            clubByEntrant[doc.id] = Entrant.fromDoc(doc).clubId;
          }
        }

        final slots = <OfficiatingSlot>[];
        final byFixtureId = <String, Fixture>{};
        for (final f in fixtures) {
          final at = f.scheduledAt;
          if (at == null) continue;
          if (f.officials.isNotEmpty) continue;
          if (f.status != FixtureStatus.scheduled) continue;

          final clubs = <String>{
            if (clubByEntrant[f.entrantAId] != null)
              clubByEntrant[f.entrantAId]!,
            if (clubByEntrant[f.entrantBId] != null)
              clubByEntrant[f.entrantBId]!,
          };

          final event = eventById[f.compId];
          slots.add(OfficiatingSlot(
            fixtureId: f.id,
            window: ScheduleWindow(
              start: at,
              end: at.add(Duration(minutes: tournament.slotMinutes)),
            ),
            courtKey: f.courtId ?? f.venue ?? f.id,
            contestingClubIds: clubs,
            sportId: event?.sportId ?? f.sportId,
            eventId: f.compId,
            eventName: event?.name ?? '',
            groupId: f.bracket == Bracket.group ? f.groupId : null,
            label: '${f.entrantAName} vs ${f.entrantBName}',
          ));
          byFixtureId[f.id] = f;
        }

        if (slots.isEmpty) {
          throw const ValidationException(
            'No scheduled, unofficiated matches to assign — generate the '
            'schedule first, or every match already has an official.',
          );
        }

        final available = [
          for (final o in roster)
            AvailableOfficial(
              uid: o.uid,
              name: o.name,
              clubId: o.clubId,
              role: o.role,
              sports: o.sports,
              availableDays: o.availableDates.toSet(),
              maxMatches: o.maxMatchesPerDay,
            ),
        ];

        final result = const OfficialsAssigner().assign(
          slots: slots,
          officials: available,
        );

        final rosterByUid = {for (final o in roster) o.uid: o};
        final batch = ChunkedBatch(Refs.db);
        for (final a in result.assignments) {
          final fixture = byFixtureId[a.fixtureId]!;
          final entry = rosterByUid[a.official.uid]!;
          final scorers = List<String>.from(fixture.scorerUids);
          if (entry.scoringRightsGranted && !scorers.contains(entry.uid)) {
            scorers.add(entry.uid);
          }
          batch.update(
            Refs.fixture(orgId, fixture.compId, fixture.id),
            {
              'officials': MatchOfficial.listTo([
                MatchOfficial(
                  uid: entry.uid,
                  name: entry.name,
                  role: entry.role,
                  grantedScoringAccess: entry.scoringRightsGranted,
                ),
              ]),
              'scorerUids': scorers,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        unawaited(batch.commitAll().catchError((Object e) {
          _writeFailures.add(_translate(e));
        }));

        return result;
      });

  // --- Ranking ----------------------------------------------------------

  /// Current ranking entries for one sport.
  ///
  /// Filtered on `expiresAt` in the query rather than in Dart so an aged-out
  /// result costs nothing to ignore: a busy sport accumulates entries forever,
  /// and reading a decade of them to sum the last year would get slower every
  /// season.
  ///
  /// [limit] caps what any one screen will read. A ranking list is a top-N
  /// board and nobody scrolls to position four hundred; the cap is what stops
  /// a popular sport turning one screen into an unbounded read.
  Stream<List<RankingEntry>> watchRankingEntries({
    required String sportId,
    int limit = 500,
  }) {
    return Refs.rankingEntries
        .where('sportId', isEqualTo: sportId)
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .orderBy('expiresAt')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(RankingEntry.fromDoc).toList());
  }

  /// Every title and placing won at tournaments this club ran.
  ///
  /// Keyed on the organizing club rather than on the winners' clubs, which is
  /// the honest thing this data can answer: a ranking entry records who ran
  /// the tournament, not which club each competitor came from. An honours
  /// board of "events we have hosted, and who won them" is a real board; one
  /// claiming "titles our members have won everywhere" would need a club on
  /// every entrant and would quietly under-report until it had one.
  Stream<List<RankingEntry>> watchClubHonours(String orgId) {
    return Refs.rankingEntries
        .where('orgId', isEqualTo: orgId)
        .where('round', isEqualTo: 'winner')
        .snapshots()
        .map((snap) => snap.docs.map(RankingEntry.fromDoc).toList()
          ..sort((a, b) => (b.awardedAt ?? DateTime(0))
              .compareTo(a.awardedAt ?? DateTime(0))));
  }

  /// One sport's club ladder.
  ///
  /// A single document read, not a query: the nightly rollup has already done
  /// the cross-club scan that no client is permitted to do — see
  /// `functions/clubs.js` for why counting this from the client would give
  /// every visitor a different, silently smaller ladder.
  Stream<ClubStandings> watchClubStandings(String sportId) {
    return Refs.clubStandings
        .doc(sportId)
        .snapshots()
        .map((doc) => ClubStandings.fromMap(doc.data(), sportId));
  }

  /// One player's ranking results, for their profile.
  Stream<List<RankingEntry>> watchPlayerRanking(String uid) {
    return Refs.rankingEntries
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(RankingEntry.fromDoc).toList()
          ..sort((a, b) => b.points.compareTo(a.points)));
  }

  // --- Venue planning ---------------------------------------------------

  /// This season's plan for every venue it has been given one for.
  ///
  /// Absent means "no opinion" everywhere it is read, so a season whose
  /// organizer never opened the venue planner behaves exactly as it did
  /// before venue planning existed.
  Stream<Map<String, VenuePlan>> watchVenuePlans(
    String orgId,
    String tournamentId,
  ) =>
      guardStream(
        () => Refs.venuePlans(orgId, tournamentId).snapshots().map(
              (snap) => {
                for (final doc in snap.docs) doc.id: VenuePlan.fromDoc(doc),
              },
            ),
      );

  Future<void> saveVenuePlan({
    required String orgId,
    required String tournamentId,
    required VenuePlan plan,
  }) =>
      guard(() async {
        for (final session in plan.sessions) {
          if (!session.isValid) {
            throw const ValidationException(
              'A playing session has to end after it starts.',
            );
          }
        }
        if ((plan.matchMinutes ?? 1) < 1) {
          throw const ValidationException(
            'A match has to be at least a minute long.',
          );
        }
        await Refs.venuePlan(orgId, tournamentId, plan.venueId)
            .set(plan.toMap(), SetOptions(merge: true));
      });

  /// Puts a venue back to "use it however the season needs".
  Future<void> clearVenuePlan({
    required String orgId,
    required String tournamentId,
    required String venueId,
  }) =>
      guard(() => Refs.venuePlan(orgId, tournamentId, venueId).delete());

  /// Answers "will this fit?" before a single fixture is drawn.
  ///
  /// ## Why this runs before Generate and not after
  ///
  /// The failure it prevents is a season that is discovered to be impossible
  /// only once it has been drawn, published and half-registered — at which
  /// point the organizer's options are all bad. Every number here is
  /// obtainable from the entrant counts and the venue plans, so the answer is
  /// available at the moment it is still cheap to act on: add a day, add a
  /// ground, shorten the match.
  ///
  /// Counts required matches from the draws when they exist and from the
  /// entrant count when they do not, so it is answerable at both ends of the
  /// season lifecycle.
  Future<CapacityReport> assessCapacity({
    required String orgId,
    required String tournamentId,
    int? matchMinutesOverride,
  }) =>
      guard(() async {
        final tDoc = await Refs.tournament(orgId, tournamentId).get();
        if (!tDoc.exists) {
          throw const NotFoundException('That season no longer exists.');
        }
        final tournament = Tournament.fromDoc(tDoc);
        final start = tournament.startDate;
        if (start == null) {
          throw const ValidationException(
            'Set the season dates before checking capacity.',
          );
        }

        final eventSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final events = eventSnap.docs.map(Competition.fromDoc).toList();
        if (events.isEmpty) {
          throw const ValidationException('This season has no events yet.');
        }

        final venues = await _venuesOf(orgId, tournament, events);
        final plans = await _venuePlansOf(orgId, tournamentId);

        final availabilityFor = <String, EventAvailability>{
          for (final event in events) event.id: availabilityOf(event, tournament),
        };
        final gridDays = _gridDaysFor(
          tournament: tournament,
          start: start,
          availabilities: availabilityFor.values,
        );

        final calendars = SeasonCapacity.buildCalendars(
          seasonStart: start,
          dayCount: gridDays,
          venues: venues,
          plans: plans,
          defaultMatchMinutes:
              matchMinutesOverride ?? tournament.matchMinutesDefault,
          defaultTurnaroundMinutes: tournament.changeoverMinutes,
        );

        final demands = <EventDemand>[];
        for (final event in events) {
          final availability =
              availabilityFor[event.id] ?? EventAvailability.anywhere;
          final eligible = <String>{
            for (final c in calendars)
              if (availability.allowsCourt(c.court) &&
                  c.allowsSport(event.sportId))
                c.court.key,
          };

          // Drawn already? Then the fixtures are the truth. Not drawn? Then
          // the entrant count and the format say exactly how many matches the
          // draw will make, which is the whole reason this can be asked first.
          final fixtureSnap = await Refs.fixtures(orgId, event.id).count().get();
          var required = fixtureSnap.count ?? 0;
          if (required == 0) {
            final entrants =
                (await Refs.entrants(orgId, event.id).count().get()).count ?? 0;
            required = MatchCount.forDraw(
              format: event.format,
              config: event.drawConfig,
              entrants: entrants,
            );
          }
          if (required == 0) continue;

          final venuePlan = _planForEvent(plans, availability);
          demands.add(EventDemand(
            compId: event.id,
            label: event.name,
            sportId: event.sportId,
            matchesRequired: required,
            eligibleCourtKeys: eligible,
            matchMinutes: matchMinutesOverride ??
                venuePlan?.matchMinutes ??
                event.scheduleConfig.matchMinutes,
            turnaroundMinutes: venuePlan?.turnaroundMinutes ??
                event.scheduleConfig.changeoverMinutes,
          ));
        }

        return SeasonCapacity.assess(calendars: calendars, demands: demands);
      });

  /// What one venue offers this season, with the organizer's own ceiling kept
  /// visibly apart from the arithmetic — see [VenueCapacityLine].
  Future<List<VenueCapacityLine>> venueCapacityLines({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(() async {
        final tDoc = await Refs.tournament(orgId, tournamentId).get();
        if (!tDoc.exists) return const <VenueCapacityLine>[];
        final tournament = Tournament.fromDoc(tDoc);
        final start = tournament.startDate;
        if (start == null) return const <VenueCapacityLine>[];

        final eventSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final events = eventSnap.docs.map(Competition.fromDoc).toList();
        final venues = await _venuesOf(orgId, tournament, events);
        final plans = await _venuePlansOf(orgId, tournamentId);

        return [
          for (final venue in venues)
            SeasonCapacity.lineFor(
              venue: venue,
              plan: plans[venue.id] ?? VenuePlan(venueId: venue.id),
              seasonStart: start,
              dayCount: tournament.dayCount,
              defaultMatchMinutes: tournament.matchMinutesDefault,
              defaultTurnaroundMinutes: tournament.changeoverMinutes,
            ),
        ];
      });

  /// Every venue this season could play at — its own list, plus any ground an
  /// event named that the season itself never did.
  ///
  /// The union matters for a multi-sport season: the cricket needs the main
  /// field and nothing else in the season goes near it, so an event's own
  /// choice has to be able to add to the pool rather than only narrow it.
  Future<List<Venue>> _venuesOf(
    String orgId,
    Tournament tournament,
    List<Competition> events,
  ) async {
    final ids = <String>{
      ...tournament.venueIds,
      for (final event in events) ...event.scheduleConfig.venueIds,
    };
    final out = <Venue>[];
    for (final id in ids) {
      final doc = await Refs.venue(orgId, id).get();
      if (!doc.exists) continue;
      final venue = Venue.fromDoc(doc);
      if (venue.isArchived || venue.usableCourts.isEmpty) continue;
      out.add(venue);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  Future<Map<String, VenuePlan>> _venuePlansOf(
    String orgId,
    String tournamentId,
  ) async {
    final snap = await Refs.venuePlans(orgId, tournamentId).get();
    return {for (final doc in snap.docs) doc.id: VenuePlan.fromDoc(doc)};
  }

  /// The plan of the one venue an event is pinned to, for reading its match
  /// length. Null when the event may go to several grounds, where no single
  /// venue's timing is the right answer.
  static VenuePlan? _planForEvent(
    Map<String, VenuePlan> plans,
    EventAvailability availability,
  ) {
    if (availability.venueIds.length != 1) return null;
    return plans[availability.venueIds.first];
  }

  /// How many days the schedule grid has to span.
  static int _gridDaysFor({
    required Tournament tournament,
    required DateTime start,
    required Iterable<EventAvailability> availabilities,
  }) {
    var days = tournament.dayCount;
    for (final availability in availabilities) {
      final last = availability.lastDay;
      if (last == null) continue;
      final span = DateTime(last.year, last.month, last.day)
              .difference(DateTime(start.year, start.month, start.day))
              .inDays +
          1;
      if (span > days) days = span;
    }
    return days;
  }

  /// `{x}` when [value] is a real id, null when it is not — so a set literal
  /// can spread it away without a branch.
  static Set<String>? _maybe(String? value) =>
      value == null || value.isEmpty ? null : {value};

  /// Everything one solve of a season needs, read once.
  ///
  /// Extracted because three operations need exactly the same picture —
  /// generating the timetable, checking the one already stored, and
  /// re-checking it after an organizer moves a match by hand. Reading it
  /// three different ways is how the health report and the scheduler end up
  /// disagreeing about whether a court is open, and a disagreement there is
  /// invisible until somebody is standing on the wrong court.
  Future<_SeasonPlan> _loadPlan({
    required String orgId,
    required String tournamentId,
    int? matchMinutesOverride,
  }) async {
    final tDoc = await Refs.tournament(orgId, tournamentId).get();
    if (!tDoc.exists) {
      throw const NotFoundException('That tournament no longer exists.');
    }
    final tournament = Tournament.fromDoc(tDoc);

    final start = tournament.startDate;
    if (start == null) {
      throw const ValidationException(
        'Set the tournament dates before generating a schedule.',
      );
    }

    // ---- Every event, and every fixture in it. ----
    //
    // Read before the venues, unlike the original order, because an event
    // may name a ground the season itself never did — a multi-sport
    // season is exactly the case where the cricket needs the main field
    // and nothing else in the season goes near it. The pool is the union
    // of both, and `EventAvailability` below is what keeps each event on
    // its own share of it.
    final eventSnap = await Refs.competitions(orgId)
        .where('tournamentId', isEqualTo: tournamentId)
        .get();
    final events = eventSnap.docs.map(Competition.fromDoc).toList();
    if (events.isEmpty) {
      throw const ValidationException(
        'This tournament has no events yet.',
      );
    }

    // ---- Venues, and this season's plan for each of them. ----
    final venues = await _venuesOf(orgId, tournament, events);
    if (venues.isEmpty) {
      throw const ValidationException(
        'This tournament has no usable courts. Add a venue with at least '
        'one court, or mark an existing court available.',
      );
    }
    final plans = await _venuePlansOf(orgId, tournamentId);

    // ---- What each event is allowed, on its own. ----
    //
    // A multi-sport season is several tournaments sharing a fortnight and
    // a set of grounds, and until this existed it was scheduled as though
    // it were one: one pool of courts, one day window, every sport
    // eligible for every court in the district. The badminton could be
    // called to the cricket field.
    //
    // Everything below is a restriction on the shared grid rather than a
    // grid of its own — that is what keeps a player entered in three
    // sports from being booked onto three courts at once, which is the
    // whole reason a season is scheduled in one pass.
    final availabilityFor = <String, EventAvailability>{
      for (final event in events)
        event.id: availabilityOf(event, tournament),
    };

    final matches = <SchedulableMatch>[];
    final fixturesByKey = <String, Fixture>{};

    for (final event in events) {
      final fSnap = await Refs.fixtures(orgId, event.id).get();
      final fixtures = fSnap.docs.map(Fixture.fromDoc).toList();

      // Individual events name their competitors on the entrant document
      // rather than in a line-up, so the uid has to come from there.
      final entrantSnap = await Refs.entrants(orgId, event.id).get();
      final uidByEntrant = <String, List<String>>{};
      final teamByEntrant = <String, String>{};
      for (final doc in entrantSnap.docs) {
        final entrant = Entrant.fromDoc(doc);
        uidByEntrant[doc.id] = entrant.uid != null
            ? [entrant.uid!]
            : entrant.memberUids;
        // The persistent team behind this entry, which is the only side
        // identity that survives leaving one draw — an entrant id is
        // scoped to its own competition and says nothing across a season.
        final teamId = entrant.teamId;
        if (teamId != null && teamId.isNotEmpty) {
          teamByEntrant[doc.id] = teamId;
        }
      }

      for (final f in fixtures) {
        // Played or playing — the timetable does not get to move it.
        if (f.status != FixtureStatus.scheduled || f.lastSeq > 0) continue;

        final uids = <String>{
          ...f.playerUids,
          ...?uidByEntrant[f.entrantAId],
          ...?uidByEntrant[f.entrantBId],
        };

        matches.add(SchedulableMatch(
          compId: event.id,
          matchIndex: f.matchIndex,
          round: f.round,
          playerUids: uids,
          teamKeys: {
            ...?_maybe(teamByEntrant[f.entrantAId]),
            ...?_maybe(teamByEntrant[f.entrantBId]),
          },
          sportId: event.sportId,
          isGroupStage: f.bracket == Bracket.group,
          // Younger age groups first, so children are not kept at a
          // venue until the evening waiting on a senior draw.
          priority: _priorityFor(event),
          matchMinutes:
              matchMinutesOverride ?? event.scheduleConfig.matchMinutes,
          availability:
              availabilityFor[event.id] ?? EventAvailability.anywhere,
        ));
        fixturesByKey['${event.id}#${f.matchIndex}'] = f;
      }
    }

    if (matches.isEmpty) {
      throw const ValidationException(
        'No unplayed matches to schedule. Generate the draws first.',
      );
    }

    // How many days the grid has to cover. An event running past the
    // season's own last day extends it rather than losing its final
    // rounds.
    final gridDays = _gridDaysFor(
      tournament: tournament,
      start: start,
      availabilities: availabilityFor.values,
    );

    // ---- The resources, one calendar per playing area. ----
    //
    // Not one shared grid: a ground lent on five days of six, shut for
    // lunch, and capped at three matches a day is a different resource
    // from the hall next door, and a single uniform grid can express none
    // of it. `buildCalendars` folds the venue's own hours, this season's
    // sessions, its blackouts and its daily ceiling into the slots each
    // court actually offers.
    final calendars = SeasonCapacity.buildCalendars(
      seasonStart: start,
      dayCount: gridDays,
      venues: venues,
      plans: plans,
      defaultMatchMinutes:
          matchMinutesOverride ?? tournament.matchMinutesDefault,
      defaultTurnaroundMinutes: tournament.changeoverMinutes,
    );
    if (calendars.isEmpty) {
      throw const ValidationException(
        'No playing area is open on any day of this season. Check the '
        'venue availability — the dates, the sessions and the blackouts.',
      );
    }

    return (
      tournament: tournament,
      events: events,
      matches: matches,
      fixturesByKey: fixturesByKey,
      calendars: calendars,
      minRest: Duration(minutes: tournament.restGapMinutes),
      transition: Duration(minutes: tournament.venueTransitionMinutes),
    );
  }

  // --- The cross-event schedule ----------------------------------------

  /// Lays out every match of every event in [tournamentId] across the courts
  /// of its venues, and writes the result back onto the fixtures.
  ///
  /// ## Why this reads everything before it writes anything
  ///
  /// The three constraints that matter are all global — courts are shared
  /// between events, players are shared between events, and the day is shared
  /// by everything. None of them can be evaluated from inside one draw, so the
  /// whole tournament is loaded, scheduled in one pass, and written back.
  ///
  /// ## Players, not entrants
  ///
  /// Clash detection keys on player uid, gathered from each fixture's line-ups
  /// and from the entrant documents of individual events. That is the point of
  /// the exercise: the same person is a different `Entrant` in the singles,
  /// the doubles and the mixed, so an entrant-keyed check sees three unrelated
  /// competitors and cheerfully books them onto three courts at once.
  Future<TournamentScheduleReport> generateSchedule({
    required String orgId,
    required String tournamentId,

    /// Replaces every event's own `matchMinutes` for this solve.
    ///
    /// Per-event match length is the right default — a U-13 singles and a
    /// men's doubles final are not the same match — so this stays null on
    /// every automatic path. It is set only when the organizer answered the
    /// tournament-wide timing dialog, where naming one duration for the whole
    /// meet is precisely what they were asked for.
    int? matchMinutesOverride,
  }) =>
      guard(() async {
        final plan = await _loadPlan(
          orgId: orgId,
          tournamentId: tournamentId,
          matchMinutesOverride: matchMinutesOverride,
        );
        final matches = plan.matches;
        final calendars = plan.calendars;
        final fixturesByKey = plan.fixturesByKey;
        final events = plan.events;
        final minRest = plan.minRest;
        final transition = plan.transition;
        final schedule = const TournamentScheduler().schedule(
          matches: matches,
          calendars: calendars,
          minRestBetweenMatches: minRest,
          venueTransition: transition,
        );

        // The promises, checked rather than asserted in a comment. A clash
        // that reaches an organizer is discovered at the venue by the person
        // standing on the wrong court, so the schedule is verified before it
        // is written and a violation refuses the write outright.
        //
        // Refusing is the right response even though it means no schedule:
        // the previous timetable is still intact and still correct, whereas a
        // published one with a double-booking in it has already been read,
        // shared and acted on by the time anybody notices.
        final violations = ScheduleGuarantees.verify(
          matches: matches,
          schedule: schedule,
          minRestBetweenMatches: minRest,
          calendars: calendars,
          venueTransition: transition,
        );
        if (violations.isNotEmpty) {
          throw ValidationException(
            'The schedule was rejected because it broke a guarantee, so '
            'nothing was changed. ${violations.take(3).join('; ')}'
            '${violations.length > 3 ? ' (+${violations.length - 3} more)' : ''}',
          );
        }

        // ---- Write it back. ----
        final batch = ChunkedBatch(Refs.db);
        for (final entry in schedule.placements.entries) {
          final fixture = fixturesByKey[entry.key];
          if (fixture == null) continue;
          batch.update(
            Refs.fixture(orgId, fixture.compId, fixture.id),
            {
              'scheduledAt': Timestamp.fromDate(entry.value.window.start),
              'courtId': entry.value.court.courtName,
              'venue': entry.value.court.venueName,
              // The ids beside the names, so the timetable can be checked
              // against the real resource later — a manual move, or a health
              // report — without matching two display names.
              'courtRefId': entry.value.court.courtId,
              'venueId': entry.value.court.venueId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        batch.update(Refs.tournament(orgId, tournamentId), {
          'status': TournamentStatus.scheduled.wire,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        unawaited(batch.commitAll().catchError((Object e) {
          _writeFailures.add(_translate(e));
        }));

        return TournamentScheduleReport(
          scheduled: schedule.placements.length,
          unscheduled: schedule.unplaced.length,
          courts: calendars.length,
          events: events.length,
          finishesAt: schedule.finishesAt,
          problems: {
            for (final u in schedule.unplaced) u.reason,
          }.toList(),
        );
      });

  /// Checks the timetable that is actually stored, rather than the one that
  /// was generated.
  ///
  /// ## Why these are different questions
  ///
  /// `generateSchedule` verifies its own output and refuses to write a broken
  /// one, which makes a freshly generated timetable sound by construction. It
  /// does not stay sound: an organizer moves a match, a ground withdraws a
  /// day, a session is shortened, an event's dates change. Every one of those
  /// is a legitimate action that can invalidate a timetable nobody has looked
  /// at since, and until this existed nothing ever asked again.
  ///
  /// So this reads the fixtures back and runs the same guarantees over them.
  /// It is the "Schedule Health" panel, and it is the check behind every
  /// manual move.
  Future<ScheduleHealthReport> checkScheduleHealth({
    required String orgId,
    required String tournamentId,
  }) =>
      guard(() async {
        final plan = await _loadPlan(
          orgId: orgId,
          tournamentId: tournamentId,
        );
        return _healthOf(plan, overrides: const {});
      });

  /// Moves one match to another time, another court, or both — and refuses a
  /// move that would break the timetable unless the organizer insists.
  ///
  /// ## Why this refuses rather than warns
  ///
  /// A manual move is the organizer's right and most of them are correct: a
  /// team asks for a later start, a ground frees up. The one that is not
  /// correct is invisible — moving a badminton semi-final to 17:00 is fine
  /// until you know the same player is in the table-tennis doubles at 17:00,
  /// which is a fact about a different event on a different page. Refusing by
  /// default puts that fact in front of the person making the change, at the
  /// moment they can still choose differently.
  ///
  /// [force] is the deliberate second press. It exists because an organizer at
  /// a ground sometimes knows something the data does not, and a system that
  /// cannot be overridden gets worked around with a piece of paper.
  Future<ScheduleHealthReport> moveFixture({
    required String orgId,
    required String tournamentId,
    required String compId,
    required String fixtureId,
    DateTime? newStart,
    String? venueId,
    String? courtRefId,
    bool force = false,
  }) =>
      guard(() async {
        if (newStart == null && venueId == null) {
          throw const ValidationException(
            'Say a new time, a new court, or both.',
          );
        }

        final plan = await _loadPlan(orgId: orgId, tournamentId: tournamentId);

        Fixture? target;
        String? targetKey;
        for (final entry in plan.fixturesByKey.entries) {
          if (entry.value.id == fixtureId && entry.value.compId == compId) {
            target = entry.value;
            targetKey = entry.key;
            break;
          }
        }
        if (target == null || targetKey == null) {
          throw const NotFoundException(
            'That match is not part of this season\'s draft timetable — it may '
            'already have been played.',
          );
        }

        final start = newStart ?? target.scheduledAt;
        if (start == null) {
          throw const ValidationException(
            'This match has no time yet, so give it one.',
          );
        }

        CourtRef? court;
        if (venueId != null && courtRefId != null) {
          for (final c in plan.calendars) {
            if (c.court.venueId == venueId && c.court.courtId == courtRefId) {
              court = c.court;
              break;
            }
          }
          if (court == null) {
            throw const ValidationException(
              'That playing area is not open to this season.',
            );
          }
        }

        final health = _healthOf(
          plan,
          overrides: {targetKey: (start: start, court: court)},
        );
        final blocking = [
          for (final v in health.violations)
            if (v.matchKeys.contains(targetKey)) v,
        ];
        if (blocking.isNotEmpty && !force) {
          throw ValidationException(
            'That move breaks the timetable, so nothing was changed. '
            '${blocking.take(3).map((v) => v.detail).join('; ')}',
          );
        }

        await Refs.fixture(orgId, compId, fixtureId).update({
          'scheduledAt': Timestamp.fromDate(start),
          if (court != null) ...{
            'courtId': court.courtName,
            'venue': court.venueName,
            'courtRefId': court.courtId,
            'venueId': court.venueId,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return health;
      });

  /// Runs the guarantees over the timetable as stored, optionally with one
  /// match moved — which is how a move is tested before it is written.
  ScheduleHealthReport _healthOf(
    _SeasonPlan plan, {
    required Map<String, ({DateTime start, CourtRef? court})> overrides,
  }) {
    final calendarByKey = {for (final c in plan.calendars) c.court.key: c};
    final placements = <String, Placement>{};
    final extraCalendars = <String, CourtCalendar>{};
    var unscheduled = 0;
    var unverifiable = 0;

    for (final match in plan.matches) {
      final fixture = plan.fixturesByKey[match.key];
      final override = overrides[match.key];
      final start = override?.start ?? fixture?.scheduledAt;
      if (fixture == null || start == null) {
        unscheduled++;
        continue;
      }

      var court = override?.court;
      if (court == null) {
        final key = '${fixture.venueId}/${fixture.courtRefId}';
        court = calendarByKey[key]?.court;
        if (court == null) {
          // Placed by hand, or before the ids were stored. It still has a
          // court in the sense that matters to a player, so it is checked for
          // clashes — but nothing can say whether that court was open, so it
          // gets an unbounded calendar rather than a false violation.
          court = CourtRef(
            venueId: fixture.venueId ?? 'unknown',
            venueName: fixture.venue ?? 'Venue',
            courtId: fixture.courtRefId ?? (fixture.courtId ?? 'court'),
            courtName: fixture.courtId ?? 'Court',
          );
          if (!calendarByKey.containsKey(court.key)) {
            extraCalendars.putIfAbsent(
              court.key,
              () => CourtCalendar(court: court!, slotStarts: const []),
            );
            unverifiable++;
          }
        }
      }

      placements[match.key] = Placement(
        court: court,
        window: ScheduleWindow(
          start: start,
          end: start.add(Duration(minutes: match.matchMinutes)),
        ),
      );
    }

    final violations = ScheduleGuarantees.verify(
      matches: plan.matches,
      schedule: TournamentSchedule(
        placements: placements,
        unplaced: const [],
      ),
      minRestBetweenMatches: plan.minRest,
      calendars: [...plan.calendars, ...extraCalendars.values],
      venueTransition: plan.transition,
    );

    return ScheduleHealthReport(
      scheduled: placements.length,
      unscheduled: unscheduled,
      unverifiable: unverifiable,
      violations: violations,
    );
  }

  /// Moves the whole remaining schedule, keeping the plan intact.
  ///
  /// The operation an organizer needs when a day slips. Everything the
  /// scheduler solved — courts, order, rest gaps, round dependencies — is
  /// *relative*, so an hour's delay makes none of it wrong; only the clock is
  /// wrong. Regenerating would re-solve the whole allocation and could hand a
  /// player a different court and a different position in the order for
  /// reasons they cannot see. This keeps the announced plan and moves it
  /// bodily, which is what "we are running an hour late" means to everyone
  /// standing in the hall.
  ///
  /// Pass [newStart] to say "we are starting at half past ten now" — the
  /// offset is computed from the earliest match still to be played. Pass [by]
  /// to nudge everything a fixed amount. Pass [from] to leave a morning that
  /// ran to time alone and move only what is left.
  Future<ShiftPlan> shiftSchedule({
    required String orgId,
    required String tournamentId,
    Duration? by,
    DateTime? newStart,
    DateTime? from,
  }) =>
      guard(() async {
        if (by == null && newStart == null) {
          throw const ValidationException(
            'Say either a new start time or how long to move by.',
          );
        }

        final snap = await Refs.allFixturesQuery
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final fixtures = snap.docs.map(Fixture.fromDoc).toList();

        final plan = newStart != null
            ? ScheduleShift.planNewStart(
                fixtures: fixtures,
                newStart: newStart,
              )
            : ScheduleShift.plan(fixtures: fixtures, by: by!, from: from);

        if (plan.isEmpty) return plan;

        final byId = {for (final f in fixtures) f.id: f};
        final batch = ChunkedBatch(Refs.db);
        for (final entry in plan.moves.entries) {
          final fixture = byId[entry.key]!;
          batch.update(
            Refs.fixture(orgId, fixture.compId, fixture.id),
            {
              'scheduledAt': Timestamp.fromDate(entry.value),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        unawaited(batch.commitAll().catchError((Object e) {
          _writeFailures.add(_translate(e));
        }));

        return plan;
      });

  /// Younger age groups go first.
  ///
  /// Encoded from the category's upper age bound rather than its label,
  /// because "U-13 Boys" and "Under 13 Boys" are the same constraint spelled
  /// two ways and an organizer should not have to spell it either way.
  static int _priorityFor(Competition event) {
    final maxAge = event.category.maxAge;
    if (maxAge == null) return 100;
    return maxAge;
  }

  /// The grounds, days and hours one event of a season is confined to.
  ///
  /// Every field is a restriction relative to the season, and every one of
  /// them is dropped when it merely restates it. That is what keeps this
  /// change invisible to the seasons that already exist: an event whose
  /// `scheduleConfig.venueIds` is the season's own list, whose dates are the
  /// season's own dates and whose hours are the season's own hours produces
  /// [EventAvailability.anywhere] and schedules exactly as it did before.
  ///
  /// Dates come off the COMPETITION rather than the schedule config because
  /// that is where they already live and where the event page already reads
  /// them from — an event that says "12–13 September" on its own page and
  /// then gets scheduled on the 15th is a bug whichever of the two is right.
  /// Public because it is the translation worth testing on its own: every
  /// promise this feature makes rests on turning two stored documents into
  /// the right restriction, and the schedule that comes out of a wrong one is
  /// wrong in a way nobody can see by reading it.
  @visibleForTesting
  static EventAvailability availabilityOf(
    Competition event,
    Tournament tournament,
  ) {
    final config = event.scheduleConfig;

    // Only a genuine subset restricts anything. An event listing every ground
    // the season has is not choosing one.
    final seasonVenues = tournament.venueIds.toSet();
    final eventVenues = config.venueIds.toSet();
    final venueIds = eventVenues.isEmpty ||
            (eventVenues.length >= seasonVenues.length &&
                eventVenues.containsAll(seasonVenues))
        ? const <String>{}
        : eventVenues;

    // A start on the season's own opening day is not a restriction, and
    // treating it as one would pin every legacy event to day one.
    final start = event.startDate;
    final seasonStart = tournament.startDate;
    final firstDay = (start == null ||
            seasonStart == null ||
            !start.isAfter(seasonStart))
        ? null
        : start;

    final end = event.endDate;
    final seasonEnd = tournament.endDate;
    final lastDay =
        (end == null || (seasonEnd != null && !end.isBefore(seasonEnd)))
            ? null
            : end;

    return EventAvailability(
      venueIds: venueIds,
      firstDay: firstDay,
      lastDay: lastDay,
      // Applied as written, with no "is this the default" test. The
      // single-event scheduler in `CompetitionRepository` has always built
      // its grid straight from these two numbers; a tournament that instead
      // took the union of its buildings' opening hours was the odd one out,
      // and it is why a season whose form said 09:00–19:00 could still put a
      // match on at seven in the morning because one ground unlocks then.
      dayStartHour: config.dayStartHour,
      dayEndHour: config.dayEndHour,
    );
  }
}

/// The state of a timetable as it actually stands.
///
/// The panel behind "Publish": an organizer is entitled to see, in one place,
/// that nobody is double-booked before they send the schedule to two hundred
/// people. Zeroes across the board is the whole point — a health check that
/// only ever appears when something is wrong teaches nobody to trust it.
class ScheduleHealthReport {
  const ScheduleHealthReport({
    required this.scheduled,
    required this.unscheduled,
    required this.unverifiable,
    required this.violations,
  });

  final int scheduled;

  /// Matches still without a time — waiting on a feeder result, or never
  /// placed.
  final int unscheduled;

  /// Matches on a court that cannot be resolved to a venue document, so the
  /// venue-side checks could not run on them. Placed by hand, or scheduled
  /// before the court ids were stored.
  final int unverifiable;

  final List<ScheduleViolation> violations;

  bool get isHealthy => violations.isEmpty;

  int countOf(ScheduleViolationKind kind) {
    var n = 0;
    for (final v in violations) {
      if (v.kind == kind) n++;
    }
    return n;
  }

  /// The first few details of one kind, for a panel that names the problem
  /// rather than only counting it.
  List<String> detailsOf(ScheduleViolationKind kind, {int limit = 3}) => [
        for (final v in violations)
          if (v.kind == kind) v.detail,
      ].take(limit).toList();
}

/// What one scheduling run produced, in the terms an organizer decides on.
class TournamentScheduleReport {
  const TournamentScheduleReport({
    required this.scheduled,
    required this.unscheduled,
    required this.courts,
    required this.events,
    required this.finishesAt,
    required this.problems,
  });

  final int scheduled;
  final int unscheduled;
  final int courts;
  final int events;

  /// When the last match is due to end — the number an organizer actually
  /// wants, and the one nothing could answer before.
  final DateTime? finishesAt;

  /// Distinct reasons, deduplicated: forty matches blocked by the same
  /// missing court is one problem, not forty.
  final List<String> problems;

  bool get isComplete => unscheduled == 0;
}

/// What one press of "set up the whole season" actually did.
class SeasonSetupReport {
  const SeasonSetupReport({
    required this.eventsDrawn,
    required this.eventsSkipped,
    required this.schedule,
  });

  final int eventsDrawn;

  /// Events left alone, each with the reason — "Under-13 Singles: 1 entered,
  /// needs at least 2". Surfaced in full rather than counted, because the
  /// organizer's next action depends on which event and why.
  final List<String> eventsSkipped;

  final TournamentScheduleReport schedule;

  bool get isClean => eventsSkipped.isEmpty && schedule.isComplete;
}
