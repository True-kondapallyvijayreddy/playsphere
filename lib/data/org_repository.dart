import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_exception.dart';
import '../core/firebase/firestore_refs.dart';
import '../core/models/app_user.dart';
import '../core/models/membership_application.dart';
import '../core/models/billing.dart';
import '../core/models/claim_code.dart';
import '../core/models/enums.dart';
import '../core/models/firestore_codec.dart';
import '../core/models/player_code.dart';
import '../core/models/organization.dart';
import '../core/models/owner_proposal.dart';
import '../domain/governance/owner_vote.dart';
import 'media_uploader.dart';

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
///
/// ## Why a rejected read is retried before it is believed
///
/// A Firestore listener that errors is finished — the SDK never re-subscribes
/// it, and the Riverpod provider holding it keeps that error for the life of
/// the app. That is the right behaviour for a permanent refusal and the wrong
/// one for the refusal a founder actually meets, which is temporary and is
/// caused by us:
///
/// Writes here are deliberately not awaited (see `createOrganization`), so a
/// new club and its owner membership land in the LOCAL cache first and reach
/// the server a moment later. The membership listener sees the local copy
/// immediately, the dashboard fans out over the new club at once — and every
/// one of those org-scoped reads is refused, because `firestore.rules` asks
/// the server whether an owner membership exists and the server does not have
/// it yet. Nothing retries, so five red "could not load" strips sit on the
/// Notifications screen of somebody who has owned a club for four seconds,
/// and stay there until the app is restarted.
///
/// So `permission-denied` — and only that code — is retried a couple of times
/// with a short backoff. A denial that is real survives it and reaches the
/// user about five seconds later than it used to; a denial that was a race
/// against our own write disappears on its own, which is what the founder
/// should have seen in the first place.
Stream<T> guardStream<T>(Stream<T> Function() body) async* {
  // Two extra attempts is enough for a server acknowledgement on a phone
  // network, and short enough that a genuine refusal is not left looking
  // like a hung screen.
  const backoff = [Duration(milliseconds: 1500), Duration(seconds: 4)];

  for (var attempt = 0;; attempt++) {
    try {
      // `await for` rather than `yield*`: a `yield*` hands the inner stream's
      // error straight to the listener without ever entering this frame, so
      // the catch below would never run and the retry would be dead code.
      await for (final value in body()) {
        yield value;
      }
      return;
    } on FirebaseException catch (e) {
      final mapped = asAppException(e);
      if (mapped is! PermissionDeniedException || attempt >= backoff.length) {
        throw mapped;
      }
      await Future<void>.delayed(backoff[attempt]);
    }
  }
}

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
  const UserRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the photo upload against a fake bucket,
  /// matching [OrgRepository].
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

  Stream<AppUser?> watch(String uid) => guardStream(
        () => Refs.user(uid).snapshots().map(
              (doc) => doc.exists ? AppUser.fromDoc(doc) : null,
            ),
      );

  Future<AppUser?> fetch(String uid) => guard(() async {
        final doc = await Refs.user(uid).get();
        return doc.exists ? AppUser.fromDoc(doc) : null;
      });

  /// Several accounts in as few reads as Firestore allows, keyed by uid.
  ///
  /// Exists for the team sheet. A registered squad is stored as a list of
  /// uids — Rule 31's snapshot of who entered — and turning that back into
  /// names on a match-day screen is eleven documents. One at a time that is
  /// eleven round trips on a phone at a ground; batched it is one.
  ///
  /// A uid with no readable document is simply absent from the result rather
  /// than an error: a squad member whose profile is private to this viewer
  /// must not blank the whole team sheet. Callers fall back to whatever name
  /// they already hold.
  ///
  /// `whereIn` takes at most 30 values per query, so the input is chunked and
  /// the chunks run together.
  Future<Map<String, AppUser>> fetchMany(Iterable<String> uids) async {
    final ids = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    const chunkSize = 30;
    final chunks = <List<String>>[
      for (var i = 0; i < ids.length; i += chunkSize)
        ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize),
    ];

    final snaps = await Future.wait([
      for (final chunk in chunks)
        Refs.users.where(FieldPath.documentId, whereIn: chunk).get(),
    ]);

    return {
      for (final snap in snaps)
        for (final doc in snap.docs) doc.id: AppUser.fromDoc(doc),
    };
  }

  /// Replaces this person's profile photo with one they picked themselves.
  ///
  /// `storage.rules` has permitted `users/{uid}/profile/**` since it was
  /// written, and until now nothing in the app wrote there — a member's photo
  /// came from Google's `photoURL` at sign-in or it did not exist. That left
  /// anyone who signed in without a Google photo with a grey initial on every
  /// squad sheet and leaderboard in the product, permanently, with no way to
  /// fix it.
  ///
  /// Two uids, deliberately.
  ///
  /// [uid] is the profile the photo belongs TO; [uploaderUid] is the account
  /// doing the uploading, and it is the one in the storage path. They are the
  /// same person for an ordinary account and differ for exactly one case: a
  /// guardian setting the photo on a child's managed profile.
  ///
  /// The split is forced by what each rule file can see. `storage.rules`
  /// cannot read Firestore — it says so itself — so the only fact it can
  /// check about an upload is that the path segment is the caller's own uid;
  /// custody is invisible to it. `firestore.rules` CAN see custody, and it is
  /// the write of `photoUrl` there that decides which object is anybody's
  /// photo. So the object is owned by the account that uploaded it, and the
  /// reference is governed where custody is knowable — the same division the
  /// club-logo rule already documents.
  Future<String> uploadProfilePhoto({
    required String uid,
    required String uploaderUid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'users/$uid/profile',
          uid: uploaderUid,
          bytes: bytes,
          contentType: contentType,
          // The rules ceiling for this path is 8 MB; a 512px crest that
          // reaches even 4 is already pathological.
          maxMegabytes: 4,
        );
        await Refs.user(uid).update({
          'photoUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return url;
      });

  /// Goes back to having no photo.
  ///
  /// Clears the reference rather than the object, for the reason
  /// [MediaUploader] documents: the URL may be cached in half a dozen places
  /// and an unreferenced object is already unreachable.
  Future<void> removeProfilePhoto(String uid) => guard(
        () => Refs.user(uid).update({
          'photoUrl': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

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

  /// Mirrors the clubs this user has an OUTSTANDING application to, most
  /// recently applied first.
  ///
  /// The counterpart of [mirrorOrgIds], and the thing that lets a club's
  /// owner read the profile of somebody asking to join it — see
  /// `AppUser.pendingOrgIds` and the `appliedToClubIManage` rule.
  ///
  /// Only the applicant can write it, because `firestore.rules` lets nobody
  /// else write a `users/{uid}` document. That is why the rule does not trust
  /// this list on its own: it re-checks the membership row's status, so a
  /// stale entry left behind by a decision made on somebody else's device
  /// grants exactly nothing.
  Future<void> mirrorPendingOrgIds(String uid, List<String> orgIds) =>
      guard(() => Refs.user(uid).update({'pendingOrgIds': orgIds}));

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

  // -----------------------------------------------------------------------
  // Guardian-managed children — see functions/family.js for why the two
  // Admin-privileged steps (minting the auth user, minting the custom
  // token) have to be callables while everything else here is a plain
  // rules-governed write, same split as [ensureCode] above.
  // -----------------------------------------------------------------------

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// A guardian creates a profile for a child with no device or Google
  /// account of their own yet. Throws [ValidationException] with a message
  /// safe to show directly.
  Future<ManagedChild> createManagedChild({
    required String displayName,
    required DateTime dateOfBirth,
    required Gender gender,
  }) =>
      guard(() async {
        try {
          final callable =
              _functions.httpsCallable('createManagedChildProfile');
          final result = await callable.call<Map<String, dynamic>>({
            'displayName': displayName,
            'dateOfBirth': dateOfBirth.toIso8601String(),
            'gender': gender.wire,
          });
          final data = result.data;
          return ManagedChild(
            uid: data['childUid'] as String,
            playerCode: data['playerCode'] as String?,
          );
        } on FirebaseFunctionsException catch (e) {
          throw ValidationException(
            e.message ?? 'Could not create that profile. Try again.',
          );
        }
      });

  /// Every child this guardian has created, most-recently-added first —
  /// both still-managed and already-claimed, so a claimed child does not
  /// simply vanish from the list the moment they get their own phone.
  ///
  /// Sorted on the client rather than with `orderBy`. A single equality
  /// filter is served by the automatic single-field index, so this query can
  /// never fail with `failed-precondition` — an ordered version needs a
  /// composite index, and a guardian staring at "not finished setting up on
  /// the server" is a bad trade for ordering a list that is realistically
  /// three documents long. A child written seconds ago has a null
  /// `createdAt` until the server timestamp resolves; those sort first,
  /// which is where a just-added child belongs anyway.
  Stream<List<AppUser>> watchManagedChildren(String guardianUid) => guardStream(
        () => Refs.users
            .where('custodianUid', isEqualTo: guardianUid)
            .snapshots()
            .map((s) {
          final children = s.docs.map(AppUser.fromDoc).toList()
            ..sort((a, b) {
              if (a.createdAt == null) return b.createdAt == null ? 0 : -1;
              if (b.createdAt == null) return 1;
              return b.createdAt!.compareTo(a.createdAt!);
            });
          return children;
        }),
      );

  /// Generates a fresh, short-lived code for `childUid` and claims it,
  /// retrying on collision exactly like [ensureCode] does for player codes.
  /// `firestore.rules` bounds the expiry to 30 minutes regardless of what is
  /// requested here; 25 leaves headroom for clock skew between this device
  /// and the server deciding the write's actual timestamp.
  Future<String> createClaimCode({
    required String childUid,
    required String guardianUid,
  }) =>
      guard(() async {
        for (var attempt = 0; attempt < 5; attempt++) {
          final candidate = ClaimCode.generate();
          try {
            await Refs.claimCode(candidate).set({
              'code': candidate,
              'childUid': childUid,
              'guardianUid': guardianUid,
              'createdAt': FieldValue.serverTimestamp(),
              'expiresAt': Timestamp.fromDate(
                DateTime.now().add(const Duration(minutes: 25)),
              ),
            });
            return candidate;
          } on FirebaseException catch (e) {
            // Same ALREADY_EXISTS-as-permission-denied shape as
            // [ensureCode] — the create rule requires the doc not to exist
            // yet, so a collision surfaces as a rejected write.
            if (e.code != 'permission-denied') rethrow;
          }
        }
        throw const ValidationException(
          'Could not generate a code right now. Try again.',
        );
      });

  /// The child's half of the handoff: exchanges a code for the custom token
  /// that signs them into the exact uid the guardian's profile named. See
  /// `AuthService.linkGoogleAccount` for what happens right after.
  Future<ClaimedToken> redeemClaimCode(String code) => guard(() async {
        try {
          final callable = _functions.httpsCallable('redeemClaimCode');
          final result =
              await callable.call<Map<String, dynamic>>({'code': code});
          final data = result.data;
          return ClaimedToken(
            customToken: data['customToken'] as String,
            displayName: data['displayName'] as String?,
          );
        } on FirebaseFunctionsException catch (e) {
          throw ValidationException(
            e.message ?? 'This code is invalid or has expired.',
          );
        }
      });

  /// Marks the claim complete. Only ever called from the child's own
  /// session, immediately after [AuthService.linkGoogleAccount] succeeds —
  /// `settableOnce('claimedAt')` in `firestore.rules` is what makes this a
  /// one-way door, not this call site.
  Future<void> completeClaim(String childUid) => guard(
        () => Refs.user(childUid).update({
          'claimedAt': FieldValue.serverTimestamp(),
        }),
      );
}

/// What `createManagedChildProfile` hands back.
class ManagedChild {
  const ManagedChild({required this.uid, this.playerCode});
  final String uid;
  final String? playerCode;
}

/// What `redeemClaimCode` hands back: enough to sign in as the claimed
/// profile and greet the child by name before they've done anything else.
class ClaimedToken {
  const ClaimedToken({required this.customToken, this.displayName});
  final String customToken;
  final String? displayName;
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
  const OrgRepository({FirebaseStorage? storage}) : _storage = storage;

  /// Injectable so a test can drive the branding upload against a fake
  /// bucket, matching [MemoryRepository] and [ClubFileRepository].
  final FirebaseStorage? _storage;

  MediaUploader get _media => MediaUploader(storage: _storage);

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

  // --- Branding ---------------------------------------------------------

  /// Uploads a club crest and links it, in that order.
  ///
  /// ## Why the object is written before the document
  ///
  /// `orgs/{orgId}.logoUrl` is what every screen actually reads, and
  /// `storage.rules` deliberately allows any signed-in person to write under
  /// their own uid segment — Cloud Storage rules cannot read Firestore, so
  /// "admins only" is not expressible there (see that file's note). The real
  /// gate is this Firestore write, which only an org admin may make. So an
  /// object that fails to be linked is an object nobody can reach, which is
  /// the failure mode worth having: the reverse order would point the club at
  /// an image that may not exist.
  ///
  /// The previous object is not deleted. A logo URL may already be sitting in
  /// a cached feed, a notification payload or somebody's open tab, and
  /// breaking those to reclaim a few hundred kilobytes is a poor trade.
  Future<String> uploadClubLogo({
    required String orgId,
    required String uid,
    required Uint8List bytes,
    required String contentType,
  }) =>
      guard(() async {
        final url = await _media.putImage(
          folder: 'orgs/$orgId/logo',
          uid: uid,
          bytes: bytes,
          contentType: contentType,
          maxMegabytes: 4,
        );
        await Refs.org(orgId).update({
          'logoUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return url;
      });

  /// Goes back to the generated crest.
  Future<void> removeClubLogo(String orgId) => guard(
        () => Refs.org(orgId).update({
          'logoUrl': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  // --- Following --------------------------------------------------------
  //
  // Following is not a lightweight membership and must not drift into one. It
  // puts a public club's events on your home feed and grants nothing else —
  // no roster seat, no capability, no read the club had not already
  // published. That is what lets it be self-served with no approval queue.

  /// Every club this person follows.
  ///
  /// A collection-group query, safe for the same reason the memberships one
  /// is: rules restrict rows to those whose document id is the caller's uid.
  Stream<List<String>> watchMyFollowedOrgIds(String uid) {
    return guardStream(
      () => Refs.myFollowsQuery
          .where('uid', isEqualTo: uid)
          .snapshots()
          .map((snap) => [
                for (final doc in snap.docs)
                  if (doc.data()['orgId'] is String)
                    doc.data()['orgId'] as String,
              ]),
    );
  }

  /// Whether this person follows [orgId] — a single document read, so the
  /// button on a club page does not wait on the whole follow list.
  Stream<bool> watchIsFollowing(String orgId, String uid) {
    return guardStream(
      () => Refs.follower(orgId, uid).snapshots().map((d) => d.exists),
    );
  }

  Future<void> followOrg({required String orgId, required String uid}) =>
      guard(() => Refs.follower(orgId, uid).set({
            'uid': uid,
            'orgId': orgId,
            'followedAt': FieldValue.serverTimestamp(),
          }));

  Future<void> unfollowOrg({required String orgId, required String uid}) =>
      guard(() => Refs.follower(orgId, uid).delete());

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
  /// Creates a club, its founding owner membership, its invite code and — if
  /// one was bought — its plan and the ledger row that paid for it, in a
  /// single batch.
  ///
  /// [planGrant] comes from `BillingRepository.purchasePlanForNewClub`, which
  /// has already taken the money by the time this is called. Everything after
  /// that point must land together: a club that exists without the plan its
  /// founder just paid for is the one failure here that costs money and
  /// cannot be repaired from the client.
  Future<String> createOrganization({
    required Organization org,
    required AppUser founder,
    ClubPlanGrant? planGrant,
  }) =>
      guard(() async {
        final orgRef = Refs.orgs.doc();
        final batch = Refs.db.batch();

        batch.set(orgRef, {
          ...org.toCreate(),
          if (planGrant != null) ...planGrant.orgFields(),
        });
        if (planGrant != null) {
          batch.set(
            Refs.payment(planGrant.paymentId),
            planGrant.ledgerRow(orgRef.id),
          );
        }
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

  /// Sets or clears the club's own ground — see [Organization.homeGroundId].
  ///
  /// A raw write rather than going through [Organization.toUpdate]: that map
  /// is pruned of nulls so a general profile save never wipes a field the
  /// form didn't touch, but clearing a chosen ground here *is* the action —
  /// switching from a registered [Ground] back to a free-text name, or
  /// removing it altogether, both pass `groundId: null`.
  Future<void> setHomeGround(
    String orgId, {
    String? groundId,
    String? groundName,
  }) =>
      guard(() => Refs.org(orgId).update({
            'homeGroundId': groundId,
            'homeGroundName': groundName,
            'updatedAt': FieldValue.serverTimestamp(),
          }));

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
  /// [application] is the introduction the applicant chose to send with the
  /// request — see [MembershipApplication] for why the club reads that rather
  /// than opening a profile it is usually not entitled to open. Empty is a
  /// valid answer and the row simply carries no introduction.
  Future<MembershipStatus> requestToJoin({
    required String orgId,
    required AppUser user,
    required bool requiresApproval,
    MembershipApplication application = MembershipApplication.empty,
  }) =>
      guard(() async {
        // Immediate membership is for a PUBLIC club that has opted out of
        // approving joiners. An unlisted club always decides for itself,
        // whatever its approval setting says: `firestore.rules` refuses an
        // active self-join there, so writing one would be a local success the
        // server rejects a second later — and before that rule existed, anyone
        // who learned the orgId could walk into an unlisted club and read its
        // roster, announcements and files.
        final status = (!requiresApproval && await _orgIsPublic(orgId))
            ? MembershipStatus.active
            : MembershipStatus.pending;

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
              // A second application replaces the first. Keeping the old one
              // would show the reviewer the pitch that was already declined.
              if (application.isNotEmpty) 'application': application.toMap(),
            });
            await _markApplicationPending(orgId, user);
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
            application: application,
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
        if (status == MembershipStatus.pending) {
          await _markApplicationPending(orgId, user);
        }
        return status;
      });

  /// Whether [orgId] is a publicly listed club.
  ///
  /// Read rather than taken from the invite card on purpose: an
  /// `inviteCodes/{code}` document written before this mattered carries no
  /// visibility at all, and a stale card must not be what decides whether
  /// somebody walks straight in.
  ///
  /// An unreadable org is treated as unlisted, which is the safe direction and
  /// usually the literal truth — the org read rule admits members and public
  /// clubs only, so a non-member who cannot read it is looking at an unlisted
  /// club.
  Future<bool> _orgIsPublic(String orgId) async {
    try {
      final snap = await Refs.org(orgId).get();
      return snap.exists &&
          Fs.str(snap.data()?['visibility']) == OrgVisibility.public.wire;
    } catch (_) {
      return false;
    }
  }

  /// Puts [orgId] at the head of the applicant's own `pendingOrgIds`, which is
  /// what lets that club's owner and admins open their profile while the
  /// decision is outstanding.
  ///
  /// Deliberately best-effort and never awaited into the caller's error path:
  /// the application itself is already committed by the time this runs, and a
  /// failed mirror must not report a successful request as a failure. The
  /// reviewer falls back to the introduction on the membership row, which is
  /// on the document they can always read, and `profileOrgMirrorProvider`
  /// rebuilds the list on this person's next visit.
  Future<void> _markApplicationPending(String orgId, AppUser user) async {
    final wanted = [
      orgId,
      for (final id in user.pendingOrgIds)
        if (id != orgId) id,
    ].take(_maxPendingMirrored).toList();
    try {
      await const UserRepository().mirrorPendingOrgIds(user.uid, wanted);
    } catch (_) {
      // Intentionally swallowed. See the doc comment.
    }
  }

  /// The rule checks only the first few entries of `pendingOrgIds`, so there
  /// is no point storing more — and a list bounded here is a list the rules'
  /// own size check can never be surprised by.
  static const _maxPendingMirrored = 5;

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

  /// Puts somebody in charge of a set of departments — see [ClubPortfolio].
  ///
  /// Takes the whole set rather than an add/remove pair because the screen
  /// that calls it shows every portfolio as a row of switches, and the person
  /// using it thinks in terms of "these are Ramesh's jobs now", not a
  /// sequence of grants. Sending the final state also makes the write
  /// idempotent, so a double tap on a slow connection cannot leave a brief
  /// half-granted.
  ///
  /// Portfolios are never written for an owner: they hold all of them by
  /// rank, and a stored grant would outlive the rank if they ever stepped
  /// down. Callers pass owners through unchanged and this is the guard for it.
  Future<void> setPortfolios({
    required String orgId,
    required String uid,
    required Set<ClubPortfolio> portfolios,
  }) =>
      guard(() => Refs.member(orgId, uid).update({
            'portfolios': ClubPortfolio.wiresOf(portfolios),
          }));

  /// Demotes somebody out of every position of authority in one go: back to
  /// plain member, with every department brief taken off them.
  ///
  /// One write, not two, because the two-write version has a window in which
  /// a removed admin still runs the club's finances — which is precisely the
  /// window that matters when an admin is being removed in a hurry.
  Future<void> standDown({
    required String orgId,
    required String uid,
  }) =>
      guard(() => Refs.member(orgId, uid).update({
            'role': MembershipRole.member.wire,
            'portfolios': <String>[],
          }));

  // --- Roster grouping ---------------------------------------------------

  /// Records where members sit inside this club — house, department, year,
  /// class, section. See [MemberGrouping] for why this is club-scoped data on
  /// the membership rather than anything on the person's profile.
  ///
  /// Takes a map rather than one uid because the realistic unit of work is a
  /// whole class: an admin who has to tap through four hundred students one at
  /// a time will not do it, and a roster half-filled-in is worse than an empty
  /// one — auto-placement would quietly split a year group in two.
  ///
  /// Merged into the existing document rather than replacing it: stamping a
  /// department onto a batch of students must not wipe the houses somebody
  /// else set last term.
  Future<void> setMemberGroupings({
    required String orgId,
    required Map<String, MemberGrouping> groupings,
  }) =>
      guard(() async {
        if (groupings.isEmpty) return;
        final batch = Refs.db.batch();
        for (final e in groupings.entries) {
          batch.set(
            Refs.member(orgId, e.key),
            {'grouping': e.value.toMap()},
            SetOptions(mergeFields: ['grouping']),
          );
        }
        await batch.commit();
      });

  /// One member, for the edit-in-place path on the roster.
  Future<void> setMemberGrouping({
    required String orgId,
    required String uid,
    required MemberGrouping grouping,
  }) =>
      setMemberGroupings(orgId: orgId, groupings: {uid: grouping});

  // --- Ownership --------------------------------------------------------

  /// Everyone who currently holds `owner` in this club.
  ///
  /// The members subcollection is the source of truth for who owns a club, not
  /// `Organization.ownerUids` — the role is what `firestore.rules` actually
  /// checks, so anything reading a separate list would be answering a
  /// different question from the one the database enforces.
  Stream<List<Membership>> watchOwners(String orgId) => guardStream(
        () => Refs.members(orgId)
            .where('role', isEqualTo: MembershipRole.owner.wire)
            .where('status', isEqualTo: MembershipStatus.active.wire)
            .snapshots()
            .map((s) => s.docs.map(Membership.fromDoc).toList()),
      );

  Stream<List<OwnerProposal>> watchOwnerProposals(String orgId) => guardStream(
        () => Refs.ownerProposals(orgId)
            .where('status', isEqualTo: OwnerProposalStatus.open.wire)
            .snapshots()
            .map((s) => s.docs.map(OwnerProposal.fromDoc).toList()),
      );

  /// Gives up your own ownership of a club, dropping to admin.
  ///
  /// Unilateral by design — see [OwnerVote.canResign]. The one refusal is the
  /// last owner, because a club with no owner has nobody who can appoint one
  /// and would be permanently stuck. They are told to appoint a co-owner
  /// first, which is now something they can actually do.
  ///
  /// Drops to `admin` rather than `member`: somebody stepping back from
  /// running a club is usually still helping run it, and demoting them all the
  /// way out would cost them access to the events they are still organizing.
  Future<void> resignOwnership({
    required String orgId,
    required String uid,
  }) =>
      guard(() async {
        final owners = await Refs.members(orgId)
            .where('role', isEqualTo: MembershipRole.owner.wire)
            .where('status', isEqualTo: MembershipStatus.active.wire)
            .get();

        if (!OwnerVote.canResign(owners.docs.length)) {
          throw const ValidationException(
            'You are this club\'s only owner. Make someone else an owner '
            'first — a club with no owner cannot appoint one.',
          );
        }

        await Refs.member(orgId, uid).update({
          'role': MembershipRole.admin.wire,
        });
      });

  /// Opens a motion to remove another owner.
  ///
  /// Opening it counts as voting for it, which is why [byUid] goes straight
  /// into `votes`. Anything else would make a two-owner club need a vote the
  /// proposer then has to cast separately against their own motion.
  Future<void> proposeOwnerRemoval({
    required String orgId,
    required String targetUid,
    required String targetName,
    required String reason,
    required String byUid,
  }) =>
      guard(() async {
        if (targetUid == byUid) {
          throw const ValidationException(
            'To give up your own ownership, use Step down.',
          );
        }
        final text = reason.trim();
        if (text.isEmpty) {
          throw const ValidationException(
            'Give a reason. The other owners are being asked to agree to '
            'this and cannot do that from a name alone.',
          );
        }

        final existing = await Refs.ownerProposal(orgId, targetUid).get();
        if (existing.exists &&
            OwnerProposal.fromDoc(existing).isOpen) {
          throw const ValidationException(
            'There is already an open motion about this owner.',
          );
        }

        await Refs.ownerProposal(orgId, targetUid).set(
          OwnerProposal(
            targetUid: targetUid,
            targetName: targetName,
            openedBy: byUid,
            reason: text,
            status: OwnerProposalStatus.open,
            votes: [byUid],
          ).toCreate(),
        );
      });

  /// Adds your vote to an open motion.
  ///
  /// `arrayUnion` rather than a read-modify-write: two owners voting in the
  /// same second would otherwise each write a list built from what they read
  /// before the other, and one vote would vanish. It is also the shape
  /// `firestore.rules` can check — a union of exactly one element, that
  /// element being the caller.
  ///
  /// Crossing the threshold is NOT decided here. The `onOwnerVote` Cloud
  /// Function tallies and executes, because a client that could carry out the
  /// removal could carry it out without the votes.
  Future<void> voteToRemoveOwner({
    required String orgId,
    required String targetUid,
    required String byUid,
  }) =>
      guard(() => Refs.ownerProposal(orgId, targetUid).update({
            'votes': FieldValue.arrayUnion([byUid]),
          }));

  /// Withdraws a motion. Only the owner who opened it may.
  Future<void> withdrawOwnerProposal({
    required String orgId,
    required String targetUid,
  }) =>
      guard(() => Refs.ownerProposal(orgId, targetUid).update({
            'status': OwnerProposalStatus.withdrawn.wire,
            'resolvedAt': FieldValue.serverTimestamp(),
          }));

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
