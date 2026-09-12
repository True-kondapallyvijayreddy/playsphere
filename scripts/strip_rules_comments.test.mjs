/**
 * Tests for the deploy-time ruleset stripper.
 *
 * This tool sits between the reviewed rules and the rules that actually
 * enforce anything, so a bug in it is a silent security bug: a stripper that
 * eats half a `matches()` argument leaves a ruleset that still compiles and no
 * longer means what the reviewed file said. The string-literal cases below are
 * the ones that matter — the rest is about not regressing the size win.
 */

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

import {
  RULESET_LIMIT_BYTES,
  stripComments,
} from './strip_rules_comments.mjs';

test('removes whole-line comments', () => {
  assert.equal(stripComments('// gone\nallow read: if true;\n'), 'allow read: if true;\n');
});

test('removes trailing comments but keeps the code before them', () => {
  assert.equal(
    stripComments('allow delete: if false; // soft-delete only\n'),
    'allow delete: if false;\n',
  );
});

test('removes block comments', () => {
  assert.equal(stripComments('/* a\n b */\nallow read: if true;\n'), 'allow read: if true;\n');
});

test('leaves a // inside a single-quoted string alone', () => {
  const src = "allow read: if resource.data.url.matches('^https://x/.*');\n";
  assert.equal(stripComments(src), src);
});

test('leaves a // inside a double-quoted string alone', () => {
  const src = 'allow read: if s.matches("//dev/null");\n';
  assert.equal(stripComments(src), src);
});

test('a /* inside a string does not open a block comment', () => {
  const src = "allow read: if s.matches('/*');\nallow write: if false;\n";
  assert.equal(stripComments(src), src);
});

test('an escaped quote does not end the string early', () => {
  const src = "allow read: if s == 'it\\'s // fine';\n";
  assert.equal(stripComments(src), src);
});

test('collapses the blank lines a removed comment leaves behind', () => {
  assert.equal(
    stripComments('allow read: if true;\n\n// note\n\n\nallow write: if false;\n'),
    'allow read: if true;\nallow write: if false;\n',
  );
});

test('is idempotent — stripping a stripped file changes nothing', () => {
  const once = stripComments(readFileSync('firestore.rules', 'utf8'));
  assert.equal(stripComments(once), once);
});

test('the real ruleset survives with every statement intact', () => {
  const original = readFileSync('firestore.rules', 'utf8');
  const stripped = stripComments(original);

  // Every line of actual rule logic must still be there. Counting statements
  // in the ORIGINAL is not a valid comparison — the comments themselves quote
  // `allow` and `match` lines constantly — so the expectation is derived from
  // the original's non-comment lines instead.
  const codeLines = original
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith('//'))
    .map((l) => (l.includes('//') ? l.split('//')[0].trim() : l))
    .filter((l) => l.length > 0);

  assert.equal(stripped.trim(), codeLines.join('\n'));
  assert.equal(stripped.match(/\{/g).length, stripped.match(/\}/g).length);
  assert.equal(stripped.match(/\(/g).length, stripped.match(/\)/g).length);

  // The deny-all must be the last thing in the file, still.
  assert.match(stripped.trimEnd(), /allow read, write: if false;\s*\}\s*\}\s*\}$/);
});

test('the deployed ruleset fits, with room to spare', () => {
  const stripped = stripComments(readFileSync('firestore.rules', 'utf8'));
  const size = Buffer.byteLength(stripped, 'utf8');

  assert.ok(
    size < RULESET_LIMIT_BYTES,
    `stripped ruleset is ${size} B, over the ${RULESET_LIMIT_BYTES} B limit`,
  );
  // The whole point of the exercise. If this ever fails, the ruleset has grown
  // enough that stripping comments is no longer the answer and a second
  // database is.
  assert.ok(
    size < RULESET_LIMIT_BYTES * 0.6,
    `stripped ruleset is ${size} B, past 60% of the limit — plan the split`,
  );
});
