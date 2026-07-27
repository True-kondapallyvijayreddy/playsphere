/// Base type for all handled failures surfaced to the UI layer.
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'Network error, please retry.']);
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Session expired.']);
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}

class NotFoundException extends AppException {
  const NotFoundException([super.message = 'Resource not found.']);
}
