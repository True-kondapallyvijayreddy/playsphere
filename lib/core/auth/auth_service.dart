import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  /// Deleting an account requires a recent sign-in. Surfacing that as a
  /// distinct, actionable error avoids the generic "something went wrong"
  /// that leaves a user unable to exercise their deletion right.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw const UnauthorizedException();
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const ReauthenticationRequiredException();
      }
      throw _translate(e);
    }
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
