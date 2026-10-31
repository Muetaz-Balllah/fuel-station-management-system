import 'package:dio/dio.dart';
import 'package:frontend/core/networking/api_config.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/auth/data/repos/token_store.dart';

class SessionTokens {
  String? access;
}

typedef SessionExpired = void Function();

Dio buildDio({
  required SessionTokens tokens,
  required TokenStore store,
  required SessionExpired onSessionExpired,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
    ),
  );
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      tokens: tokens,
      store: store,
      onSessionExpired: onSessionExpired,
    ),
  );
  return dio;
}

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.dio,
    required this.tokens,
    required this.store,
    required this.onSessionExpired,
  });

  final Dio dio;
  final SessionTokens tokens;
  final TokenStore store;
  final SessionExpired onSessionExpired;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final access = tokens.access;
    if (access != null && access.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final path = err.requestOptions.path;
    final isAuthCall = path.contains('/auth/login') || path.contains('/auth/refresh');
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    if (status != 401 || isAuthCall || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refresh = await store.read();
    if (refresh == null || refresh.isEmpty) {
      onSessionExpired();
      handler.next(err);
      return;
    }

    try {
      final response = await Dio(BaseOptions(baseUrl: dio.options.baseUrl)).post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = response.data as Map<String, dynamic>;
      tokens.access = data['access_token'] as String;
      await store.save(
        refreshToken: data['refresh_token'] as String,
        remember: store.remember,
      );
      final request = err.requestOptions;
      request.extra['retried'] = true;
      request.headers['Authorization'] = 'Bearer ${tokens.access}';
      final replay = await dio.fetch(request);
      handler.resolve(replay);
    } catch (_) {
      await store.clear();
      tokens.access = null;
      onSessionExpired();
      handler.next(err);
    }
  }
}

ApiException mapDioError(DioException error) {
  final data = error.response?.data;
  if (data is Map && data['message'] is String) {
    return ApiException(data['message'] as String, code: data['code'] as String?);
  }
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return ApiException('تعذر الاتصال بالخادم. تأكد أن النظام يعمل ثم أعد المحاولة.');
  }
  return ApiException('حدث خطأ غير متوقع. حاول مرة أخرى.');
}
