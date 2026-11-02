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

  void showDesignPreview() {
    emit(
      const DashboardState(
        loaded: true,
        date: '2024-05-24',
        revenue: '18450.00',
        liters: '12300.000',
        inventoryLiters: '128400.000',
        staffOnDuty: 12,
        alert: DashboardAlert(
          tankName: 'خزان بنزين 95',
          productName: 'بنزين 95',
          percent: 15,
          message: 'المستوى حرج: أقل من 15%',
        ),
        week: [
          DashboardWeekDay(date: '2024-05-19', label: 'الأحد', morning: '12000.00', evening: '8000.00'),
          DashboardWeekDay(date: '2024-05-20', label: 'الاثنين', morning: '15000.00', evening: '9000.00'),
          DashboardWeekDay(date: '2024-05-21', label: 'الثلاثاء', morning: '9000.00', evening: '6000.00'),
          DashboardWeekDay(date: '2024-05-22', label: 'الأربعاء', morning: '18000.00', evening: '11000.00'),
          DashboardWeekDay(date: '2024-05-23', label: 'الخميس', morning: '16000.00', evening: '10000.00'),
          DashboardWeekDay(date: '2024-05-24', label: 'الجمعة', morning: '11000.00', evening: '7000.00'),
          DashboardWeekDay(date: '2024-05-25', label: 'السبت', morning: '14000.00', evening: '8500.00'),
        ],
        tanks: [
          DashboardTank(name: 'الخزان 1', productName: 'بنزين 95', percent: 15, currentLiters: '12500.000', capacityLiters: '80000.000'),
          DashboardTank(name: 'الخزان 2', productName: 'ديزل', percent: 67, currentLiters: '54000.000', capacityLiters: '80000.000'),
          DashboardTank(name: 'الخزان 3', productName: 'بنزين 98', percent: 84, currentLiters: '42000.000', capacityLiters: '50000.000'),
          DashboardTank(name: 'الخزان 4', productName: 'ديزل شاحنات', percent: 20, currentLiters: '19900.000', capacityLiters: '100000.000'),
        ],
        sessions: [
          ShiftLogRow(
            id: 'preview-104',
            code: 'SH-2024-104',
            businessDate: '2024-05-24',
            window: 'الوردية 1 (08:00 - 16:00)',
            supervisor: 'أحمد الترهوني',
            statusLabel: 'جارية الآن',
            liters: '12300.000',
            revenue: '18450.00',
            varianceLabel: '0.00 د.ل (مطابق)',
          ),
          ShiftLogRow(
            id: 'preview-103',
            code: 'SH-2024-103',
            businessDate: '2024-05-23',
            window: 'الوردية 2 (16:00 - 00:00)',
            supervisor: 'سالم الشريف',
            statusLabel: 'معتمدة ومغلقة',
            liters: '15420.000',
            revenue: '23130.00',
            varianceLabel: '+15.00 د.ل (فائض)',
          ),
          ShiftLogRow(
            id: 'preview-102',
            code: 'SH-2024-102',
            businessDate: '2024-05-23',
            window: 'الوردية 1 (08:00 - 16:00)',
            supervisor: 'طارق الورفلي',
            statusLabel: 'معتمدة ومغلقة',
            liters: '11800.000',
            revenue: '17700.00',
            varianceLabel: '-25.00 د.ل (عجز)',
          ),
        ],
      ),
    );
  }

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
