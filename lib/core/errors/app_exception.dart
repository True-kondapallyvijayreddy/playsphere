/// Every failure the UI is expected to render is one of these.
///
/// Raw `FirebaseException`s never reach a widget: they carry codes like
/// `permission-denied` that mean nothing to a PE teacher standing courtside.
/// Repositories translate at the boundary so screens always have a sentence
/// they can display verbatim.
sealed class AppException implements Exception {
  const AppException(this.message);

  /// Safe to show to a user as-is.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkException extends AppException {
  const NetworkException([
    super.message = 'No connection. Your changes are saved and will sync '
        'automatically.',
  ]);
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([
    super.message = 'You are signed out. Sign in again to continue.',
  ]);
}

/// The caller is signed in but lacks the role for this action. Distinct from
/// [UnauthorizedException] because the fix is different: ask an admin, not
/// sign in again.
class PermissionDeniedException extends AppException {
  const PermissionDeniedException([
    super.message =
        'You do not have permission to do that in this organization.',
  ]);
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// The server refused the QUERY rather than the caller — in practice a
/// Firestore index that exists in `firestore.indexes.json` but was never
/// deployed.
///
/// Worth its own type because it is the one failure a retry provably cannot
/// fix, and the landing screen spent a release offering "Try again" against
/// it: with offline persistence on, the cache answered first, so every tap
/// repainted the dashboard for a frame before the server rejected it again.
/// Naming it lets the UI say so instead of inviting that loop.
class BackendNotReadyException extends AppException {
  const BackendNotReadyException([
    super.message = 'This part of the app is not finished setting up on the '
        'server. Trying again will not help — please report it.',
  ]);
}

class NotFoundException extends AppException {
  const NotFoundException([super.message = 'That no longer exists.']);
}

/// Two scorers acted on the same delivery. The loser re-syncs and retries —
/// this is an expected, recoverable condition, not a bug.
class ConflictException extends AppException {
  const ConflictException([
    super.message = 'Someone else scored this first. Refreshing to the '
        'latest score.',
  ]);
}

class AuthException extends AppException {
  const AuthException(super.message);
}

/// The user closed the Google popup or backed out of the account chooser.
/// Should be swallowed silently — it is not an error, it is a decision.
class AuthCancelledException extends AuthException {
  const AuthCancelledException([super.message = 'Sign-in cancelled.']);
}

class ReauthenticationRequiredException extends AuthException {
  const ReauthenticationRequiredException([
    super.message = 'For security, sign in again before making this change.',
  ]);
}
