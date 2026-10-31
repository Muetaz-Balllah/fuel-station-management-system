import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';

class DashboardState {
  const DashboardState({
    this.loaded = false,
    this.error,
    this.date = '',
    this.revenue = '0.00',
    this.liters = '0.000',
    this.inventoryLiters = '0.000',
    this.staffOnDuty = 0,
    this.alert,
    this.week = const [],
    this.tanks = const [],
    this.sessions = const [],
  });

  final bool loaded;
  final String? error;
  final String date;
  final String revenue;
  final String liters;
  final String inventoryLiters;
  final int staffOnDuty;
  final DashboardAlert? alert;
  final List<DashboardWeekDay> week;
  final List<DashboardTank> tanks;
  final List<ShiftLogRow> sessions;

  DashboardState copyWith({
    bool? loaded,
    String? error,
    bool clearError = false,
    String? date,
    String? revenue,
    String? liters,
    String? inventoryLiters,
    int? staffOnDuty,
    DashboardAlert? alert,
    bool clearAlert = false,
    List<DashboardWeekDay>? week,
    List<DashboardTank>? tanks,
    List<ShiftLogRow>? sessions,
  }) {
    return DashboardState(
      loaded: loaded ?? this.loaded,
      error: clearError ? null : error ?? this.error,
      date: date ?? this.date,
      revenue: revenue ?? this.revenue,
      liters: liters ?? this.liters,
      inventoryLiters: inventoryLiters ?? this.inventoryLiters,
      staffOnDuty: staffOnDuty ?? this.staffOnDuty,
      alert: clearAlert ? null : alert ?? this.alert,
      week: week ?? this.week,
      tanks: tanks ?? this.tanks,
      sessions: sessions ?? this.sessions,
    );
  }
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repository, {DashboardState? initial}) : super(initial ?? const DashboardState());

  final DashboardRepository _repository;

  Future<void> load({String? date}) async {
    emit(state.copyWith(clearError: true));
    try {
      final snapshot = await _repository.fetch(date: date ?? (state.date.isEmpty ? null : state.date));
      emit(_from(snapshot));
    } on ApiException catch (error) {
      emit(state.copyWith(loaded: false, error: error.message));
    }
  }

  DashboardState _from(DashboardSnapshot snapshot) {
    return DashboardState(
      loaded: true,
      date: snapshot.date,
      revenue: snapshot.revenue,
      liters: snapshot.liters,
      inventoryLiters: snapshot.inventoryLiters,
      staffOnDuty: snapshot.staffOnDuty,
      alert: snapshot.alert,
      week: snapshot.week,
      tanks: snapshot.tanks,
      sessions: snapshot.sessions,
    );
  }
}
