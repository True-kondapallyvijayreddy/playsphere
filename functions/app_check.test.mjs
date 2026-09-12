/**
 * The App Check switch.
 *
 * Enforcement is one constant for twenty-two callables, deliberately — a
 * partially enforced surface has the same rollout risk as a fully enforced one
 * and an attacker uses whichever function was forgotten. These tests hold that
 * property rather than the value of the flag, which is a decision for the
 * rollout and not for a test.
 */

import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { test } from 'node:test';

import { CALLABLE_OPTS, ENFORCE_APP_CHECK } from './app_check.js';

test('the shared options carry the region and the flag', () => {
  assert.equal(CALLABLE_OPTS.region, 'asia-south1');
  assert.equal(CALLABLE_OPTS.enforceAppCheck, ENFORCE_APP_CHECK);
  // Replay protection makes a token single-use, which is right for a payment
  // and wrong for a scoring pad on a ground with intermittent signal: a
  // retried call is the normal case here, not an attack.
  assert.equal(CALLABLE_OPTS.consumeAppCheckToken, false);
});

test('every callable in the codebase uses the shared options', () => {
  // The structural guard. A new `onCall` that forgets this is a hole in a
  // surface the rest of which is enforced, and it is exactly the kind of thing
  // that arrives with a feature and is noticed years later.
  const offenders = [];
  for (const file of readdirSync('.')) {
    if (!file.endsWith('.js') || file.endsWith('.test.mjs')) continue;
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(/onCall\(([\s\S]{0,80})/g)) {
      if (!m[1].includes('CALLABLE_OPTS')) {
        offenders.push(`${file}: onCall(${m[1].split('\n')[0].slice(0, 50)}`);
      }
    }
  }
  assert.deepEqual(
    offenders.sort(),
    [],
    'these callables do not spread CALLABLE_OPTS, so App Check enforcement ' +
      'will not apply to them when it is switched on.',
  );
});

test('the rollout order is written down where it will be read', () => {
  // Not a test of behaviour. Enforcing Firestore before Cloud Functions locks
  // every old build out of the whole product at once, and the only thing
  // standing between somebody and that mistake is this comment.
  const src = readFileSync('app_check.js', 'utf8');
  assert.match(src, /Firestore last/);
  assert.match(src, /metrics/);
});
