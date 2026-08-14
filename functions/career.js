/**
 * Per-match tally extraction, server-side.
 *
 * Mirrors `PlayerTally.of` (lib/domain/scoring/player_stats.dart) and
 * `CareerAggregator.contributionsFrom` (lib/domain/career/career_stats.dart)
 * — the Dart aggregator was written to compute exactly this shape but has
 * never been reachable from the JS Cloud Function that is the only writer
 * of `career_stats`. This file is the JS side of the same computation,
 * duplicated deliberately for the same reason `contribution.js` duplicates
 * `match_award.dart`: the server has to be the only writer, and both
 * languages need the shape to be independently testable.
 */

/** The key every scoring engine writes its per-player tallies under. Mirrors `PlayerTally.stateKey`. */
const TALLY_KEY = 'players';

/** One player's raw tally from a match's score state. Mirrors `PlayerTally.of`. */
export function playerTally(scoreState, playerId) {
  const all = (scoreState && scoreState[TALLY_KEY]) || {};
  const mine = all[playerId] || {};
  const out = {};
  for (const [k, v] of Object.entries(mine)) {
    if (typeof v === 'number') out[k] = v;
  }
  return out;
}
