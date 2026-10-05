import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';

import '../services/secure_storage_service.dart';

/// Attaches the access token (Bearer) to outgoing requests and, on a 401,
/// refreshes it once (shared across concurrent requests) and retries the call.
///
/// Backend contract:
///   POST /api/auth/refresh   (no body)
///     - reads the HttpOnly refresh cookie (path `/api/auth`) from the request
///     - responds { "accessToken": "..." } (optionally under "data")
///     - rotates the cookie via Set-Cookie
///
/// The refresh token never touches Dart code: the [CookieManager] on both
/// Dio instances sends and stores it automatically.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio dio,
    required SecureStorageService storage,
    required CookieJar cookieJar,
    this.onSessionExpired,
  })  : _dio = dio,
        _storage = storage,
        _cookieJar = cookieJar,
        // Separate instance WITHOUT this interceptor, so a failing refresh
        // can never trigger another refresh. It shares the SAME cookie jar.
        _refreshDio = Dio(
          BaseOptions(
            baseUrl: dio.options.baseUrl,
            connectTimeout: dio.options.connectTimeout,
            receiveTimeout: dio.options.receiveTimeout,
            contentType: Headers.jsonContentType,
          ),
        )..interceptors.add(CookieManager(cookieJar));

  /// Called when the session can no longer be refreshed; use it to log out.
  final VoidCallback? onSessionExpired;

  final Dio _dio;
  final Dio _refreshDio;
  final SecureStorageService _storage;
  final CookieJar _cookieJar;

  static const String _refreshPath = '/api/auth/refresh';
  static const String _retriedKey = 'auth_retried';

  /// Set `extra: {AuthInterceptor.skipAuthKey: true}` on a request to skip
  /// the Bearer header and the 401 refresh logic.
  static const String skipAuthKey = 'skipAuth';

  static const List<String> _publicPaths = [
    '/api/auth/login',
    '/api/auth/register',
    _refreshPath,
  ];

  /// In-flight refresh shared by all requests that hit 401 at the same time
  /// (important with refresh-token rotation: the cookie can only be used once).
  Future<String?>? _refreshFuture;

  bool _isPublic(RequestOptions o) =>
      o.extra[skipAuthKey] == true || _publicPaths.any(o.path.contains);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isPublic(options)) {
      final token = await _storage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;

    final shouldRefresh = err.response?.statusCode == 401 &&
        !_isPublic(request) &&
        request.extra[_retriedKey] != true;

    if (!shouldRefresh) return handler.next(err);

    final newToken = await _refreshAccessToken();
    if (newToken == null) return handler.next(err);

    // Retry the original request exactly once with the new token.
    request.extra[_retriedKey] = true;
    request.headers['Authorization'] = 'Bearer $newToken';

    try {
      final response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<String?> _refreshAccessToken() {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    final future = _performRefresh().whenComplete(() => _refreshFuture = null);
    _refreshFuture = future;
    return future;
  }

  Future<String?> _performRefresh() async {
    try {
      // No body: the refresh token travels in the HttpOnly cookie.
      final res = await _refreshDio.post<dynamic>(_refreshPath);

      final body = res.data;
      final payload = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : body)
          : const <String, dynamic>{};

      final accessToken = payload['accessToken'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        await _expireSession();
        return null;
      }

      await _storage.saveAccessToken(accessToken);
      return accessToken;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Only end the session if the server rejected the cookie (or none was
      // sent). Network errors/timeouts shouldn't log the user out.
      if (status == 400 || status == 401 || status == 403) {
        await _expireSession();
      }
      return null;
    }
  }

  Future<void> _expireSession() async {
    await _storage.clearAccessToken();
    await _cookieJar.deleteAll();
    onSessionExpired?.call();
  }
}
