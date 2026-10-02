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
import '../core/models/firestore_codec.dart';
import '../core/models/match_official.dart';
import '../core/models/club_registration_request.dart';
import '../core/models/club_standing.dart';
import '../core/models/ranking_entry.dart';
import '../core/models/tournament.dart';
import '../core/models/season_interest.dart';
import '../core/models/season_nomination.dart';
import '../core/models/tournament_invite.dart';
import '../core/models/tournament_official.dart';
import '../core/models/venue.dart';
import '../core/models/venue_plan.dart';
import '../domain/draw/draft_season_plan.dart';
import '../domain/draw/match_count.dart';
import '../domain/draw/officials_roster.dart';
import '../domain/draw/schedule_guarantees.dart';
import '../domain/draw/schedule_shift.dart';
import '../domain/draw/season_capacity.dart';
import '../domain/draw/tournament_scheduler.dart';
import '../domain/tournament/house_roster.dart';
import '../domain/tournament/season_blueprint.dart';
import '../domain/tournament/season_date_shift.dart';
import '../domain/tournament/season_name.dart';
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

  /// Refuses [name] when it is too short, too long, or already held by
  /// another live season of [orgId] — see [SeasonName].
  ///
  /// Every create and rename goes through this. The forms check the club's
  /// seasons they already hold as the organizer types; this asks the server,
  /// so a season made on another phone a minute ago counts too.
  ///
  /// Settles for the local cache when the server does not answer in a few
  /// seconds. Seasons are created offline-first (see [createSeason]), and an
  /// organizer at a ground with no signal must not be refused because the
  /// check could not reach anybody.
  Future<void> ensureSeasonNameFree({
    required String orgId,
    required String name,
    String? exceptId,
    String noun = 'season',
  }) async {
    final shape = SeasonName.problem(name, noun: noun);
    if (shape != null) throw ValidationException(shape);

    final query = Refs.tournaments(orgId)
        .where('nameLower', isEqualTo: SeasonName.key(name))
        .limit(10);
    Iterable<Tournament> same;
    try {
      same = (await query.get().timeout(const Duration(seconds: 4)))
          .docs
          .map(Tournament.fromDoc);
    } catch (_) {
      try {
        same = (await query.get(const GetOptions(source: Source.cache)))
            .docs
            .map(Tournament.fromDoc);
      } catch (_) {
        same = const [];
      }
    }
    final problem = SeasonName.problem(
      name,
      noun: noun,
      taken: SeasonName.takenKeys(same, exceptId: exceptId),
    );
    if (problem != null) throw ValidationException(problem);
  }

  Future<String> createTournament(Tournament tournament) => guard(() async {
        await ensureSeasonNameFree(
          orgId: tournament.orgId,
          name: tournament.name,
          noun: tournament.kind.noun,
        );
        tournament = tournament.copyWith(
          name: SeasonName.normalize(tournament.name),
        );
        final ref = Refs.tournaments(tournament.orgId).doc();
        unawaited(ref.set(tournament.toCreate()).catchError((Object e) {
          _writeFailures.add(_translate(e));
        }));
        return ref.id;
      });

  /// Creates a whole season — its new grounds, the season, every event, the
  /// per-ground terms and the officiating panel — in ONE atomic commit.
  ///
  /// ## Why one commit
  ///
  /// It used to be a dozen separate writes in sequence, and each one could
  /// fail on its own. A dropped connection on the ninth event left a season
  /// with eight, the form still open, and a second press of Create made a
  /// second season. A rules rejection went to a stream nobody listened to,
  /// so the organizer was sent to a season page that then vanished. A batch
  /// is applied entirely or not at all, which makes "half a season" a state
  /// the database cannot be in.
  ///
  /// ## Why the commit is not awaited
  ///
  /// Awaiting a Firestore write waits for the SERVER. An organizer setting a
  /// season up from a school ground on a patchy 4G signal would sit on a
  /// spinner until the signal came back. The batch is applied to the local
  /// cache the instant it is queued, so the season page opens immediately and
  /// shows everything; the commit lands when the phone reconnects. A genuine
  /// rejection rolls the whole season back and is reported on
  /// [writeFailures], which the app shell turns into a message.
  ///
  /// [committed] completes when the server has the season, for work that
  /// genuinely needs it there first — artwork, whose storage path is checked
  /// against the season document.
  ///
  /// The returned future only waits for the name check
  /// ([ensureSeasonNameFree]), which gives up on the server after a few
  /// seconds. It never waits for the commit.
  ///
  /// The season is published as it is written: entries are open on the
  /// season and on every event from the first moment. See
  /// [SeasonBlueprint.tournament].
  Future<({String seasonId, Future<void> committed})> createSeason({
    required SeasonBlueprint blueprint,
    required List<SeasonGround> grounds,
    List<TournamentOfficial> officials = const [],
    DateTime? now,
  }) async {
    final problems = blueprint.problems(now: now);
    if (problems.isNotEmpty) throw ValidationException(problems.first);
    await ensureSeasonNameFree(orgId: blueprint.orgId, name: blueprint.name);

    final orgId = blueprint.orgId;
    final newGrounds = [
      for (final g in grounds)
        if (g.isNew) g,
    ];
    final plans = [
      for (final g in grounds)
        if (!g.plan.isUnrestricted) g,
    ];
    final writes = newGrounds.length +
        1 +
        blueprint.categories.length +
        plans.length +
        officials.length;
    if (writes > 500) {
      throw const ValidationException(
        'This season is too large to create in one go. Create it with fewer '
        'categories or officials and add the rest from the season page.',
      );
    }

    final batch = Refs.db.batch();
    for (final ground in newGrounds) {
      if (ground.venue.id.isEmpty) {
        throw const ValidationException(
          'A new ground has no id yet. Pick the grounds again.',
        );
      }
      batch.set(Refs.venue(orgId, ground.venue.id), ground.venue.toCreate());
    }

    final seasonRef = Refs.tournaments(orgId).doc();
    batch.set(seasonRef, blueprint.tournament().toCreate());

    for (final event in blueprint.events(seasonRef.id)) {
      batch.set(
        Refs.competitions(orgId).doc(),
        event.toCreate(openForEntries: true),
      );
    }
    for (final ground in plans) {
      batch.set(
        Refs.venuePlan(orgId, seasonRef.id, ground.venue.id),
        ground.plan
            .rekeyed(ground.venue.id)
            .copyWith(venueName: ground.venue.name)
            .toMap(),
      );
    }
    for (final official in officials) {
      batch.set(
        Refs.tournamentOfficial(orgId, seasonRef.id, official.uid),
        official.toCreate(addedBy: blueprint.createdBy),
      );
    }

    final seasonName = blueprint.trimmedName;
    final committed = batch.commit().catchError((Object e) {
      final reason = _translate(e);
      // Named, because this can arrive minutes later on another screen, and
      // "You do not have permission" alone does not say what was refused.
      _writeFailures.add(ValidationException(
        '"$seasonName" was not saved — ${reason.message} Nothing from it was '
        'created, so you can set it up again.',
      ));
      throw e;
    });
    // Nobody may be awaiting it; an unobserved rejection must not surface as
    // an uncaught async error on top of the message already sent.
    unawaited(committed.catchError((_) {}));
    return (seasonId: seasonRef.id, committed: committed);
  }

  /// A one-sport tournament: the season container with [event] as its only
  /// draw, written together.
  ///
  /// A tournament used to be stored as a bare competition, which put it on
  /// the event page and outside every season feature — sport panels, the
  /// umpire panel, the venue planner, club invitations. Written this way it
  /// opens on the season page like any season, and everything built for
  /// seasons from here on reaches it without anybody remembering to. See
  /// [SeasonKind].
  ///
  /// The container is derived from the event rather than typed twice, so the
  /// two can never disagree about the dates or the grounds. Fees stay on the
  /// event ([SeasonFeeMode.perEvent]) because that is where both tournament
  /// forms already put them, and a later category added to the tournament
  /// gets a price of its own.
  ///
  /// Not awaited on the server, for the reason [createSeason] is not: the
  /// batch is applied to the local cache at once, and a genuine rejection is
  /// reported on [writeFailures]. The future waits only for the name check.
  ///
  /// Published as it is written, like a season: entries open at once.
  Future<({String tournamentId, String compId, Future<void> committed})>
      createSingleSportTournament({
    required Competition event,
    required String createdBy,
    String? shortName,
  }) async {
    final name = SeasonName.normalize(event.name);
    final orgId = event.orgId;
    await ensureSeasonNameFree(orgId: orgId, name: name, noun: 'tournament');
    final tournamentRef = Refs.tournaments(orgId).doc();
    final compRef = Refs.competitions(orgId).doc();
    final trimmedShort = shortName?.trim();

    final container = Tournament(
      id: tournamentRef.id,
      orgId: orgId,
      name: name,
      kind: SeasonKind.tournament,
      shortName:
          trimmedShort == null || trimmedShort.isEmpty ? null : trimmedShort,
      // Published at once, like a season, with its one event taking entries
      // in the same commit.
      status: TournamentStatus.entriesOpen,
      startDate: event.startDate,
      endDate: event.endDate ?? event.startDate,
      entryDeadline: event.registrationClosesAt,
      venueIds: List.of(event.scheduleConfig.venueIds),
      eventCount: 1,
      feeMode: SeasonFeeMode.perEvent,
      matchMinutesDefault: event.scheduleConfig.matchMinutes,
      changeoverMinutes: event.scheduleConfig.changeoverMinutes,
      restGapMinutes: event.scheduleConfig.restGapMinutes,
      createdBy: createdBy,
    );

    final batch = Refs.db.batch();
    batch.set(tournamentRef, container.toCreate());
    batch.set(
      compRef,
      event
          .copyWith(
            tournamentId: tournamentRef.id,
            name: name,
            status: CompetitionStatus.registrationOpen,
          )
          .toCreate(openForEntries: true),
    );

    final committed = batch.commit().catchError((Object e) {
      final reason = _translate(e);
      _writeFailures.add(ValidationException(
        '"$name" was not saved — ${reason.message} Nothing from it was '
        'created, so you can set it up again.',
      ));
      throw e;
    });
    unawaited(committed.catchError((_) {}));
    return (
      tournamentId: tournamentRef.id,
      compId: compRef.id,
      committed: committed,
    );
  }

  /// Saves [tournament] over [before], the season as the caller last read
  /// it. The name rules apply only when this renames it — see
  /// [SeasonName.isRename].
  Future<void> updateTournament(
    Tournament tournament, {
    required Tournament before,
  }) =>
      guard(() async {
        if (SeasonName.isRename(before.name, tournament.name)) {
          await ensureSeasonNameFree(
            orgId: tournament.orgId,
            name: tournament.name,
            exceptId: tournament.id,
            noun: tournament.kind.noun,
          );
        }
        await Refs.tournament(tournament.orgId, tournament.id).update(
          tournament
              .copyWith(name: SeasonName.toStore(before.name, tournament.name))
              .toUpdate(),
        );
      });

  /// Saves the season edit sheet, and keeps its events inside the dates.
  ///
  /// ## Why the events move too
  ///
  /// Every event carries its own `startDate`/`endDate`, and the scheduler
  /// reads a date that differs from the season's as a restriction. So moving
  /// a season used to strand its events: postpone a sports week by seven days
  /// for the monsoon and every event still "started" on the old Monday —
  /// inside the new span, so each was quietly pinned to a single day, or
  /// outside it, so nothing could be scheduled at all.
  ///
  /// - The whole season moved by N days (start and end shifted together):
  ///   every event's own window moves by N as well. That is a postponement,
  ///   and "badminton on the Saturday" is still the Saturday.
  /// - Only the span changed: an event that followed the season's first day
  ///   follows the new one, and a window that now falls outside the season is
  ///   put back to following the season rather than left unschedulable.
  ///
  /// Completed and cancelled events are part of the record and never move.
  /// Timetabled fixtures are not touched — the season page's shift and
  /// regenerate tools own match times.
  ///
  /// Each event keeps its own time of day on its new date (see
  /// [SeasonDateShift]). When that is still not what the organizer wants,
  /// an event's start date and time can be set by hand from its edit
  /// dialog on the season page.
  ///
  /// Returns how many events had their dates moved, so the sheet can tell
  /// the organizer to check them.
  Future<int> updateSeasonDetails({
    required Tournament before,
    required Tournament after,
  }) =>
      guard(() async {
        // Only a rename is checked. An old season whose name predates the
        // rules must still be movable — see [SeasonName.isRename].
        if (SeasonName.isRename(before.name, after.name)) {
          await ensureSeasonNameFree(
            orgId: after.orgId,
            name: after.name,
            exceptId: after.id,
            noun: after.kind.noun,
          );
        }
        final season =
            after.copyWith(name: SeasonName.toStore(before.name, after.name));
        final oldStart = _dayOrNull(before.startDate);
        final newStart = _dayOrNull(season.startDate);
        final oldEnd = _dayOrNull(before.endDate) ?? oldStart;
        final newEnd = _dayOrNull(season.endDate) ?? newStart;
        if (oldStart != null && newStart != null && newEnd != null &&
            newEnd.isBefore(newStart)) {
          throw const ValidationException(
            'The season cannot end before it starts.',
          );
        }

        final seasonRef = Refs.tournament(season.orgId, season.id);
        final datesMoved = oldStart != newStart || oldEnd != newEnd;
        if (!datesMoved || oldStart == null || newStart == null) {
          await seasonRef.update(season.toUpdate());
          return 0;
        }

        final eventSnap = await Refs.competitions(season.orgId)
            .where('tournamentId', isEqualTo: season.id)
            .get();
        final batch = ChunkedBatch(Refs.db);
        batch.update(seasonRef, season.toUpdate());

        var movedCount = 0;
        for (final doc in eventSnap.docs) {
          final event = Competition.fromDoc(doc);
          if (event.status == CompetitionStatus.completed ||
              event.status == CompetitionStatus.cancelled) {
            continue;
          }
          final moved = SeasonDateShift.moveEvent(
            eventStart: event.startDate,
            eventEnd: event.endDate,
            oldStart: oldStart,
            oldEnd: oldEnd!,
            newStart: newStart,
            newEnd: newEnd!,
          );
          if (moved.start == event.startDate && moved.end == event.endDate) {
            continue;
          }
          movedCount++;
          batch.update(Refs.competition(season.orgId, event.id), {
            'startDate': Fs.ts(moved.start),
            'endDate': Fs.ts(moved.end),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commitAll();
        return movedCount;
      });

  /// Sets one event's start (date and time) and last day by hand — the
  /// organizer's word over [SeasonDateShift]'s guess after a season moves.
  ///
  /// Written as its own update, not through `Competition.toUpdate`, because
  /// that map drops nulls, and a null [end] is a real answer here: "runs to
  /// the season's last day".
  Future<void> setEventDates({
    required String orgId,
    required String compId,
    required DateTime? start,
    required DateTime? end,
  }) =>
      guard(() async {
        if (start != null && end != null && _dayOrNull(end)!.isBefore(_dayOrNull(start)!)) {
          throw const ValidationException(
            'The event cannot end before it starts.',
          );
        }
        await Refs.competition(orgId, compId).update({
          'startDate': Fs.ts(start),
          'endDate': Fs.ts(end),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  static DateTime? _dayOrNull(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  /// Names who is in charge of [sportId] in this season — or nobody, for an
  /// empty [leads]. See [Tournament.sportLeads].
  ///
  /// One field path, not the whole map, so two organizers assigning two
  /// different sports at the same moment do not overwrite each other.
  Future<void> setSportLeads({
    required String orgId,
    required String tournamentId,
    required String sportId,
    required List<SportLead> leads,
  }) =>
      guard(() => Refs.tournament(orgId, tournamentId).update({
            FieldPath(['sportLeads', sportId]): leads.isEmpty
                ? FieldValue.delete()
                : [for (final l in leads) l.toMap()],
            'updatedAt': FieldValue.serverTimestamp(),
          }));

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
  ///
  /// ## One sport at a time
  ///
  /// A season is several tournaments sharing a fortnight. Its cricket can be
  /// drawn, laid out and published while its badminton is still taking
  /// entries, and publishing it must not touch the badminton. So this
  /// publishes [sportId] alone. It records the moment in
  /// `sportSchedulesReleasedAt`, which the server announces to that sport's
  /// entrants. It locks the season as a whole only once every sport that
  /// plays matches has been published.
  Future<void> lockSchedule({
    required String orgId,
    required String tournamentId,
    required String sportId,
  }) =>
      guard(() async {
        final seasonSnap = await Refs.tournament(orgId, tournamentId).get();
        if (!seasonSnap.exists) {
          throw const NotFoundException('That season no longer exists.');
        }
        final season = Tournament.fromDoc(seasonSnap);
        final eventsSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final events = [
          for (final doc in eventsSnap.docs)
            if (Competition.fromDoc(doc).status != CompetitionStatus.cancelled)
              Competition.fromDoc(doc),
        ];
        final inSport = [
          for (final e in events)
            if (e.sportId == sportId) e,
        ];
        final sportName =
            inSport.isEmpty ? 'this sport' : inSport.first.sportName;
        if (inSport.isEmpty) {
          throw ValidationException('This season has no $sportName events.');
        }

        // Read every event before writing anything, so a sport that cannot
        // legally publish has not already half-published itself.
        final placeholderEvents = <String>[];
        var fixtureCount = 0;
        for (final event in inSport) {
          final fixtureSnap = await Refs.fixtures(orgId, event.id).get();
          fixtureCount += fixtureSnap.docs.length;
          final hasPlaceholder =
              fixtureSnap.docs.map(Fixture.fromDoc).any((f) => f.isDraft);
          if (hasPlaceholder) placeholderEvents.add(event.name);
        }

        if (fixtureCount == 0) {
          throw ValidationException(
            'There are no $sportName matches to publish yet. Generate the '
            'draws first.',
          );
        }

        if (placeholderEvents.isNotEmpty) {
          throw ValidationException(
            'These events still have a placeholder draw, not a real one: '
            '${placeholderEvents.join(', ')}. Generate the draw for each '
            'before publishing, or their entrants go out as "Team A".',
          );
        }

        // Every sport that plays matches. Track and field, recorded as marks,
        // has no timetable to publish and must not hold the season open.
        final timetabled = {
          for (final e in events)
            if (!e.format.isPerformanceFormat &&
                e.archetype != CompetitionArchetype.performance)
              e.sportId,
        };
        final released = {...season.sportSchedulesReleasedAt.keys, sportId};
        final wholeSeason = released.containsAll(timetabled);

        final batch = ChunkedBatch(Refs.db);
        // A dotted path, because a batch update takes string keys only. Sport
        // ids are catalogue ids (`table_tennis`), never user text, so they
        // hold no dot; the check keeps it that way.
        if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(sportId)) {
          throw ValidationException('"$sportId" is not a sport id.');
        }
        batch.update(Refs.tournament(orgId, tournamentId), {
          'sportSchedulesReleasedAt.$sportId': FieldValue.serverTimestamp(),
          if (wholeSeason) ...{
            'isScheduleLocked': true,
            'scheduleReleasedAt': FieldValue.serverTimestamp(),
            if (const {
              TournamentStatus.draft,
              TournamentStatus.entriesOpen,
              TournamentStatus.entriesClosed,
            }.contains(season.status))
              'status': TournamentStatus.scheduled.wire,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Only events that have not got further. Writing `scheduled` over one
        // already being played would put a live event back before its first
        // ball, and a completed one is refused by the rules — which used to
        // fail the whole publish.
        for (final event in inSport) {
          if (!const {
            CompetitionStatus.draft,
            CompetitionStatus.registrationOpen,
            CompetitionStatus.registrationClosed,
          }.contains(event.status)) {
            continue;
          }
          batch.update(Refs.competition(orgId, event.id), {
            'status': CompetitionStatus.scheduled.wire,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // Telling everybody is `onScheduleReleased`'s job, in
        // functions/index.js, and it fires off the new entry in
        // `sportSchedulesReleasedAt` this batch writes. A client cannot write
        // notifications (`allow create: if false`), and an earlier version
        // that tried failed the whole publish.
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
  ///
  /// Scoped to [sportId]. A match length chosen here is that sport's, so it
  /// is stored on the sport's own events. It lasts for the next time too,
  /// and doesn't reach any other sport. The changeover and the rest gap stay
  /// on the season, because courts and players are shared between sports.
  Future<TournamentScheduleReport> regenerateDraftSchedule({
    required String orgId,
    required String tournamentId,
    required String sportId,
    int? matchMinutes,
    int? changeoverMinutes,
    int? restGapMinutes,
  }) =>
      guard(() async {
        final overrides = <String, Object?>{
          if (changeoverMinutes != null) 'changeoverMinutes': changeoverMinutes,
          if (restGapMinutes != null) 'restGapMinutes': restGapMinutes,
        };
        // Awaited, unlike most writes here: `generateSchedule` re-reads the
        // season and its events on its first line, so a fire-and-forget write
        // would race the read it is meant to inform.
        final batch = ChunkedBatch(Refs.db);
        if (overrides.isNotEmpty) {
          batch.update(Refs.tournament(orgId, tournamentId), {
            ...overrides,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        if (matchMinutes != null) {
          final eventSnap = await Refs.competitions(orgId)
              .where('tournamentId', isEqualTo: tournamentId)
              .where('sportId', isEqualTo: sportId)
              .get();
          for (final doc in eventSnap.docs) {
            final status = Competition.fromDoc(doc).status;
            if (status == CompetitionStatus.completed ||
                status == CompetitionStatus.cancelled) {
              continue;
            }
            batch.update(doc.reference, {
              'scheduleConfig.matchMinutes': matchMinutes,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        await batch.commitAll();
        return generateSchedule(
          orgId: orgId,
          tournamentId: tournamentId,
          sportId: sportId,
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
          // The moment the season was published as a whole. The server sends
          // ONE "entries are open" message for the season off this, and each
          // event's own "now open" push stands down — a thirty-category
          // sports week used to send every member thirty-one notifications.
          'entriesOpenedAt': FieldValue.serverTimestamp(),
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
  ///
  /// Scoped to [sportId]: its events are drawn, and its matches placed around
  /// the timetable the season's other sports already have. Nothing of
  /// another sport is closed, drawn or moved.
  Future<SeasonSetupReport> setUpSport({
    required String orgId,
    required String tournamentId,
    required String sportId,
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
            .where('sportId', isEqualTo: sportId)
            .get();
        final events = eventSnap.docs.map(Competition.fromDoc).toList();
        if (events.isEmpty) {
          throw const ValidationException(
            'This season has no events in this sport yet.',
          );
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
          // Track, field and swimming are recorded as marks, not drawn into
          // matches — `generateDraw` refuses them. Checked FIRST, because the
          // close below is not undoable: this used to shut registration on
          // the 100m and only then discover it could not be drawn, so the
          // one button quietly locked out every athlete still to enter.
          if (event.format.isPerformanceFormat ||
              event.archetype == CompetitionArchetype.performance) {
            skipped.add('${event.name}: recorded as times and marks — '
                'entries stay as they are; score it from the event page');
            continue;
          }
          // Cancelled or suspended events are not part of the timetable.
          if (event.status == CompetitionStatus.cancelled || event.isSuspended) {
            skipped.add('${event.name}: '
                '${event.isSuspended ? 'on hold' : 'cancelled'}');
            continue;
          }

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
          sportId: sportId,
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

  /// Adds new sports to a season that already exists, and attaches existing
  /// events to it — in one atomic commit, with the event count kept true.
  ///
  /// The new events are built by [SeasonBlueprint], taking every setting an
  /// event of this season needs from the season and its existing events: the
  /// grounds, the hours, who may enter, the houses, how fees are charged.
  /// The sheet this serves used to create a bare `Competition` — no grounds,
  /// a 30-minute match for cricket, individual entry for a team sport, open
  /// to approval-only when the rest of the season was open — one sequential
  /// write at a time.
  Future<int> addSportsToSeason({
    required Tournament season,
    required List<SeasonCategorySpec> sports,
    List<String> attachCompIds = const [],
    required String createdBy,
  }) =>
      guard(() async {
        if (sports.isEmpty && attachCompIds.isEmpty) return 0;
        final orgId = season.orgId;
        final existing = (await Refs.competitions(orgId)
                .where('tournamentId', isEqualTo: season.id)
                .get())
            .docs
            .map(Competition.fromDoc)
            .where((e) => e.status != CompetitionStatus.cancelled)
            .toList();
        final template = existing.isEmpty ? null : existing.first;
        final names = {for (final e in existing) e.name.toLowerCase()};

        final blueprint = SeasonBlueprint(
          orgId: orgId,
          name: season.name,
          createdBy: createdBy,
          startDate: season.startDate,
          endDate: season.endDate,
          groundIds: season.venueIds,
          venueLabel: template?.venue,
          // Whole specs, not (sport, format) pairs. Pairs pinned every added
          // event to the sport's default arrangement and the Open category,
          // so a live season could never gain its Doubles or its U-17 — and
          // the refusal below sent the organizer to a season form that has
          // no categories section (test run TC-24).
          categories: sports,
          changeoverMinutes: season.changeoverMinutes,
          restGapMinutes: season.restGapMinutes,
          dayStartHour: template?.scheduleConfig.dayStartHour ?? 9,
          dayEndHour: template?.scheduleConfig.dayEndHour ?? 19,
          externalEntries: template?.openToNonMembers ?? false,
          feeMode: season.feeMode,
          presetHouses: template == null || template.presetHouses.isEmpty
              ? HouseTemplates.schoolColours
              : template.presetHouses,
        );
        final events = blueprint.events(season.id);
        for (final e in events) {
          if (names.contains(e.name.toLowerCase())) {
            throw ValidationException(
              '${e.name} is already in this season. Pick a different '
              'arrangement or category for it, or edit the existing event.',
            );
          }
        }

        // A published season takes entries on a sport the moment it is
        // added, like the sports it was created with. Only a season still in
        // draft (created before seasons were published on creation) keeps
        // its new sports as drafts for its own "Open entries" press.
        final open = season.status != TournamentStatus.draft;
        final attached = [
          for (final compId in attachCompIds)
            if (await Refs.competition(orgId, compId).get() case final doc
                when doc.exists)
              Competition.fromDoc(doc),
        ];

        final batch = Refs.db.batch();
        for (final e in events) {
          batch.set(
            Refs.competitions(orgId).doc(),
            e.toCreate(openForEntries: open),
          );
        }
        for (final compId in attachCompIds) {
          batch.update(Refs.competition(orgId, compId), {
            'tournamentId': season.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        batch.update(Refs.tournament(orgId, season.id), {
          'eventCount':
              FieldValue.increment(events.length + attachCompIds.length),
          ..._reopenForNewEvents(
            season: season,
            existing: existing,
            added: [...events, ...attached],
          ),
          // The first events of a season created empty. Nothing announced it
          // when it was created, because there was nothing to enter
          // (`onTournamentCreated` skips an empty season). Now there is, so
          // this is the season's one "entries are open" push —
          // `onTournamentPublished` fires off the stamp, and each new event's
          // own push stands down for it rather than sending one per sport.
          if (open && season.eventCount == 0 && existing.isEmpty)
            'entriesOpenedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
        return events.length + attachCompIds.length;
      });

  /// The season fields that take a published timetable back to draft for
  /// the sports [added] events belong to.
  ///
  /// ## Why adding an event reopens its sport
  ///
  /// A published sport's matches are final and its schedule page offers no
  /// way to draw or place anything. An event added to it afterwards — a new
  /// sport, or a new category of a sport already out — has no matches yet,
  /// and until this existed it could never get any: its panel read
  /// "Published", the Draw & schedule and Lock buttons were hidden, and the
  /// desk did not list it as unpublished. So the sport's release stamp is
  /// removed, it reads as a draft, and publishing it again announces the
  /// timetable again — which is right, because scheduling the sport
  /// re-places its unplayed matches.
  ///
  /// The season stops being wholly locked for the same reason, and a
  /// `scheduled` season goes back to taking entries, since the new events
  /// take entries. `lockSchedule` promotes it again when the last sport is
  /// published.
  ///
  /// A season published season-wide (no per-sport stamps) has every OTHER
  /// sport stamped here, so those stay published. `onScheduleReleased` knows
  /// that write for a backfill and announces nothing.
  ///
  /// Events recorded as times and marks have no timetable and reopen
  /// nothing.
  static Map<String, Object> _reopenForNewEvents({
    required Tournament season,
    required List<Competition> existing,
    required List<Competition> added,
  }) {
    bool timetabled(Competition e) =>
        !e.format.isPerformanceFormat &&
        e.archetype != CompetitionArchetype.performance;
    if (season.status == TournamentStatus.completed) return const {};
    final reopened = {
      for (final e in added)
        if (timetabled(e) && season.isSportScheduleLocked(e.sportId))
          e.sportId,
    };
    if (reopened.isEmpty) return const {};
    final validId = RegExp(r'^[A-Za-z0-9_]+$');

    final fields = <String, Object>{};
    if (season.sportSchedulesReleasedAt.isEmpty) {
      final releasedAt = season.scheduleReleasedAt;
      for (final sportId in {
        for (final e in existing)
          if (timetabled(e)) e.sportId,
      }) {
        if (reopened.contains(sportId) || !validId.hasMatch(sportId)) continue;
        fields['sportSchedulesReleasedAt.$sportId'] = releasedAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(releasedAt);
      }
    } else {
      for (final sportId in reopened) {
        if (!validId.hasMatch(sportId)) continue;
        fields['sportSchedulesReleasedAt.$sportId'] = FieldValue.delete();
      }
    }
    if (season.isScheduleLocked) fields['isScheduleLocked'] = false;
    if (season.status == TournamentStatus.scheduled) {
      fields['status'] = TournamentStatus.entriesOpen.wire;
    }
    return fields;
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
    List<String> sportNames = const [],
    String? place,
  }) =>
      guard(() async {
        final targets = [
          for (final c in clubs)
            if (c.orgId != tournament.orgId) c,
        ];
        if (targets.isEmpty) {
          throw const ValidationException('Pick at least one club to invite.');
        }

        if (targets.length > 450) {
          throw const ValidationException(
            'That is more clubs than one send can carry. Invite up to 450 '
            'at a time.',
          );
        }
        // Shaped to what the rules accept BEFORE the batch, so one long line
        // cannot refuse the invitation to every club at once. The letter is
        // refused with a reason rather than cut: it is the host's own words,
        // and silently losing its ending would send something they didn't
        // write. The composer's field already stops at the limit.
        final trimmed = message?.trim();
        if (trimmed != null &&
            trimmed.length > TournamentInvite.maxMessageLength) {
          throw ValidationException(
            'The invitation letter is ${trimmed.length} characters. Shorten '
            'it to ${TournamentInvite.maxMessageLength} or fewer and send '
            'again.',
          );
        }
        final trimmedPlace =
            TournamentInvite.fit(place, TournamentInvite.maxPlaceLength);
        final sports = TournamentInvite.fitSportNames(sportNames);

        // A club already waiting on an invitation, or already coming, is not
        // asked twice: the rules refuse overwriting a live one, and one refusal
        // would fail the whole send. A declined or withdrawn invitation is
        // sent again — the rules admit exactly that re-send.
        final existing = await Refs.tournamentInvites
            .where('fromOrgId', isEqualTo: tournament.orgId)
            .where('tournamentId', isEqualTo: tournament.id)
            .get();
        final live = {
          for (final doc in existing.docs)
            if (TournamentInvite.fromDoc(doc) case final i
                when i.isPending || i.isAccepted)
              i.toOrgId,
        };
        final toSend = [
          for (final club in targets)
            if (!live.contains(club.orgId)) club,
        ];
        if (toSend.isEmpty) {
          throw const ValidationException(
            'Every club you picked has already been invited.',
          );
        }

        final batch = Refs.db.batch();
        for (final club in toSend) {
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
              kind: tournament.kind,
              sportNames: List.unmodifiable(sports),
              place: trimmedPlace,
              startDate: tournament.startDate,
              endDate: tournament.endDate,
              invitedBy: invitedByUid,
            ).toCreate(),
          );
        }
        // Bounded: on web the commit can sit unacknowledged long after the
        // write is in the local cache and on screen as "invited", which left
        // the Send button spinning forever. A rules refusal arrives well
        // inside this window; past it the write is queued and will sync.
        try {
          await batch.commit().timeout(const Duration(seconds: 8));
        } on TimeoutException {
          // Queued locally.
        }
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

  /// Every invitation [orgId] has sent, to every club, for every season —
  /// the host's half of the invitations space, newest first.
  Stream<List<TournamentInvite>> watchSentInvites(String orgId) {
    return guardStream(
      () => Refs.tournamentInvites
          .where('fromOrgId', isEqualTo: orgId)
          .snapshots()
          .map((snap) => snap.docs.map(TournamentInvite.fromDoc).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(9999))
                .compareTo(a.createdAt ?? DateTime(9999)))),
    );
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

  // --- Club registration requests (uninvited club asking to enter) -------

  /// A club with no invite asking to bring a side into [tournament] —
  /// TC-CLUB-034. [viaCompId] is the specific open event the requester found
  /// this door through; the write is refused server-side unless that
  /// competition genuinely has `openToNonMembers == true`.
  Future<void> requestClubRegistration({
    required Tournament tournament,
    required String hostOrgName,
    required String viaCompId,
    required String requestingOrgId,
    required String requestingOrgName,
    required String requestedByUid,
    String? note,
  }) =>
      guard(() async {
        if (requestingOrgId == tournament.orgId) {
          throw const ValidationException(
            'You already run this season\'s host club.',
          );
        }
        final id = ClubRegistrationRequest.idFor(
          hostOrgId: tournament.orgId,
          tournamentId: tournament.id,
          requestingOrgId: requestingOrgId,
        );
        final existing = await Refs.clubRegistrationRequest(id).get();
        if (existing.exists &&
            ClubRegistrationRequest.fromDoc(existing).isPending) {
          throw const ValidationException(
            'You already have a request waiting on this host.',
          );
        }

        await Refs.clubRegistrationRequest(id).set(
          ClubRegistrationRequest(
            id: id,
            tournamentId: tournament.id,
            tournamentName: tournament.name,
            hostOrgId: tournament.orgId,
            hostOrgName: hostOrgName,
            requestingOrgId: requestingOrgId,
            requestingOrgName: requestingOrgName,
            viaCompId: viaCompId,
            status: 'pending',
            note: note?.trim().isEmpty == true ? null : note?.trim(),
            requestedBy: requestedByUid,
          ).toCreate(),
        );
      });

  /// Every uninvited club waiting on this season's host.
  Stream<List<ClubRegistrationRequest>> watchClubRegistrationRequests({
    required String hostOrgId,
    required String tournamentId,
  }) =>
      guardStream(
        () => Refs.clubRegistrationRequests
            .where('hostOrgId', isEqualTo: hostOrgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .snapshots()
            .map((s) => s.docs.map(ClubRegistrationRequest.fromDoc).toList()),
      );

  /// Whether [requestingOrgId] already has a live (pending) ask on this
  /// season, so the requesting club's own screen can show its status instead
  /// of offering to ask again.
  Stream<ClubRegistrationRequest?> watchMyClubRegistrationRequest({
    required String hostOrgId,
    required String tournamentId,
    required String requestingOrgId,
  }) =>
      guardStream(() => Refs.clubRegistrationRequest(
            ClubRegistrationRequest.idFor(
              hostOrgId: hostOrgId,
              tournamentId: tournamentId,
              requestingOrgId: requestingOrgId,
            ),
          ).snapshots().map(
            (s) => s.exists ? ClubRegistrationRequest.fromDoc(s) : null,
          ));

  /// The host's decision. Approving does not unlock entry by itself — it
  /// sends the requesting club an ordinary [TournamentInvite] via
  /// [inviteClubs], the one audited path everything else that lets a club
  /// enter a season already goes through; the requester still accepts it,
  /// exactly as any invited club does. Declining just records why.
  Future<void> decideClubRegistrationRequest({
    required Tournament tournament,
    required String hostOrgName,
    required ClubRegistrationRequest request,
    required bool approve,
    required String invitedByUid,
    String? declineReason,
  }) =>
      guard(() async {
        if (approve) {
          await inviteClubs(
            tournament: tournament,
            hostOrgName: hostOrgName,
            clubs: [
              (orgId: request.requestingOrgId, name: request.requestingOrgName),
            ],
            invitedByUid: invitedByUid,
          );
        }
        await Refs.clubRegistrationRequest(request.id).update({
          'status': approve ? 'approved' : 'declined',
          if (!approve) 'declineReason': declineReason?.trim(),
          'decidedAt': FieldValue.serverTimestamp(),
        });
      });

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

  /// Picks members for a draw their club cannot enter them into.
  ///
  /// The singles half of "Build our entry". A team draw's selection is its
  /// entry — the side is registered and the job is done — but a singles draw
  /// is entered by the player, so what the club can do is choose, record the
  /// choice, and tell them. See [SeasonNomination] for why that is a document
  /// rather than a message.
  ///
  /// One batch, so a secretary picking eight players sends one thing or
  /// nothing. The deterministic id makes re-picking the same person a rewrite
  /// rather than a second notification.
  Future<void> nominateForSeason({
    required String orgId,
    required String hostOrgId,
    required String tournamentId,
    required Competition competition,
    required List<String> uids,
    required String byUid,
    required String clubName,
    String? tournamentName,
  }) =>
      guard(() async {
        if (uids.isEmpty) return;
        final batch = Refs.db.batch();
        for (final uid in uids) {
          final id = SeasonNomination.idFor(
            hostOrgId: hostOrgId,
            tournamentId: tournamentId,
            compId: competition.id,
            uid: uid,
          );
          batch.set(
            Refs.seasonNominationDoc(orgId, id),
            SeasonNomination(
              id: id,
              orgId: orgId,
              hostOrgId: hostOrgId,
              tournamentId: tournamentId,
              compId: competition.id,
              uid: uid,
              nominatedByUid: byUid,
              compName: competition.name,
              tournamentName: tournamentName,
              clubName: clubName,
            ).toCreate(),
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      });

  /// Who this club has picked for a season, so the selection screen can show
  /// a tick beside somebody already chosen rather than picking them twice.
  Stream<List<SeasonNomination>> watchSeasonNominations({
    required String orgId,
    required String hostOrgId,
    required String tournamentId,
  }) {
    return guardStream(
      () => Refs.seasonNominations(orgId)
          .where('hostOrgId', isEqualTo: hostOrgId)
          .where('tournamentId', isEqualTo: tournamentId)
          .snapshots()
          .map((snap) => snap.docs.map(SeasonNomination.fromDoc).toList()),
    );
  }

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
        final uidsByEntrant = <String, List<String>>{};
        for (final compId in {for (final f in fixtures) f.compId}) {
          final entrantSnap = await Refs.entrants(orgId, compId).get();
          for (final doc in entrantSnap.docs) {
            final entrant = Entrant.fromDoc(doc);
            clubByEntrant[doc.id] = entrant.clubId;
            uidsByEntrant[doc.id] = <String>{
              if (entrant.uid != null) entrant.uid!,
              ...entrant.memberUids,
            }.toList();
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
            playerUids: {
              ...f.playerUids,
              if (f.entrantAUid != null) f.entrantAUid!,
              if (f.entrantBUid != null) f.entrantBUid!,
              ...?uidsByEntrant[f.entrantAId],
              ...?uidsByEntrant[f.entrantBId],
            },
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

        final seasonHours = SeasonCapacity.hoursOf(
          [for (final e in events) e.scheduleConfig],
        );
        final calendars = SeasonCapacity.buildCalendars(
          seasonStart: start,
          dayCount: gridDays,
          venues: venues,
          plans: plans,
          defaultMatchMinutes:
              matchMinutesOverride ?? tournament.matchMinutesDefault,
          defaultTurnaroundMinutes: tournament.changeoverMinutes,
          // The season's own playing hours, so an unplanned ground does not
          // contribute the sixteen-hour day its opening hours imply.
          dayStartHour: seasonHours?.startHour,
          dayEndHour: seasonHours?.endHour,
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

        final hours = SeasonCapacity.hoursOf(
          [for (final e in events) e.scheduleConfig],
        );

        return [
          for (final venue in venues)
            SeasonCapacity.lineFor(
              venue: venue,
              plan: plans[venue.id] ?? VenuePlan(venueId: venue.id),
              seasonStart: start,
              dayCount: tournament.dayCount,
              defaultMatchMinutes: tournament.matchMinutesDefault,
              defaultTurnaroundMinutes: tournament.changeoverMinutes,
              // Capacity over the season's playing hours, not the ground's
              // opening hours — a season running 08:00–20:00 was being costed
              // against a ground open 06:00–22:00.
              dayStartHour: hours?.startHour,
              dayEndHour: hours?.endHour,
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
        // Both: a team entrant carries its captain as `uid` AND its squad
        // as `memberUids`, and taking only the captain hid every other
        // member's clash with their own matches in other sports.
        uidByEntrant[doc.id] = <String>{
          if (entrant.uid != null) entrant.uid!,
          ...entrant.memberUids,
        }.toList();
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
    final seasonHours = SeasonCapacity.hoursOf(
      [for (final e in events) e.scheduleConfig],
    );
    final calendars = SeasonCapacity.buildCalendars(
      seasonStart: start,
      dayCount: gridDays,
      venues: venues,
      plans: plans,
      defaultMatchMinutes:
          matchMinutesOverride ?? tournament.matchMinutesDefault,
      defaultTurnaroundMinutes: tournament.changeoverMinutes,
      dayStartHour: seasonHours?.startHour,
      dayEndHour: seasonHours?.endHour,
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
  ///
  /// ## One sport at a time
  ///
  /// [sportId] narrows what is PLACED to that sport's events. Everything the
  /// season already has on its courts stays where it is and is passed to the
  /// scheduler as fixed. That covers other sports, including ones already
  /// published. A cricket timetable built this way can't take a court the
  /// badminton holds at 11:00, or call a player from their doubles to the
  /// nets, whatever order the sports were scheduled in. The guarantees are
  /// checked over the whole season, and a violation that involves this sport
  /// refuses the write.
  Future<TournamentScheduleReport> generateSchedule({
    required String orgId,
    required String tournamentId,
    required String sportId,

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
        final calendars = plan.calendars;
        final fixturesByKey = plan.fixturesByKey;
        final minRest = plan.minRest;
        final transition = plan.transition;

        final sportEventIds = {
          for (final e in plan.events)
            if (e.sportId == sportId) e.id,
        };
        final events = [
          for (final e in plan.events)
            if (sportEventIds.contains(e.id)) e,
        ];
        final matches = [
          for (final m in plan.matches)
            if (sportEventIds.contains(m.compId)) m,
        ];
        if (matches.isEmpty) {
          throw const ValidationException(
            'This sport has no unplayed matches to schedule. Generate its '
            'draws first.',
          );
        }
        final others = [
          for (final m in plan.matches)
            if (!sportEventIds.contains(m.compId)) m,
        ];
        final stored = _storedPlacements(plan, others);
        final fixed = [
          for (final m in others)
            if (stored.placements[m.key] != null)
              (match: m, placement: stored.placements[m.key]!),
        ];

        final schedule = const TournamentScheduler().schedule(
          matches: matches,
          calendars: calendars,
          minRestBetweenMatches: minRest,
          venueTransition: transition,
          courtTurnaround:
              Duration(minutes: plan.tournament.changeoverMinutes),
          fixed: fixed,
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
        //
        // Checked against the season as it will stand: this sport's new
        // placements beside every other sport's stored ones. Only violations
        // this sport is part of count. A clash between two other sports was
        // there before this press and is Schedule health's to report.
        final ownKeys = {for (final m in matches) m.key};
        final violations = [
          for (final v in ScheduleGuarantees.verify(
            matches: [...matches, for (final f in fixed) f.match],
            schedule: TournamentSchedule(
              placements: {
                for (final f in fixed) f.match.key: f.placement,
                ...schedule.placements,
              },
              unplaced: const [],
            ),
            minRestBetweenMatches: minRest,
            calendars: [...calendars, ...stored.extraCalendars],
            venueTransition: transition,
          ))
            if (v.matchKeys.any(ownKeys.contains)) v,
        ];
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

        // No season status here. A draft timetable is not a published one,
        // and writing `scheduled` made the season read as published the
        // moment a draft was generated. Publishing is `lockSchedule`'s.

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

  /// Where [matches] stand in the stored timetable, with [overrides] applied.
  ///
  /// A match with no time is left out. One placed by hand, or before court
  /// ids were stored, still has a court as far as a player is concerned. It
  /// is kept, on an unbounded calendar in [extraCalendars]: nothing can say
  /// whether that court was open, and a false violation is worse than none.
  ({Map<String, Placement> placements, List<CourtCalendar> extraCalendars})
      _storedPlacements(
    _SeasonPlan plan,
    Iterable<SchedulableMatch> matches, {
    Map<String, ({DateTime start, CourtRef? court})> overrides = const {},
  }) {
    final calendarByKey = {for (final c in plan.calendars) c.court.key: c};
    final placements = <String, Placement>{};
    final extra = <String, CourtCalendar>{};

    for (final match in matches) {
      final fixture = plan.fixturesByKey[match.key];
      final override = overrides[match.key];
      final start = override?.start ?? fixture?.scheduledAt;
      if (fixture == null || start == null) continue;

      var court = override?.court;
      if (court == null) {
        final key = '${fixture.venueId}/${fixture.courtRefId}';
        court = calendarByKey[key]?.court;
        if (court == null) {
          final fallback = CourtRef(
            venueId: fixture.venueId ?? 'unknown',
            venueName: fixture.venue ?? 'Venue',
            courtId: fixture.courtRefId ?? (fixture.courtId ?? 'court'),
            courtName: fixture.courtId ?? 'Court',
          );
          court = fallback;
          if (!calendarByKey.containsKey(fallback.key)) {
            extra.putIfAbsent(
              fallback.key,
              () => CourtCalendar(court: fallback, slotStarts: const []),
            );
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
    return (placements: placements, extraCalendars: extra.values.toList());
  }

  /// Runs the guarantees over the timetable as stored, optionally with one
  /// match moved — which is how a move is tested before it is written.
  ScheduleHealthReport _healthOf(
    _SeasonPlan plan, {
    required Map<String, ({DateTime start, CourtRef? court})> overrides,
  }) {
    final stored = _storedPlacements(plan, plan.matches, overrides: overrides);
    final placements = stored.placements;
    final extraCalendars = {
      for (final c in stored.extraCalendars) c.court.key: c,
    };
    final unscheduled = plan.matches.length - placements.length;
    final unverifiable = placements.values
        .where((p) => extraCalendars.containsKey(p.court.key))
        .length;

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

        // `orgId` is what AUTHORIZES this query, not merely what narrows it —
        // the same reason [watchTournamentFixtures] and `checkOfficial-
        // Availability` pin it. A collection-group `list` is authorised
        // against the QUERY rather than the documents it would return, so the
        // rules' `orgIsReadable(resource.data.orgId)` clause can only be
        // satisfied when the query itself names the org; filtering on
        // `tournamentId` alone left `orgId` unbound and the whole list was
        // refused. That reached the organizer as "You do not have permission
        // to do that in this organization" on their own season's rain-delay
        // tool, owner included (test run TC-ADM-023).
        final snap = await Refs.allFixturesQuery
            .where('orgId', isEqualTo: orgId)
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
