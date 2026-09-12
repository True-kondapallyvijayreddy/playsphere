#!/bin/sh
# Force `serviceWorkerVersion: null` into the built flutter_bootstrap.js.
#
# ## Why this exists: the build flag does NOT do this
#
# `scripts/check_web_build.sh` and `web/sw_selfdestruct.js` both state that
# `flutter build web --pwa-strategy=none` sets `serviceWorkerVersion: null`.
# On Flutter 3.27.4 that is false, and it is false BY CONSTRUCTION:
#
#   flutter_tools/lib/src/build_system/targets/web.dart:597
#     final String serviceWorkerVersion = Random().nextInt(4294967296).toString();
#     bootstrapTemplate.applySubstitutions(
#       serviceWorkerVersion: serviceWorkerVersion, ...);
#
# That random version goes into the bootstrap unconditionally -- the strategy
# is never consulted at that line. The strategy reaches only
# `generateServiceWorker` (web.dart:779), which returns an empty string for
# `none`. So the flag empties `flutter_service_worker.js` and does nothing
# whatsoever to the bootstrap.
#
# What the flag actually produces on this SDK is therefore the precise outage
# condition the guard was written to catch: a non-null version makes
# `flutter.js` call
#   navigator.serviceWorker.register('flutter_service_worker.js?v=<random>')
# on every page load, and the predeploy step two lines later replaces that
# (empty) worker with the self-destructing one.
#
# This was verified against TWO builds, the second after `rm -rf build/web`, so
# it is not a stale-cache artefact. Both emitted a random version; the guard
# refused both, correctly.
#
# ## What this does
#
# Rewrites the version to `null` -- which is what the live, working production
# build carries. `flutter.js` then registers nothing at all, and
# `sw_selfdestruct.js` remains on hosting purely for devices still holding a
# real worker from an older build, which fetch it through their own update
# check. That is the mechanism `web/sw_selfdestruct.js` describes, and it is
# unaffected by this.
#
# Deliberately runs BEFORE `check_web_build.sh`: this normalizes, and the guard
# then independently verifies the end state. If this rewrite ever silently
# fails or the bootstrap's shape changes, the guard still refuses the deploy --
# the two stay independent defences rather than one script trusting itself.
set -e

BOOTSTRAP="build/web/flutter_bootstrap.js"

if [ ! -f "$BOOTSTRAP" ]; then
  echo "REFUSING TO DEPLOY: $BOOTSTRAP is missing -- build the web app first."
  exit 1
fi

if grep -q 'serviceWorkerVersion: null' "$BOOTSTRAP"; then
  echo "bootstrap already registers no worker (serviceWorkerVersion: null)."
  exit 0
fi

if ! grep -q 'serviceWorkerVersion: "[0-9]*"' "$BOOTSTRAP"; then
  # Neither the expected generated form nor the desired one. Something about
  # the bootstrap's shape has changed and a blind rewrite would be a guess.
  echo "REFUSING TO DEPLOY: cannot find serviceWorkerVersion in $BOOTSTRAP."
  echo "  Expected either 'serviceWorkerVersion: null' or a quoted number."
  echo "  The Flutter bootstrap template has changed; re-check this script."
  exit 1
fi

# Rewritten via a temp file rather than `sed -i`, whose in-place flag takes an
# argument on BSD/macOS and does not on GNU/Linux.
sed 's/serviceWorkerVersion: "[0-9]*"/serviceWorkerVersion: null/' \
  "$BOOTSTRAP" > "$BOOTSTRAP.tmp"
mv "$BOOTSTRAP.tmp" "$BOOTSTRAP"

if ! grep -q 'serviceWorkerVersion: null' "$BOOTSTRAP"; then
  echo "REFUSING TO DEPLOY: rewrite of serviceWorkerVersion did not take."
  exit 1
fi

echo "bootstrap normalized: serviceWorkerVersion -> null (no worker will register)."
