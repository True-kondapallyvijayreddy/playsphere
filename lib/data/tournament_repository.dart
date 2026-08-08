import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/chunked_batch.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/competition.dart';
import '../core/models/draw_slot.dart';
import '../core/models/enums.dart';
import '../core/models/fixture.dart';
import '../core/models/match_official.dart';
import '../core/models/ranking_entry.dart';
import '../core/models/tournament.dart';
import '../core/models/tournament_invite.dart';
import '../core/models/tournament_official.dart';
import '../core/models/venue.dart';
import '../domain/draw/officials_roster.dart';
import '../domain/draw/schedule_shift.dart';
import '../domain/draw/tournament_scheduler.dart';
import 'org_repository.dart' show guard;

/// Venues, tournaments, and the one operation that needs both: laying out
/// every match of every event across one shared pool of courts.
class TournamentRepository {
  const TournamentRepository();

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
            Refs.tournamentInvites.doc(),
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
  Stream<List<TournamentInvite>> watchIncomingInvites(String orgId) {
    return Refs.tournamentInvites
        .where('toOrgId', isEqualTo: orgId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map(TournamentInvite.fromDoc).toList()
          ..sort((a, b) => (a.startDate ?? DateTime(9999))
              .compareTo(b.startDate ?? DateTime(9999))));
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

          slots.add(OfficiatingSlot(
            fixtureId: f.id,
            window: ScheduleWindow(
              start: at,
              end: at.add(Duration(minutes: tournament.slotMinutes)),
            ),
            courtKey: f.courtId ?? f.venue ?? f.id,
            contestingClubIds: clubs,
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

  /// One player's ranking results, for their profile.
  Stream<List<RankingEntry>> watchPlayerRanking(String uid) {
    return Refs.rankingEntries
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(RankingEntry.fromDoc).toList()
          ..sort((a, b) => b.points.compareTo(a.points)));
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
  }) =>
      guard(() async {
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

        // ---- Courts, from real venue documents. ----
        final courts = <CourtRef>[];
        var openHour = 23;
        var closeHour = 0;
        for (final venueId in tournament.venueIds) {
          final vDoc = await Refs.venue(orgId, venueId).get();
          if (!vDoc.exists) continue;
          final venue = Venue.fromDoc(vDoc);
          if (venue.isArchived) continue;
          for (final court in venue.usableCourts) {
            courts.add(CourtRef(
              venueId: venue.id,
              venueName: venue.name,
              courtId: court.id,
              courtName: court.name,
            ));
          }
          // The union of the buildings' hours: a tournament runs as long as
          // any of its venues is open, and the per-court check is implicit in
          // a court only existing while its venue does.
          if (venue.openHour < openHour) openHour = venue.openHour;
          if (venue.closeHour > closeHour) closeHour = venue.closeHour;
        }
        if (courts.isEmpty) {
          throw const ValidationException(
            'This tournament has no usable courts. Add a venue with at least '
            'one court, or mark an existing court available.',
          );
        }

        // ---- Every event, and every fixture in it. ----
        final eventSnap = await Refs.competitions(orgId)
            .where('tournamentId', isEqualTo: tournamentId)
            .get();
        final events = eventSnap.docs.map(Competition.fromDoc).toList();
        if (events.isEmpty) {
          throw const ValidationException(
            'This tournament has no events yet.',
          );
        }

        final matches = <SchedulableMatch>[];
        final fixturesByKey = <String, Fixture>{};

        for (final event in events) {
          final fSnap = await Refs.fixtures(orgId, event.id).get();
          final fixtures = fSnap.docs.map(Fixture.fromDoc).toList();

          // Individual events name their competitors on the entrant document
          // rather than in a line-up, so the uid has to come from there.
          final entrantSnap = await Refs.entrants(orgId, event.id).get();
          final uidByEntrant = <String, List<String>>{
            for (final doc in entrantSnap.docs)
              if (Entrant.fromDoc(doc).uid != null)
                doc.id: [Entrant.fromDoc(doc).uid!]
              else
                doc.id: Entrant.fromDoc(doc).memberUids,
          };

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
              isGroupStage: f.bracket == Bracket.group,
              // Younger age groups first, so children are not kept at a
              // venue until the evening waiting on a senior draw.
              priority: _priorityFor(event),
              matchMinutes: event.scheduleConfig.matchMinutes,
            ));
            fixturesByKey['${event.id}#${f.matchIndex}'] = f;
          }
        }

        if (matches.isEmpty) {
          throw const ValidationException(
            'No unplayed matches to schedule. Generate the draws first.',
          );
        }

        final slots = TournamentScheduler.buildSlots(
          firstDay: start,
          dayCount: tournament.dayCount,
          openHour: openHour > closeHour ? 9 : openHour,
          closeHour: closeHour <= openHour ? 19 : closeHour,
          slotMinutes: tournament.slotMinutes,
        );

        final schedule = const TournamentScheduler().schedule(
          matches: matches,
          courts: courts,
          slots: slots,
          minRestBetweenMatches:
              Duration(minutes: tournament.restGapMinutes),
        );

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
          courts: courts.length,
          events: events.length,
          finishesAt: schedule.finishesAt,
          problems: {
            for (final u in schedule.unplaced) u.reason,
          }.toList(),
        );
      });

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
