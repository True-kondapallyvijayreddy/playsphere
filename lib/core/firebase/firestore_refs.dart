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

  /// A guardian's one-time handoff of a managed child's profile onto the
  /// child's own device — id = the short code itself, same uniqueness trick
  /// as [playerCode]. See `functions/family.js`'s `redeemClaimCode`, the
  /// only thing that ever reads one back.
  static CollectionReference<Map<String, dynamic>> get claimCodes =>
      db.collection('claimCodes');

  static DocumentReference<Map<String, dynamic>> claimCode(String code) =>
      claimCodes.doc(code);

  /// People who have asked to be findable, id = their uid.
  ///
  /// Separate from `users` for the reason `PlayerListing`'s class doc gives:
  /// a discovery search must not run its filters across the document that
  /// also holds a birth date and a phone number. Opt-in, adults only, and
  /// deleted the moment its owner withdraws.
  static CollectionReference<Map<String, dynamic>> get playerDirectory =>
      db.collection('playerDirectory');

  static DocumentReference<Map<String, dynamic>> playerListing(String uid) =>
      playerDirectory.doc(uid);

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

  /// Every player's career stats, across every account — the only way to ask
  /// "who has played cricket recently" without reading every `users/{uid}`
  /// document in the app. Requires the composite index on (`sportId`,
  /// `lastPlayedAt`) — see `firestore.indexes.json`. Feeds
  /// `ScoutRepository.searchCandidates`.
  static Query<Map<String, dynamic>> get careerStatsGroup =>
      db.collectionGroup('career_stats');

  /// One guardian's consent grant for one scout to see one minor, at
  /// `users/{minorUid}/guardianConsents/{granteeUid}`. See `firestore.rules`
  /// on `/users/{userId}` for how this is what actually makes a minor's
  /// profile readable at all — this repository never bypasses that, it only
  /// reads the same record back for its own audit trail.
  static DocumentReference<Map<String, dynamic>> guardianConsent(
    String minorUid,
    String granteeUid,
  ) =>
      user(minorUid).collection('guardianConsents').doc(granteeUid);

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

  /// The discussion under a match availability call. A subcollection rather
  /// than a field on the announcement — see [MatchChatMessage] for why.
  static CollectionReference<Map<String, dynamic>> matchComments(
    String orgId,
    String announcementId,
  ) =>
      announcement(orgId, announcementId).collection('messages');

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

  /// Teams, top-level and org-free.
  ///
  /// Not `orgs/{orgId}/teams` on purpose: Rule 4 says a team does not need a
  /// club, and a path with an org segment in it makes the club compulsory no
  /// matter how nullable the `clubId` field is. Club affiliation is a field
  /// here, and a query — see [teamsForClub]. `subgroups` remains the
  /// club-scoped concept.
  static CollectionReference<Map<String, dynamic>> get teams =>
      db.collection('teams');

  static DocumentReference<Map<String, dynamic>> team(String teamId) =>
      teams.doc(teamId);

  /// Every team a person is on the roster of.
  ///
  /// Filtered to active teams, because the caller is always building a picker
  /// or a profile list and an archived squad from 2023 is noise in both. The
  /// history of a disbanded team is reached from the matches it played, which
  /// is where somebody looking for it is actually looking.
  static Query<Map<String, dynamic>> teamsForMember(String uid) => teams
      .where('memberUids', arrayContains: uid)
      .where('status', isEqualTo: 'active');

  /// A club's teams, permanent and event alike.
  static Query<Map<String, dynamic>> teamsForClub(String orgId) =>
      teams.where('clubId', isEqualTo: orgId).where('status', isEqualTo: 'active');

  /// The event teams raised for one competition.
  static Query<Map<String, dynamic>> teamsForCompetition(String compId) =>
      teams.where('competitionId', isEqualTo: compId);

  /// Independent teams in one sport — the squads with no club behind them.
  ///
  /// A direct query, not a fan-out across clubs. It is allowed because
  /// `firestore.rules` opens `/teams/{teamId}` to any signed-in reader as a
  /// flat rule with no per-club condition on it — unlike a fixture, whose
  /// read depends on `orgIsReadable(orgId)` and therefore genuinely cannot be
  /// asked platform-wide. A club team is still reached through
  /// [teamsForClub]; this is the half that has no club to be reached through.
  static Query<Map<String, dynamic>> independentTeamsForSport(String sportId) =>
      teams
          .where('type', isEqualTo: 'independent')
          .where('sportId', isEqualTo: sportId)
          .where('status', isEqualTo: 'active');

  /// The team a shared code points at. See `Team.joinCode` for why finding a
  /// team is all a code does.
  static Query<Map<String, dynamic>> teamsByJoinCode(String code) =>
      teams.where('joinCode', isEqualTo: code.trim().toUpperCase()).limit(1);

  /// People asking to be let onto one team.
  static CollectionReference<Map<String, dynamic>> teamJoinRequests(
    String teamId,
  ) =>
      team(teamId).collection('joinRequests');

  static DocumentReference<Map<String, dynamic>> teamJoinRequest(
    String teamId,
    String uid,
  ) =>
      teamJoinRequests(teamId).doc(uid);

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

  /// Who follows a club. Distinct from membership on purpose: following is a
  /// reader's relationship — it asks for a club's news on the home feed and
  /// confers nothing else — where membership is a roster entry with a role.
  static CollectionReference<Map<String, dynamic>> followers(String orgId) =>
      org(orgId).collection('followers');

  static DocumentReference<Map<String, dynamic>> follower(
    String orgId,
    String uid,
  ) =>
      followers(orgId).doc(uid);

  /// Collection-group query across every org's followers. Restricted by rules
  /// to rows whose document id is the caller's uid, exactly like
  /// [myMembershipsQuery], so it can only return the caller's own follows.
  static Query<Map<String, dynamic>> get myFollowsQuery =>
      db.collectionGroup('followers');

  /// Members of THIS club putting their hand up for a season another club
  /// invited it into. Nested under the invited club, not the host — see
  /// [SeasonInterest] for why the host neither needs nor gets this list.
  static CollectionReference<Map<String, dynamic>> seasonInterest(
    String orgId,
  ) =>
      org(orgId).collection('seasonInterest');

  static DocumentReference<Map<String, dynamic>> seasonInterestDoc(
    String orgId,
    String interestId,
  ) =>
      seasonInterest(orgId).doc(interestId);

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

  /// Every entry this person has made, across every club and event.
  ///
  /// The only way to answer "what have I entered?" without opening each of a
  /// club's events in turn and reading its entry list. Two shapes of entry
  /// answer to one person and both are queried through here: an individual
  /// entry, whose document id and `uid` are the person, and a TEAM entry,
  /// whose id is the team's and which names its players in `memberUids` —
  /// see [Registration.teamId].
  ///
  /// Needs the collection-group indexes on `uid` and `memberUids`, and the
  /// `{path=**}/registrations` read rule: a rule written at the nested
  /// registrations path does not apply to a collectionGroup query, and that
  /// rule is deliberately narrower than the nested one — a club's members can
  /// all read who has entered their own club's event, but a cross-club query
  /// has no club to be a member of, so the only defensible reader is somebody
  /// the entry is about. Same reasoning as [allGroupEntriesQuery].
  static Query<Map<String, dynamic>> get allRegistrationsQuery =>
      db.collectionGroup('registrations');

  /// Groups of members entering an event together. See [GroupEntry].
  static CollectionReference<Map<String, dynamic>> groupEntries(
    String orgId,
    String compId,
  ) =>
      competition(orgId, compId).collection('groupEntries');

  /// Every squad invitation across every club and event, for the one screen
  /// that can answer "who is asking me to play for them".
  ///
  /// Needs the collection-group index on (`memberUids` array-contains,
  /// `status`) and the `{path=**}/groupEntries` read rule — see
  /// firestore.indexes.json and firestore.rules. A group entry only reaches
  /// the person it names through this query: the invitation lives on an event
  /// page they have no reason to open.
  static Query<Map<String, dynamic>> get allGroupEntriesQuery =>
      db.collectionGroup('groupEntries');

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

  /// One club ladder per sport, written nightly by `functions/clubs.js`.
  /// Server-written only — see `firestore.rules`.
  static CollectionReference<Map<String, dynamic>> get clubStandings =>
      db.collection('clubStandings');

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

  /// How one season is using one venue — its days, sessions, blackouts, match
  /// length and daily ceiling. Doc id = the venue id, so a season cannot hold
  /// two conflicting plans for the same ground.
  ///
  /// Season-scoped rather than written onto the venue itself: a school lending
  /// its ground for a fortnight in June is a fact about June, and storing it
  /// on the building would have August's season inherit June's blackouts.
  static CollectionReference<Map<String, dynamic>> venuePlans(
    String orgId,
    String tournamentId,
  ) =>
      tournament(orgId, tournamentId).collection('venuePlans');

  static DocumentReference<Map<String, dynamic>> venuePlan(
    String orgId,
    String tournamentId,
    String venueId,
  ) =>
      venuePlans(orgId, tournamentId).doc(venueId);

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

  /// One document per hour a booking covers, at
  /// `grounds/{groundId}/hourHolds/{dayKey}_{hour}` — the mechanism that
  /// actually makes [GroundRepository.book] exclusive.
  ///
  /// Nothing reads this collection; the booking calendar is [groundBookings].
  /// It exists purely so two people racing for the same hour collide on a
  /// document id inside one transaction. A `Transaction` can only detect a
  /// conflict on a document it read BY REFERENCE — reading it via a `Query`
  /// (which is what the exclusivity check used to do) is untracked and
  /// proves nothing. See `firestore.rules` on `hourHolds` for the full
  /// story, and `GroundRepository.book`/`cancelBooking` for where these are
  /// created and released.
  static CollectionReference<Map<String, dynamic>> groundHourHolds(
    String groundId,
  ) =>
      ground(groundId).collection('hourHolds');

  static DocumentReference<Map<String, dynamic>> groundHourHold(
    String groundId,
    String dayKey,
    int hour,
  ) =>
      groundHourHolds(groundId).doc('${dayKey}_$hour');

  /// The evidence behind a listing, at
  /// `grounds/{groundId}/verification/{proofId}`.
  ///
  /// ## Why a private subcollection and not fields on the ground
  ///
  /// `grounds/{groundId}` is world-readable so that search works for somebody
  /// who has not signed in. The proofs carry the owner's precise standing
  /// position at a known time and an electricity bill with their home address
  /// on it. Hanging those off a public document to power a badge would leak
  /// more than the fraud it prevents takes.
  ///
  /// Readable by the owner who filed it and by an admin reviewing it, and by
  /// nobody else — see `firestore.rules`.
  static CollectionReference<Map<String, dynamic>> groundVerification(
    String groundId,
  ) =>
      ground(groundId).collection('verification');

  /// The ownership declaration, at a fixed id because there is exactly one
  /// per ground and re-submitting after a rejection replaces it rather than
  /// appending a second claim beside the first.
  static DocumentReference<Map<String, dynamic>> groundClaim(String groundId) =>
      groundVerification(groundId).doc('claim');

  /// Arrivals, at `grounds/{groundId}/checkIns/{bookingId}`.
  ///
  /// Keyed by the booking rather than by a generated id, which is what makes
  /// "one check-in per slot" a property of the collection instead of a rule
  /// somebody has to remember. A second arrival on the same booking
  /// overwrites the first and the count does not move.
  static CollectionReference<Map<String, dynamic>> groundCheckIns(
    String groundId,
  ) =>
      ground(groundId).collection('checkIns');

  static DocumentReference<Map<String, dynamic>> groundCheckIn(
    String groundId,
    String bookingId,
  ) =>
      groundCheckIns(groundId).doc(bookingId);

  /// Complaints about listings, at `groundReports/{reporterUid}_{groundId}`.
  ///
  /// Top-level rather than nested under the ground it is about, for the same
  /// reason grounds are not nested under orgs: the query that matters is the
  /// admin's — "everything reported, worst first, across every ground" — and
  /// under a subcollection that is a collectionGroup read of a collection
  /// whose parents are the very documents under suspicion.
  static CollectionReference<Map<String, dynamic>> get groundReports =>
      db.collection('groundReports');

  static DocumentReference<Map<String, dynamic>> groundReport(String id) =>
      groundReports.doc(id);

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
  /// District rollups written by `functions/gov.js` — see
  /// `GovAggregateRow`. Admin-claim gated in `firestore.rules`.
  static CollectionReference<Map<String, dynamic>> get govAggregates =>
      db.collection('gov_aggregates');

  /// Precomputed talent-discovery leaderboards written by
  /// `functions/talent.js`. The document id is a `TalentBoardKey`, and its
  /// final segment (`__public` / `__scout`) is what `firestore.rules` gates
  /// the read on — see `TalentBoard` for why the audience lives in the id.
  static CollectionReference<Map<String, dynamic>> get talentBoards =>
      db.collection('talentBoards');

  static DocumentReference<Map<String, dynamic>> talentBoard(String boardId) =>
      talentBoards.doc(boardId);

  /// Per-sport directory totals written nightly by `functions/sports.js`.
  /// The document id is the `SportCatalog` sport id. Publicly readable —
  /// see the rule's comment in `firestore.rules` for why this aggregate is
  /// ungated where the others are not.
  static CollectionReference<Map<String, dynamic>> get sportStats =>
      db.collection('sportStats');

  static DocumentReference<Map<String, dynamic>> sportStat(String sportId) =>
      sportStats.doc(sportId);

  /// Per-sport, per-stat leaderboards written hourly by
  /// `functions/leaderboard.js`. The document id is `{sportId}:{statKey}` —
  /// see `LeaderboardKey.docId`. Publicly readable, same reasoning as
  /// [sportStats]: eligibility (public visibility, not a minor) was decided
  /// server-side before the document was ever written.
  static CollectionReference<Map<String, dynamic>> get leaderboards =>
      db.collection('leaderboards');

  static DocumentReference<Map<String, dynamic>> leaderboard(String boardId) =>
      leaderboards.doc(boardId);

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

  // --- Coaches -------------------------------------------------------------

  /// Coach listings, at `coaches/{uid}`. Top-level for the same reason
  /// [grounds] is: "who coaches kabaddi in Warangal" has to be one query, and
  /// most coaches belong to no club at all, so there is no org to nest them
  /// under. Keyed by uid — see `CoachProfile` for why a person is one coach.
  static CollectionReference<Map<String, dynamic>> get coaches =>
      db.collection('coaches');

  static DocumentReference<Map<String, dynamic>> coach(String uid) =>
      coaches.doc(uid);

  // --- Sports medicine -----------------------------------------------------

  /// Sports doctors, physiotherapists and surgeons who have listed
  /// themselves, at `sportsMedics/{uid}`.
  ///
  /// A separate collection from [coaches] rather than a `role` field on it.
  /// The two answer different questions and carry different duties of care —
  /// see `SportsMedicProfile` — and merging them would put an unverified
  /// coach into the results for "orthopaedic surgeon", which is the one
  /// mistake this directory must not make. Keyed by uid for the same reason
  /// [coach] is: a person is one practitioner.
  static CollectionReference<Map<String, dynamic>> get sportsMedics =>
      db.collection('sportsMedics');

  static DocumentReference<Map<String, dynamic>> sportsMedic(String uid) =>
      sportsMedics.doc(uid);

  /// Local sports shops that have listed themselves, at `sportsShops/{uid}`.
  ///
  /// A third selling surface and deliberately none of the other two — see
  /// `SportsShop`'s class doc. [products] is a curated catalogue with prices,
  /// [clubProducts] is one club selling to its own members, and this is a
  /// real shop a club rings about twenty jerseys. Keyed by uid for the same
  /// reason [coach] and [sportsMedic] are: one account is one listing.
  static CollectionReference<Map<String, dynamic>> get sportsShops =>
      db.collection('sportsShops');

  static DocumentReference<Map<String, dynamic>> sportsShop(String uid) =>
      sportsShops.doc(uid);

  // --- Sponsor an Athlete / Sponsor a Team --------------------------------

  /// Discoverable sponsorship listings, at `sponsorshipListings/{listingId}`.
  /// Top-level for the same reason [grounds] is: "athletes in Warangal
  /// playing kabaddi" has to be a query, not a scan of every org in the
  /// country.
  static CollectionReference<Map<String, dynamic>> get sponsorshipListings =>
      db.collection('sponsorshipListings');

  static DocumentReference<Map<String, dynamic>> sponsorshipListing(
    String listingId,
  ) =>
      sponsorshipListings.doc(listingId);

  /// Every pledge, at `sponsorPledges/{pledgeId}`. Top-level rather than a
  /// subcollection of the listing — see `SponsorPledge`'s class doc: both
  /// "every pledge I've made" (by `sponsorUid`) and "every pledge waiting on
  /// my listing" (by `listingId`) need to be direct queries.
  static CollectionReference<Map<String, dynamic>> get sponsorPledges =>
      db.collection('sponsorPledges');

  static DocumentReference<Map<String, dynamic>> sponsorPledge(
    String pledgeId,
  ) =>
      sponsorPledges.doc(pledgeId);

  // --- Club Commerce -------------------------------------------------------

  /// Every club's storefront items, at `clubProducts/{productId}`. Top-level
  /// like [grounds] and [giveNeeds] — denormalized `orgId`/`orgName` on each
  /// document is what makes "this club's storefront" a plain equality query
  /// rather than a nested-collection read that a future "discover club merch
  /// near me" screen could never span.
  static CollectionReference<Map<String, dynamic>> get clubProducts =>
      db.collection('clubProducts');

  static DocumentReference<Map<String, dynamic>> clubProduct(
    String productId,
  ) =>
      clubProducts.doc(productId);

  /// Every order, at `clubOrders/{orderId}`. Top-level for the same reason
  /// `giveDonations` is: "everything I've ordered" and "everything waiting on
  /// my club to fulfil" are both single-field queries a person can run
  /// without reading every club's order book.
  static CollectionReference<Map<String, dynamic>> get clubOrders =>
      db.collection('clubOrders');

  static DocumentReference<Map<String, dynamic>> clubOrder(String orderId) =>
      clubOrders.doc(orderId);

  // --- Advertising -----------------------------------------------------

  /// Every advertiser's campaign, at `adCampaigns/{campaignId}`. See
  /// `AdCampaign` and `lib/core/ads/promo.dart`.
  static CollectionReference<Map<String, dynamic>> get adCampaigns =>
      db.collection('adCampaigns');

  static DocumentReference<Map<String, dynamic>> adCampaign(
    String campaignId,
  ) =>
      adCampaigns.doc(campaignId);

  // --- Food & delivery at the ground ---------------------------------------

  /// One ground's canteen menu, at `groundMenuItems/{itemId}`. Top-level,
  /// denormalized `groundId`/`groundName`, same reasoning as [clubProducts].
  static CollectionReference<Map<String, dynamic>> get groundMenuItems =>
      db.collection('groundMenuItems');

  static DocumentReference<Map<String, dynamic>> groundMenuItem(
    String itemId,
  ) =>
      groundMenuItems.doc(itemId);

  /// Every food order, at `foodOrders/{orderId}`. Top-level, same reasoning
  /// as [clubOrders].
  static CollectionReference<Map<String, dynamic>> get foodOrders =>
      db.collection('foodOrders');

  static DocumentReference<Map<String, dynamic>> foodOrder(String orderId) =>
      foodOrders.doc(orderId);

  // --- The operations team -------------------------------------------------

  /// The PlaySphere ops roster, at `platformStaff/{uid}` — see
  /// `StaffMember`'s class doc for why this exists alongside the `admin`
  /// custom claim rather than instead of it. Keyed by uid so a member is
  /// their own document id and adding somebody twice is idempotent.
  static CollectionReference<Map<String, dynamic>> get platformStaff =>
      db.collection('platformStaff');

  static DocumentReference<Map<String, dynamic>> staffMember(String uid) =>
      platformStaff.doc(uid);

  // --- The club owners' network --------------------------------------------

  /// The messages of one conversation between two clubs, at
  /// `clubThreads/{threadId}/messages/{messageId}`.
  ///
  /// Top-level and id-derived — see [ClubThread.idFor] for why the sorted
  /// pair IS the document id, and why a conversation is between two CLUBS
  /// rather than two people. There is deliberately no document at
  /// `clubThreads/{threadId}` itself: the messages are the conversation, and
  /// each club's summary of it lives on its own side in [clubInbox].
  static CollectionReference<Map<String, dynamic>> clubMessages(
    String threadId,
  ) =>
      db.collection('clubThreads').doc(threadId).collection('messages');

  /// A thread's messages, newest first and capped. A conversation is read
  /// from the bottom, and holding a listener over an unbounded history on a
  /// phone is a bill rather than a feature.
  static Query<Map<String, dynamic>> clubMessageHistory(
    String threadId, {
    int limit = 120,
  }) =>
      clubMessages(threadId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

  /// One club's inbox, at `orgs/{orgId}/clubThreads/{threadId}` — one row per
  /// conversation it is part of.
  ///
  /// Under the club rather than alongside the messages, and this is the one
  /// path in the file whose shape is dictated by the security rules rather
  /// than by the data. Firestore evaluates a `list` against the QUERY, with a
  /// resource synthesised from its constraints, not against the documents it
  /// would return — so a top-level collection filtered by
  /// `orgIds array-contains myClub` cannot be authorised by any rule that
  /// reads the document, and the inbox would be permission-denied for
  /// everybody. The club id has to be in the PATH. See `firestore.rules`.
  ///
  /// It also means the read marker sits on a document only its own club can
  /// write, and each club's unread state is its own business.
  static CollectionReference<Map<String, dynamic>> clubInbox(String orgId) =>
      org(orgId).collection('clubThreads');

  static DocumentReference<Map<String, dynamic>> clubInboxRow(
    String orgId,
    String threadId,
  ) =>
      clubInbox(orgId).doc(threadId);

  /// Every conversation one club is part of, most recent first. A single-field
  /// order, so no composite index is needed.
  static Query<Map<String, dynamic>> threadsForClub(String orgId) =>
      clubInbox(orgId)
          .orderBy('lastMessageAt', descending: true)
          .limit(80);

  // --- The Arena -----------------------------------------------------------

  /// Board games between two members, at `arenaMatches/{matchId}`.
  ///
  /// Top-level and org-free on purpose. An Arena game is between two PEOPLE:
  /// they may have found each other inside a club and the club is recorded as
  /// a label, but a game must not disappear because somebody left that club,
  /// and two members of different clubs must be able to play at all.
  static CollectionReference<Map<String, dynamic>> get arenaMatches =>
      db.collection('arenaMatches');

  static DocumentReference<Map<String, dynamic>> arenaMatch(String matchId) =>
      arenaMatches.doc(matchId);

  /// Every game a member is in, newest activity first. One query for the
  /// whole Arena home screen: invitations, games in progress and finished
  /// games are the same documents in different states, so splitting them
  /// into three queries would cost three indexes to show one list.
  /// The Arena ladder, at `arenaStats/{uid}`. Readable by any signed-in
  /// member and written only by `functions/arena.js` — see the rule.
  static CollectionReference<Map<String, dynamic>> get arenaStats =>
      db.collection('arenaStats');

  static DocumentReference<Map<String, dynamic>> arenaStatsFor(String uid) =>
      arenaStats.doc(uid);

  /// The leaderboard: most wins first, most games played breaking the tie so
  /// somebody with one lucky win does not outrank a regular.
  ///
  /// Ordered on the overall totals rather than per game. Firestore would need
  /// a separate composite index for every game to sort on `byGame.chess.won`,
  /// which is six indexes to reorder a list of fifty rows the client already
  /// holds — so the per-game view re-sorts these in memory instead.
  static Query<Map<String, dynamic>> get arenaLeaderboard => arenaStats
      .orderBy('won', descending: true)
      .orderBy('played', descending: true)
      .limit(50);

  static Query<Map<String, dynamic>> arenaMatchesFor(String uid) =>
      arenaMatches
          .where('players', arrayContains: uid)
          .orderBy('updatedAt', descending: true)
          .limit(60);

  // --- Player auctions ---------------------------------------------------
  //
  // Top-level and org-free, like `giveDonations` and `sponsorships`. See the
  // header of lib/core/models/auction.dart for why an auction is not nested
  // under a club even when a club runs it.

  /// Every auction, at `auctions/{auctionId}`.
  static CollectionReference<Map<String, dynamic>> get auctions =>
      db.collection('auctions');

  static DocumentReference<Map<String, dynamic>> auction(String auctionId) =>
      auctions.doc(auctionId);

  /// One document per claimed join code, id = the code itself.
  ///
  /// Exactly the trick `playerCodes` uses, for exactly the same two reasons:
  /// Firestore has no unique constraint, so uniqueness is bought by making
  /// the code a DOCUMENT ID and claiming it with a create that fails if it is
  /// taken; and the lookup has to work for somebody who cannot yet read the
  /// auction at all — an unlisted auction is invisible until you are in it,
  /// and the code is the whole way in — so it has to be a tiny public
  /// document holding a name and an id, never the auction itself.
  static CollectionReference<Map<String, dynamic>> get auctionCodes =>
      db.collection('auctionCodes');

  static DocumentReference<Map<String, dynamic>> auctionCode(String code) =>
      auctionCodes.doc(code);

  /// Everyone taking part in one auction, id = their uid.
  static CollectionReference<Map<String, dynamic>> auctionParticipants(
    String auctionId,
  ) =>
      auction(auctionId).collection('participants');

  static DocumentReference<Map<String, dynamic>> auctionParticipant(
    String auctionId,
    String uid,
  ) =>
      auctionParticipants(auctionId).doc(uid);

  /// "Which auctions am I in", across every auction in the product.
  ///
  /// A collection-group query, authorised by the `/{path=**}/participants`
  /// rule, which is the same shape as the members and followers groups
  /// already in firestore.rules. It is the ONLY way to find an unlisted
  /// auction you have already joined — nothing else the client can query
  /// names it.
  static Query<Map<String, dynamic>> get auctionParticipantsGroup =>
      db.collectionGroup('participants');

  /// The bidding sides, id = the owner's uid. See `AuctionTeam`.
  static CollectionReference<Map<String, dynamic>> auctionTeams(
    String auctionId,
  ) =>
      auction(auctionId).collection('teams');

  static DocumentReference<Map<String, dynamic>> auctionTeam(
    String auctionId,
    String teamId,
  ) =>
      auctionTeams(auctionId).doc(teamId);

  /// The player pool, id = the player's uid.
  static CollectionReference<Map<String, dynamic>> auctionLots(
    String auctionId,
  ) =>
      auction(auctionId).collection('lots');

  static DocumentReference<Map<String, dynamic>> auctionLot(
    String auctionId,
    String lotId,
  ) =>
      auctionLots(auctionId).doc(lotId);

  /// Sealed bids on one player, id = the bidding team's id.
  ///
  /// The id is what keeps a bid secret — see `AuctionBid`. No client ever
  /// writes here; `placeAuctionBid` does, in a transaction with the team's
  /// purse.
  static CollectionReference<Map<String, dynamic>> auctionBids(
    String auctionId,
    String lotId,
  ) =>
      auctionLot(auctionId, lotId).collection('bids');

  static DocumentReference<Map<String, dynamic>> auctionBid(
    String auctionId,
    String lotId,
    String teamId,
  ) =>
      auctionBids(auctionId, lotId).doc(teamId);

  /// One team's own bids across every lot in one auction — the "my bids"
  /// screen, and the only read that needs a collection group inside a single
  /// auction. Filtered by `teamId` so the per-bid rule can authorise each
  /// document it returns.
  static Query<Map<String, dynamic>> get auctionBidsGroup =>
      db.collectionGroup('bids');

  /// Proposed exchanges between two squads.
  static CollectionReference<Map<String, dynamic>> auctionTrades(
    String auctionId,
  ) =>
      auction(auctionId).collection('trades');

  static DocumentReference<Map<String, dynamic>> auctionTrade(
    String auctionId,
    String tradeId,
  ) =>
      auctionTrades(auctionId).doc(tradeId);
}
