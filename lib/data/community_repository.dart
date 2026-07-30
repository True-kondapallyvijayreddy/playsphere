import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firebase/firestore_refs.dart';
import '../core/models/announcement.dart';
import '../core/models/challenge.dart';
import '../core/models/enums.dart';
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

  Stream<List<Challenge>> watchChallengesForOrg(String orgId) {
    return Refs.challenges.snapshots().map((snap) => snap.docs
        .map(Challenge.fromDoc)
        .where((c) => c.fromOrgId == orgId || c.toOrgId == orgId)
        .toList());
  }

  /// Accepts a challenge and automatically creates a new Fixture for the match!
  Future<void> acceptChallenge({
    required Challenge challenge,
    required DateTime selectedSlot,
  }) async {
    final challengeRef = Refs.challenge(challenge.id);

    final fixRef =
        Refs.fixtures(challenge.fromOrgId, 'inter_club_league').doc();
    final fixture = Fixture(
      id: fixRef.id,
      orgId: challenge.fromOrgId,
      compId: 'inter_club_league',
      entrantAId: challenge.fromOrgId,
      entrantBId: challenge.toOrgId,
      entrantAName: challenge.fromOrgName,
      entrantBName: challenge.toOrgName,
      status: FixtureStatus.scheduled,
      scheduledAt: selectedSlot,
      venue: challenge.venue,
      scoringPluginKey: SportCatalog.byId(challenge.sportId).pluginKey,
      sportId: challenge.sportId,
      scoringConfig: SportCatalog.byId(challenge.sportId).config,
    );

    final batch = _firestore.batch();
    batch.set(fixRef, fixture.toCreate());
    batch.update(challengeRef, {
      'status': 'accepted',
      'createdFixtureId': fixRef.id,
    });

    await batch.commit();
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
