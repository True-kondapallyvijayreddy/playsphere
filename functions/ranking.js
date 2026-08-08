/**
 * Ranking points, computed server-side.
 *
 * ## Why this is not in the client
 *
 * Everything else in this product is client + security rules, deliberately.
 * A ranking table cannot be: it decides seeding, selection and funding, which
 * makes it the most valuable thing in the database to forge. A client that can
 * write its own ranking entry can award itself a national title.
 *
 * So `rankingEntries` is written only here and is read-only to every client.
 * That is the whole reason this file exists.
 *
 * ## The duplication with Dart, stated plainly
 *
 * `lib/domain/ranking/ranking_points.dart` contains the same algorithm, and
 * that is a real cost — two implementations can drift. It is accepted because
 * the alternatives are worse: the client needs it to *preview* what an event
 * will award before a tournament is closed, and the server needs it to be the
 * only writer. The Dart version is the reference; `test/ranking_points_test.dart`
 * pins the behaviour, and the share/weight tables below are duplicated
 * verbatim so a change is a two-line diff in an obvious place rather than a
 * subtle recalculation.
 */

/** Relative worth of each finish, before grade. Mirrors `FinishingRound`. */
export const ROUND_SHARE = {
  winner: 100,
  runner_up: 60,
  semi_final: 36,
  quarter_final: 20,
  last_16: 11,
  last_32: 6,
  group_stage: 3,
  participated: 1,
};

/** Mirrors `TournamentGrade.weight`. */
export const GRADE_WEIGHT = {
  club: 1,
  district: 3,
  state: 6,
  national: 10,
  international: 15,
};

/** Formats settled by a table rather than by a deciding match. */
const TABLE_FORMATS = new Set(['round_robin', 'league_table', 'swiss']);

export function pointsFor(grade, round) {
  return (GRADE_WEIGHT[grade] ?? 1) * (ROUND_SHARE[round] ?? 1);
}

/**
 * The match that settled an event, or null for a league.
 *
 * Nobody is "runner-up" of a round robin in the sense a ranking table means,
 * so a league must not have one invented for it.
 */
function deciderOf(format, decided) {
  if (TABLE_FORMATS.has(format)) return null;
  const bracket = decided.filter((f) => f.bracket !== 'group');
  if (bracket.length === 0) return null;
  bracket.sort((a, b) =>
    b.round !== a.round ? b.round - a.round : b.matchIndex - a.matchIndex,
  );
  return bracket[0];
}

/**
 * How far out from the final somebody went.
 *
 * Derived from the bracket's actual depth rather than a round label, so
 * "semi-finalist" of a draw of 4 and of a draw of 128 are scored differently
 * and nobody can farm points from tiny events.
 */
function roundFor({
  entrantId,
  champion,
  finalist,
  lastRound,
  deepestRound,
  wonAnything,
}) {
  if (entrantId === champion) return 'winner';
  if (entrantId === finalist) return 'runner_up';
  if (lastRound === 0) return wonAnything ? 'group_stage' : 'participated';

  const fromEnd = deepestRound - lastRound;
  if (fromEnd <= 1) return 'semi_final';
  if (fromEnd === 2) return 'quarter_final';
  if (fromEnd === 3) return 'last_16';
  if (fromEnd === 4) return 'last_32';
  return 'participated';
}

/**
 * The finish a FINAL TABLE POSITION is worth.
 *
 * A league has no bracket depth to measure against, and measuring one anyway
 * is how every entrant in a round robin came out a semi-finalist: everybody
 * plays every round, so "the deepest round I reached" is the last round for
 * all of them and `deepestRound - lastRound` is zero for the champion and the
 * bottom of the table alike. A ten-player league paid 36 × grade to the player
 * who lost every match.
 *
 * A table is ranked, so the honest translation is position → the round a
 * knockout of the same field would have put you out in. First is the winner,
 * second the runner-up, third and fourth are the semi-finalists, and so on by
 * doubling. That keeps a league and a bracket of the same size worth the same,
 * which is the property the whole scheme depends on.
 */
function roundForPosition(position) {
  if (position <= 1) return 'winner';
  if (position === 2) return 'runner_up';
  if (position <= 4) return 'semi_final';
  if (position <= 8) return 'quarter_final';
  if (position <= 16) return 'last_16';
  if (position <= 32) return 'last_32';
  return 'participated';
}

/**
 * Orders a table format's entrants.
 *
 * Deliberately simple — wins, then fewest losses, then name — and deliberately
 * NOT the full `StandingsCalculator` chain the app shows on screen. This has to
 * produce the same answer as `RankingPoints` in Dart, and the tiebreak chain
 * needs per-sport configuration and decoded score states that this trigger does
 * not have. Points are what a ranking list is for; separating two entrants who
 * finished on identical records matters far less than both of them being
 * ranked above the player who lost everything, which is what was actually
 * broken. Change this and `ranking_points.dart` together.
 */
function tablePositions(decided, names) {
  const wins = new Map();
  const losses = new Map();
  for (const id of names.keys()) {
    wins.set(id, 0);
    losses.set(id, 0);
  }
  for (const f of decided) {
    const winner = f.winnerEntrantId;
    if (!wins.has(winner)) continue;
    wins.set(winner, wins.get(winner) + 1);
    const loser = winner === f.entrantAId ? f.entrantBId : f.entrantAId;
    if (losses.has(loser)) losses.set(loser, losses.get(loser) + 1);
  }

  const ordered = [...names.keys()].sort((a, b) => {
    const byWins = wins.get(b) - wins.get(a);
    if (byWins !== 0) return byWins;
    const byLosses = losses.get(a) - losses.get(b);
    if (byLosses !== 0) return byLosses;
    return nameOf(names, a).localeCompare(nameOf(names, b));
  });

  const position = new Map();
  ordered.forEach((id, index) => position.set(id, index + 1));
  return position;
}

/**
 * An entrant's display name, never undefined.
 *
 * A fixture written before a name was denormalized onto it — or one whose
 * entrant slot was filled by advancement that only wrote the id — leaves this
 * absent, and `undefined.localeCompare` threw inside the sort below. That
 * aborted `onTournamentCompleted` part-way, after some ranking batches had
 * already committed, leaving a tournament half-settled.
 */
function nameOf(names, id) {
  const n = names.get(id);
  return typeof n === 'string' && n.length > 0 ? n : id;
}

/**
 * Works out what everyone in one event earned.
 *
 * [fixtures] must be every fixture of the event; [format] and [grade] its
 * competition format wire token and the tournament's grade wire token.
 * Returns `[{ entrantId, displayName, round, points }]`.
 */
export function awardsFor({ format, grade, fixtures }) {
  const decided = fixtures.filter(
    (f) =>
      (f.status === 'completed' || f.status === 'walkover') &&
      f.winnerEntrantId,
  );
  if (decided.length === 0) return [];

  const names = new Map();
  const lastRound = new Map();
  const everWon = new Set();
  let deepestRound = 0;

  for (const f of decided) {
    for (const side of [
      { id: f.entrantAId, name: f.entrantAName },
      { id: f.entrantBId, name: f.entrantBName },
    ]) {
      if (!side.id) continue;
      names.set(side.id, side.name);
      const r = f.bracket === 'group' ? 0 : f.round;
      if (r > (lastRound.get(side.id) ?? -1)) lastRound.set(side.id, r);
      if (r > deepestRound) deepestRound = r;
    }
    everWon.add(f.winnerEntrantId);
  }
  if (names.size === 0) return [];

  const decider = deciderOf(format, decided);
  const champion = decider ? decider.winnerEntrantId : null;
  const finalist = decider
    ? decider.winnerEntrantId === decider.entrantAId
      ? decider.entrantBId
      : decider.entrantAId
    : null;

  // A format settled by a table is scored by where you finished in it; one
  // settled by a deciding match is scored by how far out you were beaten.
  const positions = TABLE_FORMATS.has(format)
    ? tablePositions(decided, names)
    : null;

  const awards = [];
  for (const entrantId of names.keys()) {
    const round = positions
      ? roundForPosition(positions.get(entrantId) ?? names.size)
      : roundFor({
          entrantId,
          champion,
          finalist,
          lastRound: lastRound.get(entrantId) ?? 0,
          deepestRound,
          wonAnything: everWon.has(entrantId),
        });
    awards.push({
      entrantId,
      displayName: nameOf(names, entrantId),
      round,
      points: pointsFor(grade, round),
    });
  }

  awards.sort((a, b) =>
    b.points !== a.points
      ? b.points - a.points
      : a.displayName.localeCompare(b.displayName),
  );
  return awards;
}

/** Human wording for a finish, for the notification a player actually reads. */
export const ROUND_LABEL = {
  winner: 'Champion',
  runner_up: 'Runner-up',
  semi_final: 'Semi-finalist',
  quarter_final: 'Quarter-finalist',
  last_16: 'Last 16',
  last_32: 'Last 32',
  group_stage: 'Group stage',
  participated: 'Took part',
};

/** 52 weeks — the rolling window every federation ranking uses. */
export const WINDOW_DAYS = 364;
