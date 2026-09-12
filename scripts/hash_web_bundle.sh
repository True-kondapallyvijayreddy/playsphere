#!/bin/sh
# Give main.dart.js a content-addressed name so browsers can cache it forever.
#
# ## The problem this solves
#
# Nothing `flutter build web` emits is content-hashed, so every file has the
# same name in every build. That leaves exactly one safe cache policy for the
# browser -- `max-age=0, must-revalidate` -- and `firebase.json` sets it for
# that reason: serve a stale main.dart.js and the app on the device is a
# different app from the one that was deployed.
#
# The cost is paid on every single page load, by everyone. The bundle is ~1.4MB
# compressed, and a revalidation is a full round trip before a byte of it can be
# reused -- on a phone on mobile data that is most of a second of nothing
# happening, repeated on every visit and every refresh, forever.
#
# ## What this does instead
#
# Renames the bundle to `main.<hash>.dart.js`, where the hash is of the bundle's
# own bytes, and rewrites the two places that name it: `mainJsPath` in
# `flutter_bootstrap.js` (the loader reads it from there) and the `<link
# rel=preload>` in `index.html`. `firebase.json` then serves `/main.*.dart.js`
# as `immutable` for a year.
#
# A new build produces different bytes, so it produces a different name, so
# there is nothing to invalidate: the old URL is never requested again and the
# new one was never cached. Staleness becomes impossible rather than merely
# guarded against -- which is the same reason `index.html` itself must STAY
# no-cache, since it is the file that names the hash.
#
# Idempotent: running twice on one build is a no-op, because the second run
# finds no un-hashed bundle to rename. That matters because `firebase deploy`
# runs predeploy hooks every time, including on a redeploy of an unchanged
# build directory.
set -e

WEB="build/web"
BOOTSTRAP="$WEB/flutter_bootstrap.js"
INDEX="$WEB/index.html"
BUNDLE="$WEB/main.dart.js"

if [ ! -f "$BOOTSTRAP" ] || [ ! -f "$INDEX" ]; then
  echo "REFUSING TO DEPLOY: $WEB is not a built web app."
  exit 1
fi

if [ ! -f "$BUNDLE" ]; then
  # Already hashed by an earlier run against this same build directory.
  if ls "$WEB"/main.*.dart.js >/dev/null 2>&1; then
    echo "bundle already content-hashed: $(basename "$(ls "$WEB"/main.*.dart.js | head -1)")"
    exit 0
  fi
  echo "REFUSING TO DEPLOY: $BUNDLE is missing and nothing is hashed."
  exit 1
fi

# First 12 hex characters of the SHA-256. Long enough that a collision is not a
# thing that happens, short enough to read in a network panel.
HASH=$(shasum -a 256 "$BUNDLE" | cut -c1-12)
HASHED="main.$HASH.dart.js"

mv "$BUNDLE" "$WEB/$HASHED"

# Rewrite by hand rather than with `sed -i`, whose in-place flag takes an
# argument on BSD/macOS and does not on GNU/Linux -- the one spelling that
# works on both is not using it.
for f in "$BOOTSTRAP" "$INDEX"; do
  sed "s|main\.dart\.js|$HASHED|g" "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
done

# The loader reads the bundle's name from `mainJsPath`; if that substitution
# missed, the app would deploy and then fail to boot with a 404 that nothing
# server-side would catch.
if ! grep -q "\"mainJsPath\":\"$HASHED\"" "$BOOTSTRAP"; then
  echo "REFUSING TO DEPLOY: mainJsPath was not rewritten to $HASHED."
  exit 1
fi

echo "bundle content-hashed: $HASHED (cacheable forever; index.html stays no-cache)"
