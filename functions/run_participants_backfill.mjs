/**
 * Runs the participants backfill from a terminal, against the real project.
 *
 * The same work as the `backfillFixtureParticipants` callable — it imports the
 * identical function, so there is no second implementation to drift — but
 * reachable without an admin-claimed ID token, which the app has no button to
 * mint. The callable stays deployed for the day there is one.
 *
 *   gcloud auth application-default login          # once
 *   node run_participants_backfill.mjs --dry-run   # see what it would do
 *   node run_participants_backfill.mjs             # do it
 *
 * Dry run first, always. This touches every historical match in the database
 * and writes the field the settlement rules authorize against; seeing the
 * counts on real data before committing to them costs one extra command.
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';

const projectId = process.env.GCLOUD_PROJECT ?? 'playsphere-os';
const dryRun = process.argv.includes('--dry-run');

initializeApp({ credential: applicationDefault(), projectId });

// Imported after initializeApp: the module calls getFirestore() at use time,
// which needs an initialized app.
const { backfillParticipants } = await import('./participants.js');

console.log(
  `${dryRun ? 'DRY RUN' : 'LIVE'} — participants backfill on ${projectId}`,
);

const result = await backfillParticipants({ dryRun });

console.log(JSON.stringify(result, null, 2));
console.log(
  dryRun
    ? '\nNothing was written. Re-run without --dry-run to apply.'
    : '\nDone. Individual-event matches now name their players.',
);
process.exit(0);
