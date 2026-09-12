/**
 * Lifts seasons out of `draft` when their own draws are already taking
 * entries — the backfill half of `CompetitionRepository._liftSeasonOutOfDraft`.
 *
 * Opening ONE draw from its own page used to leave the season document at
 * `draft`, so a season page reads "Draft" while people register through it.
 * The code fix stops it happening again; this repairs the ones already
 * written. Only `draft` is touched, and only when a draw under it is
 * `registration_open`. Idempotent.
 *
 *   node lift_draft_seasons.mjs --dry-run
 *   node lift_draft_seasons.mjs
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const dryRun = process.argv.includes('--dry-run');
initializeApp({ credential: applicationDefault(), projectId: process.env.GCLOUD_PROJECT ?? 'playsphere-os' });
const db = getFirestore();

const comps = await db.collectionGroup('competitions').get();
const openSeasons = new Set();
for (const d of comps.docs) {
  const c = d.data();
  if (c.status !== 'registration_open') continue;
  if (!c.tournamentId) continue;
  openSeasons.add(`${d.ref.parent.parent.id}/${c.tournamentId}`);
}

let lifted = 0, skipped = 0, missing = 0;
for (const key of openSeasons) {
  const [orgId, tid] = key.split('/');
  const ref = db.doc(`orgs/${orgId}/tournaments/${tid}`);
  const snap = await ref.get();
  if (!snap.exists) { missing++; continue; }
  const status = snap.data().status ?? 'draft';
  if (status !== 'draft') { skipped++; continue; }
  console.log(`${dryRun ? 'would lift' : 'lifting'}: ${key}  "${snap.data().name}"  draft -> entries_open`);
  if (!dryRun) {
    await ref.update({ status: 'entries_open', updatedAt: FieldValue.serverTimestamp() });
  }
  lifted++;
}
console.log(`\nseasons with an open draw: ${openSeasons.size}`);
console.log(`${dryRun ? 'would lift' : 'lifted'}: ${lifted}   left alone (not draft): ${skipped}   season doc missing: ${missing}`);
