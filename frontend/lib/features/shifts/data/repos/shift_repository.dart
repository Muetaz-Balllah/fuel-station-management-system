import 'package:dio/dio.dart';
import 'package:frontend/core/models/paged_list.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';

class AssignmentSnapshot {
  const AssignmentSnapshot({
    required this.canOpen,
    required this.reason,
    required this.sessionId,
    required this.templateName,
    required this.duty,
    required this.nozzles,
    this.selfService = false,
    this.shifts = const [],
    this.identityName = '',
  });

  final bool canOpen;
  final String? reason;
  final String? sessionId;
  final String? templateName;
  final DutyRecord? duty;
  final List<AssignedNozzle> nozzles;
  final bool selfService;
  final List<ClaimableShift> shifts;
  final String identityName;

  factory AssignmentSnapshot.fromJson(Map<String, dynamic> json) {
    final shift = json['session'] as Map<String, dynamic>?;
    final duty = json['duty'] as Map<String, dynamic>?;
    final nozzles = json['nozzles'] as List<dynamic>? ?? const [];
    final shifts = json['shifts'] as List<dynamic>? ?? const [];
    final identity = json['identity'] as Map<String, dynamic>?;
    return AssignmentSnapshot(
      canOpen: json['can_open'] as bool? ?? false,
      selfService: json['self_service'] as bool? ?? false,
      reason: json['reason'] as String?,
      sessionId: shift?['id'] as String?,
      templateName: shift?['template_name'] as String?,
      duty: duty == null ? null : DutyRecord.fromJson(duty),
      nozzles: nozzles.map((item) => AssignedNozzle.fromJson(item as Map<String, dynamic>)).toList(),
      shifts: shifts.map((item) => ClaimableShift.fromJson(item as Map<String, dynamic>)).toList(),
      identityName: identity?['full_name'] as String? ?? '',
    );
  }
}

class ShiftRepository {
  ShiftRepository(this._dio);

  final Dio _dio;

  Future<AssignmentSnapshot> fetchAssignment() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/me/assignment');
      return AssignmentSnapshot.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<PagedList<DutyRecord>> fetchMine({int page = 1, int pageSize = 10}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/me/duties',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return PagedList.fromJson(response.data as Map<String, dynamic>, DutyRecord.fromJson);
    });
  }

  Future<DutyRecord> openDuty({
    String? sessionId,
    String? templateId,
    required List<AssignedNozzle> nozzles,
  }) {
    return _guard(() async {
      final response = await _dio.post(
        '/api/v1/duties/open',
        data: {
          if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
          if (templateId != null && templateId.isNotEmpty) 'template_id': templateId,
          'nozzles': [
            for (final nozzle in nozzles)
              {'nozzle_id': nozzle.id, 'opening_meter': nozzle.currentMeter},
          ],
        },
      );
      return DutyRecord.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<DutyRecord> closeDuty({
    required String dutyId,
    required List<Map<String, String>> lines,
    required String cash,
  }) {
    return _guard(() async {
      final response = await _dio.post(
        '/api/v1/duties/$dutyId/close',
        data: {'lines': lines, 'cash_handed': cash},
      );
      return DutyRecord.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<PagedList<DutyRecord>> fetchDutiesByDate(String date, {int page = 1, int pageSize = 10}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/duties/by-date',
        queryParameters: {'date': date, 'page': page, 'page_size': pageSize},
      );
      return PagedList.fromJson(response.data as Map<String, dynamic>, DutyRecord.fromJson);
    });
  }

  Future<PagedList<DutyRecord>> fetchSessionDuties(String sessionId, {int page = 1, int pageSize = 10}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/sessions/$sessionId/duties',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return PagedList.fromJson(response.data as Map<String, dynamic>, DutyRecord.fromJson);
    });
  }

  Future<void> approve(String dutyId) {
    return _guard(() async {
      await _dio.post('/api/v1/duties/$dutyId/approve');
    });
  }

  Future<void> reject(String dutyId, String reason) {
    return _guard(() async {
      await _dio.post('/api/v1/duties/$dutyId/reject', data: {'reason': reason});
    });
  }

  List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
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
