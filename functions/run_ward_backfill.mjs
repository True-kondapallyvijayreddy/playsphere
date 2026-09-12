/**
 * Rebuilds `users/{guardianUid}.managedChildUids` from the authoritative
 * `custodianUid`/`claimedAt` fields, against the real project.
 *
 * Needed once, after the profile-switching change: children created before
 * the mirror existed have no entry in it, and `firestore.rules`' collection-
 * group rules (`wardUids()`) read the mirror — so without this a guardian
 * switches into an older child's profile and finds their clubs and matches
 * empty. Idempotent; safe to re-run, and re-running also repairs drift.
 *
 *   gcloud auth application-default login   # once
 *   node run_ward_backfill.mjs --dry-run    # see the counts
 *   node run_ward_backfill.mjs              # apply
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';

const projectId = process.env.GCLOUD_PROJECT ?? 'playsphere-os';
const dryRun = process.argv.includes('--dry-run');

initializeApp({ credential: applicationDefault(), projectId });

// Imported after initializeApp, same as the other runners here: the module
// calls getFirestore() at use time, which needs an initialized app.
const { backfillCustodyMirror } = await import('./family.js');

console.log(
  `${dryRun ? 'DRY RUN' : 'LIVE'} — custody mirror backfill on ${projectId}`,
);

const result = await backfillCustodyMirror({ dryRun });

console.log(JSON.stringify(result, null, 2));
console.log(
  dryRun
    ? '\nNothing was written. Re-run without --dry-run to apply.'
    : '\nDone. Guardians can switch into every child profile they manage.',
);
