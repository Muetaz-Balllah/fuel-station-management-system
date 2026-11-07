import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/assets/data/models/asset_models.dart';
import 'package:frontend/features/assets/data/repos/assets_repository.dart';

class AssetsState {
  const AssetsState({
    this.loading = false,
    this.error,
    this.board,
    this.events = const [],
    this.eventTotal = 0,
    this.productFilter = '',
    this.eventOffset = 0,
  });

  static const pageSize = 8;

  final bool loading;
  final String? error;
  final AssetBoard? board;
  final List<InventoryEvent> events;
  final int eventTotal;
  final String productFilter;
  final int eventOffset;

  AssetsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    AssetBoard? board,
    List<InventoryEvent>? events,
    int? eventTotal,
    String? productFilter,
    int? eventOffset,
  }) {
    return AssetsState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      board: board ?? this.board,
      events: events ?? this.events,
      eventTotal: eventTotal ?? this.eventTotal,
      productFilter: productFilter ?? this.productFilter,
      eventOffset: eventOffset ?? this.eventOffset,
    );
  }
}

class AssetsCubit extends Cubit<AssetsState> {
  AssetsCubit(this._repository, {AssetsState? initial}) : super(initial ?? const AssetsState());

  final AssetsRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(loading: state.board == null, clearError: true));
    try {
      final board = await _repository.fetchBoard();
      final events = await _repository.fetchEvents(
        productId: state.productFilter,
        offset: state.eventOffset,
      );
      emit(
        state.copyWith(
          loading: false,
          board: board,
          events: events.items,
          eventTotal: events.total,
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<void> filterEvents(String productId) async {
    emit(state.copyWith(productFilter: productId, eventOffset: 0, clearError: true));
    await _reloadEvents();
  }

  Future<void> changePage(int offset) async {
    emit(state.copyWith(eventOffset: offset, clearError: true));
    await _reloadEvents();
  }

  Future<bool> createTank({
    required String name,
    required String productId,
    required String capacity,
  }) {
    return _mutate(() => _repository.createTank(name: name, productId: productId, capacityLiters: capacity));
  }

  Future<bool> createPump({required String code, required String tankId}) {
    return _mutate(() => _repository.createPump(code: code, tankId: tankId));
  }

  Future<bool> setPumpStatus({required String pumpId, required String status}) {
    return _mutate(() => _repository.updatePumpStatus(pumpId: pumpId, status: status));
  }

  Future<bool> createNozzle({
    required String pumpId,
    required String code,
    required String label,
    required String meter,
    required String status,
  }) {
    return _mutate(
      () => _repository.createNozzle(
        pumpId: pumpId,
        code: code,
        label: label,
        initialMeter: meter,
        status: status,
      ),
    );
  }

  Future<bool> adjust({required String tankId, required String delta, required String note}) {
    return _mutate(() => _repository.adjustTank(tankId: tankId, litersDelta: delta, note: note));
  }

  Future<bool> deleteTank(String tankId) => _mutate(() => _repository.deleteTank(tankId));

  Future<bool> deletePump(String pumpId) => _mutate(() => _repository.deletePump(pumpId));

  Future<bool> deleteNozzle(String nozzleId) => _mutate(() => _repository.deleteNozzle(nozzleId));

  Future<bool> adjustNozzleMeter({
    required String nozzleId,
    required String meter,
    required String reason,
  }) {
    return _mutate(() => _repository.adjustNozzleMeter(nozzleId: nozzleId, meter: meter, reason: reason));
  }

  Future<bool> setNozzleStatus({required String nozzleId, required String status}) {
    return _mutate(() => _repository.updateNozzleStatus(nozzleId: nozzleId, status: status));
  }

  Future<void> _reloadEvents() async {
    try {
      final events = await _repository.fetchEvents(
        productId: state.productFilter,
        offset: state.eventOffset,
      );
      emit(state.copyWith(loading: false, events: events.items, eventTotal: events.total));
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
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
