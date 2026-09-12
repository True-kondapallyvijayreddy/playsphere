# Shipping PlaySphere to Google Play

Everything Play checks *inside the bundle* is configured in the repo and
verified on the artifact. Everything Play checks *outside* the bundle is a
Console form, and those are listed at the bottom — they cannot be committed.

## Building the bundle

```
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
flutter clean && flutter pub get
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

`build/` is gitignored and `flutter clean` deletes it. Copy the `.aab`
somewhere durable before cleaning.

## The upload key

`android/upload-keystore.jks` + `android/key.properties`. **Both are
gitignored and exist only on this machine** — back them up somewhere you will
still have in three years, or the next release cannot be signed.

```
alias   : upload
algo    : RSA 4096, SHA384withRSA
expires : 2054-01-20
SHA-1   : 9B:18:29:A8:62:56:48:80:F0:B5:20:00:D0:0A:56:41:A8:47:C5:AC
SHA-256 : 52:B6:38:6F:1D:D6:93:3B:96:B9:8A:02:51:F5:4D:5E:F0:B5:9E:48:
          32:4A:95:1E:51:AA:8D:B1:40:3E:50:DF
```

If `key.properties` is missing the release build falls back to the debug key
rather than failing — deliberate, so a fresh clone can still `flutter run
--release`. Play rejects debug-signed bundles, so the failure is caught at
upload, not silently shipped.

### Google Sign-In will fail until the SHAs are registered

Auth is Google-only, so a wrong SHA is a completely unusable app (the symptom
is `ApiException: 10`). Two fingerprints must be added to the
`com.company.playsphere` Android app in the Firebase console, then
`google-services.json` re-downloaded to `android/app/`:

1. The **upload key** SHA-1 above — needed for release APKs you sideload.
2. The **Play app signing key** SHA-1 — Play re-signs every download with its
   own key, so this is the one real users hit. It only exists after the first
   upload: Play Console → Release → Setup → App integrity → App signing.

Confirm the new `google-services.json` contains an `"client_type": 1` entry.
Without one, sign-in fails no matter what fingerprints are registered.

## What was configured for Play, and how it was verified

| Requirement | Where | Verified on the artifact |
|---|---|---|
| Target API 36 (Android 16), mandatory 2026-11-01 | `android/app/build.gradle` `targetSdk = 36` | manifest in the AAB reads `targetSdkVersion="36"` |
| compileSdk ≥ targetSdk | `compileSdk = 36`, `buildToolsVersion 36.0.0` | builds clean |
| 16 KB memory page sizes | AGP 8.7.3 + Gradle 8.9 + NDK 27, `useLegacyPackaging=false`, `android.bundle.enableUncompressedNativeLibs=true`, `extractNativeLibs="false"` | every `LOAD` segment ≥ `0x4000`; `BundleConfig.pb` carries `PAGE_ALIGNMENT_16K` |
| 64-bit native code | `abiFilters "arm64-v8a", "x86_64"` | no `armeabi-v7a` in the bundle |
| Signed with a non-debug key | `signingConfigs.release` from `key.properties` | signer is `CN=PlaySphere`, not `Android Debug` |
| Not debuggable / not test-only | release build type | neither attribute present |
| Real app name | `android:label="PlaySphere"` | was the lowercase `playsphere` |
| Network access in release | `INTERNET` in the **main** manifest | Flutter's template only declares it for debug/profile |
| Push notifications on Android 13+ | `POST_NOTIFICATIONS` | `requestPermission()` was a silent no-op without it |
| Android 16 forced edge-to-edge | `SystemUiMode.edgeToEdge` in `main.dart` | opted in on every API level so there is one layout, not two |
| Predictive back (forced at API 36) | `enableOnBackInvokedCallback="true"` | Flutter 3.27's `FlutterActivity` registers the callback |

### R8

Shrinking and obfuscation are **on**, and verified by running the minified
release build, not by watching it compile. Turning it on needed one rule:
Flutter's embedding references `com.google.android.play.core.splitcompat
.SplitCompatApplication` for deferred components, which this app does not use
and does not depend on. R8 treats the unresolved reference as a hard error, so
`-dontwarn com.google.android.play.core.**` in `proguard-rules.pro` is what
makes minification complete at all.

Verified on an API 33 emulator with the minified release APK installed: the
process stays up, the sign-in screen renders, `FirebaseApp initialization
successful`, Crashlytics initialises, the geolocator plugin binds, and logcat
has no `FATAL`, `ClassNotFoundException`, `NoSuchMethodError` or
`NoClassDefFoundError`. Those four are the entire failure surface of an
over-aggressive R8 pass, and none of them appear.

## Console work — what to answer

### Privacy policy URL

    https://playsphere-legal.web.app/privacy

Live now. It is served from its own Firebase Hosting site
(`playsphere-legal`), deliberately separate from the app site so publishing a
policy change never means redeploying the app, and vice versa. Source is in
`hosting/legal/`; deploy it with:

    firebase deploy --only hosting:legal

Terms of service is at `/terms` on the same site.

### Target audience and content — read this before answering

**PlaySphere knowingly serves children.** `AppUser.dateOfBirth` is a required,
write-once field, `isMinor` is derived from it, and a guardian can create and
run a child's profile from their own account. Answering "18 and over" would be
a misrepresentation, and apps get pulled for it after launch, not before.

Declare that the app targets under-13s alongside teens and adults, which puts
it under the **Families Policy**. What that requires is already true here:
no ads SDK, no advertising ID, no third-party analytics beyond Crashlytics,
and no in-app purchases. The privacy policy has a Children section written for
this.

### Data safety form

| Question | Answer |
|---|---|
| Data encrypted in transit | Yes |
| Users can request deletion | Yes — in-app, and by email |
| **Personal info → Name** | Collected, not shared. Account management + app functionality. Required. |
| **Personal info → Email address** | Collected, not shared. Account management. Required. |
| **Personal info → User IDs** | Collected, not shared. Account management. Required. |
| **Personal info → Other (date of birth)** | Collected, not shared. App functionality (age-category eligibility). Required. |
| **Location → Approximate** | Collected, not shared. App functionality (nearby grounds and events). Optional. |
| **Location → Precise** | Collected, not shared. App functionality ("use my location" on the grounds map). Optional. |
| **Photos and videos → Photos** | Collected, not shared. App functionality (profile, club and ground images). Optional. |
| **App activity → Other user-generated content** | Collected, not shared. App functionality (entries, squads, scores, ratings). Required. |
| **App info and performance → Crash logs** | Collected, not shared. Diagnostics. Required. |
| **App info and performance → Diagnostics** | Collected, not shared. Diagnostics. Required. |
| **Advertising ID** | **No.** No ads SDK is linked and `AD_ID` is not in the merged manifest — verifiable in the bundle. |
| Financial info | **No.** No billing SDK, no payment is taken in-app. |

"Collected, not shared" throughout: data reaches Firebase as our processor,
and reaches other users only inside the product (a team sheet, a scoreboard) —
neither is "shared" in Play's sense, which means transfer to a third party for
their own use.

### Payments

No Play Billing integration, and none is required. Entry fees and ground hire
are settled in person at the venue, which is a real-world service and outside
the scope of Play's billing requirement. No payment SDK is linked — check
`pubspec.yaml` if a reviewer asks.

### Health content

The sports-medicine library ships warm-up, injury and emergency guidance.
Expect the health declaration to come up. The content is general information
for coaches and players, is not personalised, does not diagnose, and the terms
of service say so explicitly.

### Permissions justification

- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` — foreground only, used at
  the moment the user opens the grounds map or taps "use my location". There
  is no background location permission and no location history.
- `POST_NOTIFICATIONS` — match reminders and squad invitations.

### Still to produce

- Feature graphic, 1024×500.
- Phone screenshots (2–8), plus 7" and 10" tablet sets — the app has a
  distinct two-pane tablet layout, so use real tablet captures rather than
  stretched phone ones.
- Short description (80 chars) and full description (4000 chars).

The 512×512 store icon is done: `assets/branding/play_store_icon_512.png`
(not shipped inside the app — `pubspec.yaml` only bundles `mark.png` and
`splash.png` from that folder).

## Known, accepted

- `applicationId` is `com.company.playsphere` — a template leftover, kept
  because Firebase and the Google Sign-In OAuth client are already wired to
  it. **Permanent from the first upload**; changing it later means a new
  store listing.
- No native debug symbols in the bundle. `debugSymbolLevel "SYMBOL_TABLE"` is
  set but only covers `externalNativeBuild` output, and Flutter's `.so` files
  are prebuilt, so there is nothing for AGP to package. Play warns; it does
  not block, and there is no clean fix for a Flutter app.
- iOS still carries `com.example.playsphere` as its bundle identifier. It does
  not affect Play, but it must be changed before any App Store submission, and
  that change needs its own Firebase iOS app.
