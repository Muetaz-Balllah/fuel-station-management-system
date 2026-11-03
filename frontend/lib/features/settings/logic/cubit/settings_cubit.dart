import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';

class SettingsState {
  const SettingsState({
    this.loading = false,
    this.error,
    this.station,
    this.users = const [],
    this.roles = const [],
    this.products = const [],
    this.templates = const [],
    this.userQuery = '',
    this.roleFilter = 'all',
  });

  final bool loading;
  final String? error;
  final StationProfile? station;
  final List<StaffMember> users;
  final List<RoleGrant> roles;
  final List<FuelProductItem> products;
  final List<ShiftTemplateItem> templates;
  final String userQuery;
  final String roleFilter;

  SettingsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    StationProfile? station,
    List<StaffMember>? users,
    List<RoleGrant>? roles,
    List<FuelProductItem>? products,
    List<ShiftTemplateItem>? templates,
    String? userQuery,
    String? roleFilter,
  }) {
    return SettingsState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      station: station ?? this.station,
      users: users ?? this.users,
      roles: roles ?? this.roles,
      products: products ?? this.products,
      templates: templates ?? this.templates,
      userQuery: userQuery ?? this.userQuery,
      roleFilter: roleFilter ?? this.roleFilter,
    );
  }
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository, {SettingsState? initial}) : super(initial ?? const SettingsState());

  final SettingsRepository _repository;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(loading: true, clearError: true));
    }
    try {
      final station = await _repository.fetchStation();
      final users = await _repository.fetchUsers(search: state.userQuery, role: state.roleFilter);
      final roles = await _repository.fetchRoles();
      final products = await _repository.fetchProducts();
      final templates = await _repository.fetchTemplates();
      emit(
        state.copyWith(
          loading: false,
          station: station,
          users: users,
          roles: roles,
          products: products,
          templates: templates,
        ),
      );
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<void> saveStation({
    required String name,
    required String licenseNumber,
    required String licenseExpiresOn,
    required String latitude,
    required String longitude,
  }) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final station = await _repository.saveStation({
        'name': name,
        'license_number': licenseNumber,
        'license_expires_on': licenseExpiresOn,
        'latitude': latitude.trim().isEmpty ? null : double.parse(latitude),
        'longitude': longitude.trim().isEmpty ? null : double.parse(longitude),
      });
      emit(state.copyWith(loading: false, station: station));
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    } on FormatException {
      emit(state.copyWith(loading: false, error: 'الإحداثيات يجب أن تكون أرقاماً.'));
    }
  }

  Future<bool> uploadLogo({required List<int> bytes, required String filename}) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final station = await _repository.uploadLogo(bytes: bytes, filename: filename);
      emit(state.copyWith(loading: false, station: station));
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
      return false;
    }
  }

  Future<void> applyUserFilter({String? search, String? role}) async {
    final query = search ?? state.userQuery;
    final roleFilter = role ?? state.roleFilter;
    emit(state.copyWith(loading: true, clearError: true, userQuery: query, roleFilter: roleFilter));
    try {
      final users = await _repository.fetchUsers(search: query, role: roleFilter);
      emit(state.copyWith(loading: false, users: users));
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<bool> createUser(Map<String, dynamic> body) async {
    return _run(() async {
      await _repository.createUser(body);
      final users = await _repository.fetchUsers(search: state.userQuery, role: state.roleFilter);
      emit(state.copyWith(loading: false, users: users));
    });
  }

  Future<bool> uploadUserPhoto({required String userId, required List<int> bytes, required String filename}) {
    return _run(() async {
      await _repository.uploadUserPhoto(userId: userId, bytes: bytes, filename: filename);
      final users = await _repository.fetchUsers(search: state.userQuery, role: state.roleFilter);
      emit(state.copyWith(loading: false, users: users));
    });
  }

  Future<bool> updateUser(String id, Map<String, dynamic> body) async {
    return _run(() async {
      await _repository.updateUser(id, body);
      final users = await _repository.fetchUsers(search: state.userQuery, role: state.roleFilter);
      emit(state.copyWith(loading: false, users: users));
    });
  }

  Future<void> setPermission(RoleGrant role, String code, bool enabled) async {
    final next = [...role.permissions];
    if (enabled) {
      if (!next.contains(code)) {
        next.add(code);
      }
    } else {
      next.remove(code);
    }
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _repository.replacePermissions(role.id, next);
      final roles = await _repository.fetchRoles();
      emit(state.copyWith(loading: false, roles: roles));
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<void> addPrice(String productId, String price) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _repository.addPrice(productId, price.trim());
      final products = await _repository.fetchProducts();
      emit(state.copyWith(loading: false, products: products));
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
    }
  }

  Future<bool> saveTemplate(ShiftDraft draft, {String? id}) async {
    return _run(() async {
      if (id == null) {
        await _repository.createTemplate(draft);
      } else {
        await _repository.updateTemplate(id, draft);
      }
      final templates = await _repository.fetchTemplates();
      emit(state.copyWith(loading: false, templates: templates));
    });
  }

  Future<String?> deleteTemplate(String id) async {
    emit(state.copyWith(clearError: true));
    try {
      await _repository.deleteTemplate(id);
      final templates = await _repository.fetchTemplates();
      emit(state.copyWith(templates: templates));
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await action();
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(loading: false, error: error.message));
      return false;
    }
  }
}
