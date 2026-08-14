/**
 * Runs the leaderboard rebuild from a terminal, against the real project —
 * the same shape as `run_career_rebuild.mjs`, for the same reason: reachable
 * without an admin-claimed ID token, which the app has no button to mint.
 *
 *   gcloud auth application-default login   # once
 *   node run_leaderboard_rebuild.mjs
 *
 * Useful right after a deploy, so the first boards exist before the hourly
 * schedule would otherwise get to them.
 */

import { initializeApp, applicationDefault } from 'firebase-admin/app';

const projectId = process.env.GCLOUD_PROJECT ?? 'playsphere-os';

initializeApp({ credential: applicationDefault(), projectId });

// Imported after initializeApp: the module calls getFirestore() at use time,
// which needs an initialized app.
const { runLeaderboards } = await import('./leaderboard.js');

console.log(`Rebuilding leaderboards on ${projectId}...`);
const result = await runLeaderboards();
console.log(JSON.stringify(result, null, 2));
process.exit(0);
