#!/bin/sh
# Refuse to deploy a web build that would put the app into a reload loop.
#
# `flutter build web` WITHOUT `--pwa-strategy=none` writes a real
# serviceWorkerVersion into flutter_bootstrap.js, so the bootstrap registers
# /flutter_service_worker.js on every page load. The predeploy step after this
# one replaces that worker with web/sw_selfdestruct.js, whose activate handler
# unregisters itself and reloads the tab. Registration and reload then chase
# each other forever and the app never renders at all.
#
# That took https://playsphere-os.web.app down completely: every route served
# HTTP 200 with a correct 6.6MB bundle, and the page still rendered nothing,
# which is why it read as "the site is broken" rather than as a bad deploy.
#
# This lives in a script rather than inline in firebase.json because the
# Firebase CLI warns that predeploy commands containing '=' "may result in the
# command not running" -- a guard that might silently not run is worthless.
set -e

BOOTSTRAP="build/web/flutter_bootstrap.js"

if [ ! -f "$BOOTSTRAP" ]; then
  echo "REFUSING TO DEPLOY: $BOOTSTRAP is missing -- build the web app first."
  exit 1
fi

if ! grep -q 'serviceWorkerVersion: null' "$BOOTSTRAP"; then
  echo "REFUSING TO DEPLOY: this build registers a service worker."
  echo
  echo "  $BOOTSTRAP does not contain 'serviceWorkerVersion: null'."
  echo "  Deploying it reload-loops the app and the site renders nothing."
  echo
  echo "  NOTE: rebuilding with --pwa-strategy=none does NOT fix this on"
  echo "  Flutter 3.27.4. That flag only empties flutter_service_worker.js;"
  echo "  the bootstrap's version is an unconditional random number --"
  echo "  see web.dart:597 and the long comment in"
  echo "  scripts/normalize_web_bootstrap.sh, which is what actually sets it"
  echo "  to null and is supposed to have run immediately before this guard."
  echo
  echo "  So this failing means that script did not run, or failed. Check the"
  echo "  predeploy list for the 'app' hosting target in firebase.json."
  echo
  exit 1
fi

echo "web build OK: serviceWorkerVersion is null, no worker will be registered."
