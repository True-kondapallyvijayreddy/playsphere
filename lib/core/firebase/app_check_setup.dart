import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Turns on Firebase App Check.
///
/// ## What this is for
///
/// `firestore.rules` is excellent and it authorizes IDENTITIES, not CLIENTS.
/// Every rule in it asks "who is signed in and what may they do" — which is
/// the right question and leaves a second one unasked: is this the app at all?
/// A web API key is public by design, so until now every Firestore read, every
/// Storage upload and every callable was reachable by a script holding a key
/// lifted from the web bundle.
///
/// Three findings in the review depended on that being true:
///
///   * the rating-injection path was cheap to automate, because there was
///     nothing to stop a script running the four writes in a loop;
///   * `storage.rules` names the missing control by name in its own header —
///     any signed-in account can write unlimited objects under its own uid
///     segment, and "the per-object ceilings are the only limit, and there is
///     no limit on the NUMBER of objects" is a billing risk with no fence;
///   * `redeemClaimCode` is callable SIGNED OUT (the child has no session
///     yet), so the only thing between a guessing script and a token for a
///     child's account was the code length and `maxInstances: 2`.
///
/// App Check does not replace any rule. It adds the precondition every rule
/// was implicitly assuming.
///
/// ## Deliberately not fatal
///
/// A failure here is logged and swallowed. App Check needs network to fetch
/// its first token, and this app is used on grounds with none — an
/// initialisation that threw would turn "no signal" into "the app will not
/// start", which is a far worse outcome than an unattested session. Enforcement
/// is the server's decision, not the client's, and while enforcement is off
/// (see below) an unattested client works exactly as before.
///
/// ## Rolling this out
///
/// Enforcement is a Firebase console setting, per product, and it must be
/// turned on in this order or it locks out real users:
///
///   1. Ship this. It starts sending tokens and changes nothing.
///   2. Watch the App Check metrics page for a week. It reports verified
///      versus unverified requests per product, which is how you find the
///      old app versions still in the wild.
///   3. Enforce Cloud Functions first — the smallest surface and the one with
///      `redeemClaimCode` on it.
///   4. Then Storage, then Firestore. Firestore last, because a mistake there
///      is the whole product rather than one feature.
///
/// Registering the debug provider's token for each developer device is part of
/// step 1; without it a debug build reports as unverified and pollutes the
/// metrics you are about to make a decision from.
Future<void> activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      // Play Integrity on Android and Device Check on iOS in release; the
      // debug provider otherwise, so a simulator and a CI run can still
      // obtain a token. `kDebugMode` rather than a compile-time flag because
      // a profile build should attest like a release one.
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      // reCAPTCHA Enterprise on the web.
      //
      // The site key is NOT a secret — it is served in the page and is meant
      // to be public, exactly like the Firebase API key beside it. The secret
      // half lives in the Google Cloud project. Left null here on purpose so
      // this file needs no configuration to compile: web attestation is
      // enabled by setting `kRecaptchaSiteKey` once the key exists, and until
      // then the web build simply sends no token, which is the state it has
      // always been in.
      webProvider: kRecaptchaSiteKey == null
          ? null
          : ReCaptchaEnterpriseProvider(kRecaptchaSiteKey!),
    );

    // Tokens are refreshed automatically from here. Worth having on: without
    // it, a token expires mid-match and the writes behind it start failing
    // once enforcement is enabled, which on a ground with intermittent signal
    // is indistinguishable from the network.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (error, stack) {
    // Never fatal. See the class comment: no signal must not mean no app.
    debugPrint('[PlaySphere] App Check activation failed: $error');
    debugPrintStack(stackTrace: stack);
  }
}

/// The reCAPTCHA Enterprise site key for the web build, once one exists.
///
/// Public by design — see [activateAppCheck]. Null until the key is created in
/// the Google Cloud console, so that adding web attestation is a one-line
/// change here rather than a change to the startup sequence.
const String? kRecaptchaSiteKey = null;
