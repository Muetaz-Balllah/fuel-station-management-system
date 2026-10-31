import 'package:dio/dio.dart';
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
  });

  final bool canOpen;
  final String? reason;
  final String? sessionId;
  final String? templateName;
  final DutyRecord? duty;
  final List<AssignedNozzle> nozzles;

  factory AssignmentSnapshot.fromJson(Map<String, dynamic> json) {
    final shift = json['session'] as Map<String, dynamic>?;
    final duty = json['duty'] as Map<String, dynamic>?;
    final nozzles = json['nozzles'] as List<dynamic>? ?? const [];
    return AssignmentSnapshot(
      canOpen: json['can_open'] as bool? ?? false,
      reason: json['reason'] as String?,
      sessionId: shift?['id'] as String?,
      templateName: shift?['template_name'] as String?,
      duty: duty == null ? null : DutyRecord.fromJson(duty),
      nozzles: nozzles.map((item) => AssignedNozzle.fromJson(item as Map<String, dynamic>)).toList(),
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

  Future<List<DutyRecord>> fetchMine() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/me/duties');
      return _list(response.data, DutyRecord.fromJson);
    });
  }

  Future<DutyRecord> openDuty({
    required String sessionId,
    required List<AssignedNozzle> nozzles,
  }) {
    return _guard(() async {
      final response = await _dio.post(
        '/api/v1/duties/open',
        data: {
          'session_id': sessionId,
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

  Future<List<ShiftLogRow>> fetchLog() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/shift-log');
      return _list(response.data, ShiftLogRow.fromJson);
    });
  }

  Future<List<DutyRecord>> fetchSessionDuties(String sessionId) {
    return _guard(() async {
      final response = await _dio.get('/api/v1/sessions/$sessionId/duties');
      return _list(response.data, DutyRecord.fromJson);
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
