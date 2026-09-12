# `/.well-known/` — the two files that make shared links open the app

Served at `/.well-known/assetlinks.json` and
`/.well-known/apple-app-site-association` by the rewrites in `firebase.json`,
on both names the `app` Hosting site answers to — `playsphere-os.web.app` and
`playsphere-os.firebaseapp.com`, which the Android intent-filter both list.

## Why they live here and not in `web/.well-known/`

Flutter copies `web/**` into `build/web/`, which is what Firebase Hosting
deploys — but the `app` hosting target's `ignore` list contains `**/.*`, and a
directory whose name starts with a dot matches it. Files put in
`web/.well-known/` therefore build correctly, look correct locally, and are
silently dropped at deploy time. The rewrite from the dotted public path to
this undotted directory is what avoids that trap without loosening `ignore`
for every other dotfile.

## `assetlinks.json` — Android App Links

Android fetches this at install time and verifies that it names
`com.company.playsphere` together with a SHA-256 certificate fingerprint that
matches the installed APK's signature. Five are listed, and each is here for a
reason:

| Fingerprint starts | Certificate |
| --- | --- |
| `4E:DB:D6:FB` | Play App Signing (one of the three Play issues) |
| `80:E1:7F:0F` | Play App Signing |
| `F6:28:84:04` | Play App Signing |
| `52:B6:38:6F` | `android/upload-keystore.jks`, alias `upload` |
| `64:67:87:C7` | the local debug keystore |

The three Play values are the SHA-256 entries registered against the Firebase
Android app (`firebase apps:android:sha:list`), which were added for Play's
deployment certificate and its two hybrid certificates — see
`docs/PLAY_STORE_RELEASE.md`. **Confirm the first of them against Play Console
→ Test and release → App integrity → App signing key certificate (SHA-256)
before relying on this in production**: that is the certificate that actually
signs delivered APKs, and it is the one entry here that has to be right.

Listing more certificates than necessary is safe — verification passes if
*any* entry matches — and listing too few fails closed: the link opens in the
browser instead of the app, which is the intended fallback anyway.

## `apple-app-site-association` — iOS Universal Links

**Not live yet.** It needs `TEAMID.BUNDLEID`, and iOS still carries the
template bundle id `com.example.playsphere`. Fill in the real values, add
`applinks:playsphere-os.web.app` to the Runner target's Associated Domains
capability, and it starts working — nothing else in this repo has to change.
Until then the file names a bundle that does not exist, which no device
matches, so iOS links keep falling back to the web build.

## Adding a custom domain

Three things, together, or links quietly go to the browser:

1. an `<intent-filter>` `<data>` entry for the new host in
   `android/app/src/main/AndroidManifest.xml`,
2. these two files served from that host's `/.well-known/`,
3. `--dart-define=PLAYSPHERE_WEB_ORIGIN=https://the-new-host` at build time,
   so `Routes.publicOrigin` actually mints links on it.
