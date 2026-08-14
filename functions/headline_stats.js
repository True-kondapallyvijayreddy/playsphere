/**
 * Server-side mirror of `ScoringPlugin.headlineStats`
 * (lib/domain/scoring/scoring_plugin.dart and its per-sport overrides) —
 * the 1-2 tally keys that stand for "the" stat in each sport for a
 * leaderboard, cricket's `runsScored`/`wickets`, kabaddi's
 * `raidPoints`/`tacklePoints`.
 *
 * Cloud Functions cannot import Dart, so this is the JS half of the same
 * declaration, kept in sync by hand — the same reason `contribution.js`
 * duplicates `match_award.dart` and `career.js` duplicates
 * `CareerAggregator`. `leaderboard.test.mjs` cross-checks the keys this file
 * lists against the tally keys `career.test.mjs` already exercises, which
 * catches a renamed key even though it cannot catch a plugin added on one
 * side and not the other.
 *
 * Keyed by base sport id — before any `:qualifier` a rating key can carry
 * (chess's `blitz`/`classical`) — mirroring how `CareerLine.sportId` is
 * split everywhere else career data is read.
 *
 * A sport absent here (or mapped to an empty list) is not ranked. Athletics
 * is the deliberate case: its headline number is a personal best, not a
 * running count, and summing bests across meets would not mean anything —
 * see the Dart base class's own doc for the same reasoning. The generic
 * fallback plugins (`goal_based`, `simple_points`, `set_based` — used by
 * sports with no bespoke engine) keep no per-player box score at all, so
 * they have nothing to rank either.
 */
export const HEADLINE_STATS = {
  cricket: ['runsScored', 'wickets'],
  badminton: ['pointsWon'],
  table_tennis: ['pointsWon'],
  tennis: ['pointsWon'],
  volleyball: ['kills'],
  basketball: ['points'],
  football: ['goals'],
  hockey: ['goals'],
  kabaddi: ['raidPoints', 'tacklePoints'],
  kho_kho: ['touchPoints'],
  carrom: ['boardsWon'],
  chess: ['points'],
};

/** The headline stat keys for a sport id, `[]` if it is not ranked. */
export function headlineStatsFor(sportId) {
  const base = typeof sportId === 'string' ? sportId.split(':')[0] : '';
  return HEADLINE_STATS[base] ?? [];
}
