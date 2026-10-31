import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/widgets/manager_shell.dart';
import 'package:frontend/core/widgets/operator_shell.dart';
import 'package:frontend/core/widgets/splash_screen.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/dashboard/logic/cubit/notification_cubit.dart';
import 'package:frontend/features/dashboard/ui/dashboard_screen.dart';
import 'package:frontend/features/assets/ui/assets_screen.dart';
import 'package:frontend/features/attendance/ui/attendance_screen.dart';
import 'package:frontend/features/auth/ui/login_screen.dart';
import 'package:frontend/features/settings/ui/settings_screen.dart';
import 'package:frontend/features/shifts/ui/shift_log_screen.dart';
import 'package:frontend/features/supply/ui/supply_screen.dart';
import 'package:go_router/go_router.dart';

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter? _router;

GoRouter buildRouter() {
  final session = getIt<SessionCubit>();
  return _router ??= GoRouter(
    initialLocation: '/',
    refreshListenable: _RouterRefresh(session.stream),
    redirect: (context, state) {
      final current = getIt<SessionCubit>().state;
      final location = state.matchedLocation;
      if (current is SessionRestoring) {
        return location == '/' ? null : '/';
      }
      if (current is SessionAnonymous) {
        return location == '/login' ? null : '/login';
      }
      final user = (current as SessionSignedIn).user;
      if (user.isOperator) {
        return location.startsWith('/operator') ? null : '/operator';
      }
      return location.startsWith('/manager') ? null : '/manager';
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => ManagerShell(
          location: state.uri.path,
          notifications: getIt<NotificationCubit>(),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/manager',
            builder: (context, state) => const DashboardScreen(),
            routes: [
              GoRoute(
                path: 'assets',
                builder: (context, state) => const AssetsScreen(),
              ),
              GoRoute(
                path: 'supply',
                builder: (context, state) => SupplyScreen(openCreate: state.uri.queryParameters['new'] == '1'),
              ),
              GoRoute(
                path: 'attendance',
                builder: (context, state) => const AttendanceScreen(),
              ),
              GoRoute(
                path: 'shifts',
                builder: (context, state) => const ShiftLogScreen(),
              ),
              GoRoute(
                path: 'settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/operator', builder: (context, state) => const OperatorShell()),
    ],
  );
}
