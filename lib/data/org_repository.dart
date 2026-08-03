import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/enums.dart';
import '../core/models/firestore_codec.dart';
import '../core/models/player_code.dart';
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
    throw asAppException(e);
  }
}

/// The same translation for a long-lived listener.
///
/// Reads were left unguarded on the theory that a query which passed review
/// cannot fail, and a whole class of failure went unnamed because of it: a
/// listener errors LATE — after it has already delivered from the local
/// cache — so a rejected query looks like a screen that works and then
/// stops, and every one of them reached the UI as a raw `FirebaseException`
/// rendered as "Something went wrong". A stream that feeds a screen belongs
/// behind this for the same reason a write does.
Stream<T> guardStream<T>(Stream<T> Function() body) => body().handleError(
      (Object e) => throw asAppException(e as FirebaseException),
      test: (e) => e is FirebaseException,
    );

/// Firebase error code -> the sentence a user sees. Shared by [guard] and
/// [guardStream] so a read and a write never disagree about what a code means.
AppException asAppException(FirebaseException e) => switch (e.code) {
      'permission-denied' => const PermissionDeniedException(),
      'not-found' => const NotFoundException(),
      'already-exists' => const ConflictException(),
      'unavailable' || 'deadline-exceeded' => const NetworkException(),
      'unauthenticated' => const UnauthorizedException(),
      // Almost always a missing composite or collection-group index. The
      // client cannot recover, so it must not be reported as something the
      // user could have done differently.
      'failed-precondition' => const BackendNotReadyException(),
      _ => ValidationException(e.message ?? 'Something went wrong.'),
    };

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

  /// Mirrors the clubs this user actively belongs to onto their own profile
  /// document, most-recently-joined first.
  ///
  /// This is the only structure `firestore.rules` can use to answer "do these
  /// two people share a club", which is what `profileVisibility: community` —
  /// the default for every new account — turns on. Rules cannot run a query,
  /// so without the mirror the community setting could not be honoured at all
  /// and nobody could open anybody else's profile.
  ///
  /// Order matters: the rule can only afford to check the first few entries
  /// (a single-document read may make ten lookups at most), so the freshest
  /// club has to come first.
  ///
  /// Safe to call on every membership change — it is a plain overwrite of one
  /// field, and the caller skips it when nothing moved.
  Future<void> mirrorOrgIds(String uid, List<String> orgIds) =>
      guard(() => Refs.user(uid).update({'orgIds': orgIds}));

  /// Makes sure this person has a player code, claiming one if they do not.
  ///
  /// Firestore has no unique constraint, so uniqueness is bought structurally:
  /// the code is the id of a document in `playerCodes`, and a `create` on an
  /// id that already exists fails. Retrying with a fresh candidate is the
  /// whole collision strategy, and with 33 million codes it effectively never
  /// runs twice.
  ///
  /// Idempotent and safe to call on every launch. It returns early when the
  /// profile already carries a code, so the common path costs nothing beyond
  /// the read the caller had already done.
  ///
  /// Deliberately a backfill rather than something only profile creation does:
  /// every account that existed before codes did needs one, and there is no
  /// server tier here to run a migration.
  Future<String?> ensureCode(AppUser user) => guard(() async {
        final existing = user.playerCode;
        if (existing != null && existing.isNotEmpty) return existing;

        for (var attempt = 0; attempt < 5; attempt++) {
          final candidate = PlayerCode.generate();
          try {
            // Both writes, one batch: a claimed code with no profile pointing
            // at it is a code permanently burned, and a profile naming a code
            // nobody reserved is a code somebody else can still take.
            final batch = Refs.db.batch();
            batch.set(Refs.playerCode(candidate), {
              'uid': user.uid,
              // Denormalized so a lookup by a stranger — the entire point of
              // a code — costs one public read and never touches the profile
              // document, which they are not entitled to see.
              'displayName': user.displayName,
              'photoUrl': user.photoUrl,
              'createdAt': FieldValue.serverTimestamp(),
            });
            batch.update(Refs.user(user.uid), {'playerCode': candidate});
            await batch.commit();
            return candidate;
          } on FirebaseException catch (e) {
            // ALREADY_EXISTS surfaces as permission-denied, because the rule
            // that permits the claim requires the document not to exist.
            // Either way the answer is the same: try another code.
            if (e.code != 'permission-denied' && e.code != 'already-exists') {
              rethrow;
            }
          }
        }
        // Five collisions in a row is not a thing that happens; if it somehow
        // does, the person keeps working without a code rather than being
        // blocked from signing in.
        return null;
      });

  /// Resolves a code somebody typed to the player it belongs to.
  ///
  /// Returns null for a code that is not claimed, which is the same answer as
  /// for a mistyped one — deliberately, so this cannot be used to enumerate
  /// which codes exist any faster than guessing already would.
  Future<PlayerLookup?> findByPlayerCode(String typed) => guard(() async {
        final code = PlayerCode.normalize(typed);
        if (code == null) return null;

        final doc = await Refs.playerCode(code).get();
        final data = doc.data();
        if (!doc.exists || data == null) return null;

        return PlayerLookup(
          uid: Fs.str(data['uid']),
          code: code,
          displayName: Fs.str(data['displayName'], 'Player'),
          photoUrl: Fs.strOrNull(data['photoUrl']),
        );
      });
}

/// What a code lookup returns: enough to put somebody on a team sheet, and
/// nothing else.
///
/// Not an [AppUser]. The caller may well have no right to read that person's
/// profile — a code is for adding a player from another club — so this is
/// only ever a name, a photo and the uid that ties the match record to the
/// right career. No date of birth, no phone, no email.
class PlayerLookup {
  const PlayerLookup({
    required this.uid,
    required this.code,
    required this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String code;
  final String displayName;
  final String? photoUrl;
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
  /// Every club this person belongs to, in one query across all of them.
  ///
  /// The landing screen has no second source for this, so a failure here is
  /// the whole dashboard rather than one section — hence [guardStream].
  /// Needs the collection-group index declared under `fieldOverrides` in
  /// firestore.indexes.json; see the matching rule in firestore.rules.
  Stream<List<Membership>> watchMyMemberships(String uid) {
    return guardStream(
      () => Refs.myMembershipsQuery
          .where('uid', isEqualTo: uid)
          .snapshots()
          .map((snap) => snap.docs.map(Membership.fromDoc).toList()),
    );
  }

  Stream<Membership?> watchMembership(String orgId, String uid) {
    return guardStream(
      () => Refs.member(orgId, uid).snapshots().map(
            (doc) => doc.exists ? Membership.fromDoc(doc) : null,
          ),
    );
  }

  Stream<List<Membership>> watchMembers(String orgId, {MembershipStatus? status}) {
    Query<Map<String, dynamic>> q = Refs.members(orgId);
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    return guardStream(
      () => q.snapshots().map(
            (snap) => snap.docs.map(Membership.fromDoc).toList()
              ..sort((a, b) => b.role.rank.compareTo(a.role.rank)),
          ),
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
        // The public code -> club lookup, written atomically with the club so
        // a code can never point at an organization that does not exist.
        batch.set(
          Refs.inviteCode(org.inviteCode),
          InviteTarget.payload(
            code: org.inviteCode.toUpperCase(),
            orgId: orgRef.id,
            org: org,
          ),
        );
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

  /// Resolves a shareable invite code to the club it opens.
  ///
  /// Reads the public `inviteCodes/{CODE}` document rather than querying
  /// `orgs`. The query could never work for an unlisted club: the org read
  /// rule requires the caller to be public-visible or already a member, so
  /// the people who most needed the code — invitees of a private community —
  /// were told "no organization uses that code".
  ///
  /// Codes are uppercased on both write and read: they get typed by hand off
  /// a whiteboard and half of those will be lowercase.
  Future<InviteTarget?> findByInviteCode(String code) => guard(() async {
        final doc = await Refs.inviteCode(code).get();
        if (!doc.exists) return null;
        return InviteTarget.fromDoc(doc);
      });

  /// Joins a club, or applies to.
  ///
  /// Returns the status the caller actually ended up in, so the UI can tell
  /// the truth rather than guessing. Previously this always wrote `pending`
  /// while the join screen announced "You have joined" whenever the club had
  /// approval switched off — the user was in fact sitting invisibly in a
  /// queue nobody was reviewing.
  ///
  /// A club that does not require approval grants membership immediately; the
  /// invite code is the authorization. The security rules enforce both paths
  /// independently, and neither can mint a role above `member`.
  Future<MembershipStatus> requestToJoin({
    required String orgId,
    required AppUser user,
    required bool requiresApproval,
  }) =>
      guard(() async {
        final status = requiresApproval
            ? MembershipStatus.pending
            : MembershipStatus.active;

        final existing = await Refs.member(orgId, user.uid).get();
        if (existing.exists) {
          final m = Membership.fromDoc(existing);
          // Someone declined by mistake must be able to apply again. Their row
          // is kept for the audit trail, so re-applying is an update back to
          // pending rather than a fresh create.
          if (m.status == MembershipStatus.removed) {
            await Refs.member(orgId, user.uid).update({
              'status': MembershipStatus.pending.wire,
              'role': MembershipRole.member.wire,
              'displayName': user.displayName,
              'photoUrl': user.photoUrl,
              'reappliedAt': FieldValue.serverTimestamp(),
            });
            return MembershipStatus.pending;
          }
          throw ValidationException(
            switch (m.status) {
              MembershipStatus.pending =>
                'You have already applied to join. An admin will review it.',
              MembershipStatus.suspended =>
                'Your membership here is suspended. Contact an admin.',
              _ => 'You are already a member of this organization.',
            },
          );
        }

        final batch = Refs.db.batch();
        batch.set(
          Refs.member(orgId, user.uid),
          Membership(
            uid: user.uid,
            orgId: orgId,
            role: MembershipRole.member,
            status: status,
            displayName: user.displayName,
            photoUrl: user.photoUrl,
          ).toCreate(),
        );
        // Joining without approval takes effect immediately, so the roster
        // count must move with it — the approval path increments on approval
        // instead.
        if (status == MembershipStatus.active) {
          batch.update(Refs.org(orgId), {
            'memberCount': FieldValue.increment(1),
          });
        }
        await batch.commit();
        return status;
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
        // Only an active member was ever counted. Decrementing for a pending
        // applicant drove memberCount below the number of actual members and,
        // with enough declines, below zero.
        final doc = await Refs.member(orgId, uid).get();
        final wasActive = doc.exists &&
            Membership.fromDoc(doc).status == MembershipStatus.active;

        final batch = Refs.db.batch();
        batch.delete(Refs.member(orgId, uid));
        if (wasActive) {
          batch.update(Refs.org(orgId), {
            'memberCount': FieldValue.increment(-1),
          });
        }
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
