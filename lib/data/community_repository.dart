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

  Future<void> createChallenge(Challenge challenge) async {
    await Refs.challenges.add(challenge.toCreate());
  }

  /// Challenges involving [orgId], in either direction.
  ///
  /// Server-side filtered. This used to call `Refs.challenges.snapshots()` and
  /// filter in Dart, which billed every client for a read of every challenge on
  /// the platform and leaked other clubs' negotiations into memory. Two `where`
  /// clauses under `Filter.or` push both directions to the server, so a village
  /// club with three challenges downloads three documents.
  Stream<List<Challenge>> watchChallengesForOrg(String orgId) {
    return Refs.challenges
        .where(Filter.or(
          Filter('fromOrgId', isEqualTo: orgId),
          Filter('toOrgId', isEqualTo: orgId),
        ))
        .snapshots()
        .map((snap) => snap.docs.map(Challenge.fromDoc).toList());
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
        venue: challenge.venue,
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
        scheduledAt: selectedSlot,
        venue: challenge.venue,
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
