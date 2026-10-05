/// Thrown by [AuthRepository] for any auth failure, with a user-safe message.
class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}

abstract interface class AuthRepository {
  /// True if an access token is stored on the device.
  Future<bool> hasSession();

  /// Returns the user JSON until a `UserEntity` exists.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  });

  /// Always clears local session state, even if the server call fails.
  Future<void> logout();
}
