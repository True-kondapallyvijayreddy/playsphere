/**
 * Whether the people a fixture NAMES may have their ratings moved by it.
 *
 * ## The hole this closes
 *
 * `entrantAUid`, `entrantBUid` and `playerUids` decide whose Glicko a finished
 * match moves. In firestore.rules they were `frozen()` on every update path and
 * validated on none of the creates — so the attack was four cheap writes:
 *
 *   1. found a club (free, unlimited, `allow create: if isSignedIn()`),
 *   2. open a competition stamped `sourceType: 'tournament'`, which is rated,
 *   3. create a fixture naming any two account ids in the country,
 *   4. post one event, which the events rule admits for
 *      `canManageCompetitions(orgId)`.
 *
 * `onMatchSettled` then moved both accounts' platform-wide rating, credited
 * their career records, and pushed the result out to rankingEntries,
 * talentBoards, leaderboards and every scout search. The victims were never
 * registered, never asked and never notified. Ratings could be farmed upward
 * for an account or driven down for a rival, at the cost of one free club.
 *
 * ## Why this cannot be fixed in rules alone
 *
 * Rules now tie a fixture's uids back to an `entrants` document and an
 * entrants document back to a registration, which forces a paper trail. But
 * the trail legitimately starts with the organizer: `registrations` has a
 * branch letting `canManageCompetitions` enter somebody directly, because a
 * player who turns up at the ground and is added to the draw on the day is
 * completely normal and the product has to allow it. A rule cannot tell that
 * write apart from a forged one — both are an organizer naming a uid.
 *
 * What separates them is the RELATIONSHIP. A real walk-up entrant is somebody
 * the club knows: a member, or a person who registered themselves. A forged
 * entrant is a uid the attacker's club has never had any connection to. That
 * is a question about two documents, so it belongs here rather than in a rule.
 *
 * ## What happens to an unverified participant
 *
 * Their rating does not move. Everything else does — career totals,
 * appearances, the sport tally, officiating credit — because a match a club
 * says happened is a match for the purposes of its own records, and stripping
 * somebody's appearance count is a worse failure than declining to rate them.
 * The withheld rating is logged with a reason, so a legitimate case that trips
 * this shows up as a log line an organizer can be asked about rather than as a
 * number that silently never moved.
 *
 * Pure functions over plain objects, for the same reason `ratingWithheldReason`
 * and `resolveClaim` are: the rule a settlement enforces should be checkable
 * without a database.
 */

/**
 * The membership statuses that count as a real relationship with a club.
 *
 * `pending` deliberately does not. An application nobody has decided on is
 * exactly what an attacker would write for their victim — the member-create
 * rule lets anybody self-apply to any public club, so a `pending` row proves
 * only that a write happened, not that a club accepted anyone.
 */
const TRUSTED_MEMBER_STATUSES = new Set(['active']);

/**
 * Why `uid`'s rating is being withheld on this fixture, or null when it may
 * move.
 *
 * `facts` is what the caller looked up, so this stays testable:
 *   - `memberStatus`     the uid's status in the organising club, or any club
 *                        contesting an inter-club fixture. Null when no
 *                        membership row exists anywhere relevant.
 *   - `selfRegistered`   true when a registration for this uid exists on this
 *                        competition and was NOT written by an organizer
 *                        (`preselected !== true`).
 *   - `namedInTeamEntry` true when the uid appears in the `memberUids` of a
 *                        team registration on this competition. A squad player
 *                        has no registration of their own — the document id is
 *                        the team's — and whoever runs the team put them on it,
 *                        which is a relationship of the same kind.
 */
export function ratingWithheldForParticipant(facts) {
  if (!facts) return 'unknown';
  if (facts.selfRegistered === true) return null;
  if (facts.namedInTeamEntry === true) return null;
  if (TRUSTED_MEMBER_STATUSES.has(facts.memberStatus)) return null;
  return facts.memberStatus ? `member_${facts.memberStatus}` : 'no_relationship';
}

/** The positive form, for callers that only want the yes/no. */
export function participantMayBeRated(facts) {
  return ratingWithheldForParticipant(facts) === null;
}

/**
 * Splits the uids a fixture names into the ones this match may rate and the
 * ones it may not.
 *
 * `factsByUid` is a Map or plain object keyed by uid. A uid with no entry is
 * withheld rather than allowed — the safe direction, and the one that covers a
 * read that failed.
 */
export function splitParticipantsByTrust(uids, factsByUid) {
  const get = (uid) =>
    factsByUid instanceof Map ? factsByUid.get(uid) : factsByUid?.[uid];

  const rated = [];
  const withheld = [];
  for (const uid of uids) {
    const reason = ratingWithheldForParticipant(get(uid));
    if (reason === null) rated.push(uid);
    else withheld.push({ uid, reason });
  }
  return { rated, withheld };
}

/**
 * The clubs a uid's membership may be checked against for this fixture.
 *
 * The organising club always, plus both contesting clubs in an inter-club
 * match — a visiting side's players are members of the visitor, not the host,
 * and refusing to rate them would break every school-v-school fixture.
 */
export function relevantOrgIds(fixture, orgId) {
  const ids = new Set([orgId]);
  const participants = fixture?.participantOrgIds;
  if (Array.isArray(participants)) {
    for (const id of participants) {
      if (typeof id === 'string' && id.length > 0) ids.add(id);
    }
  }
  return [...ids];
}
