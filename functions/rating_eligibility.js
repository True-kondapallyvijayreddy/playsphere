/**
 * Whether a finished match is allowed to move a Glicko rating.
 *
 * ## The rule
 *
 * Glicko is for ORGANISED COMPETITION only — a season, a tournament, or a
 * standalone league table. A single match and a challenge never move a rating,
 * however they end.
 *
 * Everything else about them still settles: career totals, the sport-specific
 * tally, appearances, officiating credit, club records. A challenge is a real
 * match and counts as one everywhere a match is counted. It just does not move
 * the number that ranks players against the whole platform.
 *
 * ## Why
 *
 * A single match or a challenge is arranged, staffed and scored by the people
 * playing it. There is no draw, no organiser who did not want either side to
 * win, and no confirmation from the other end — the same unverifiable setup the
 * Arena keeps out of every rating (see arena.js). Glicko is the most valuable
 * thing in this database to forge, because it travels onto rosters, ranking
 * boards and scout searches, so it is the one number that only comes from
 * matches somebody else organised.
 *
 * `onMatchSettled` already withheld `single_match` on exactly this reasoning.
 * Challenges were rated, which is what this closes.
 *
 * ## Unstamped fixtures
 *
 * A fixture with no `sourceType` is NOT rated. Every path that creates one
 * stamps it (`CompetitionRepository` from `Competition.matchSource`,
 * `CommunityRepository` for a challenge), so a blank means a fixture older than
 * those fields — and the honest answer for a match whose provenance is unknown
 * is to leave the rating alone. `backfillMatchSource` (matchsource.js) fills
 * them in; anything it has reached rates normally from then on.
 *
 * Pure functions over plain objects, with no Firestore in sight, for the same
 * reason `resolveClaim` and `participantsOf` are: the rule a settlement
 * enforces should be checkable without a database.
 */

/**
 * The `MatchSource` wire values that carry a rating — mirroring
 * `Competition.matchSource` in lib/core/models/competition.dart, which is what
 * stamps them:
 *
 *   - `season`     — a competition inside a season container
 *   - `tournament` — a standalone competition, one sport, with a draw
 *   - `league`     — a standalone league table, which is a season by another
 *                    name: fixtures an organiser generated and a table nobody
 *                    playing controls
 *
 * Deliberately absent: `single_match`, `challenge`, and `club_event`.
 */
export const RATED_SOURCE_TYPES = new Set(['season', 'tournament', 'league']);

/** The result types a rating may be settled from. */
const RATED_RESULT_TYPES = new Set(['normal', 'retired']);

/**
 * Why this fixture's rating is being withheld, or null when it may be rated.
 *
 * One question for the trigger to ask and one word for it to log, so the
 * reasons stay enumerable instead of scattered through it.
 */
export function ratingWithheldReason(fixture) {
  if (!fixture) return 'missing';

  const source = fixture.sourceType;
  if (typeof source !== 'string' || source.length === 0) return 'unstamped';
  if (!RATED_SOURCE_TYPES.has(source)) return source;

  // A walkover, an abandonment or a disqualification is a ruling, not a
  // performance. A retirement is rated: somebody played until they could not.
  const resultType = fixture.resultType ?? 'normal';
  if (!RATED_RESULT_TYPES.has(resultType)) return resultType;

  return null;
}

/** The positive form, for callers that only want the yes/no. */
export function isRated(fixture) {
  return ratingWithheldReason(fixture) === null;
}

/**
 * The smallest field a rating may come out of.
 *
 * ## Why a floor at all
 *
 * `RATED_SOURCE_TYPES` above rests on an argument about who organised the
 * match — "a draw, an organiser who did not want either side to win,
 * confirmation from the other end". That argument is sound and it does not
 * survive a club the winner founded five minutes earlier.
 *
 * Anyone signed in may create an organization (`allow create: if isSignedIn()`
 * in firestore.rules, deliberately — a village side should not need permission
 * to exist). Its founder is its owner, so they may open a competition, stamp
 * it `tournament`, enter two accounts they control, and score it. Every check
 * in this file passes: the source type is rated, the result type is normal.
 * The rating that came out travelled onto rosters, ranking boards, talent
 * boards and scout searches exactly like one from a district championship.
 *
 * Four entrants is not a strong claim about legitimacy and is not meant to be.
 * It is the point at which a forged event stops being two accounts and a
 * fixture, and starts being a draw with byes, rounds and a bracket the forger
 * has to keep consistent — which is a great deal of work for one rating and,
 * unlike the two-account version, leaves a shape somebody reviewing the club
 * can recognise.
 *
 * The real defences are the two this sits between: `participant_trust.js`
 * refuses to rate a player with no verifiable relationship to the
 * competition, and nothing here can be reached without an organiser role in
 * the club that owns it.
 */
export const MIN_RATED_ENTRANTS = 4;

/**
 * Why the COMPETITION this fixture belongs to may not carry a rating, or null
 * when it may.
 *
 * Separate from `ratingWithheldReason` because it asks about a different
 * document, and kept pure for the same reason everything else here is: the
 * rule should be checkable without a database.
 *
 * `entrantCount` is the field `seedEntrants` and `_closeEntries` write when a
 * field is locked, so it is the organiser's own statement of how many sides
 * were in the draw. A competition with no count at all is withheld rather than
 * waved through — an unstamped field is the same unknown provenance an
 * unstamped `sourceType` is, and the honest answer to an unknown is not to
 * rate it.
 */
export function competitionRatingWithheldReason(competition) {
  if (!competition) return 'no_competition';
  const entrants = Number(competition.entrantCount);
  if (!Number.isFinite(entrants)) return 'entrant_count_missing';
  if (entrants < MIN_RATED_ENTRANTS) return `field_of_${entrants}`;
  return null;
}

/**
 * Whether the two sides of a match are actually two different people.
 *
 * A side rating itself is not a contest, and it is the cheapest forgery there
 * is: one account on both team sheets, a result, and a rating that moved
 * against an opponent who was the same person. Nothing checked it —
 * `interClubShapeValid` requires two distinct CLUBS but says nothing about
 * accounts, and an individual event has no clubs to compare.
 *
 * Takes the two already-verified squads, so a guardian playing a match
 * "against" a child whose profile they manage is caught by the same test: both
 * uids are real and distinct accounts, but a shared custodian is passed in as
 * `custodianByUid` and collapses them.
 */
export function sidesAreDistinct(sideA, sideB, custodianByUid = {}) {
  const identity = (uid) => custodianByUid[uid] ?? uid;
  const a = new Set(sideA.map(identity));
  for (const uid of sideB) {
    if (a.has(identity(uid))) return false;
  }
  return sideA.length > 0 && sideB.length > 0;
}
