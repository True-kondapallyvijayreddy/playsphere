import 'package:cloud_firestore/cloud_firestore.dart';

/// Every Firestore path in the product, in one file.
///
/// Collection paths appear as string literals nowhere else. A typo in a path
/// is not a compile error and does not throw — it silently reads an empty
/// collection, which surfaces days later as "the fixtures disappeared".
/// Centralising them makes that class of bug impossible to introduce quietly
/// and gives the security rules a single document to be checked against.
class Refs {
  const Refs._();

  static FirebaseFirestore get db => FirebaseFirestore.instance;

  // --- Global -----------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> get users =>
      db.collection('users');

  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      users.doc(uid);

  /// One document per claimed player code, id = the code itself.
  ///
  /// It does two jobs that a field on the user document cannot. Firestore has
  /// no unique constraint, so uniqueness is bought by making the code a
  /// DOCUMENT ID and claiming it with a create, which fails if it is taken.
  /// And a code has to be resolvable by someone who cannot read the target's
  /// profile — the point of a code is adding a player from another club — so
  /// the lookup has to be a tiny public document holding a display name and a
  /// photo, never the profile itself.
  static CollectionReference<Map<String, dynamic>> get playerCodes =>
      db.collection('playerCodes');

  static DocumentReference<Map<String, dynamic>> playerCode(String code) =>
      playerCodes.doc(code);

  /// Devices a user has signed in on, so the server can reach them.
  ///
  /// One document per token rather than a single field on the user: a player
  /// has a phone and a lab machine, and a scorer borrows the club tablet on
  /// match day. A single field would mean only the most recent device ever
  /// hears "your match starts in an hour".
  static CollectionReference<Map<String, dynamic>> deviceTokens(String uid) =>
      user(uid).collection('devices');

  static DocumentReference<Map<String, dynamic>> deviceToken(
    String uid,
    String token,
  ) =>
      deviceTokens(uid).doc(token);

  static CollectionReference<Map<String, dynamic>> get umpires =>
      db.collection('umpires');

  static DocumentReference<Map<String, dynamic>> umpire(String uid) =>
      umpires.doc(uid);

  static CollectionReference<Map<String, dynamic>> userRatings(String uid) =>
      user(uid).collection('ratings');

  static DocumentReference<Map<String, dynamic>> userRating(
    String uid,
    String sportId,
  ) =>
      userRatings(uid).doc(sportId);

  static CollectionReference<Map<String, dynamic>> userCareerStats(
    String uid,
  ) =>
      user(uid).collection('career_stats');

  static DocumentReference<Map<String, dynamic>> userCareerStat(
    String uid,
    String sportId,
  ) =>
      userCareerStats(uid).doc(sportId);

  static CollectionReference<Map<String, dynamic>> get orgs =>
      db.collection('orgs');

  /// Public lookup table mapping an invite code to the club it opens.
  ///
  /// Exists because resolving a code by querying `orgs` cannot work for an
  /// unlisted club: the org read rule requires membership the applicant does
  /// not yet have. Readable by document id only — never listable.
  static DocumentReference<Map<String, dynamic>> inviteCode(String code) =>
      db.collection('inviteCodes').doc(code.trim().toUpperCase());

  static DocumentReference<Map<String, dynamic>> org(String orgId) =>
      orgs.doc(orgId);

  static CollectionReference<Map<String, dynamic>> subGroups(String orgId) =>
      org(orgId).collection('subgroups');

  static DocumentReference<Map<String, dynamic>> subGroup(
    String orgId,
    String subGroupId,
  ) =>
      subGroups(orgId).doc(subGroupId);

  static CollectionReference<Map<String, dynamic>> announcements(String orgId) =>
      org(orgId).collection('announcements');

  static DocumentReference<Map<String, dynamic>> announcement(
    String orgId,
    String announcementId,
  ) =>
      announcements(orgId).doc(announcementId);

  /// Documents a club has shared with its members.
  static CollectionReference<Map<String, dynamic>> clubFiles(String orgId) =>
      org(orgId).collection('files');

  static CollectionReference<Map<String, dynamic>> get challenges =>
      db.collection('challenges');

  static DocumentReference<Map<String, dynamic>> challenge(String challengeId) =>
      challenges.doc(challengeId);

  static CollectionReference<Map<String, dynamic>> get lookingForPosts =>
      db.collection('lookingForPosts');

  static DocumentReference<Map<String, dynamic>> lookingForPost(String postId) =>
      lookingForPosts.doc(postId);

  static CollectionReference<Map<String, dynamic>> get sportRules =>
      db.collection('sportRules');

  static DocumentReference<Map<String, dynamic>> sportRule(String ruleId) =>
      sportRules.doc(ruleId);

  // --- Membership -------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> members(String orgId) =>
      org(orgId).collection('members');

  static DocumentReference<Map<String, dynamic>> member(
    String orgId,
    String uid,
  ) =>
      members(orgId).doc(uid);

  /// Collection-group query across every org's members. Security rules
  /// restrict this to rows whose document id equals the caller's uid, so it
  /// can only ever return the caller's own memberships.
  static Query<Map<String, dynamic>> get myMembershipsQuery =>
      db.collectionGroup('members');

  // --- Competitions -----------------------------------------------------

  static CollectionReference<Map<String, dynamic>> competitions(String orgId) =>
      org(orgId).collection('competitions');

  static DocumentReference<Map<String, dynamic>> competition(
    String orgId,
    String compId,
  ) =>
      competitions(orgId).doc(compId);

  static CollectionReference<Map<String, dynamic>> registrations(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('registrations');

  static DocumentReference<Map<String, dynamic>> registration(
    String orgId,
    String compId,
    String uid,
  ) =>
      registrations(orgId, compId).doc(uid);

  static CollectionReference<Map<String, dynamic>> entrants(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('entrants');

  static CollectionReference<Map<String, dynamic>> standings(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('standings');

  static CollectionReference<Map<String, dynamic>> attempts(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('attempts');

  // --- Fixtures & scoring ----------------------------------------------

  static CollectionReference<Map<String, dynamic>> fixtures(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('fixtures');

  static DocumentReference<Map<String, dynamic>> fixture(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixtures(orgId, compId).doc(fixtureId);

  static CollectionReference<Map<String, dynamic>> matchEvents(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixture(orgId, compId, fixtureId).collection('events');

  /// Members putting their hand up for their own club's side of a match.
  ///
  /// Hangs off the fixture rather than the competition because a challenge is
  /// one fixture and two independent selection problems — see [SquadEntry].
  static CollectionReference<Map<String, dynamic>> squadEntries(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixture(orgId, compId, fixtureId).collection('squadEntries');

  static DocumentReference<Map<String, dynamic>> squadEntry(
    String orgId,
    String compId,
    String fixtureId,
    String uid,
  ) =>
      squadEntries(orgId, compId, fixtureId).doc(uid);

  /// Every fixture across an organization, for "what is live right now" and
  /// "what am I scoring today" screens.
  static Query<Map<String, dynamic>> get allFixturesQuery =>
      db.collectionGroup('fixtures');

  /// "Let me score this one" — one document per person per match.
  ///
  /// The document id is the requester's uid, which makes "one open request
  /// per person per match" structural rather than something a repeated tap on
  /// a village 4G connection could violate.
  static CollectionReference<Map<String, dynamic>> scoringRequests(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixture(orgId, compId, fixtureId).collection('scoringRequests');

  static DocumentReference<Map<String, dynamic>> scoringRequest(
    String orgId,
    String compId,
    String fixtureId,
    String uid,
  ) =>
      scoringRequests(orgId, compId, fixtureId).doc(uid);

  /// Every scoring request across a club, for the admin's "waiting on you"
  /// list. Needs the collection-group index on (`orgId`, `status`) — a rule
  /// alone is not enough, see firestore.indexes.json.
  static Query<Map<String, dynamic>> get allScoringRequestsQuery =>
      db.collectionGroup('scoringRequests');

  // --- Memories ---------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> memories(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixture(orgId, compId, fixtureId).collection('memories');

  static DocumentReference<Map<String, dynamic>> memory(
    String orgId,
    String compId,
    String fixtureId,
    String memoryId,
  ) =>
      memories(orgId, compId, fixtureId).doc(memoryId);

  /// Every memory a player is tagged in, wherever it was taken.
  ///
  /// A collectionGroup query is the only way to answer "show me my career" for
  /// someone who has played for four clubs in three districts — the whole
  /// premise of a portable lifelong profile. Requires the composite index on
  /// (`taggedUids` array-contains, `createdAt` desc) in firestore.indexes.json.
  static Query<Map<String, dynamic>> get allMemoriesQuery =>
      db.collectionGroup('memories');

  // --- Governance -------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> auditLogs(String orgId) =>
      org(orgId).collection('auditLogs');
}
