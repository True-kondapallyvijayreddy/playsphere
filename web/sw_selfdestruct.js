// A service worker whose only job is to remove itself and everything the
// previous one cached.
//
// ## Why this file exists
//
// `flutter build web --pwa-strategy=none` emits a ZERO-BYTE
// `flutter_service_worker.js` AND sets `serviceWorkerVersion: null` in
// `flutter_bootstrap.js`, so a new visitor registers no worker at all.
//
// (An earlier version of this comment claimed the bootstrap "registers it
// regardless". It does not, and believing otherwise is what made the reload
// loop in `activate` below look safe. Build WITHOUT the flag and the
// bootstrap registers this worker on every load — see the guard there.)
//
// None of that helps the visitor who already has a REAL Flutter worker
// installed from an earlier build, and that is the case this file exists for:
//
//   1. the old worker intercepts the navigation and serves `index.html` from
//      its own CacheStorage — the old one;
//   2. the old `index.html` pulls the old `flutter_bootstrap.js`, which pulls
//      the old `main.dart.js`. The device is now running a build from weeks
//      ago;
//   3. the "unregister every worker" script in the CURRENT `index.html`
//      never runs, because the current `index.html` was never fetched;
//   4. the browser does byte-compare `flutter_service_worker.js` on
//      navigation and installs the new one — but an ordinary worker waits for
//      every tab to close before activating, and a phone's tab never closes.
//
// Net effect: a device can sit on a stale build indefinitely, and the app
// looks like it is missing features that shipped, or showing artwork that was
// replaced. Both were reported as bugs in the app.
//
// This file breaks that loop on the FIRST navigation, because the worker
// script itself is always revalidated against the network:
//
//   * `skipWaiting()` in `install` — do not queue behind the old worker;
//   * `clients.claim()` plus deleting every CacheStorage entry in `activate`
//     — the old build's cached `index.html` and `main.dart.js` are gone;
//   * `registration.unregister()` — leave no worker behind at all;
//   * then reload every open tab, which now goes to the network.
//
// It is installed over the zero-byte file by the `predeploy` hook in
// `firebase.json`. If that hook is ever removed, stale-on-mobile comes
// straight back.

self.addEventListener('install', (event) => {
  // Activate immediately rather than waiting for existing tabs to close.
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    // Take over the pages the old worker was controlling, so the reload
    // below is not intercepted by it.
    await self.clients.claim();

    // Everything the previous worker stored — including its copy of
    // index.html and main.dart.js. An EMPTY list means there was no stale
    // build on this device: nothing cached it, so nothing needs rescuing.
    const names = await caches.keys();
    const rescuedStaleBuild = names.length > 0;
    await Promise.all(names.map((name) => caches.delete(name)));

    // Remove this worker too. Nothing here should persist; the app is served
    // straight from hosting from now on.
    await self.registration.unregister();

    // Now that no worker is in the way, put every open tab on the current
    // build — but ONLY when there was actually a stale build to move it off.
    //
    // Reloading unconditionally is an INFINITE LOOP on any bundle built
    // without `--pwa-strategy=none`. Such a build registers this worker on
    // every single page load, so: activate → unregister → navigate → the
    // fresh page registers it again → activate → … and the app never renders
    // at all. That took the whole site down, so this guard stays even now
    // that the build flag is enforced — the flag and the guard are
    // independent defences and either one alone closes the loop.
    if (!rescuedStaleBuild) return;

    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      if ('navigate' in client) client.navigate(client.url);
    }
  })());
});

// Deliberately no `fetch` listener. A worker with no fetch handler does not
// intercept anything, so even in the window before it unregisters, every
// request goes to the network.
