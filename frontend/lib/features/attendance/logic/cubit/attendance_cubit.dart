import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';

class AttendanceState {
  const AttendanceState({
    this.loading = false,
    this.error,
    this.date = '',
    this.sessionId,
    this.templateId,
    this.templates = const [],
    this.sessions = const [],
    this.users = const [],
    this.nozzles = const [],
    this.rows = const [],
    this.attendancePage = 1,
    this.attendanceTotal = 0,
    this.sessionDuties = const [],
    this.dutiesPage = 1,
    this.dutiesTotal = 0,
    this.summary,
  });

  final bool loading;
  final String? error;
  final String date;
  final String? sessionId;
  final String? templateId;
  final List<AttendanceTemplateOption> templates;
  final List<AttendanceSessionOption> sessions;
  final List<AttendanceUserOption> users;
  final List<AttendanceNozzleOption> nozzles;
  final List<AttendanceRow> rows;
  final int attendancePage;
  final int attendanceTotal;
  final List<DutyRecord> sessionDuties;
  final int dutiesPage;
  final int dutiesTotal;
  final AttendanceSummary? summary;

  int get attendancePageCount => attendanceTotal <= 0 ? 1 : ((attendanceTotal + 9) ~/ 10);
  int get dutiesPageCount => dutiesTotal <= 0 ? 1 : ((dutiesTotal + 9) ~/ 10);

  AttendanceState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    String? date,
    String? sessionId,
    String? templateId,
    List<AttendanceTemplateOption>? templates,
    List<AttendanceSessionOption>? sessions,
    List<AttendanceUserOption>? users,
    List<AttendanceNozzleOption>? nozzles,
    List<AttendanceRow>? rows,
    int? attendancePage,
    int? attendanceTotal,
    List<DutyRecord>? sessionDuties,
    int? dutiesPage,
    int? dutiesTotal,
    AttendanceSummary? summary,
  }) {
    return AttendanceState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      date: date ?? this.date,
      sessionId: sessionId ?? this.sessionId,
      templateId: templateId ?? this.templateId,
      templates: templates ?? this.templates,
      sessions: sessions ?? this.sessions,
      users: users ?? this.users,
      nozzles: nozzles ?? this.nozzles,
      rows: rows ?? this.rows,
      attendancePage: attendancePage ?? this.attendancePage,
      attendanceTotal: attendanceTotal ?? this.attendanceTotal,
      sessionDuties: sessionDuties ?? this.sessionDuties,
      dutiesPage: dutiesPage ?? this.dutiesPage,
      dutiesTotal: dutiesTotal ?? this.dutiesTotal,
      summary: summary ?? this.summary,
    );
  }
}

class AttendanceCubit extends Cubit<AttendanceState> {
  AttendanceCubit(this._repository, this._shifts, {AttendanceState? initial})
      : super(initial ?? const AttendanceState());

  final AttendanceRepository _repository;
  final ShiftRepository _shifts;

  Future<void> load({
    String? date,
    String? templateId,
    String? sessionId,
    int? attendancePage,
    int? dutiesPage,
    bool silent = false,
  }) async {
    final day = date ?? state.date;
    emit(state.copyWith(loading: !silent && state.summary == null, clearError: true, date: day));
    try {
      final options = await _repository.fetchOptions();
      final daySessions = day.isEmpty ? const <AttendanceSessionOption>[] : await _repository.fetchSessions(day);
      final chosenSession = _pickSession(
        daySessions,
        sessionId: sessionId ?? state.sessionId,
        templateId: templateId ?? state.templateId ?? _morningTemplate(options.templates)?.id,
      );
      String? activeSessionId = chosenSession?.status == 'cancelled' ? null : chosenSession?.id;
      if (activeSessionId == null) {
        for (final item in daySessions) {
          if (item.status != 'cancelled') {
            activeSessionId = item.id;
            break;
          }
        }
      }
      if (activeSessionId == null) {
        final template = templateId ?? state.templateId ?? _morningTemplate(options.templates)?.id;
        if (template != null && day.isNotEmpty) {
          try {
            activeSessionId = await _repository.openSession(templateId: template, date: day);
          } on ApiException {
            activeSessionId = null;
          }
        }
      }
      final attPage = attendancePage ?? state.attendancePage;
      final dutyPage = dutiesPage ?? state.dutiesPage;
      final attendance = activeSessionId == null
          ? null
          : await _repository.fetchAttendance(activeSessionId, page: attPage, pageSize: 10);
      final dutyList = activeSessionId == null
          ? null
          : await _shifts.fetchSessionDuties(activeSessionId, page: dutyPage, pageSize: 10);
      final summary = day.isEmpty ? null : await _repository.fetchSummary(day);
      emit(
        state.copyWith(
          loading: false,
          date: day,
          sessionId: activeSessionId,
          templateId: chosenSession?.templateId ?? templateId ?? state.templateId,
          templates: options.templates,
          sessions: daySessions,
          users: options.users,
          nozzles: options.nozzles,
          rows: attendance?.items ?? const [],
          attendancePage: attendance?.page ?? 1,
          attendanceTotal: attendance?.total ?? 0,
          sessionDuties: dutyList?.items ?? const [],
          dutiesPage: dutyList?.page ?? 1,
          dutiesTotal: dutyList?.total ?? 0,
          summary: summary,
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<void> selectSession(String sessionId) => load(sessionId: sessionId, attendancePage: 1, dutiesPage: 1, silent: true);

  Future<void> setAttendancePage(int page) => load(attendancePage: page, silent: true);

  Future<void> setDutiesPage(int page) => load(dutiesPage: page, silent: true);

  Future<String?> approveDuty(String dutyId) => _dutyAction(() => _shifts.approve(dutyId));

  Future<String?> rejectDuty(String dutyId, String reason) => _dutyAction(() => _shifts.reject(dutyId, reason));

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

  AttendanceSessionOption? _pickSession(
    List<AttendanceSessionOption> sessions, {
    String? sessionId,
    String? templateId,
  }) {
    if (sessionId != null) {
      for (final item in sessions) {
        if (item.id == sessionId) {
          return item;
        }
      }
    }
    if (templateId != null) {
      for (final item in sessions) {
        if (item.templateId == templateId) {
          return item;
        }
      }
    }
    for (final item in sessions) {
      if (item.status != 'cancelled') {
        return item;
      }
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  AttendanceTemplateOption? _morningTemplate(List<AttendanceTemplateOption> templates) {
    for (final item in templates) {
      if (item.nameAr.contains('صباح')) {
        return item;
      }
    }
    return templates.isEmpty ? null : templates.first;
  }

  Future<String?> _dutyAction(Future<void> Function() action) async {
    emit(state.copyWith(clearError: true));
    try {
      await action();
      await load(silent: true);
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    emit(state.copyWith(clearError: true));
    try {
      await action();
      await load(silent: true);
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
      return false;
    }
  }
}
