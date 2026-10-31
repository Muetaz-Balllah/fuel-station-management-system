import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';

class ShiftLogState {
  const ShiftLogState({
    this.loaded = false,
    this.error,
    this.rows = const [],
    this.selectedId,
    this.duties = const [],
  });

  final bool loaded;
  final String? error;
  final List<ShiftLogRow> rows;
  final String? selectedId;
  final List<DutyRecord> duties;

  ShiftLogState copyWith({
    bool? loaded,
    String? error,
    bool clearError = false,
    List<ShiftLogRow>? rows,
    String? selectedId,
    List<DutyRecord>? duties,
  }) {
    return ShiftLogState(
      loaded: loaded ?? this.loaded,
      error: clearError ? null : error ?? this.error,
      rows: rows ?? this.rows,
      selectedId: selectedId ?? this.selectedId,
      duties: duties ?? this.duties,
    );
  }
}

class ShiftLogCubit extends Cubit<ShiftLogState> {
  ShiftLogCubit(this._repository, {ShiftLogState? initial}) : super(initial ?? const ShiftLogState());

  final ShiftRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(clearError: true));
    try {
      final rows = await _repository.fetchLog();
      emit(state.copyWith(loaded: true, rows: rows));
    } on ApiException catch (error) {
      emit(state.copyWith(loaded: true, error: error.message));
    }
  }

  Future<void> select(String sessionId) async {
    emit(state.copyWith(selectedId: sessionId, clearError: true));
    try {
      final duties = await _repository.fetchSessionDuties(sessionId);
      emit(state.copyWith(duties: duties));
    } on ApiException catch (error) {
      emit(state.copyWith(error: error.message));
    }
  }

  Future<bool> approve(String dutyId) => _act(() => _repository.approve(dutyId));

  Future<bool> reject(String dutyId, String reason) => _act(() => _repository.reject(dutyId, reason));

  Future<bool> _act(Future<void> Function() action) async {
    final selected = state.selectedId;
    emit(state.copyWith(clearError: true));
    try {
      await action();
      await load();
      if (selected != null) {
        await select(selected);
      }
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(error: error.message));
      return false;
    }
  }
}
