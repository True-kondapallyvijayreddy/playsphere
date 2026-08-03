/**
 * Glicko-2, server-side.
 *
 * ## Why this had to move off the client
 *
 * `firestore.rules` already narrowed rating writes a long way: the caller must
 * be an assigned scorer on a fixture the target actually played in, every
 * field is typed and range-checked, `gamesPlayed` may only advance by one, and
 * a single write may only move a rating by a bounded amount. That stopped a
 * passing stranger from overwriting anybody's rating.
 *
 * It could not stop the thing that matters most. The rules file says so
 * itself: they cannot verify that a bounded single-game delta corresponds to a
 * real result rather than a small self-serving nudge, repeated. A scorer of
 * genuine matches could walk their own rating upward a little at a time and
 * every individual write would look legitimate. `matchesPlayed` and the career
 * tallies are worse — they go through `FieldValue.increment()`, whose resolved
 * value rules cannot see at evaluation time, so they were never range-checked
 * at all.
 *
 * Settling here removes the question. The client no longer writes ratings, the
 * rules deny every client write outright, and the numbers are derived from the
 * event-sourced fixture the trigger reads for itself.
 *
 * Ported from `lib/domain/rating/glicko2.dart`, which stays as the reference
 * and keeps its tests. Same duplication trade as `ranking.js`, for the same
 * reason: the client still needs to *show* a projected rating change.
 */

const DEFAULT_RATING = 1500;
const DEFAULT_DEVIATION = 350;
const DEFAULT_VOLATILITY = 0.06;

/** Glicko → Glicko-2 scale factor. */
const SCALE = 173.7178;
const EPSILON = 0.000001;

/** Glickman's τ. 0.5 suits amateur sport, where genuine step changes in
 *  ability are rarer than upsets. */
const SYSTEM_CONSTANT = 0.5;

function g(phi) {
  return 1 / Math.sqrt(1 + (3 * phi * phi) / (Math.PI * Math.PI));
}

function e(mu, muJ, phiJ) {
  return 1 / (1 + Math.exp(-g(phiJ) * (mu - muJ)));
}

/**
 * Illinois-variant regula falsi, as Glickman specifies. Iterative because the
 * volatility equation has no closed form.
 */
function newVolatility({ phi, sigma, v, delta }) {
  const a = Math.log(sigma * sigma);
  const tau = SYSTEM_CONSTANT;

  const f = (x) => {
    const ex = Math.exp(x);
    const phi2 = phi * phi;
    const num = ex * (delta * delta - phi2 - v - ex);
    const den = 2 * Math.pow(phi2 + v + ex, 2);
    return num / den - (x - a) / (tau * tau);
  };

  let bigA = a;
  let bigB;
  if (delta * delta > phi * phi + v) {
    bigB = Math.log(delta * delta - phi * phi - v);
  } else {
    let k = 1;
    while (f(a - k * tau) < 0 && k < 100) k++;
    bigB = a - k * tau;
  }

  let fA = f(bigA);
  let fB = f(bigB);
  let guard = 0;
  while (Math.abs(bigB - bigA) > EPSILON && guard < 200) {
    const c = bigA + ((bigA - bigB) * fA) / (fB - fA);
    const fC = f(c);
    if (fC * fB <= 0) {
      bigA = bigB;
      fA = fB;
    } else {
      fA = fA / 2;
    }
    bigB = c;
    fB = fC;
    guard++;
  }
  return Math.exp(bigA / 2);
}

/**
 * Applies one rating period's worth of results.
 *
 * `games` is `[{ opponent: {rating, deviation}, score, weight }]`, score being
 * 1 / 0.5 / 0.
 *
 * With no games the rating is unchanged but the deviation GROWS: a player who
 * has not played for months is genuinely less predictable, and a system that
 * pretends otherwise lets a stale rating sit at the top of a leaderboard
 * indefinitely.
 */
export function rate(player, games) {
  const mu = (player.rating - DEFAULT_RATING) / SCALE;
  const phi = player.deviation / SCALE;
  const sigma = player.volatility;

  if (!games || games.length === 0) {
    const phiStar = Math.sqrt(phi * phi + sigma * sigma);
    return {
      ...player,
      deviation: Math.min(phiStar * SCALE, DEFAULT_DEVIATION),
    };
  }

  let vInv = 0;
  let deltaSum = 0;
  for (const game of games) {
    const weight = game.weight ?? 1;
    const muJ = (game.opponent.rating - DEFAULT_RATING) / SCALE;
    const phiJ = game.opponent.deviation / SCALE;
    const gj = g(phiJ);
    const ej = e(mu, muJ, phiJ);
    vInv += weight * gj * gj * ej * (1 - ej);
    deltaSum += weight * gj * (game.score - ej);
  }
  if (vInv <= 0) return player;

  const v = 1 / vInv;
  const delta = v * deltaSum;

  const sigmaPrime = newVolatility({ phi, sigma, v, delta });
  const phiStar = Math.sqrt(phi * phi + sigmaPrime * sigmaPrime);
  const phiPrime = 1 / Math.sqrt(1 / (phiStar * phiStar) + 1 / v);
  const muPrime = mu + phiPrime * phiPrime * deltaSum;

  return {
    rating: muPrime * SCALE + DEFAULT_RATING,
    deviation: phiPrime * SCALE,
    volatility: sigmaPrime,
    gamesPlayed: (player.gamesPlayed ?? 0) + games.length,
  };
}

export function defaultRating() {
  return {
    rating: DEFAULT_RATING,
    deviation: DEFAULT_DEVIATION,
    volatility: DEFAULT_VOLATILITY,
    gamesPlayed: 0,
  };
}

export { DEFAULT_RATING, DEFAULT_DEVIATION, DEFAULT_VOLATILITY };
