/**
 * Builds the club ladder now, instead of waiting for tonight's 03:45 IST run.
 *
 * Imports the same function the schedule and the callable use, so there is no
 * second implementation that could compute a different ladder. Worth running
 * once after first deploy: until it has, `clubStandings/{sportId}` does not
 * exist and the Club Rankings tab shows its empty state — which is graceful,
 * but says "no club results yet" about a database that may have plenty.
 *
 *   gcloud auth application-default login     # once
 *   node run_club_standings.mjs
 *
 * Read-only apart from the `clubStandings` documents it publishes, and safe to
 * re-run: every figure is recomputed from the fixtures each time.
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';

const projectId = process.env.GCLOUD_PROJECT ?? 'playsphere-os';

initializeApp({ credential: applicationDefault(), projectId });

// Imported after initializeApp — the module calls getFirestore() at use time.
const { computeClubStandingsByScan } = await import('./clubs.js');

console.log(`Building club standings on ${projectId}...`);

const result = await computeClubStandingsByScan();

console.log(JSON.stringify(result, null, 2));
if (result.counted === 0) {
  console.log(
    '\nNo inter-club matches found, so no club has a position yet. That is ' +
      'the honest answer: the ladder counts matches between clubs, and a club ' +
      'that only runs internal events has not played anybody.',
  );
} else {
  console.log(`\nDone. ${result.sportCount} sport ladder(s) published.`);
}
process.exit(0);
