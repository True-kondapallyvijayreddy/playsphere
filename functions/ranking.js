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

  const awards = [];
  for (const [entrantId, displayName] of names) {
    const round = roundFor({
      entrantId,
      champion,
      finalist,
      lastRound: lastRound.get(entrantId) ?? 0,
      deepestRound,
      wonAnything: everWon.has(entrantId),
    });
    awards.push({
      entrantId,
      displayName,
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
