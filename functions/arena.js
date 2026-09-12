/**
 * The Arena — board games between two members.
 *
 * Two jobs, both of which have to live on the server because a client cannot
 * be trusted with either:
 *
 *   1. Closing games that have been walked away from. The clients can and do
 *      close them — the waiting player gets a "Claim the win" button the
 *      moment the ten minutes elapse — but that only works while somebody is
 *      looking at the board. Games where BOTH players closed the app would
 *      otherwise sit in "active" forever, cluttering two people's lists and
 *      leaving the stats below permanently owed a result.
 *
 *   2. Keeping the Arena leaderboard. Stats are written from the finished
 *      match document rather than reported by a client, for the same reason
 *      `onMatchSettled` reads the fixture instead of trusting the scorer: a
 *      number a client can write is a number a client can invent.
 *
 * ## These stats are NOT ratings
 *
 * Nothing here touches `users/{uid}/ratings/*`, career totals, club standings
 * or the Overall Glicko. An Arena game is unwatched and trivially cheated, so
 * its results stay inside the Arena — a fun ladder, reset-able, and no
 * evidence about anybody's ability at anything. That separation is the whole
 * premise of the feature and must not erode.
 */

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

const db = () => getFirestore();

/** Must match `ArenaMatch.idleLimit` and the ten minutes in firestore.rules. */
const IDLE_LIMIT_MS = 10 * 60 * 1000;

/**
 * Closes games nobody has moved in for ten minutes.
 *
 * Runs every five, which means a game closes somewhere between ten and
 * fifteen minutes after the last move. That looseness is fine precisely
 * because it is only the backstop: a player who is actually waiting closes it
 * themselves on the dot, from the board.
 *
 * The player who was to move loses. That is the same ruling every online
 * board applies to a clock running out, and the alternative — voiding the
 * game — rewards walking away from a losing position.
 */
export const closeIdleArenaGames = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Kolkata',
    // Stated explicitly, unlike everything else in this codebase, which
    // inherits it from `setGlobalOptions` in index.js. It cannot here: ES
    // module imports are evaluated before the importing module's body, so
    // this file runs before that call does. A Firestore trigger survives
    // that because it infers its region from the database; a scheduler has
    // nothing to infer from and silently defaulted to us-central1, querying
    // a Mumbai database from Iowa every five minutes.
    region: 'asia-south1',
  },
  async () => {
    const cutoff = new Date(Date.now() - IDLE_LIMIT_MS);

    // Ordered by the field being filtered so this stays one index, and capped
    // so a backlog cannot turn into an unbounded write burst.
    const stale = await db()
      .collection('arenaMatches')
      .where('status', '==', 'active')
      .where('updatedAt', '<', cutoff)
      .orderBy('updatedAt')
      .limit(200)
      .get();

    if (stale.empty) return;

    let closed = 0;
    for (const doc of stale.docs) {
      const match = doc.data();

      // `updatedAt` moves on a draw offer too, so the authoritative clock is
      // the last MOVE where there has been one. A game filtered in on
      // updatedAt but whose last move is recent is simply skipped.
      const since = match.lastMoveAt ?? match.updatedAt ?? match.createdAt;
      const sinceMs = since?.toMillis?.() ?? 0;
      if (!sinceMs || Date.now() - sinceMs < IDLE_LIMIT_MS) continue;

      const players = Array.isArray(match.players) ? match.players : [];
      const stalled = match.turnUid;
      const winner = players.find((uid) => uid !== stalled) ?? null;
      const names = match.names ?? {};

      await doc.ref.update({
        status: 'finished',
        turnUid: null,
        result: {
          winnerUid: winner,
          reason: `${names[stalled] ?? 'A player'} stopped playing`,
        },
        closedBy: 'timeout',
        updatedAt: FieldValue.serverTimestamp(),
      });
      closed++;
    }

    if (closed > 0) {
      logger.info(`Arena: closed ${closed} idle game(s).`);
    }
  },
);

/**
 * Keeps `arenaStats/{uid}` as games finish.
 *
 * Idempotent by construction: `settledMatches` on each stats document records
 * which games have already been counted, so a retried trigger — or an
 * organiser-style reopen, were one ever added — cannot pay the same game
 * twice. Same mechanism as `settledFixtures` on a rating document, for the
 * same reason.
 */
export const onArenaMatchFinished = onDocumentUpdated(
  'arenaMatches/{matchId}',
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === 'finished' || after.status !== 'finished') return;

    const matchId = event.params.matchId;
    const players = Array.isArray(after.players) ? after.players : [];
    if (players.length !== 2) return;

    // A challenge declined or withdrawn never became a game, and a game with
    // no moves in it is not a result anybody should carry — two people opened
    // a board and one of them left.
    const moves = Array.isArray(after.moves) ? after.moves : [];
    if (moves.length === 0) {
      logger.info(`Arena: ${matchId} finished with no moves, not counted.`);
      return;
    }

    const gameId = typeof after.gameId === 'string' ? after.gameId : 'unknown';
    const winner = after.result?.winnerUid ?? null;
    const names = after.names ?? {};
    const photos = after.photos ?? {};

    await Promise.all(
      players.map(async (uid) => {
        const ref = db().collection('arenaStats').doc(uid);

        await db().runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          const settled = snap.exists
            ? (snap.data().settledMatches ?? [])
            : [];
          if (settled.includes(matchId)) return;

          const outcome =
            winner === null ? 'drawn' : winner === uid ? 'won' : 'lost';

          tx.set(
            ref,
            {
              uid,
              displayName: names[uid] ?? 'Player',
              photoUrl: photos[uid] ?? null,
              played: FieldValue.increment(1),
              won: FieldValue.increment(outcome === 'won' ? 1 : 0),
              drawn: FieldValue.increment(outcome === 'drawn' ? 1 : 0),
              lost: FieldValue.increment(outcome === 'lost' ? 1 : 0),
              // Per game as well as overall, because being the club's best at
              // connect four and its worst at go is the interesting fact, and
              // one combined number hides it.
              [`byGame.${gameId}.played`]: FieldValue.increment(1),
              [`byGame.${gameId}.won`]: FieldValue.increment(
                outcome === 'won' ? 1 : 0,
              ),
              [`byGame.${gameId}.drawn`]: FieldValue.increment(
                outcome === 'drawn' ? 1 : 0,
              ),
              [`byGame.${gameId}.lost`]: FieldValue.increment(
                outcome === 'lost' ? 1 : 0,
              ),
              // Capped: this exists to make the write idempotent, not to be a
              // history — the matches themselves are that.
              settledMatches: settled.concat(matchId).slice(-400),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        });
      }),
    );
  },
);
