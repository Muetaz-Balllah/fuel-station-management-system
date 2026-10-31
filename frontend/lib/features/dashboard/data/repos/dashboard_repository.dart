import 'package:dio/dio.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  Future<DashboardSnapshot> fetch({String? date}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/dashboard',
        queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
      );
      return DashboardSnapshot.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<StationNotice>> notifications() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/notifications');
      final body = response.data as Map<String, dynamic>? ?? const {};
      final items = body['items'] as List<dynamic>? ?? const [];
      return items.map((item) => StationNotice.fromJson(item as Map<String, dynamic>)).toList();
    });
  }

  Future<void> markRead(String id) {
    return _guard(() async {
      await _dio.post('/api/v1/notifications/$id/read');
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
