/**
 * Rebuilds every player's career statistics from a terminal, against the real
 * project.
 *
 * The same work as the `rebuildPlayerCareerStats` callable — it imports the
 * identical function, so there is no second implementation to drift — but
 * reachable without an admin-claimed ID token, which the app has no button to
 * mint.
 *
 *   gcloud auth application-default login       # once
 *   node run_career_rebuild.mjs --dry-run       # see what it would do
 *   node run_career_rebuild.mjs                 # do it
 *   node run_career_rebuild.mjs --keep-orphans  # do it, prune nothing
 *   node run_career_rebuild.mjs --uid=<uid>     # one player only
 *
 * Dry run first, always. Every write here REPLACES a career record with its
 * recomputation and, by default, deletes records no match supports; seeing the
 * counts and the prune list on real data before committing to them costs one
 * extra command.
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';

const projectId = process.env.GCLOUD_PROJECT ?? 'playsphere-os';
const dryRun = process.argv.includes('--dry-run');
const prune = !process.argv.includes('--keep-orphans');
const uidArg = process.argv.find((a) => a.startsWith('--uid='));
const uid = uidArg ? uidArg.slice('--uid='.length) : null;

initializeApp({ credential: applicationDefault(), projectId });

// Imported after initializeApp: the module calls getFirestore() at use time,
// which needs an initialized app.
const { rebuildCareerStats } = await import('./careerrebuild.js');

console.log(
  `${dryRun ? 'DRY RUN' : 'LIVE'} — career rebuild on ${projectId}` +
    `${uid ? ` for ${uid}` : ''}${prune ? '' : ' (keeping orphans)'}`,
);

const result = await rebuildCareerStats({ dryRun, prune, uid });

console.log(JSON.stringify(result, null, 2));
console.log(
  dryRun
    ? '\nNothing was written. Re-run without --dry-run to apply.'
    : '\nDone. Career totals now match a recomputation from the matches.',
);
process.exit(0);
