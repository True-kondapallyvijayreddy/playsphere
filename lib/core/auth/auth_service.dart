import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../errors/app_exception.dart';

/// Google Sign-In, with the platform difference contained here and nowhere
/// else.
///
/// The two paths are genuinely different mechanisms, not a style choice:
///
///  * **Web** must use `signInWithPopup`. The native Google Sign-In SDK has no
///    web equivalent that returns a Firebase credential, and a redirect flow
///    loses in-memory state — which on a school laptop means a half-scored
///    match disappears.
///  * **Android / iOS** must use the native SDK, because it reuses the account
///    already on the device. A popup on mobile would force the user to type a
///    password that the phone already knows.
///
/// Callers never branch on platform; they call [signInWithGoogle].
class AuthService {
  AuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _injectedGoogleSignIn = googleSignIn;

  final FirebaseAuth _auth;

  final GoogleSignIn? _injectedGoogleSignIn;
  GoogleSignIn? _lazyGoogleSignIn;

  /// Built on first use, and never on the web.
  ///
  /// `google_sign_in_web` asserts that a client ID is configured as soon as it
  /// initialises. Constructing this eagerly therefore threw during app
  /// startup on the web and took the whole widget tree down before anything
  /// rendered — a blank page, with the real cause only visible in the browser
  /// console. Nothing on the web path needs this object anyway: [
  /// signInWithGoogle] uses `signInWithPopup` there, and [signOut] already
  /// skips it. Keeping it lazy means the web build never touches the plugin.
  GoogleSignIn get _googleSignIn {
    assert(
      !kIsWeb,
      'The native Google Sign-In SDK must not be used on the web — '
      'signInWithGoogle uses signInWithPopup there.',
    );
    return _injectedGoogleSignIn ??
        (_lazyGoogleSignIn ??= GoogleSignIn(scopes: const ['email']));
  }

  /// Emits on every sign-in, sign-out and token refresh. This is the single
  /// source of truth for "is anyone signed in" — never a local bool.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          // Always show the chooser. On a shared school or college laptop,
          // silently reusing the last account signs the next teacher in as
          // the previous one — which would attribute their scoring actions
          // to the wrong person in the audit log.
          ..setCustomParameters({'prompt': 'select_account'});
        return await _auth.signInWithPopup(provider);
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthCancelledException();
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    } on PlatformException catch (e) {
      throw _translatePlatform(e);
    }
  }

  /// Signs in as the exact uid a custom token was minted for.
  ///
  /// The one caller is the first half of a managed-profile claim
  /// (`UserRepository.redeemClaimCode`, `functions/family.js`): the token
  /// proves the child's device presented a code only their guardian could
  /// have generated, and this is what turns that proof into an actual
  /// session — the same uid the guardian's managed profile always was, with
  /// every match, every player code, everything already on it.
  Future<UserCredential> signInWithCustomToken(String token) async {
    try {
      return await _auth.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  /// Attaches the caller's own Google account to whichever uid they are
  /// CURRENTLY signed in as, rather than signing into a new one.
  ///
  /// The one caller today is the child's half of a managed-profile claim
  /// (`ClaimEntryScreen`): they've just signed in with a custom token minted
  /// for their existing profile's uid (`UserRepository.redeemClaimCode`),
  /// and this is what turns that one-shot token into a durable login they
  /// can use again tomorrow. Everything about the platform split above
  /// applies identically here — same popup-vs-native reasoning — so this
  /// mirrors [signInWithGoogle] almost exactly; the only real difference is
  /// `linkWithCredential` instead of `signInWithCredential`.
  Future<UserCredential> linkGoogleAccount() async {
    final current = _auth.currentUser;
    if (current == null) throw const UnauthorizedException();
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..setCustomParameters({'prompt': 'select_account'});
        return await current.linkWithPopup(provider);
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthCancelledException();
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await current.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    } on PlatformException catch (e) {
      throw _translatePlatform(e);
    }
  }

  Future<void> signOut() async {
    // Sign out of Google as well as Firebase on mobile, otherwise the next
    // sign-in silently reuses the same account and "switch user" appears
    // broken to anyone sharing a device.
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // A failure to clear the Google session must not block the Firebase
        // sign-out — the user asked to leave, so leaving takes priority.
      }
    }
    await _auth.signOut();
  }

  /// Erases the account: the profile's personal details first, then the
  /// sign-in.
  ///
  /// Both halves happen in `deleteMyAccount` (functions/account.js), because
  /// neither is the client's to do. This used to be `user.delete()` alone,
  /// which removes the credential and nothing else — `users/{uid}` kept the
  /// name, email, phone, date of birth and district, and `firestore.rules`
  /// refuses to delete that document for anybody, so no client could have
  /// cleaned up even if it had tried. The server scrubs it under Admin
  /// privileges instead and deletes the Auth user in the same call, which also
  /// retires the "requires a recent sign-in" failure this used to raise.
  ///
  /// Throws with a message to show when the account still manages a child
  /// profile: those are separate accounts only this one can hand over, so they
  /// have to be passed on before it goes.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw const UnauthorizedException();
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('deleteMyAccount')
          .call<Map<String, dynamic>>();
      // The account is already gone server-side. Clearing the local session
      // (and the Google one on mobile) makes the router redirect now rather
      // than whenever the next token refresh notices.
      await signOut();
    } on FirebaseFunctionsException catch (e) {
      throw ValidationException(
        e.message ?? 'Your account could not be deleted. Please try again.',
      );
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  /// Everything PlaySphere holds about this account, as JSON bytes ready to
  /// be written out.
  ///
  /// The privacy policy has always promised "ask, and we will send you your
  /// account data in a machine-readable file", and nothing implemented it —
  /// there was no automated path and no tooling to produce one by hand either,
  /// so the promise rested on somebody writing ad-hoc queries against
  /// production. India's DPDP Act gives a person the right to a summary of
  /// what is processed about them; this is that right, self-service.
  ///
  /// The server walks the same declared inventory `deleteMyAccount` erases
  /// (`functions/subject_data.js`), so the export cannot come to disagree with
  /// the deletion about which collections exist.
  ///
  /// Returns bytes rather than writing the file, because where a file goes is
  /// the caller's decision — `saveFileBytes` opens a share sheet on a phone
  /// and downloads on the web, and a service should not be reaching for either.
  Future<Uint8List> exportMyData() async {
    if (_auth.currentUser == null) throw const UnauthorizedException();
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('exportMyData')
          .call<Map<Object?, Object?>>();
      // Pretty-printed on purpose. The person receiving this is more likely to
      // open it in a text editor than to feed it to a parser, and a single
      // 40KB line is not a machine-readable file in any useful sense.
      final json = const JsonEncoder.withIndent('  ').convert(
        _plainMap(result.data),
      );
      return Uint8List.fromList(utf8.encode(json));
    } on FirebaseFunctionsException catch (e) {
      throw ValidationException(
        e.message ?? 'Your data could not be exported. Please try again.',
      );
    }
  }

  /// Recursively rebuilds the callable's result as plain Dart collections.
  ///
  /// `httpsCallable` hands back `Map<Object?, Object?>` and `List<Object?>` at
  /// every level, which `jsonEncode` refuses — it wants `Map<String, dynamic>`.
  /// Encoding the top level alone is not enough, because the failure is at
  /// whatever depth the first nested map sits, and an export is nested
  /// several deep.
  static Object? _plainMap(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _plainMap(entry.value),
      };
    }
    if (value is List) return value.map(_plainMap).toList();
    return value;
  }

  /// Failures raised by the native Google Sign-In SDK, before Firebase is
  /// ever reached.
  ///
  /// These do not arrive as [FirebaseAuthException] — the SDK throws a
  /// `PlatformException` — so without this they fell through every catch in
  /// the app and reached the UI as the generic "Something went wrong. Please
  /// try again.", which is unactionable for the one failure that actually
  /// happens in the wild.
  ///
  /// That failure is `ApiException: 10` (DEVELOPER_ERROR): the certificate
  /// the app was signed with has no OAuth client registered against it in
  /// the Firebase console. It is the signature of a Play Store install,
  /// because Play App Signing re-signs the bundle with a key that is neither
  /// the debug nor the upload keystore — so debug builds work, internal
  /// testing works, and only real users hit it. See
  /// `docs/PLAY_STORE_RELEASE.md`.
  ///
  /// Release builds minify the exception class name, so the message reads
  /// `commonapi.b: 10:` rather than `ApiException: 10:`. Matching on the
  /// code alone is what survives R8.
  AppException _translatePlatform(PlatformException e) {
    final detail = '${e.message ?? ''} ${e.details ?? ''}';
    if (detail.contains(': 10:') || detail.contains(': 10,')) {
      return const AuthException(
        'Sign-in is not configured for this build of the app. The app is '
        'signed with a certificate that has not been registered. Please '
        'report this — it needs a fix from the PlaySphere team, not from you.',
      );
    }
    if (e.code == 'network_error') {
      return const NetworkException(
        'No connection. Check your network and try again.',
      );
    }
    if (e.code == 'sign_in_canceled') return const AuthCancelledException();
    return AuthException(e.message ?? 'Sign-in failed. Please try again.');
  }

  AppException _translate(FirebaseAuthException e) {
    return switch (e.code) {
      'network-request-failed' => const NetworkException(
          'No connection. Check your network and try again.',
        ),
      'popup-closed-by-user' ||
      'cancelled-popup-request' =>
        const AuthCancelledException(),
      'popup-blocked' => const AuthException(
          'Your browser blocked the sign-in popup. Allow popups for this '
          'site and try again.',
        ),
      'account-exists-with-different-credential' => const AuthException(
          'An account already exists with this email using a different '
          'sign-in method.',
        ),
      'credential-already-in-use' => const AuthException(
          'This Google account is already linked to another PlaySphere '
          'profile. Sign in with a different Google account to claim this '
          'one.',
        ),
      'provider-already-linked' => const AuthException(
          'This profile already has a Google account linked to it.',
        ),
      'user-disabled' => const AuthException(
          'This account has been disabled. Contact your organization admin.',
        ),
      'operation-not-allowed' => const AuthException(
          'Google Sign-In is not enabled for this project yet. An administrator '
          'must switch it on in the Firebase console.',
        ),
      _ => AuthException(e.message ?? 'Sign-in failed. Please try again.'),
    };
  }
}
