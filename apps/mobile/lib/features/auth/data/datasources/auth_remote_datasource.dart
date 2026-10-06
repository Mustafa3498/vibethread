import 'package:dio/dio.dart';

import '../../../../core/network/auth_interceptor.dart';

class LoginResponse {
  const LoginResponse({required this.accessToken, required this.user});

  final String accessToken;
  final Map<String, dynamic> user;
}

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  /// The response sets the HttpOnly refresh cookie; the CookieManager on
  /// [_dio] stores it automatically. Only the access token is read here.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post<dynamic>(
      '/api/auth/login',
      data: {'email': email, 'password': password},
    );

    final body = res.data as Map<String, dynamic>;
    final payload = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;

    return LoginResponse(
      accessToken: payload['accessToken'] as String,
      user: Map<String, dynamic>.from(payload['user'] as Map),
    );
  }

  /// Authenticated probe (`GET /api/auth/me`). If the stored access token has
  /// expired the server answers 401, the [AuthInterceptor] refreshes it with
  /// the HttpOnly cookie, saves the new token and retries this call.
  Future<void> verifySession() => _dio.get<dynamic>(
        '/api/auth/me',
        options: Options(
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );

  /// Lets the server revoke the session and clear the cookie. Identified by
  /// the cookie, so it skips the Bearer header and the 401 refresh logic.
  Future<void> logout() => _dio.post<dynamic>(
        '/api/auth/logout',
        options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
      );
}
