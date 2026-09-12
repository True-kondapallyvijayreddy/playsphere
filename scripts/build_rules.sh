#!/bin/sh
# Generates the rulesets that actually deploy, from the annotated sources.
#
# `firebase.json` points at build/rules/, never at the annotated files, so a
# deploy that skips this step fails with a missing file rather than quietly
# shipping something stale. Run by the emulator harness before the rules tests
# and by CI before the size check, so the thing under test is the thing that
# ships.
#
# See scripts/strip_rules_comments.mjs for why the deployed copy is stripped.
set -e

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mkdir -p build/rules
node scripts/strip_rules_comments.mjs firestore.rules build/rules/firestore.rules
node scripts/strip_rules_comments.mjs storage.rules build/rules/storage.rules
