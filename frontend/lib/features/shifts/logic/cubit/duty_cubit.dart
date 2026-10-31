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
    this.historyExpanded = false,
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
  final bool historyExpanded;

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
    bool? historyExpanded,
  }) {
    return DutyState(
      loaded: loaded ?? this.loaded,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
      reason: clearReason ? reason : reason ?? this.reason,
      canOpen: canOpen ?? this.canOpen,
      sessionId: sessionId ?? this.sessionId,
      templateName: templateName ?? this.templateName,
      duty: clearDuty ? null : duty ?? this.duty,
      nozzles: nozzles ?? this.nozzles,
      history: history ?? this.history,
      historyExpanded: historyExpanded ?? this.historyExpanded,
    );
  }
}

class DutyCubit extends Cubit<DutyState> {
  DutyCubit(this._repository, {DutyState? initial}) : super(initial ?? const DutyState());

  final ShiftRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(busy: state.duty == null && !state.loaded, clearError: true));
    try {
      final assignment = await _repository.fetchAssignment();
      final history = await _repository.fetchMine();
      emit(
        state.copyWith(
          loaded: true,
          busy: false,
          clearReason: true,
          reason: assignment.reason,
          canOpen: assignment.canOpen,
          sessionId: assignment.sessionId,
          templateName: assignment.templateName,
          duty: assignment.duty,
          clearDuty: assignment.duty == null,
          nozzles: assignment.nozzles,
          history: history,
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loaded: true, busy: false, error: error.message));
    }
  }

  Future<bool> openAssigned() async {
    final sessionId = state.sessionId;
    final nozzles = state.nozzles.where((item) => item.selectable).toList();
    if (sessionId == null || nozzles.isEmpty) {
      emit(state.copyWith(error: state.reason ?? 'لا يمكن فتح الوردية.'));
      return false;
    }
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repository.openDuty(sessionId: sessionId, nozzles: nozzles);
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

  void showHistory() => emit(state.copyWith(historyExpanded: true));
}
