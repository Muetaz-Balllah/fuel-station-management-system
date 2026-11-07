import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';

class DutyState {
  const DutyState({
    this.loaded = false,
    this.busy = false,
    this.error,
    this.reason,
    this.canOpen = false,
    this.sessionId,
    this.templateName,
    this.duty,
    this.nozzles = const [],
    this.history = const [],
    this.historyPage = 1,
    this.historyTotal = 0,
    this.historyPageSize = 10,
    this.selfService = false,
    this.shifts = const [],
    this.identityName = '',
  });

  final bool loaded;
  final bool busy;
  final String? error;
  final String? reason;
  final bool canOpen;
  final String? sessionId;
  final String? templateName;
  final DutyRecord? duty;
  final List<AssignedNozzle> nozzles;
  final List<DutyRecord> history;
  final int historyPage;
  final int historyTotal;
  final int historyPageSize;
  final bool selfService;
  final List<ClaimableShift> shifts;
  final String identityName;

  int get historyPageCount {
    if (historyPageSize <= 0) {
      return 1;
    }
    return (historyTotal + historyPageSize - 1) ~/ historyPageSize;
  }

  DutyState copyWith({
    bool? loaded,
    bool? busy,
    String? error,
    bool clearError = false,
    String? reason,
    bool clearReason = false,
    bool? canOpen,
    String? sessionId,
    String? templateName,
    DutyRecord? duty,
    bool clearDuty = false,
    List<AssignedNozzle>? nozzles,
    List<DutyRecord>? history,
    int? historyPage,
    int? historyTotal,
    int? historyPageSize,
    bool? selfService,
    List<ClaimableShift>? shifts,
    String? identityName,
    bool clearSession = false,
  }) {
    return DutyState(
      loaded: loaded ?? this.loaded,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
      reason: clearReason ? reason : reason ?? this.reason,
      canOpen: canOpen ?? this.canOpen,
      sessionId: clearSession ? sessionId : sessionId ?? this.sessionId,
      templateName: templateName ?? this.templateName,
      duty: clearDuty ? null : duty ?? this.duty,
      nozzles: nozzles ?? this.nozzles,
      history: history ?? this.history,
      historyPage: historyPage ?? this.historyPage,
      historyTotal: historyTotal ?? this.historyTotal,
      historyPageSize: historyPageSize ?? this.historyPageSize,
      selfService: selfService ?? this.selfService,
      shifts: shifts ?? this.shifts,
      identityName: identityName ?? this.identityName,
    );
  }
}

class DutyCubit extends Cubit<DutyState> {
  DutyCubit(this._repository, {DutyState? initial}) : super(initial ?? const DutyState());

  final ShiftRepository _repository;

  Future<void> load({int? historyPage}) async {
    final page = historyPage ?? state.historyPage;
    emit(state.copyWith(busy: state.duty == null && !state.loaded, clearError: true));
    try {
      final assignment = await _repository.fetchAssignment();
      final history = await _repository.fetchMine(page: page, pageSize: state.historyPageSize);
      emit(
        state.copyWith(
          loaded: true,
          busy: false,
          clearReason: true,
          reason: assignment.reason,
          canOpen: assignment.canOpen,
          clearSession: true,
          sessionId: assignment.sessionId,
          templateName: assignment.templateName,
          duty: assignment.duty,
          clearDuty: assignment.duty == null,
          nozzles: assignment.nozzles,
          history: history.items,
          historyPage: history.page,
          historyTotal: history.total,
          historyPageSize: history.pageSize,
          selfService: assignment.selfService,
          shifts: assignment.shifts,
          identityName: assignment.identityName,
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loaded: true, busy: false, error: error.message));
    }
  }

  Future<void> loadHistoryPage(int page) => load(historyPage: page);

  Future<bool> openClaim({
    String? sessionId,
    String? templateId,
    required List<AssignedNozzle> nozzles,
    String? meterReason,
  }) {
    if (nozzles.isEmpty || ((sessionId == null || sessionId.isEmpty) && (templateId == null || templateId.isEmpty))) {
      emit(state.copyWith(error: 'اختر الوردية والمضخات التي ستتسلمها.'));
      return Future.value(false);
    }
    return _open(sessionId: sessionId, templateId: templateId, nozzles: nozzles, meterReason: meterReason);
  }

  Future<bool> adjustMeters({
    required String dutyId,
    required String reason,
    required List<Map<String, String>> lines,
  }) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repository.adjustMeters(dutyId: dutyId, reason: reason, lines: lines);
      await load();
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(busy: false, error: error.message));
      return false;
    }
  }

  Future<bool> _open({
    String? sessionId,
    String? templateId,
    required List<AssignedNozzle> nozzles,
    String? meterReason,
  }) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repository.openDuty(
        sessionId: sessionId,
        templateId: templateId,
        nozzles: nozzles,
        meterReason: meterReason,
      );
      await load();
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(busy: false, error: error.message));
      return false;
    }
  }

  Future<DutyRecord?> submitClose({required List<Map<String, String>> lines, required String cash}) async {
    final duty = state.duty;
    if (duty == null) {
      return null;
    }
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final saved = await _repository.closeDuty(dutyId: duty.id, lines: lines, cash: cash);
      await load();
      return saved;
    } on ApiException catch (error) {
      emit(state.copyWith(busy: false, error: error.message));
      return null;
    }
  }
}
