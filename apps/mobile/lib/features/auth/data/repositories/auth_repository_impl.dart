import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../../../../core/errors/dio_error_message.dart';
import '../../../../core/services/secure_storage_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required SecureStorageService storage,
    required CookieJar cookieJar,
  })  : _remote = remote,
        _storage = storage,
        _cookieJar = cookieJar;

  final AuthRemoteDataSource _remote;
  final SecureStorageService _storage;
  final CookieJar _cookieJar;

  /// True if the device holds a session that still works.
  ///
  /// Access tokens live only 15 minutes and public catalog calls never use
  /// them, so a stored token is often stale. Probing `/api/auth/me` makes the
  /// interceptor refresh it (so the socket connects with a valid token).
  @override
  Future<bool> hasSession() async {
    final token = await _storage.getAccessToken();
    if (token == null || token.isEmpty) return false;

    try {
      await _remote.verifySession();
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        // Refresh was rejected too: the interceptor already cleared the session.
        return false;
      }
      // Server unreachable / timeout: keep the session and try again later.
      return true;
    }
  }

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _remote.login(email: email, password: password);
      await _storage.saveAccessToken(result.accessToken);
      return result.user;
    } on DioException catch (e) {
      throw AuthException(messageFromDio(e), statusCode: e.response?.statusCode);
    } on TypeError {
      throw const AuthException('Unexpected response from the server.');
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _remote.logout();
    } on DioException {
      // Best effort: local state is cleared below regardless.
    } finally {
      await _storage.clearAccessToken();
      await _cookieJar.deleteAll();
    }
  }
}
