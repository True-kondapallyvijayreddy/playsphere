import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/announcement.dart';
import '../core/models/challenge.dart';
import '../core/models/competition.dart';
import '../core/models/enums.dart';
import '../core/models/firestore_codec.dart';
import '../core/models/fixture.dart';
import '../core/models/looking_for_post.dart';
import '../core/models/sub_group.dart';
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
  Future<Competition> acceptChallenge({
    required Challenge challenge,
    required DateTime selectedSlot,
    required String acceptedByUid,
  }) async {
    final sport = SportCatalog.byId(challenge.sportId);

    // The club that accepted hosts; the club that issued the challenge is the
    // visitor. Side A is the challenger, which keeps "A v B" reading the same
    // way the challenge itself was worded.
    final hostOrgId = challenge.toOrgId;
    final guestOrgId = challenge.fromOrgId;
    final participants = [guestOrgId, hostOrgId];

    final compRef = Refs.competitions(hostOrgId).doc();
    final competition = Competition(
      id: compRef.id,
      orgId: hostOrgId,
      name: '${challenge.fromOrgName} v ${challenge.toOrgName}',
      sportId: challenge.sportId,
      sportName: sport.name,
      archetype: sport.archetype,
      entrantType: sport.defaultEntrantType,
      // A single agreed match is a one-round knockout. Reusing the existing
      // format keeps the fixture on the same advancement and finalize paths as
      // every other match rather than inventing a parallel one.
      format: CompetitionFormat.knockout,
      status: CompetitionStatus.scheduled,
      category: const CompetitionCategory(label: 'Open'),
      scoringPluginKey: sport.pluginKey,
      venue: challenge.venue,
      startDate: selectedSlot,
      maxEntrants: 2,
      entrantCount: 2,
      fixtureCount: 1,
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
      // The accepting admin can score immediately, so an agreed match is never
      // blocked on a second assignment step. Either club can add more scorers
      // afterwards from the match list.
      scorerUids: [acceptedByUid],
      participantOrgIds: participants,
      scoringPluginKey: sport.pluginKey,
      sportId: challenge.sportId,
      scoringConfig: sport.config,
    );

    final batch = _firestore.batch();
    batch.set(compRef, competition.toCreate());
    batch.set(fixRef, fixture.toCreate());
    batch.update(Refs.challenge(challenge.id), {
      'status': 'accepted',
      'createdFixtureId': fixRef.id,
      'createdCompId': compRef.id,
      'hostOrgId': hostOrgId,
      'agreedSlot': Fs.ts(selectedSlot),
    });

    await batch.commit();
    return competition;
  }

  /// Declines a challenge. Recorded rather than deleted so a club cannot
  /// re-issue the same challenge repeatedly and claim it was never answered.
  Future<void> declineChallenge(Challenge challenge) async {
    await Refs.challenge(challenge.id).update({'status': 'declined'});
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
