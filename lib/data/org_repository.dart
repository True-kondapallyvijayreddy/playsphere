import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/enums.dart';
import '../core/models/organization.dart';

/// Translates raw Firestore failures into [AppException]s.
///
/// Applied at every repository boundary so no widget ever has to interpret a
/// Firebase error code. `permission-denied` in particular is worth naming
/// precisely: during development it almost always means the security rules
/// are stricter than the client assumed, and a generic "error" hides that.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on FirebaseException catch (e) {
    throw switch (e.code) {
      'permission-denied' => const PermissionDeniedException(),
      'not-found' => const NotFoundException(),
      'already-exists' => const ConflictException(),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      'unauthenticated' => const UnauthorizedException(),
      _ => ValidationException(e.message ?? 'Something went wrong.'),
    };
  }
}

class UserRepository {
  const UserRepository();

  Stream<AppUser?> watch(String uid) => Refs.user(uid).snapshots().map(
        (doc) => doc.exists ? AppUser.fromDoc(doc) : null,
      );

  Future<AppUser?> fetch(String uid) => guard(() async {
        final doc = await Refs.user(uid).get();
        return doc.exists ? AppUser.fromDoc(doc) : null;
      });

  /// Called once after the first Google sign-in, when the user supplies the
  /// date of birth Google never gives us.
  Future<void> createProfile(AppUser user) =>
      guard(() => Refs.user(user.uid).set(user.toCreate()));

  Future<void> updateProfile(AppUser user) =>
      guard(() => Refs.user(user.uid).update(user.toUpdate()));
}

class OrgRepository {
  const OrgRepository();

  Stream<Organization?> watch(String orgId) => Refs.org(orgId).snapshots().map(
        (doc) => doc.exists ? Organization.fromDoc(doc) : null,
      );

  Future<Organization?> fetch(String orgId) => guard(() async {
        final doc = await Refs.org(orgId).get();
        return doc.exists ? Organization.fromDoc(doc) : null;
      });

  /// Every organization the signed-in user belongs to.
  ///
  /// Uses a collection-group query rather than a mirrored "my orgs" list.
  /// A mirror would need two writes kept in sync from a client that can crash
  /// between them; the query has one source of truth and cannot drift.
  Stream<List<Membership>> watchMyMemberships(String uid) {
    return Refs.myMembershipsQuery
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(Membership.fromDoc).toList());
  }

  Stream<Membership?> watchMembership(String orgId, String uid) {
    return Refs.member(orgId, uid).snapshots().map(
          (doc) => doc.exists ? Membership.fromDoc(doc) : null,
        );
  }

  Stream<List<Membership>> watchMembers(String orgId, {MembershipStatus? status}) {
    Query<Map<String, dynamic>> q = Refs.members(orgId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    return q.snapshots().map(
          (snap) => snap.docs.map(Membership.fromDoc).toList()
            ..sort((a, b) => b.role.rank.compareTo(a.role.rank)),
        );
  }

  /// Creates the organization and its owner membership atomically.
  ///
  /// A batch matters here: if the org were written without the membership,
  /// the founder would be locked out of the thing they just created, with no
  /// way back in because only members can administer it.
  Future<String> createOrganization({
    required Organization org,
    required AppUser founder,
  }) =>
      guard(() async {
        final orgRef = Refs.orgs.doc();
        final batch = Refs.db.batch();

        batch.set(orgRef, org.toCreate());
        batch.set(
          Refs.member(orgRef.id, founder.uid),
          Membership(
            uid: founder.uid,
            orgId: orgRef.id,
            role: MembershipRole.owner,
            status: MembershipStatus.active,
            displayName: founder.displayName,
            photoUrl: founder.photoUrl,
          ).toCreate(),
        );

        await batch.commit();
        return orgRef.id;
      });

  Future<void> updateOrganization(Organization org) =>
      guard(() => Refs.org(org.id).update(org.toUpdate()));

  /// Finds an org by its shareable invite code.
  ///
  /// Codes are stored uppercase and compared uppercase, because they get
  /// typed by hand off a whiteboard and half of those will be lowercase.
  Future<Organization?> findByInviteCode(String code) => guard(() async {
        final snap = await Refs.orgs
            .where('inviteCode', isEqualTo: code.trim().toUpperCase())
            .limit(1)
            .get();
        if (snap.docs.isEmpty) return null;
        return Organization.fromDoc(snap.docs.first);
      });

  /// Requests membership. Lands as `pending` unless the org has opted out of
  /// approval, in which case the rules still write `pending` and an admin's
  /// auto-approval is expected — a client can never mint itself `active`.
  Future<void> requestToJoin({
    required String orgId,
    required AppUser user,
  }) =>
      guard(() async {
        final existing = await Refs.member(orgId, user.uid).get();
        if (existing.exists) {
          final m = Membership.fromDoc(existing);
          throw ValidationException(
            m.isPending
                ? 'You have already applied to join. An admin will review it.'
                : 'You are already a member of this organization.',
          );
        }
        await Refs.member(orgId, user.uid).set(
          Membership(
            uid: user.uid,
            orgId: orgId,
            role: MembershipRole.member,
            status: MembershipStatus.pending,
            displayName: user.displayName,
            photoUrl: user.photoUrl,
          ).toCreate(),
        );
      });

  Future<void> decideMembership({
    required String orgId,
    required String uid,
    required MembershipStatus status,
    required String decidedByUid,
  }) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.update(Refs.member(orgId, uid), {
          'status': status.wire,
          'approvedBy': decidedByUid,
          'decidedAt': FieldValue.serverTimestamp(),
        });
        // Keep the roster count honest without a second read. An approval
        // increments; anything else does not.
        if (status == MembershipStatus.active) {
          batch.update(Refs.org(orgId), {
            'memberCount': FieldValue.increment(1),
          });
        }
        await batch.commit();
      });

  Future<void> changeRole({
    required String orgId,
    required String uid,
    required MembershipRole role,
  }) =>
      guard(() => Refs.member(orgId, uid).update({'role': role.wire}));

  Future<void> removeMember({
    required String orgId,
    required String uid,
  }) =>
      guard(() async {
        final batch = Refs.db.batch();
        batch.delete(Refs.member(orgId, uid));
        batch.update(Refs.org(orgId), {
          'memberCount': FieldValue.increment(-1),
        });
        await batch.commit();
      });

  /// Public organizations, for the discovery/browse screen.
  Stream<List<Organization>> watchPublicOrgs({int limit = 50}) {
    return Refs.orgs
        .where('visibility', isEqualTo: OrgVisibility.public.wire)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(Organization.fromDoc)
            .where((o) => !o.isDeleted)
            .toList());
  }
}
