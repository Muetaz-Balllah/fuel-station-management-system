import 'package:dio/dio.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/core/networking/upload_file.dart';
import 'package:frontend/features/auth/data/apis/auth_api.dart';
import 'package:frontend/features/auth/data/models/auth_user.dart';
import 'package:frontend/features/auth/data/repos/token_store.dart';

abstract class AuthGateway {
  Future<AuthUser> login({
    required String username,
    required String password,
    required bool rememberMe,
  });

  Future<AuthUser?> restore();

  Future<void> logout();

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<AuthUser> uploadPhoto({required List<int> bytes, required String filename});
}

class AuthRepository implements AuthGateway {
  AuthRepository({
    required AuthApi api,
    required TokenStore store,
    required SessionTokens tokens,
  })  : _api = api,
        _store = store,
        _tokens = tokens;

  final AuthApi _api;
  final TokenStore _store;
  final SessionTokens _tokens;

  @override
  Future<AuthUser> login({
    required String username,
    required String password,
    required bool rememberMe,
  }) {
    return _guard(() async {
      final pair = await _api.login(
        username: username,
        password: password,
        rememberMe: rememberMe,
      );
      _tokens.access = pair.accessToken;
      await _store.save(refreshToken: pair.refreshToken, remember: rememberMe);
      return pair.user;
    });
  }

  @override
  Future<AuthUser?> restore() async {
    final refresh = await _store.read();
    if (refresh == null || refresh.isEmpty) {
      return null;
    }
    return _guard(() async {
      final pair = await _api.refresh(refresh);
      _tokens.access = pair.accessToken;
      await _store.save(refreshToken: pair.refreshToken, remember: _store.remember);
      return pair.user;
    });
  }

  @override
  Future<void> logout() async {
    final refresh = await _store.read();
    try {
      if (refresh != null && refresh.isNotEmpty) {
        await _api.logout(refresh);
      }
    } catch (_) {
      // The local session is cleared either way.
    } finally {
      _tokens.access = null;
      await _store.clear();
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _guard(() async {
      await _api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    });
  }

  @override
  Future<AuthUser> uploadPhoto({required List<int> bytes, required String filename}) {
    return _guard(() async {
      final response = await _api.uploadPhoto(bytes: bytes, filename: filename);
      return response;
    });
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw mapDioError(error);
    }
  }
}
