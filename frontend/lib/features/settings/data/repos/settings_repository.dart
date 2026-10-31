import 'package:dio/dio.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';

class SettingsRepository {
  SettingsRepository(this._dio);

  final Dio _dio;

  Future<StationProfile> fetchStation() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/station');
      return StationProfile.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<StationProfile> saveStation(Map<String, dynamic> body) {
    return _guard(() async {
      final response = await _dio.patch('/api/v1/station', data: body);
      return StationProfile.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<StationProfile> uploadLogo(String path, String filename) {
    return _guard(() async {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: filename),
      });
      final response = await _dio.post(
        '/api/v1/station/logo',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return StationProfile.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<StaffMember>> fetchUsers({required String search, required String role}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/users',
        queryParameters: {
          'search': search,
          'role': role,
          'limit': 100,
          'offset': 0,
        },
      );
      return _items(response.data).map(StaffMember.fromJson).toList();
    });
  }

  Future<StaffMember> createUser(Map<String, dynamic> body) {
    return _guard(() async {
      final response = await _dio.post('/api/v1/users', data: body);
      return StaffMember.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<StaffMember> updateUser(String id, Map<String, dynamic> body) {
    return _guard(() async {
      final response = await _dio.patch('/api/v1/users/$id', data: body);
      return StaffMember.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<RoleGrant>> fetchRoles() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/roles');
      return _items(response.data).map(RoleGrant.fromJson).toList();
    });
  }

  Future<RoleGrant> replacePermissions(String roleId, List<String> permissions) {
    return _guard(() async {
      final response = await _dio.put(
        '/api/v1/roles/$roleId/permissions',
        data: {'permissions': permissions},
      );
      return RoleGrant.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<List<FuelProductItem>> fetchProducts() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/products');
      return _items(response.data).map(FuelProductItem.fromJson).toList();
    });
  }

  Future<void> addPrice(String productId, String price) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/products/$productId/prices',
        data: {'price_per_liter': price},
      );
    });
  }

  Future<List<ShiftTemplateItem>> fetchTemplates() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/shift-templates');
      return _items(response.data).map(ShiftTemplateItem.fromJson).toList();
    });
  }

  Future<ShiftTemplateItem> createTemplate(ShiftDraft draft) {
    return _guard(() async {
      final response = await _dio.post('/api/v1/shift-templates', data: draft.toJson());
      return ShiftTemplateItem.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<ShiftTemplateItem> updateTemplate(String id, ShiftDraft draft) {
    return _guard(() async {
      final response = await _dio.patch('/api/v1/shift-templates/$id', data: draft.toJson());
      return ShiftTemplateItem.fromJson(response.data as Map<String, dynamic>);
    });
  }

  List<Map<String, dynamic>> _items(Object? data) {
    final body = data as Map<String, dynamic>;
    final raw = body['items'] as List<dynamic>? ?? const [];
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw mapDioError(error);
    }
  }
}
