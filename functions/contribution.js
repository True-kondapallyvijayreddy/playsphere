/**
 * Per-player contribution weighting, server-side.
 *
 * ## Why this had to exist
 *
 * CLAUDE.md §8.1 is explicit: a team result must be distributed to the players
 * "weighted by sport-specific performance inputs — never pure win/loss for team
 * members". `onMatchSettled` did exactly the thing that forbids — every player
 * on a side received an identical delta, so the eleventh man and the centurion
 * moved the same amount, and a rating stopped being a statement about the
 * player at all.
 *
 * The weights themselves were already computed, correctly, in
 * `lib/data/rating_service.dart` — and then discarded, because settlement had
 * moved to this trigger and nothing here read them.
 *
 * ## The duplication with Dart, stated plainly
 *
 * `lib/domain/scoring/match_award.dart` holds the same table and the same
 * arithmetic. Same trade as `ranking.js` and `glicko2.js`, for the same reason:
 * the client needs it to show the MVP and a projected rating change on a ground
 * with no signal, and the server needs to be the only writer. The Dart version
 * is the reference — `test/rating_service_test.dart` asserts every key below is
 * emitted by a real engine — and the tables are duplicated verbatim so a change
 * is an obvious two-file diff rather than a subtle recalculation.
 */

/**
 * What one unit of each statistic is worth. Mirrors
 * `ContributionScoring.weights`.
 *
 * **These keys must match what the engines actually write** — the same
 * camelCase names the plugins use for `PlayerTally`. A key that corresponds to
 * no real tally entry contributes nothing and silently reduces that sport to
 * pure win/loss, which is the bug this file exists to fix.
 */
export const CONTRIBUTION_WEIGHTS = {
  // Cricket.
  runsScored: 1.0,
  wickets: 20.0,
  catches: 10.0,
  stumpings: 12.0,
  runOuts: 10.0,
  ballsFaced: 0.1,
  fours: 1.0,
  sixes: 2.0,
  maidens: 5.0,

  // Goal and point sports.
  goals: 25.0,
  assists: 15.0,
  saves: 8.0,
  points: 1.0,
  rebounds: 2.0,
  steals: 5.0,
  blocks: 5.0,
  aces: 5.0,
  kills: 3.0,
  digs: 2.0,

  // Kabaddi and kho-kho.
  raidPoints: 5.0,
  tacklePoints: 6.0,
  superRaids: 10.0,
  superTackles: 10.0,
  touchPoints: 5.0,
  poleDives: 5.0,
  skyDives: 5.0,
  dreamRunPoints: 5.0,

  // Mind and board sports.
  boardsWon: 20.0,
  queensCovered: 10.0,
};

/** Mirrors `ContributionScoring.milestones`. */
export const CONTRIBUTION_MILESTONES = {
  runsScored: { threshold: 50, bonus: 15.0 },
  wickets: { threshold: 5, bonus: 20.0 },
  raidPoints: { threshold: 10, bonus: 15.0 },
  tacklePoints: { threshold: 5, bonus: 15.0 },
  points: { threshold: 30, bonus: 15.0 },
};

/** The key every engine writes its per-player tallies under. */
const TALLY_KEY = 'players';

/** Raw contribution points from one player's tally. Mirrors `pointsFrom`. */
export function pointsFrom(tally) {
  if (!tally) return 0;
  let pts = 0;
  for (const [key, value] of Object.entries(tally)) {
    const weight = CONTRIBUTION_WEIGHTS[key];
    if (typeof weight === 'number' && typeof value === 'number') {
      pts += value * weight;
    }
  }
  for (const [key, m] of Object.entries(CONTRIBUTION_MILESTONES)) {
    const value = tally[key];
    if (typeof value === 'number' && value >= m.threshold) pts += m.bonus;
  }
  return pts;
}

/**
 * Individual performance weights for one side, keyed by **uid**.
 *
 * Mirrors `RatingService.calculatePerformanceWeights`, with one deliberate
 * difference: that method keys by `player.id` because the client consumes it
 * alongside the line-up, while settlement here iterates uids. The tally is
 * still looked up by `player.id`, which is what the engines write against —
 * keying the lookup on uid instead would find nothing for every guest and for
 * every sport whose ids are positions rather than accounts.
 *
 * Clamped to [0.2, 1.8] exactly as the Dart does: everybody who played moves
 * somewhat, and the best performer moves a good deal more, but one enormous
 * individual game cannot swing a rating further than a season of them.
 */
export function contributionWeights(scoreState, lineup) {
  const out = new Map();
  if (!Array.isArray(lineup) || lineup.length === 0) return out;

  const tallies = (scoreState && scoreState[TALLY_KEY]) || {};

  let total = 0;
  const points = new Map();
  for (const player of lineup) {
    const pts = pointsFrom(tallies[player.id]);
    points.set(player.id, pts);
    total += pts;
  }

  const average = total / lineup.length;
  for (const player of lineup) {
    if (!player.uid) continue;
    if (average <= 0) {
      // Nobody's tally moved — a sport that keeps no per-player figures, or a
      // match that ended before anything happened. Everyone weighs the same,
      // which is the honest answer rather than an invented ranking.
      out.set(player.uid, 1);
      continue;
    }
    const raw = (points.get(player.id) ?? 0) / average;
    out.set(player.uid, Math.min(1.8, Math.max(0.2, raw)));
  }
  return out;
}

/**
 * The key a Glicko-2 rating is stored under. Mirrors `Fixture.ratingKey`.
 *
 * Chess is rated per time control (§7.11) because bullet and classical measure
 * different skills; every other sport rates as itself. Settlement wrote to the
 * bare `sportId` instead, which for chess is a document no client ever reads —
 * so a chess rating stayed at its 1500 default however many games were played.
 */
export function ratingKeyFor(fixture) {
  const sport = fixture.sportId ?? fixture.scoringPluginKey ?? 'unknown';
  if (sport !== 'chess') return sport;
  const tc = fixture.scoringConfig?.timeControl;
  return typeof tc === 'string' && tc.length > 0 ? `chess:${tc}` : 'chess';
}
