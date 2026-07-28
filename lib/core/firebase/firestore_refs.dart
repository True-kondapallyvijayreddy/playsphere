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

  /// Every fixture across an organization, for "what is live right now" and
  /// "what am I scoring today" screens.
  static Query<Map<String, dynamic>> get allFixturesQuery =>
      db.collectionGroup('fixtures');

  // --- Governance -------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> auditLogs(String orgId) =>
      org(orgId).collection('auditLogs');
}
