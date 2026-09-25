import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage_keys.dart';

/// Secure storage for the worker session token (never SharedPreferences or a
/// plain file). Trimmed from the Operator App's `SecureTokenStore` to the one
/// credential this app has.
abstract class SecureTokenStore {
  Future<void> writeSessionToken(String token);
  Future<String?> readSessionToken();
  Future<void> clearSessionToken();
}

class FlutterSecureTokenStore implements SecureTokenStore {
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<void> writeSessionToken(String token) =>
      _storage.write(key: SecureStorageKeys.sessionToken, value: token);

  @override
  Future<String?> readSessionToken() =>
      _storage.read(key: SecureStorageKeys.sessionToken);

  @override
  Future<void> clearSessionToken() =>
      _storage.delete(key: SecureStorageKeys.sessionToken);
}

/// In-memory token store used in tests.
class InMemoryTokenStore implements SecureTokenStore {
  InMemoryTokenStore({this._sessionToken});

  String? _sessionToken;

  @override
  Future<void> writeSessionToken(String token) async {
    _sessionToken = token;
  }

  @override
  Future<String?> readSessionToken() async => _sessionToken;

  @override
  Future<void> clearSessionToken() async {
    _sessionToken = null;
  }
}

final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return FlutterSecureTokenStore();
});
