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

  /// A durable inbox mirroring every push this person was ever sent — event
  /// reminders, match starts, results, approvals, challenges, tournament
  /// announcements and invites.
  ///
  /// Written only by Cloud Functions (the same trigger that sends the FCM
  /// push writes here too, in `sendToUsers`), never by a client. Pushes on
  /// their own are ephemeral: missed while the phone was asleep, dismissed
  /// without being read, or sent to a device that was reinstalled, they were
  /// gone for good and the in-app Notifications screen had nothing to show a
  /// member who is not an organizer — which is Bug #21, "notifications is
  /// empty for member". This collection is what that screen now reads.
  static CollectionReference<Map<String, dynamic>> notifications(String uid) =>
      user(uid).collection('notifications');

  static DocumentReference<Map<String, dynamic>> notification(
    String uid,
    String id,
  ) =>
      notifications(uid).doc(id);

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

  /// One club inviting another into its tournament. Top-level for the same
  /// reason `challenges` is — see [TournamentInvite] — because the document
  /// belongs to two tenants and neither org's rules can own it.
  static CollectionReference<Map<String, dynamic>> get tournamentInvites =>
      db.collection('tournamentInvites');

  static DocumentReference<Map<String, dynamic>> tournamentInvite(
    String inviteId,
  ) =>
      tournamentInvites.doc(inviteId);

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

  /// Motions to remove an owner. Doc id is the target's uid, so a club cannot
  /// hold two simultaneous votes about the same person.
  static CollectionReference<Map<String, dynamic>> ownerProposals(
    String orgId,
  ) =>
      org(orgId).collection('ownerProposals');

  static DocumentReference<Map<String, dynamic>> ownerProposal(
    String orgId,
    String targetUid,
  ) =>
      ownerProposals(orgId).doc(targetUid);

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

  /// Every competition on the platform, for the Global Events board.
  ///
  /// Needs the collection-group index on
  /// (`openToNonMembers`, `status`, `startDate`) and a collection-group READ
  /// rule — a rule written at the nested competitions path does not apply to
  /// a collectionGroup query. See firestore.rules and firestore.indexes.json.
  static Query<Map<String, dynamic>> get allCompetitionsQuery =>
      db.collectionGroup('competitions');

  static CollectionReference<Map<String, dynamic>> registrations(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('registrations');

  /// Groups of members entering an event together. See [GroupEntry].
  static CollectionReference<Map<String, dynamic>> groupEntries(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('groupEntries');

  static DocumentReference<Map<String, dynamic>> groupEntry(
    String orgId,
    String compId,
    String groupId,
  ) =>
      groupEntries(orgId, compId).doc(groupId);

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

  /// Ranking points, top-level so a district or state list can be read across
  /// every club at once. Server-written only — see `firestore.rules`.
  static CollectionReference<Map<String, dynamic>> get rankingEntries =>
      db.collection('rankingEntries');

  /// Venues belong to the organization, not to any one competition — a club
  /// plays at the same two or three places all season, and re-declaring them
  /// per event is how the court list drifts between events.
  static CollectionReference<Map<String, dynamic>> venues(String orgId) =>
      org(orgId).collection('venues');

  static DocumentReference<Map<String, dynamic>> venue(
    String orgId,
    String venueId,
  ) =>
      venues(orgId).doc(venueId);

  /// Protests against one fixture's result.
  static CollectionReference<Map<String, dynamic>> disputes(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixture(orgId, compId, fixtureId).collection('disputes');

  static CollectionReference<Map<String, dynamic>> tournaments(String orgId) =>
      org(orgId).collection('tournaments');

  static DocumentReference<Map<String, dynamic>> tournament(
    String orgId,
    String tournamentId,
  ) =>
      tournaments(orgId).doc(tournamentId);

  /// The season owner's curated shortlist of officials for one tournament —
  /// picked from the global `umpires` registry (or added by hand), distinct
  /// from both that registry and from any one fixture's assigned officials.
  /// This is what makes "assign the panel ahead of time" possible: the roster
  /// exists before a single match has been drawn, doc id = uid so a person
  /// cannot be added twice.
  static CollectionReference<Map<String, dynamic>> tournamentOfficials(
    String orgId,
    String tournamentId,
  ) =>
      tournament(orgId, tournamentId).collection('officials');

  static DocumentReference<Map<String, dynamic>> tournamentOfficial(
    String orgId,
    String tournamentId,
    String uid,
  ) =>
      tournamentOfficials(orgId, tournamentId).doc(uid);

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

  /// Cheers sent during a match. Doc id is the sender's uid, so one person is
  /// one cheer however many times they tap — a cheer is support, not a score,
  /// and a tally anyone can inflate by holding a button means nothing.
  static CollectionReference<Map<String, dynamic>> cheers(
    String orgId,
    String compId,
    String fixtureId,
  ) =>
      fixture(orgId, compId, fixtureId).collection('cheers');

  static DocumentReference<Map<String, dynamic>> cheer(
    String orgId,
    String compId,
    String fixtureId,
    String uid,
  ) =>
      cheers(orgId, compId, fixtureId).doc(uid);

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

  // --- Commerce ---------------------------------------------------------

  /// The ledger: one document per charge, for a club plan, a Premium
  /// membership or a ground booking.
  ///
  /// Top-level rather than nested under whatever was bought, because the
  /// questions asked of it are financial rather than product-shaped — "what
  /// did we collect this month", "what does this person's receipt history
  /// look like" — and neither can be a query if the rows are scattered across
  /// three different subcollection paths.
  static CollectionReference<Map<String, dynamic>> get payments =>
      db.collection('payments');

  static DocumentReference<Map<String, dynamic>> payment(String paymentId) =>
      payments.doc(paymentId);

  /// Bookable grounds, at `grounds/{groundId}`.
  ///
  /// Deliberately top-level, unlike [venues]. A venue is a club's own hall,
  /// declared so its own draws can be scheduled against it; a ground is a
  /// business someone else owns and rents to anybody. Nesting one under
  /// `orgs/` would make "find a cricket ground in Hyderabad free on Sunday"
  /// unanswerable without reading every club in the country, and would make
  /// the ground's owner a member of a club they have nothing to do with.
  static CollectionReference<Map<String, dynamic>> get grounds =>
      db.collection('grounds');

  static DocumentReference<Map<String, dynamic>> ground(String groundId) =>
      grounds.doc(groundId);

  /// Bookings against one ground.
  ///
  /// A subcollection of the ground rather than a top-level collection,
  /// because the query that matters for correctness is "what else is booked
  /// on THIS ground that day" — the double-booking check — and that has to be
  /// a single narrow read the booking transaction can afford to make.
  static CollectionReference<Map<String, dynamic>> groundBookings(
    String groundId,
  ) =>
      ground(groundId).collection('bookings');

  static DocumentReference<Map<String, dynamic>> groundBooking(
    String groundId,
    String bookingId,
  ) =>
      groundBookings(groundId).doc(bookingId);

  /// Every booking a club or a player has made, across every ground.
  ///
  /// The mirror image of [allMemoriesQuery], and needed for the same reason:
  /// "my bookings" spans grounds owned by strangers, so it can only be a
  /// collectionGroup query. Requires the composite indexes on
  /// (`bookedForOrgId`, `startsAt`) and (`bookedByUid`, `startsAt`).
  static Query<Map<String, dynamic>> get allGroundBookingsQuery =>
      db.collectionGroup('bookings');

  /// The shop catalog, at `products/{productId}`.
  ///
  /// Server/console-written and world-readable: these are vendor listings,
  /// not user content. Kept in Firestore rather than compiled into the app so
  /// a price change or a seasonal range does not need a store release — the
  /// app ships a small bundled catalog only as the offline fallback.
  static CollectionReference<Map<String, dynamic>> get products =>
      db.collection('products');

  static DocumentReference<Map<String, dynamic>> product(String productId) =>
      products.doc(productId);

  // --- Give — the equipment-donation network -----------------------------

  /// A donor's contributions, at `giveDonations/{donationId}`. See
  /// `GiveDonation` for why every stage past `submitted` is staff-only.
  static CollectionReference<Map<String, dynamic>> get giveDonations =>
      db.collection('giveDonations');

  static DocumentReference<Map<String, dynamic>> giveDonation(
    String donationId,
  ) =>
      giveDonations.doc(donationId);

  /// Drop-off points, at `giveCollectionCenters/{centerId}`. Curated the
  /// same way as [products] — world-readable, server/console-written only.
  static CollectionReference<Map<String, dynamic>>
      get giveCollectionCenters => db.collection('giveCollectionCenters');

  static DocumentReference<Map<String, dynamic>> giveCollectionCenter(
    String centerId,
  ) =>
      giveCollectionCenters.doc(centerId);

  /// Verified club/player equipment shortfalls, at `giveNeeds/{needId}`.
  static CollectionReference<Map<String, dynamic>> get giveNeeds =>
      db.collection('giveNeeds');

  static DocumentReference<Map<String, dynamic>> giveNeed(String needId) =>
      giveNeeds.doc(needId);

  /// The Give network's headline numbers, one document at
  /// `give/impactStats`. See `GiveImpactStats` for why this is
  /// function-written, not client-computed.
  static DocumentReference<Map<String, dynamic>> get giveImpactStats =>
      db.collection('give').doc('impactStats');
}
