import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/supply/data/models/supply_models.dart';
import 'package:frontend/features/supply/data/repos/supply_repository.dart';

class SupplyState {
  const SupplyState({
    this.loaded = false,
    this.error,
    this.deliveredLiters = '0.000',
    this.activeOrders = 0,
    this.pendingOrders = 0,
    this.activeSuppliers = 0,
    this.week = const [],
    this.suppliers = const [],
    this.orders = const [],
    this.products = const [],
    this.tanks = const [],
    this.selectedSupplierId,
  });

  final bool loaded;
  final String? error;
  final String deliveredLiters;
  final int activeOrders;
  final int pendingOrders;
  final int activeSuppliers;
  final List<SupplyWeekDay> week;
  final List<SupplierRecord> suppliers;
  final List<SupplyOrderRecord> orders;
  final List<SupplyProductOption> products;
  final List<SupplyTankOption> tanks;
  final String? selectedSupplierId;

  SupplyState copyWith({
    bool? loaded,
    String? error,
    bool clearError = false,
    String? deliveredLiters,
    int? activeOrders,
    int? pendingOrders,
    int? activeSuppliers,
    List<SupplyWeekDay>? week,
    List<SupplierRecord>? suppliers,
    List<SupplyOrderRecord>? orders,
    List<SupplyProductOption>? products,
    List<SupplyTankOption>? tanks,
    String? selectedSupplierId,
  }) {
    return SupplyState(
      loaded: loaded ?? this.loaded,
      error: clearError ? null : error ?? this.error,
      deliveredLiters: deliveredLiters ?? this.deliveredLiters,
      activeOrders: activeOrders ?? this.activeOrders,
      pendingOrders: pendingOrders ?? this.pendingOrders,
      activeSuppliers: activeSuppliers ?? this.activeSuppliers,
      week: week ?? this.week,
      suppliers: suppliers ?? this.suppliers,
      orders: orders ?? this.orders,
      products: products ?? this.products,
      tanks: tanks ?? this.tanks,
      selectedSupplierId: selectedSupplierId ?? this.selectedSupplierId,
    );
  }
}

class SupplyCubit extends Cubit<SupplyState> {
  SupplyCubit(this._repository, {SupplyState? initial}) : super(initial ?? const SupplyState());

  final SupplyRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(clearError: true));
    try {
      final summary = await _repository.fetchSummary();
      final suppliers = await _repository.fetchSuppliers();
      final orders = await _repository.fetchOrders();
      final products = await _repository.fetchProducts();
      final tanks = await _repository.fetchTanks();
      emit(
        state.copyWith(
          loaded: true,
          deliveredLiters: summary.deliveredLiters,
          activeOrders: summary.activeOrders,
          pendingOrders: summary.pendingOrders,
          activeSuppliers: summary.activeSuppliers,
          week: summary.week,
          suppliers: suppliers,
          orders: orders,
          products: products,
          tanks: tanks,
          selectedSupplierId: state.selectedSupplierId ?? (suppliers.isEmpty ? null : suppliers.first.id),
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loaded: true, error: error.message));
    }
  }

  void selectSupplier(String id) => emit(state.copyWith(selectedSupplierId: id));

  Future<bool> createOrder({
    required String supplierId,
    required String tankId,
    required String productId,
    required String liters,
    required String expectedOn,
    required String notes,
  }) {
    return _mutate(
      () => _repository.createOrder(
        supplierId: supplierId,
        tankId: tankId,
        productId: productId,
        liters: liters,
        expectedOn: expectedOn,
        notes: notes,
      ),
    );
  }

  Future<bool> receive(String orderId) => _mutate(() => _repository.receive(orderId));

  Future<bool> cancel(String orderId) => _mutate(() => _repository.cancel(orderId));

  Future<bool> updateSupplier({
    required String id,
    required String headquarters,
    required String contactName,
    required String phone,
    required String maxDailyLiters,
  }) {
    return _mutate(
      () => _repository.updateSupplier(
        id: id,
        headquarters: headquarters,
        contactName: contactName,
        phone: phone,
        maxDailyLiters: maxDailyLiters,
      ),
    );
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    emit(state.copyWith(clearError: true));
    try {
      await action();
      await load();
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(error: error.message));
      return false;
    }
  }
}
