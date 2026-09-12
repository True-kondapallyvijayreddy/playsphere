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
