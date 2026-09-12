/**
 * Read-only: shows stored vs recomputed career records for every player-sport
 * the rebuild would rewrite. Mirrors `rebuildCareerStats` exactly — same
 * `careerContributions` / `accumulateCareer` imports — but writes nothing and
 * prints the field-level difference instead of a count.
 *
 *   node inspect_career_drift.mjs            # all drifting records
 *   node inspect_career_drift.mjs --limit=3  # first few only
 *
 * Scratch diagnostic for the "22 of 31 records would be rewritten" dry run:
 * legacy matches that predate the incremental writer look like whole records
 * missing counters, a dropped-write bug looks like counters that are merely
 * short by a match or two.
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';

const projectId = process.env.GCLOUD_PROJECT ?? 'playsphere-os';
const limitArg = process.argv.find((a) => a.startsWith('--limit='));
const limit = limitArg ? Number(limitArg.slice('--limit='.length)) : Infinity;

initializeApp({ credential: applicationDefault(), projectId });

const { getFirestore } = await import('firebase-admin/firestore');
const { accumulateCareer, careerContributions } = await import('./career.js');

const db = getFirestore();

const fixturesSnap = await db.collectionGroup('fixtures').get();
const contributions = [];
for (const doc of fixturesSnap.docs) {
  const orgId = doc.ref.parent.parent?.parent.parent?.id ?? null;
  contributions.push(...careerContributions(doc.data(), { orgId }));
}
const records = accumulateCareer(contributions);

const statsSnap = await db.collectionGroup('career_stats').get();
const stored = new Map();
for (const doc of statsSnap.docs) {
  const owner = doc.ref.parent.parent?.id;
  if (owner) stored.set(`${owner}::${doc.id}`, doc);
}

const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
const counters = ['matchesPlayed', 'wins', 'draws', 'losses'];

let shown = 0;
let missing = 0;
let short = 0;
let other = 0;

for (const [key, record] of records) {
  const existing = stored.get(key)?.data();
  const next = {
    matchesPlayed: record.matchesPlayed,
    wins: record.wins,
    draws: record.draws,
    losses: record.losses,
    tally: record.tally,
    clubsPlayedFor: [...record.clubsPlayedFor].sort(),
  };

  const drifts =
    !existing ||
    counters.some((f) => existing[f] !== next[f]) ||
    !same(existing.tally, next.tally) ||
    !same(existing.clubsPlayedFor, next.clubsPlayedFor);
  if (!drifts) continue;

  // Classify before printing, so the tail of a long list is still summarised.
  if (!existing) missing += 1;
  else if (counters.every((f) => (existing[f] ?? 0) <= next[f])) short += 1;
  else other += 1;

  if (shown >= limit) continue;
  shown += 1;

  console.log(`\n=== ${key} ===`);
  if (!existing) {
    console.log('  stored: (no document)');
  } else {
    for (const f of counters) {
      const flag = existing[f] === next[f] ? '   ' : ' ! ';
      console.log(`  ${flag}${f}: stored=${existing[f]} recomputed=${next[f]}`);
    }
    if (!same(existing.tally, next.tally)) {
      console.log(`   ! tally stored=${JSON.stringify(existing.tally)}`);
      console.log(`         recomputed=${JSON.stringify(next.tally)}`);
    }
    if (!same(existing.clubsPlayedFor, next.clubsPlayedFor)) {
      console.log(
        `   ! clubsPlayedFor stored=${JSON.stringify(existing.clubsPlayedFor)} recomputed=${JSON.stringify(next.clubsPlayedFor)}`,
      );
    }
    console.log(`     careerRebuiltAt: ${existing.careerRebuiltAt?.toDate?.().toISOString() ?? '(never)'}`);
  }
}

console.log(
  `\n--- ${missing + short + other} drifting records: ${missing} with no stored doc, ${short} stored-below-recomputed, ${other} stored-above-or-mixed ---`,
);
process.exit(0);
