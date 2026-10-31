import 'package:dio/dio.dart';
import 'package:frontend/features/auth/data/models/token_pair.dart';

class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<TokenPair> login({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    final response = await _dio.post(
      '/api/v1/auth/login',
      data: {
        'username': username,
        'password': password,
        'remember_me': rememberMe,
      },
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _dio.post(
      '/api/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> logout(String refreshToken) async {
    await _dio.post(
      '/api/v1/auth/logout',
      data: {'refresh_token': refreshToken},
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.post(
      '/api/v1/auth/change-password',
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }
}
