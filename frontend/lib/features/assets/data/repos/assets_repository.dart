import 'package:dio/dio.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/features/assets/data/models/asset_models.dart';

class AssetsRepository {
  AssetsRepository(this._dio);

  final Dio _dio;

  Future<AssetBoard> fetchBoard() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/assets/board');
      return AssetBoard.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<({List<InventoryEvent> items, int total})> fetchEvents({
    String? productId,
    int limit = 8,
    int offset = 0,
  }) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/inventory/events',
        queryParameters: {
          if (productId != null && productId.isNotEmpty) 'product_id': productId,
          'limit': limit,
          'offset': offset,
        },
      );
      final body = response.data as Map<String, dynamic>;
      final raw = body['items'] as List<dynamic>? ?? const [];
      return (
        items: raw.map((item) => InventoryEvent.fromJson(item as Map<String, dynamic>)).toList(),
        total: body['total'] as int? ?? raw.length,
      );
    });
  }

  Future<void> createTank({
    required String name,
    required String productId,
    required String capacityLiters,
  }) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/tanks',
        data: {
          'name': name,
          'product_id': productId,
          'capacity_liters': capacityLiters,
        },
      );
    });
  }

  Future<void> createPump({required String code, required String tankId}) {
    return _guard(() async {
      await _dio.post('/api/v1/pumps', data: {'code': code, 'tank_id': tankId});
    });
  }

  Future<void> updatePumpStatus({required String pumpId, required String status}) {
    return _guard(() async {
      await _dio.patch('/api/v1/pumps/$pumpId', data: {'status': status});
    });
  }

  Future<void> createNozzle({
    required String pumpId,
    required String code,
    required String label,
    required String initialMeter,
    required String status,
  }) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/pumps/$pumpId/nozzles',
        data: {
          'code': code,
          'label': label,
          'initial_meter': initialMeter,
          'status': status,
        },
      );
    });
  }

  Future<void> deleteTank(String tankId) {
    return _guard(() async {
      await _dio.delete('/api/v1/tanks/$tankId');
    });
  }

  Future<void> deletePump(String pumpId) {
    return _guard(() async {
      await _dio.delete('/api/v1/pumps/$pumpId');
    });
  }

  Future<void> deleteNozzle(String nozzleId) {
    return _guard(() async {
      await _dio.delete('/api/v1/nozzles/$nozzleId');
    });
  }

  Future<void> updateNozzleStatus({required String nozzleId, required String status}) {
    return _guard(() async {
      await _dio.patch('/api/v1/nozzles/$nozzleId', data: {'status': status});
    });
  }

  Future<void> adjustTank({
    required String tankId,
    required String litersDelta,
    required String note,
  }) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/tanks/$tankId/adjustments',
        data: {'liters_delta': litersDelta, 'note': note},
      );
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
