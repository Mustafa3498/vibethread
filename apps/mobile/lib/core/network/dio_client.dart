import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/secure_storage_service.dart';
import 'auth_interceptor.dart';
import 'secure_cookie_storage.dart';

/// Central HTTP client for the VibeThread backend.
///
/// [baseUrl] must NOT end with `/api`: every datasource and the
/// [AuthInterceptor] already use full paths such as `/api/auth/login`.
///
/// Dio does NOT handle cookies on mobile by itself, so a [CookieManager]
/// backed by a persistent jar is required for the HttpOnly refresh cookie.
/// The same [cookieJar] is exposed so the auth repository can clear it.
class DioClient {
  DioClient._({required this.dio, required this.cookieJar});

  final Dio dio;
  final CookieJar cookieJar;

  static Future<DioClient> create({
    required String baseUrl,
    required SecureStorageService secureStorage,
    VoidCallback? onSessionExpired,
  }) async {
    final cookieJar = createCookieJar();

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );

    // Order matters: cookies first, then auth.
    dio.interceptors
      ..add(CookieManager(cookieJar))
      ..add(
        AuthInterceptor(
          dio: dio,
          storage: secureStorage,
          cookieJar: cookieJar,
          onSessionExpired: onSessionExpired,
        ),
      );

    if (kDebugMode) {
      // Method/URL/status only: bodies and headers contain passwords,
      // access tokens and Set-Cookie values.
      dio.interceptors.add(
        LogInterceptor(
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          responseBody: false,
          logPrint: (o) => debugPrint(o.toString()),
        ),
      );
    }

    return DioClient._(dio: dio, cookieJar: cookieJar);
  }

  /// Persistent jar whose contents are encrypted at rest (Keychain/Keystore).
  static PersistCookieJar createCookieJar([FlutterSecureStorage? storage]) =>
      PersistCookieJar(
        ignoreExpires: false,
        storage: SecureCookieStorage(
          storage ?? SecureStorageService.defaultStorage,
        ),
      );
}
