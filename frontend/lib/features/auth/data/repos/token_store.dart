import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshKey = 'refresh_token';
  static const _rememberKey = 'remember_me';

  final FlutterSecureStorage _storage;
  String? _memoryRefresh;
  bool remember = false;

  Future<void> save({
    required String refreshToken,
    required bool remember,
  }) async {
    _memoryRefresh = refreshToken;
    this.remember = remember;
    if (remember) {
      await _storage.write(key: _refreshKey, value: refreshToken);
      await _storage.write(key: _rememberKey, value: '1');
    } else {
      await _storage.delete(key: _refreshKey);
      await _storage.delete(key: _rememberKey);
    }
  }

  Future<String?> read() async {
    if (_memoryRefresh != null) {
      return _memoryRefresh;
    }
    final flag = await _storage.read(key: _rememberKey);
    if (flag != '1') {
      return null;
    }
    remember = true;
    _memoryRefresh = await _storage.read(key: _refreshKey);
    return _memoryRefresh;
  }

  Future<void> clear() async {
    _memoryRefresh = null;
    remember = false;
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _rememberKey);
  }
}
