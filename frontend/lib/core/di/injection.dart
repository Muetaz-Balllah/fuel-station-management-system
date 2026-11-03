import 'package:dio/dio.dart';
import 'package:frontend/core/networking/api_client.dart';
import 'package:frontend/core/time/system_clock.dart';
import 'package:frontend/features/assets/data/repos/assets_repository.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';
import 'package:frontend/features/dashboard/logic/cubit/notification_cubit.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';
import 'package:frontend/features/auth/data/apis/auth_api.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/data/repos/token_store.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';
import 'package:frontend/features/supply/data/repos/supply_repository.dart';
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  final tokens = SessionTokens();
  final store = TokenStore();
  final dio = buildDio(
    tokens: tokens,
    store: store,
    onSessionExpired: () {
      if (getIt.isRegistered<SessionCubit>()) {
        getIt<SessionCubit>().signedOut(localOnly: true);
      }
    },
  );
  getIt.registerSingleton<SessionTokens>(tokens);
  getIt.registerSingleton<TokenStore>(store);
  getIt.registerSingleton<Dio>(dio);
  getIt.registerSingleton<AuthApi>(AuthApi(dio));
  getIt.registerSingleton<AuthGateway>(
    AuthRepository(api: getIt(), store: store, tokens: tokens),
  );
  getIt.registerSingleton<SettingsRepository>(SettingsRepository(dio));
  getIt.registerSingleton<AssetsRepository>(AssetsRepository(dio));
  getIt.registerSingleton<AttendanceRepository>(AttendanceRepository(dio));
  getIt.registerSingleton<ShiftRepository>(ShiftRepository(dio));
  getIt.registerSingleton<SupplyRepository>(SupplyRepository(dio));
  getIt.registerSingleton<DashboardRepository>(DashboardRepository(dio));
  getIt.registerSingleton<NotificationCubit>(NotificationCubit(getIt()));
  getIt.registerSingleton<SessionCubit>(SessionCubit(getIt()));
  await getIt<SessionCubit>().restore();
  if (tokens.access != null && tokens.access!.isNotEmpty) {
    try {
      await SystemClock.sync(dio);
    } catch (_) {
      // Offline startup; attendance will retry sync on load.
    }
  }
}
