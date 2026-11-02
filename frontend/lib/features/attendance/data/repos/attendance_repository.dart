import 'package:dio/dio.dart';
import 'package:frontend/core/models/paged_list.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';

class AttendanceOptions {
  const AttendanceOptions({required this.templates, required this.users, required this.nozzles});

  final List<AttendanceTemplateOption> templates;
  final List<AttendanceUserOption> users;
  final List<AttendanceNozzleOption> nozzles;
}

class AttendanceRepository {
  AttendanceRepository(this._dio);

  final Dio _dio;

  Future<AttendanceOptions> fetchOptions() {
    return _guard(() async {
      final response = await _dio.get('/api/v1/attendance/options');
      final body = response.data as Map<String, dynamic>;
      return AttendanceOptions(
        templates: _list(body['templates'], AttendanceTemplateOption.fromJson),
        users: _list(body['users'], AttendanceUserOption.fromJson),
        nozzles: _list(body['nozzles'], AttendanceNozzleOption.fromJson),
      );
    });
  }

  Future<List<AttendanceSessionOption>> fetchSessions(String date) {
    return _guard(() async {
      final response = await _dio.get('/api/v1/sessions', queryParameters: {'date': date});
      return _list((response.data as Map<String, dynamic>)['items'], AttendanceSessionOption.fromJson);
    });
  }

  Future<List<ShiftScheduleDay>> fetchSchedule({required String dateFrom, required String dateTo}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/sessions/schedule',
        queryParameters: {'date_from': dateFrom, 'date_to': dateTo},
      );
      return _list((response.data as Map<String, dynamic>)['days'], ShiftScheduleDay.fromJson);
    });
  }

  Future<void> setSessionAvailability({
    required String templateId,
    required String businessDate,
    required bool active,
  }) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/sessions/availability',
        data: {'template_id': templateId, 'business_date': businessDate, 'active': active},
      );
    });
  }

  Future<String> openSession({required String templateId, required String date}) {
    return _guard(() async {
      final response = await _dio.post(
        '/api/v1/sessions',
        data: {'template_id': templateId, 'business_date': date},
      );
      return (response.data as Map<String, dynamic>)['id'] as String;
    });
  }

  Future<PagedList<AttendanceRow>> fetchAttendance(String sessionId, {int page = 1, int pageSize = 10}) {
    return _guard(() async {
      final response = await _dio.get(
        '/api/v1/sessions/$sessionId/attendance',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return PagedList.fromJson(response.data as Map<String, dynamic>, AttendanceRow.fromJson);
    });
  }

  Future<AttendanceSummary> fetchSummary(String date) {
    return _guard(() async {
      final response = await _dio.get('/api/v1/attendance/summary', queryParameters: {'date': date});
      return AttendanceSummary.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<void> register({
    required String sessionId,
    required String userId,
    required List<String> nozzleIds,
    required String? checkIn,
    required String? note,
    required bool absent,
  }) {
    return _guard(() async {
      await _dio.post(
        '/api/v1/sessions/$sessionId/attendance',
        data: {
          'user_id': userId,
          'nozzle_ids': nozzleIds,
          'check_in_at': checkIn,
          'note': note,
          if (absent) 'status': 'absent',
        },
      );
    });
  }

  Future<void> updateRow({
    required String attendanceId,
    required List<String> nozzleIds,
    required String? checkIn,
    required String? checkOut,
    required String? note,
    required bool absent,
  }) {
    return _guard(() async {
      await _dio.patch(
        '/api/v1/attendances/$attendanceId',
        data: {
          'nozzle_ids': absent ? <String>[] : nozzleIds,
          'check_in_at': absent ? null : checkIn,
          'check_out_at': checkOut,
          'note': note,
          if (absent) 'status': 'absent',
        },
      );
    });
  }

  List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
    final items = raw as List<dynamic>? ?? const [];
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
