import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain (iOS) / Keystore (Android) backed storage for the ACCESS token.
///
/// The refresh token is NOT stored here: the backend keeps it in an HttpOnly
/// cookie, which is persisted by the cookie jar (see `SecureCookieStorage`).
class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? defaultStorage;

  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _accessTokenKey = 'access_token';

  final FlutterSecureStorage _storage;

  // In-memory cache: avoids a Keychain/Keystore read on every HTTP request.
  String? _cachedAccessToken;
  bool _loaded = false;

  Future<String?> getAccessToken() async {
    if (!_loaded) {
      _cachedAccessToken = await _storage.read(key: _accessTokenKey);
      _loaded = true;
    }
    return _cachedAccessToken;
  }

  Future<void> saveAccessToken(String token) async {
    _cachedAccessToken = token;
    _loaded = true;
    await _storage.write(key: _accessTokenKey, value: token);
  }

  Future<void> clearAccessToken() async {
    _cachedAccessToken = null;
    _loaded = true;
    await _storage.delete(key: _accessTokenKey);
  }
}
