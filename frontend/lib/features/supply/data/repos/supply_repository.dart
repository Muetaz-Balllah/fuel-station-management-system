import 'package:dio/dio.dart';
import 'package:frontend/core/models/paged_list.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/core/networking/upload_file.dart';
import 'package:frontend/features/supply/data/models/supply_models.dart';

class SupplySummary {
  const SupplySummary({
    required this.deliveredLiters,
    required this.activeOrders,
    required this.pendingOrders,
    required this.activeSuppliers,
    required this.week,
  });

  final String deliveredLiters;
  final int activeOrders;
  final int pendingOrders;
  final int activeSuppliers;
  final List<SupplyWeekDay> week;

  factory SupplySummary.fromJson(Map<String, dynamic> json) {
    final week = json['week'] as List<dynamic>? ?? const [];
    return SupplySummary(
      deliveredLiters: json['delivered_liters'] as String? ?? '0.000',
      activeOrders: json['active_orders'] as int? ?? 0,
      pendingOrders: json['pending_orders'] as int? ?? 0,
      activeSuppliers: json['active_suppliers'] as int? ?? 0,
      week: week.map((item) => SupplyWeekDay.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class SupplyRepository {
  SupplyRepository(this._dio);

  final Dio _dio;

  Future<SupplySummary> fetchSummary() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/supply/summary');
      return SupplySummary.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<SupplierRecord>> fetchSuppliers() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/suppliers');
      return _items(response.data, SupplierRecord.fromJson);
    });
  }

  Future<SupplierRecord> createSupplier({
    required String name,
    required String headquarters,
    required String contactName,
    required String phone,
    required String maxDailyLiters,
  }) {
    return _guard(() async {
      final response = await _dio.post(
        '/api/v1/suppliers',
        data: {
          'name': name,
          'headquarters': headquarters,
          'contact_name': contactName,
          'phone': phone,
          'max_daily_liters': maxDailyLiters,
        },
      );
      return SupplierRecord.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<PagedList<SupplyOrderRecord>> fetchOrders({int page = 1, int pageSize = 20}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/supply-orders',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return PagedList.fromJson(response.data as Map<String, dynamic>, SupplyOrderRecord.fromJson);
    });
  }

  Future<List<SupplyProductOption>> fetchProducts() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/products');
      return _items(response.data, SupplyProductOption.fromJson);
    });
  }

  Future<List<SupplyTankOption>> fetchTanks() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/tanks');
      return _items(response.data, SupplyTankOption.fromJson);
    });
  }

  Future<void> createOrder({
    required String supplierId,
    required String tankId,
    required String productId,
    required String liters,
    required String expectedOn,
    required String notes,
  }) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/supply-orders',
        data: {
          'supplier_id': supplierId,
          'tank_id': tankId,
          'product_id': productId,
          'ordered_liters': liters,
          'expected_on': expectedOn,
          'notes': notes,
        },
      );
    });
  }

  Future<void> receive(String orderId, {String? liters}) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/supply-orders/$orderId/receive',
        data: {if (liters != null && liters.isNotEmpty) 'received_liters': liters},
      );
    });
  }

  Future<void> cancel(String orderId) {
    return _guard(() async {
      await _dio.post('/api/v1/supply-orders/$orderId/cancel');
    });
  }

  Future<SupplierRecord> uploadSupplierLogo({
    required String supplierId,
    required List<int> bytes,
    required String filename,
  }) {
    return _guard(() async {
      final form = FormData.fromMap({
        'file': imagePart(bytes, filename),
      });
      final response = await _dio.post(
        '/api/v1/suppliers/$supplierId/logo',
        data: form,
      );
      return SupplierRecord.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<void> updateSupplier({
    required String id,
    required String headquarters,
    required String contactName,
    required String phone,
    required String maxDailyLiters,
  }) {
    return _guard(() async {
      await _dio.patch(
        '/api/v1/suppliers/$id',
        data: {
          'headquarters': headquarters,
          'contact_name': contactName,
          'phone': phone,
          'max_daily_liters': maxDailyLiters,
        },
      );
    });
  }

  List<T> _items<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
    final body = raw as Map<String, dynamic>? ?? const {};
    final items = body['items'] as List<dynamic>? ?? const [];
    return items.map((item) => parse(Map<String, dynamic>.from(item as Map))).toList();
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw mapDioError(error);
    }
  }
}
