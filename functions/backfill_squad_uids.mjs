/**
 * Fills `squadUids` on fixtures written before `syncFixtureSquads` existed —
 * the backfill half of that trigger (functions/index.js).
 *
 * `squadUids` is every member of the team entrant on either side, plus a solo
 * entrant's own account. It is what puts a team's matches on a player's own
 * "My matches" list (test run TC-31); the trigger keeps it from now on, this
 * repairs the fixtures already written. Same computation as the trigger, and
 * only writes where the stored list differs. Idempotent.
 *
 *   node backfill_squad_uids.mjs --dry-run
 *   node backfill_squad_uids.mjs
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const dryRun = process.argv.includes('--dry-run');
initializeApp({ credential: applicationDefault(), projectId: process.env.GCLOUD_PROJECT ?? 'playsphere-os' });
const db = getFirestore();

const entrantCache = new Map();
async function entrant(orgId, compId, id) {
  const key = `${orgId}/${compId}/${id}`;
  if (!entrantCache.has(key)) {
    const snap = await db.doc(`orgs/${orgId}/competitions/${compId}/entrants/${id}`).get();
    entrantCache.set(key, snap.exists ? snap.data() : null);
  }
  return entrantCache.get(key);
}

const fixtures = await db.collectionGroup('fixtures').get();
let written = 0, unchanged = 0;
let batch = db.batch();
let pending = 0;
for (const doc of fixtures.docs) {
  const f = doc.data();
  const compRef = doc.ref.parent.parent;
  const orgRef = compRef?.parent.parent;
  if (!compRef || !orgRef || orgRef.parent.id !== 'orgs') continue;
  const orgId = orgRef.id;
  const compId = compRef.id;

  const uids = new Set();
  for (const id of [f.entrantAId, f.entrantBId]) {
    if (typeof id !== 'string' || !id) continue;
    const e = await entrant(orgId, compId, id);
    if (!e) continue;
    if (typeof e.uid === 'string' && e.uid) uids.add(e.uid);
    for (const m of e.memberUids ?? []) if (typeof m === 'string' && m) uids.add(m);
  }
  for (const uid of [f.entrantAUid, f.entrantBUid]) {
    if (typeof uid === 'string' && uid) uids.add(uid);
  }
  const squad = [...uids].sort();
  const current = Array.isArray(f.squadUids) ? [...f.squadUids].sort() : null;
  if (current && current.length === squad.length && current.every((u, i) => u === squad[i])) {
    unchanged++;
    continue;
  }
  written++;
  if (dryRun) {
    console.log(`would set ${doc.ref.path}: ${squad.length} uid(s)`);
    continue;
  }
  batch.update(doc.ref, { squadUids: squad });
  if (++pending === 400) {
    await batch.commit();
    batch = db.batch();
    pending = 0;
  }
}
if (!dryRun && pending > 0) await batch.commit();
console.log(`${dryRun ? 'would write' : 'wrote'} ${written}, unchanged ${unchanged}, of ${fixtures.size} fixtures`);
