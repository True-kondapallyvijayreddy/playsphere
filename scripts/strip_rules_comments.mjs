#!/usr/bin/env node
/**
 * Emits a comment-free copy of a Firestore/Storage ruleset for deployment.
 *
 * ## Why this exists
 *
 * `firestore.rules` is the only real security boundary in the product, and the
 * reason it is reviewable at all is that nearly every rule carries a comment
 * naming the specific bug it closed. Those comments are the file's best
 * feature and they are also, byte for byte, its problem: Firestore enforces a
 * hard 256 KiB (262,144 byte) limit on a compiled ruleset, and the annotated
 * file had reached 245,878 bytes — 93.8% of it, with under 16 KiB of headroom.
 * One more feature's worth of rules and the deploy simply fails.
 *
 * The two ways out were both bad. Deleting comments to make room trades the
 * thing that makes the file auditable for a few months of runway, and it does
 * it permanently. Splitting the ruleset across databases is a real answer but
 * a large one, and it does not help the file that is already full.
 *
 * So the annotated file stays the source of truth and this strips it on the
 * way to the server. The rules that deploy are byte-identical in behaviour and
 * roughly 40% of the size, which turns a cliff into a non-issue: the limit now
 * constrains how much *logic* the ruleset holds, which is the thing it was
 * always meant to constrain, rather than how well it is explained.
 *
 * ## Why this is hand-written rather than a regex
 *
 * `s.replace(/\/\/.*$/gm, '')` is wrong on any ruleset that contains a string
 * literal with a `//` in it — a URL pattern, a path regex — and it is wrong
 * silently, by deleting the second half of a `matches()` argument and leaving a
 * ruleset that still compiles and no longer means what it says. Today no
 * literal in either file contains one; the scanner below does not depend on
 * that staying true. It tracks single- and double-quoted string state and only
 * treats `//` as a comment outside one.
 *
 * Block comments are handled too. Neither rules file uses them today, but a
 * stripper that quietly left them behind would be a trap for whoever first
 * does.
 *
 * ## Usage
 *
 *   node scripts/strip_rules_comments.mjs <source> <destination>
 *   node scripts/strip_rules_comments.mjs --check <source>
 *
 * `--check` strips to nothing and only reports sizes, which is what CI runs.
 * It exits non-zero when the STRIPPED output would exceed the limit, so the
 * build fails on the number that actually matters rather than on the annotated
 * file's size, which is allowed to grow.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** Firestore's hard ceiling on a compiled ruleset. */
export const RULESET_LIMIT_BYTES = 262144;

/**
 * Warn well before the wall. A ruleset over this is not broken, but it is
 * close enough that the next feature should be planned rather than discovered.
 */
export const RULESET_WARN_BYTES = 220000;

/**
 * Removes comments and needless whitespace from `source`.
 *
 * Behaviour-preserving by construction: nothing inside a string literal is
 * touched, and the only characters removed outside one are comment bodies and
 * leading/trailing/blank-line whitespace. Rules have no significant
 * indentation and no statement-level newline sensitivity, so collapsing them
 * cannot change an evaluation.
 */
export function stripComments(source) {
  const out = [];
  let i = 0;
  let quote = null; // the character that opened the string we are inside

  while (i < source.length) {
    const c = source[i];
    const next = source[i + 1];

    if (quote) {
      // Inside a string: copy everything, and let a backslash escape the
      // closing quote so `'it\'s'` does not end the literal early.
      if (c === '\\' && i + 1 < source.length) {
        out.push(c, next);
        i += 2;
        continue;
      }
      if (c === quote) quote = null;
      out.push(c);
      i += 1;
      continue;
    }

    if (c === "'" || c === '"') {
      quote = c;
      out.push(c);
      i += 1;
      continue;
    }

    if (c === '/' && next === '/') {
      // Line comment: skip to (but not including) the newline, so the line
      // structure survives for the whitespace pass below.
      while (i < source.length && source[i] !== '\n') i += 1;
      continue;
    }

    if (c === '/' && next === '*') {
      i += 2;
      while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }

    out.push(c);
    i += 1;
  }

  // Trim each line and drop the ones a removed comment left empty. A single
  // trailing newline is kept so the file ends the way a text file should.
  return `${out
    .join('')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join('\n')}\n`;
}

/** Byte length, not character length — the limit is on bytes. */
function bytes(s) {
  return Buffer.byteLength(s, 'utf8');
}

function report(label, original, stripped) {
  const before = bytes(original);
  const after = bytes(stripped);
  const pct = ((after / RULESET_LIMIT_BYTES) * 100).toFixed(1);
  const saved = (((before - after) / before) * 100).toFixed(0);
  const headroom = ((RULESET_LIMIT_BYTES - after) / 1024).toFixed(1);

  console.log(
    `${label}: ${before.toLocaleString()} B annotated -> ` +
      `${after.toLocaleString()} B deployed (${saved}% smaller, ` +
      `${pct}% of the ${(RULESET_LIMIT_BYTES / 1024).toFixed(0)} KiB limit, ` +
      `${headroom} KiB headroom)`,
  );

  if (after > RULESET_LIMIT_BYTES) {
    console.error(
      `\n${label} EXCEEDS the ${RULESET_LIMIT_BYTES.toLocaleString()} byte ` +
        'ruleset limit even with comments stripped. This will not deploy. ' +
        'Move a self-contained domain to a second database.',
    );
    return false;
  }
  if (after > RULESET_WARN_BYTES) {
    console.warn(
      `\n${label} is over the ${(RULESET_WARN_BYTES / 1024).toFixed(0)} KiB ` +
        'warning line. Still deploys, but plan the next split now.',
    );
  }
  return true;
}

function main(args) {
  if (args[0] === '--check') {
    const sources = args.slice(1);
    if (sources.length === 0) {
      console.error('usage: strip_rules_comments.mjs --check <source> [<source>...]');
      process.exit(2);
    }
    let ok = true;
    for (const src of sources) {
      const original = readFileSync(src, 'utf8');
      ok = report(src, original, stripComments(original)) && ok;
    }
    process.exit(ok ? 0 : 1);
  } else if (args.length === 2) {
    const [src, dest] = args;
    const original = readFileSync(src, 'utf8');
    const stripped = stripComments(original);
    if (!report(src, original, stripped)) process.exit(1);
    writeFileSync(dest, stripped, 'utf8');
    console.log(`wrote ${dest}`);
  } else {
    console.error(
      'usage: strip_rules_comments.mjs <source> <destination>\n' +
        '       strip_rules_comments.mjs --check <source> [<source>...]',
    );
    process.exit(2);
  }
}

// Only when run as a command. Without this guard, importing the module for its
// own tests parses an empty argv and exits the test runner with code 2.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2));
}
