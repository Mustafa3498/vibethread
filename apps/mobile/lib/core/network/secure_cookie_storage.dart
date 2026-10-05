import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the cookie jar (which contains the HttpOnly refresh-token cookie)
/// in Keychain/Keystore instead of plain files on disk.
class SecureCookieStorage implements Storage {
  SecureCookieStorage(this._storage);

  final FlutterSecureStorage _storage;
  static const String _prefix = 'cookiejar_';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');

  @override
  Future<void> deleteAll(List<String> keys) =>
      Future.wait(keys.map(delete)).then((_) {});
}
