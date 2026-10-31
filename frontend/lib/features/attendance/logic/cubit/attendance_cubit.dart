import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';

class AttendanceState {
  const AttendanceState({
    this.loading = false,
    this.error,
    this.date = '',
    this.sessionId,
    this.templateId,
    this.templates = const [],
    this.users = const [],
    this.nozzles = const [],
    this.rows = const [],
    this.summary,
  });

  final bool loading;
  final String? error;
  final String date;
  final String? sessionId;
  final String? templateId;
  final List<AttendanceTemplateOption> templates;
  final List<AttendanceUserOption> users;
  final List<AttendanceNozzleOption> nozzles;
  final List<AttendanceRow> rows;
  final AttendanceSummary? summary;

  AttendanceState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    String? date,
    String? sessionId,
    String? templateId,
    List<AttendanceTemplateOption>? templates,
    List<AttendanceUserOption>? users,
    List<AttendanceNozzleOption>? nozzles,
    List<AttendanceRow>? rows,
    AttendanceSummary? summary,
  }) {
    return AttendanceState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      date: date ?? this.date,
      sessionId: sessionId ?? this.sessionId,
      templateId: templateId ?? this.templateId,
      templates: templates ?? this.templates,
      users: users ?? this.users,
      nozzles: nozzles ?? this.nozzles,
      rows: rows ?? this.rows,
      summary: summary ?? this.summary,
    );
  }
}

class AttendanceCubit extends Cubit<AttendanceState> {
  AttendanceCubit(this._repository, {AttendanceState? initial}) : super(initial ?? const AttendanceState());

  final AttendanceRepository _repository;

  Future<void> load({String? date, String? templateId}) async {
    final day = date ?? state.date;
    emit(state.copyWith(loading: state.summary == null, clearError: true, date: day));
    try {
      final options = await _repository.fetchOptions();
      final chosen = templateId ??
          state.templateId ??
          _morningTemplate(options.templates)?.id ??
          (options.templates.isEmpty ? null : options.templates.first.id);
      String? sessionId = state.sessionId;
      if (chosen != null && day.isNotEmpty) {
        sessionId = await _repository.openSession(templateId: chosen, date: day);
      }
      final rows = sessionId == null ? const <AttendanceRow>[] : await _repository.fetchAttendance(sessionId);
      final summary = day.isEmpty ? null : await _repository.fetchSummary(day);
      emit(
        state.copyWith(
          loading: false,
          date: day,
          sessionId: sessionId,
          templateId: chosen,
          templates: options.templates,
          users: options.users,
          nozzles: options.nozzles,
          rows: rows,
          summary: summary,
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<bool> register({
    required String userId,
    required List<String> nozzleIds,
    required String? checkIn,
    required String? note,
    required bool absent,
  }) async {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      emit(state.copyWith(error: 'افتح الوردية أولاً.'));
      return false;
    }
    return _mutate(
      () => _repository.register(
        sessionId: sessionId,
        userId: userId,
        nozzleIds: nozzleIds,
        checkIn: checkIn,
        note: note,
        absent: absent,
      ),
    );
  }

  Future<bool> updateRow({
    required String attendanceId,
    required List<String> nozzleIds,
    required String? checkIn,
    required String? checkOut,
    required String? note,
    required bool absent,
  }) {
    return _mutate(
      () => _repository.updateRow(
        attendanceId: attendanceId,
        nozzleIds: nozzleIds,
        checkIn: checkIn,
        checkOut: checkOut,
        note: note,
        absent: absent,
      ),
    );
  }

  AttendanceTemplateOption? _morningTemplate(List<AttendanceTemplateOption> templates) {
    for (final item in templates) {
      if (item.nameAr.contains('صباح')) {
        return item;
      }
    }
    return null;
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    emit(state.copyWith(clearError: true));
    try {
      await action();
      await load();
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
      return false;
    }
  }
}
