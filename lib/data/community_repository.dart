import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/announcement.dart';
import '../core/models/challenge.dart';
import '../core/models/competition.dart';
import '../core/models/enums.dart';
import '../core/models/firestore_codec.dart';
import '../core/models/fixture.dart';
import '../core/models/looking_for_post.dart';
import '../core/models/sub_group.dart';
import '../core/models/tournament.dart';
import '../domain/scoring/scoring_registry.dart';
import 'org_repository.dart' show guardStream;

/// Central repository for Module A — Clubs & Communities core OS features.
class CommunityRepository {
  const CommunityRepository({FirebaseFirestore? firestore}) : _db = firestore;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore => _db ?? Refs.db;

  // --- Sub-Groups --------------------------------------------------------

  Future<void> createSubGroup(SubGroup group) async {
    await Refs.subGroups(group.orgId).add(group.toCreate());
  }

  Stream<List<SubGroup>> watchSubGroups(String orgId) {
    return Refs.subGroups(orgId).snapshots().map((snap) =>
        snap.docs.map((d) => SubGroup.fromDoc(d.data(), d.id)).toList());
  }

  // --- Announcements Feed -----------------------------------------------

  Future<void> createAnnouncement(Announcement announcement) async {
    await Refs.announcements(announcement.orgId).add(announcement.toCreate());
  }

  /// Casting or changing a vote in a club poll.
  ///
  /// Written as a single field update on the votes map rather than a
  /// read-modify-write of the whole poll: two members voting at the same
  /// moment would otherwise each write back the map they read, and the second
  /// would erase the first. Dotted field paths let Firestore merge them.
  ///
  /// Passing a null [optionIndex] withdraws a vote entirely — someone who said
  /// they were coming and now cannot should be able to say so.
  Future<void> voteInPoll({
    required String orgId,
    required String announcementId,
    required String uid,
    required int? optionIndex,
  }) async {
    await Refs.announcement(orgId, announcementId).update({
      'poll.votes.$uid': optionIndex ?? FieldValue.delete(),
    });
  }

  /// Closes a poll to further votes. The result stays visible — a closed poll
  /// is the record of what the club decided, not something to be tidied away.
  Future<void> closePoll({
    required String orgId,
    required String announcementId,
  }) async {
    await Refs.announcement(orgId, announcementId).update({
      'poll.closed': true,
    });
  }

  Stream<List<Announcement>> watchAnnouncements(String orgId) {
    return Refs.announcements(orgId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Announcement.fromDoc(d.data(), d.id))
            .toList());
  }

  // --- Match availability calls -----------------------------------------
  //
  // Deliberately thin. A match call IS an announcement with a poll and four
  // extra facts (see [MatchCall]), so creating one is [createAnnouncement]
  // with the options filled in, and voting on one is [voteInPoll] unchanged.
  // Nothing below re-implements either — the vote path in particular is a
  // single dotted-field write that two members can make simultaneously
  // without erasing each other, and a second copy of it would be a second
  // chance to get that wrong.

  /// Publishes "who is free on Sunday", with the answers already set.
  ///
  /// The options are not the organizer's to choose. Three fixed answers is
  /// what makes every card in the feed readable at a glance and what lets the
  /// clash check know which index means yes — see [Rsvp]. An organizer who
  /// wants a different question is asking for an ordinary poll, which the club
  /// feed already offers.
  Future<void> createMatchRsvp({
    required String orgId,
    required String authorUid,
    required String authorName,
    required String title,
    required String content,
    required MatchCall match,
  }) =>
      createAnnouncement(
        Announcement(
          id: '',
          orgId: orgId,
          authorUid: authorUid,
          authorName: authorName,
          title: title,
          content: content,
          match: match,
          poll: const Poll(options: Rsvp.options),
        ),
      );

  /// Asks a club who is free for a match that already EXISTS.
  ///
  /// ## Why this is not just [createMatchRsvp] with more arguments
  ///
  /// It is, mechanically — and that is the point. A club call and a squad
  /// call are the same question ("who is free on Sunday?") asked about two
  /// different things, and making them two document shapes would mean two
  /// feeds, two cards and two places for a member to answer. So this posts an
  /// ordinary availability call onto the club's own board, carrying a
  /// [FixtureCallTarget] that says which match and which side the answers are
  /// for.
  ///
  /// Everything a member sees is unchanged: the call appears on their feed
  /// and they tap "In". What changes is that the organizer can then move the
  /// yeses onto the team sheet in one action instead of retyping twelve
  /// names — which is the whole reason the availability call exists and the
  /// step that was missing for inter-club matches.
  ///
  /// Posted on [orgId]'s board — the club ASKING — while the fixture it
  /// points at lives under whichever club is hosting. A visiting club polls
  /// its own members about a match at somebody else's ground, which is the
  /// ordinary case and the reason the target carries all four ids.
  Future<void> createSquadCallRsvp({
    required String orgId,
    required String authorUid,
    required String authorName,
    required String title,
    required String content,
    required MatchCall match,
    required FixtureCallTarget target,
  }) =>
      createMatchRsvp(
        orgId: orgId,
        authorUid: authorUid,
        authorName: authorName,
        title: title,
        content: content,
        match: MatchCall(
          sportId: match.sportId,
          matchDate: match.matchDate,
          venue: match.venue,
          maxPlayers: match.maxPlayers,
          forFixture: target,
        ),
      );

  /// Asks a club who is in for a challenge that has not been agreed yet.
  ///
  /// ## Why this happens before the opponent answers
  ///
  /// A challenge used to be settled entirely between two admins: one issued
  /// it, the other accepted, and the members of both clubs found out they had
  /// a match when somebody messaged them. By then the date was fixed, and a
  /// captain who then could not raise eleven had to go back and apologise for
  /// a fixture their own club had agreed to.
  ///
  /// Asking first inverts that. The call goes out on the challenging club's
  /// own board the moment the challenge is sent, so by the time the opponent
  /// replies the captain already knows who is travelling — and the accept is
  /// a decision made with the squad in hand rather than a hope.
  ///
  /// [invitedUids] is the other half of it. See [MatchCall.invitedUids]: a
  /// club with a hundred members asking all hundred about an eleven-a-side
  /// match gets a hundred answers and a squad it still has to choose by hand.
  /// Empty asks everybody, which stays the default.
  ///
  /// Posted on [orgId]'s board — whichever of the two clubs is asking. Both
  /// can, independently, and neither sees the other's answers.
  Future<void> createChallengeRsvp({
    required String orgId,
    required String authorUid,
    required String authorName,
    required String title,
    required String content,
    required MatchCall match,
    required ChallengeCallTarget target,
    List<String> invitedUids = const [],
  }) =>
      createMatchRsvp(
        orgId: orgId,
        authorUid: authorUid,
        authorName: authorName,
        title: title,
        content: content,
        match: MatchCall(
          sportId: match.sportId,
          matchDate: match.matchDate,
          venue: match.venue,
          maxPlayers: match.maxPlayers,
          forChallenge: target,
          invitedUids: invitedUids,
        ),
      );

  /// Corrects a call that is already out.
  ///
  /// ## Why the answers survive an edit
  ///
  /// The obvious alternative — cancel and re-post — throws away every vote,
  /// and the votes are the expensive part: fourteen people have already read
  /// a notification and tapped. A ground moved from one end of the village to
  /// the other does not un-ask "are you free on Sunday", so the poll is left
  /// exactly where it is and only the facts about the match change.
  ///
  /// Written as dotted field paths rather than as a whole `match` map, for the
  /// same reason [voteInPoll] is: a wholesale write of the block would carry
  /// back the `invitedUids` and `forChallenge` the editor never saw and had no
  /// business restating.
  ///
  /// The clock is the one thing an edit must be careful with. `onMatchRsvp`
  /// deliberately re-notifies nobody on an update — see its `if (!before)`
  /// guard — so a member whose Sunday just moved to Saturday finds out from
  /// the card, not from a push. Callers say so on screen.
  Future<void> updateMatchCall({
    required String orgId,
    required String announcementId,
    String? title,
    String? content,
    DateTime? matchDate,
    String? venue,
    int? maxPlayers,
  }) async {
    final patch = <String, dynamic>{
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (matchDate != null) 'match.matchDate': Timestamp.fromDate(matchDate),
      if (venue != null) 'match.venue': venue,
      if (maxPlayers != null) 'match.maxPlayers': maxPlayers,
    };
    if (patch.isEmpty) return;
    await Refs.announcement(orgId, announcementId).update(patch);
  }

  /// Calls a match off.
  ///
  /// Deletes rather than closes, and that is the distinction against
  /// [closePoll]. A closed poll is a decision the club made and wants to keep
  /// reading; a cancelled match is a question that turned out not to apply,
  /// and leaving it on the feed with a "cancelled" badge means every member
  /// who opens their home screen for the next four days has to re-read a
  /// fixture that is not happening to work out that it is not happening.
  ///
  /// The discussion under it goes too — Firestore does not cascade, so the
  /// subcollection is cleared first, or its messages would outlive the card
  /// they belong to and be unreachable forever.
  Future<void> cancelMatchCall({
    required String orgId,
    required String announcementId,
  }) async {
    final comments =
        await Refs.matchComments(orgId, announcementId).limit(400).get();
    if (comments.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final d in comments.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await Refs.announcement(orgId, announcementId).delete();
  }

  /// The club's match calls, newest first, with the ones already played
  /// dropped.
  ///
  /// Filtered in Dart rather than by a `where` clause on purpose. A compound
  /// query on `match.matchDate` plus the existing `createdAt` ordering needs
  /// its own composite index, and this collection is a club's notice board —
  /// tens of documents, not thousands — so the read is the same one
  /// [watchAnnouncements] already makes and the feed costs nothing extra.
  Stream<List<Announcement>> watchMatchRsvps(String orgId) =>
      watchAnnouncements(orgId).map(
        (all) => [
          for (final a in all)
            if (a.isMatchRsvp && !_isPast(a)) a,
        ],
      );

  /// A match stays on the feed until it has actually been played.
  ///
  /// The grace period is the point: a card that vanishes at kick-off vanishes
  /// exactly when the people standing at the ground are looking at it to find
  /// out who else is coming.
  static bool _isPast(Announcement a) {
    final when = a.match?.matchDate;
    if (when == null) return true;
    return DateTime.now().difference(when) > const Duration(hours: 4);
  }

  /// The discussion under a match call, oldest first — the order a chat reads.
  Stream<List<MatchChatMessage>> watchMatchComments({
    required String orgId,
    required String announcementId,
  }) =>
      guardStream(
        () => Refs.matchComments(orgId, announcementId)
            .orderBy('createdAt')
            .snapshots()
            .map((snap) => snap.docs
                .map((d) => MatchChatMessage.fromDoc(d.data(), d.id))
                .toList()),
      );

  /// Posts a line to the discussion.
  ///
  /// Not awaited by its caller, and it must not be: this is typed at a ground
  /// on a phone with one bar, and Firestore does not resolve a write until the
  /// SERVER acknowledges it. The local cache has the message immediately and
  /// the listener above renders it, so the thread moves at the speed of the
  /// keyboard rather than the speed of the signal.
  Future<void> sendMatchComment({
    required String orgId,
    required String announcementId,
    required String senderUid,
    required String senderName,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await Refs.matchComments(orgId, announcementId).add(
      MatchChatMessage(
        id: '',
        senderUid: senderUid,
        senderName: senderName,
        text: trimmed,
      ).toCreate(),
    );
  }

  // --- RSVP & Waitlist Auto-Promotion ------------------------------------

  /// Withdraws or cancels a user's registration and automatically promotes
  /// the oldest waitlisted registration to confirmed.
  Future<void> withdrawAndPromoteWaitlist({
    required String orgId,
    required String compId,
    required String uid,
  }) async {
    final regRef = Refs.registration(orgId, compId, uid);
    final doc = await regRef.get();
    if (!doc.exists) return;

    final currentStatus = doc.data()?['status'] as String?;

    await regRef.update({'status': RegistrationStatus.withdrawn.wire});

    // If the withdrawing user occupied a confirmed slot, promote oldest waitlisted
    if (currentStatus == RegistrationStatus.confirmed.wire ||
        currentStatus == RegistrationStatus.pending.wire) {
      final waitlistedSnap = await Refs.registrations(orgId, compId)
          .where('status', isEqualTo: RegistrationStatus.waitlisted.wire)
          .orderBy('createdAt')
          .limit(1)
          .get();

      if (waitlistedSnap.docs.isNotEmpty) {
        final oldestWaitlistDoc = waitlistedSnap.docs.first;
        await oldestWaitlistDoc.reference.update({
          'status': RegistrationStatus.confirmed.wire,
        });
      }
    }
  }

  // --- Inter-Club Challenges --------------------------------------------

  /// Issues a challenge and hands back the id it was written under.
  ///
  /// The id is returned rather than discarded because the caller's very next
  /// act is to ask its own club who is in, and a [ChallengeCallTarget] cannot
  /// be built without it. Before this returned anything, the availability call
  /// could only be posted later, by hand, from the challenge card — which is
  /// how a club ended up agreeing a date its members had never been asked
  /// about.
  Future<String> createChallenge(Challenge challenge) async {
    final doc = await Refs.challenges.add(challenge.toCreate());
    return doc.id;
  }

  /// Challenges involving [orgId], in either direction.
  ///
  /// Server-side filtered. This used to call `Refs.challenges.snapshots()` and
  /// filter in Dart, which billed every client for a read of every challenge on
  /// the platform and leaked other clubs' negotiations into memory. Two `where`
  /// clauses under `Filter.or` push both directions to the server, so a village
  /// club with three challenges downloads three documents.
  ///
  /// Guarded, like every other stream that feeds a screen. Unguarded, a
  /// rejection arrived at the Notifications screen as a raw
  /// `FirebaseException` and was rendered as "Something went wrong. Please
  /// try again." — the fallback for a failure nobody modelled, next to four
  /// sections that could name theirs.
  Stream<List<Challenge>> watchChallengesForOrg(String orgId) {
    return guardStream(
      () => Refs.challenges
          .where(Filter.or(
            Filter('fromOrgId', isEqualTo: orgId),
            Filter('toOrgId', isEqualTo: orgId),
          ))
          .snapshots()
          .map((snap) => snap.docs.map(Challenge.fromDoc).toList()),
    );
  }

  /// Accepts a challenge and creates the competition and fixture the two clubs
  /// will actually play.
  ///
  /// ## Why the accepting club hosts the match
  ///
  /// Competitions live at `orgs/{orgId}/competitions/{compId}` — a path that
  /// names exactly one owner. The previous implementation wrote the fixture
  /// under the *challenging* club, into a hardcoded `'inter_club_league'`
  /// competition that no code ever created. Both halves of that were broken:
  ///
  /// 1. The person accepting is an admin of the *challenged* club, so
  ///    `canManageCompetitions(fromOrgId)` was false and the batch was rejected
  ///    with `permission-denied` every single time. The feature had never
  ///    worked, and because the UI defaulted failed reads to empty lists, it
  ///    failed silently.
  /// 2. Even with the write allowed, the parent competition did not exist, so
  ///    the fixture would have been unreachable from every screen — standings,
  ///    the match list and the spectator view all descend from a competition.
  ///
  /// Hosting under the accepting club fixes both without a special case: the
  /// acceptor is writing inside their own tenant, exactly like any other
  /// competition they create. The challenging club's access comes from
  /// [Competition.participantOrgIds], which the security rules read to widen
  /// visibility to both sides — so a real competition doc means standings,
  /// scoring, undo, the live spectator link and Glicko settlement all work on
  /// an inter-club friendly with no code that knows it is one.
  ///
  /// Returns the created competition so the caller can navigate straight to it.
  /// Accepts a challenge, creating one competition and one fixture per leg.
  ///
  /// ## Why this returns the FIRST competition and not the only one
  ///
  /// A challenge used to be one sport, so accepting it produced one match and
  /// the caller navigated to it. A multi-sport challenge produces several —
  /// table tennis singles, badminton doubles, a cricket match — and they are
  /// one afternoon between two clubs, not three unrelated events that happen
  /// to share a date.
  ///
  /// So when there is more than one leg they are grouped under a tournament,
  /// exactly as a season groups its sports, and `createdTournamentId` on the
  /// challenge points at it. The first competition is still returned because
  /// that is what a single-sport accept means and it keeps every existing
  /// caller correct; multi-sport callers should navigate to the tournament.
  ///
  /// One batch for all of it. A partial accept — two of three matches created,
  /// the challenge left `pending` — would leave both clubs looking at
  /// different truths about what they had agreed to play.
  Future<Competition> acceptChallenge({
    required Challenge challenge,
    required DateTime selectedSlot,
    required String acceptedByUid,
  }) async {
    // Accepting a date that was never on the table would produce a fixture
    // one club never agreed to. Checked against `liveSlots` so that after a
    // counter-offer it is the counter's dates that count — the original
    // proposal is history at that point, and accepting one of its dates would
    // be agreeing with nobody.
    if (challenge.liveSlots.isNotEmpty &&
        !challenge.liveSlots.any((s) => s.isAtSameMomentAs(selectedSlot))) {
      throw const ValidationException(
        'That date is not one of the dates on offer. Pick one of the '
        'proposed slots.',
      );
    }

    // The club that accepted hosts; the club that issued the challenge is the
    // visitor. Side A is the challenger, which keeps "A v B" reading the same
    // way the challenge itself was worded.
    final hostOrgId = challenge.toOrgId;
    final guestOrgId = challenge.fromOrgId;
    final participants = [guestOrgId, hostOrgId];

    final legs = challenge.resolvedLegs((id) => SportCatalog.byId(id).name);
    final batch = _firestore.batch();

    // Only a multi-leg challenge gets a container. A single match under a
    // tournament of one is a layer of navigation for nothing.
    String? tournamentId;
    if (legs.length > 1) {
      final tRef = Refs.tournaments(hostOrgId).doc();
      tournamentId = tRef.id;
      batch.set(tRef, {
        'orgId': hostOrgId,
        'name': '${challenge.fromOrgName} v ${challenge.toOrgName}',
        'status': TournamentStatus.scheduled.wire,
        'startDate': Fs.ts(selectedSlot),
        'endDate': Fs.ts(selectedSlot),
        'eventCount': legs.length,
        'createdBy': acceptedByUid,
        'participantOrgIds': participants,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    Competition? first;
    String? firstFixtureId;

    for (final leg in legs) {
      final sport = SportCatalog.byId(leg.sportId);
      // The arrangement the two clubs agreed — singles, doubles, 8-a-side —
      // layered over the sport's preset. This is what makes a doubles leg
      // actually scored as doubles rather than as singles with four names on
      // the sheet.
      final format = SideFormats.forSport(leg.sportId)
          .where((f) => f.id == leg.sideFormatId)
          .firstOrNull;
      final config = format == null
          ? sport.config
          : {...sport.config, ...format.configOverrides};

      final compRef = Refs.competitions(hostOrgId).doc();
      final competition = Competition(
        id: compRef.id,
        orgId: hostOrgId,
        // Named for the leg when there are several, so a list of three does
        // not read as the same event three times.
        name: legs.length == 1
            ? '${challenge.fromOrgName} v ${challenge.toOrgName}'
            : '${challenge.fromOrgName} v ${challenge.toOrgName} — ${leg.label}',
        sportId: leg.sportId,
        sportName: sport.name,
        archetype: sport.archetype,
        entrantType: sport.defaultEntrantType,
        // A single agreed match is a one-round knockout. Reusing the existing
        // format keeps the fixture on the same advancement and finalize paths
        // as every other match rather than inventing a parallel one.
        format: CompetitionFormat.knockout,
        status: CompetitionStatus.scheduled,
        category: const CompetitionCategory(label: 'Open'),
        scoringPluginKey: sport.pluginKey,
        // `liveVenue`, not `venue`: once the challenge has been countered the
        // ground on the table is the counter-offer's, and booking the match
        // at the originally-proposed ground would send two clubs to different
        // places on the same afternoon.
        venue: challenge.liveVenue,
        startDate: selectedSlot,
        maxEntrants: 2,
        entrantCount: 2,
        fixtureCount: 1,
        tournamentId: tournamentId,
        scoringConfig: format?.configOverrides ?? const {},
        participantOrgIds: participants,
        createdBy: acceptedByUid,
      );

      final fixRef = Refs.fixtures(hostOrgId, compRef.id).doc();
      final fixture = Fixture(
        id: fixRef.id,
        orgId: hostOrgId,
        compId: compRef.id,
        entrantAId: guestOrgId,
        entrantBId: hostOrgId,
        entrantAName: challenge.fromOrgName,
        entrantBName: challenge.toOrgName,
        status: FixtureStatus.scheduled,
        // §12 — carried so the match history can say this game came out of a
        // challenge rather than a tournament, which is the whole point of
        // recording a source. The id is the challenge's, not the
        // competition's: the competition here is an implementation detail
        // created to hold the fixture, and the challenge is the thing a
        // player would recognise.
        sourceType: MatchSource.challenge,
        sourceId: challenge.id,
        scheduledAt: selectedSlot,
        venue: challenge.liveVenue,
        // The accepting admin can score immediately, so an agreed match is
        // never blocked on a second assignment step. Either club can add more
        // scorers afterwards from the match list.
        scorerUids: [acceptedByUid],
        participantOrgIds: participants,
        scoringPluginKey: sport.pluginKey,
        sportId: leg.sportId,
        scoringConfig: config,
      );

      batch.set(compRef, competition.toCreate());
      batch.set(fixRef, fixture.toCreate());

      first ??= competition;
      firstFixtureId ??= fixRef.id;
    }

    batch.update(Refs.challenge(challenge.id), {
      'status': 'accepted',
      'createdFixtureId': firstFixtureId,
      'createdCompId': first!.id,
      'hostOrgId': hostOrgId,
      'createdTournamentId': tournamentId,
      'agreedSlot': Fs.ts(selectedSlot),
    });

    await batch.commit();
    return first;
  }

  /// Declines a challenge. Recorded rather than deleted so a club cannot
  /// re-issue the same challenge repeatedly and claim it was never answered.
  Future<void> declineChallenge(Challenge challenge) async {
    await Refs.challenge(challenge.id).update({'status': 'declined'});
  }

  /// Takes back a challenge the caller's club issued and the other club has
  /// not yet answered.
  ///
  /// The counterpart to [declineChallenge], and its absence was a real hole:
  /// a club that proposed three dates and then had its ground washed out
  /// could neither cancel nor amend, so the only way out was for the other
  /// club to decline an offer that was no longer real. Withdrawal is only
  /// possible while the challenge is `pending` — after acceptance there is a
  /// fixture in both clubs' schedules, and that is a match to be cancelled,
  /// not an offer to be retracted.
  Future<void> withdrawChallenge(Challenge challenge) async {
    if (!challenge.isPending) {
      throw const ValidationException(
        'This challenge has already been answered, so it can no longer be '
        'withdrawn.',
      );
    }
    await Refs.challenge(challenge.id).update({'status': 'withdrawn'});
  }

  /// Answers a challenge with different terms rather than a yes or a no.
  ///
  /// The common real answer to "play us on the 25th" is "yes, but the 26th",
  /// and without this the receiving club had to decline and issue a fresh
  /// challenge back — which lost the thread and read to the first club as a
  /// refusal.
  ///
  /// Guarded here as well as in `firestore.rules` so the caller gets a
  /// sentence rather than a permission error. The rules are what actually
  /// enforce it; this is what makes the failure legible.
  Future<void> counterChallenge(
    Challenge challenge, {
    required String byOrgId,
    required List<DateTime> slots,
    String? venue,
    String? note,
  }) async {
    if (!challenge.canCounterAs(byOrgId)) {
      throw ValidationException(
        challenge.isPending
            ? 'Only the club that was challenged can propose different terms.'
            : 'This challenge has already been answered.',
      );
    }
    if (slots.isEmpty) {
      throw const ValidationException(
        'Propose at least one date, or the other club has nothing to agree '
        'to.',
      );
    }
    await Refs.challenge(challenge.id).update(
      Challenge.counterUpdate(slots: slots, venue: venue, note: note),
    );
  }

  // --- Looking For Community Board ---------------------------------------

  Future<void> createLookingForPost(LookingForPost post) async {
    await Refs.lookingForPosts.add(post.toCreate());
  }

  Stream<List<LookingForPost>> watchLookingForPosts({
    String? sportId,
  }) {
    Query<Map<String, dynamic>> query = Refs.lookingForPosts
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true);

    if (sportId != null && sportId.isNotEmpty) {
      query = query.where('sportId', isEqualTo: sportId);
    }

    return query.snapshots().map(
        (snap) => snap.docs.map(LookingForPost.fromDoc).toList());
  }
}
