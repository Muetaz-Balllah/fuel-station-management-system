import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/data/models/auth_user.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/features/settings/ui/settings_screen.dart';

class _UpdatingSettingsCubit extends SettingsCubit {
  _UpdatingSettingsCubit(SettingsState initial)
    : super(SettingsRepository(Dio()), initial: initial);

  @override
  Future<bool> updateUser(String id, Map<String, dynamic> body) async {
    emit(state.copyWith(loading: true, clearError: true));
    await Future<void>.delayed(Duration.zero);
    emit(
      state.copyWith(
        loading: false,
        users: [
          for (final user in state.users)
            if (user.id == id)
              StaffMember(
                id: user.id,
                employeeCode: user.employeeCode,
                fullName: body['full_name'] as String,
                username: body['username'] as String,
                email: body['email'] as String?,
                jobTitle: body['job_title'] as String,
                roleCode: body['role_code'] as String,
                roleNameAr: user.roleNameAr,
                isActive: user.isActive,
                isMaintenance: false,
                lastLoginAt: user.lastLoginAt,
                photoUrl: user.photoUrl,
              )
            else
              user,
        ],
      ),
    );
    return true;
  }
}

class _FakeGateway implements AuthGateway {
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<AuthUser> login({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser?> restore() async => null;

  @override
  Future<AuthUser> uploadPhoto({
    required List<int> bytes,
    required String filename,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('saving a renamed user on a narrow screen does not crash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = _UpdatingSettingsCubit(
      const SettingsState(
        station: StationProfile(
          id: 's',
          code: 'ST-104',
          name: 'محطة',
          licenseNumber: 'LY-1',
          licenseExpiresOn: '2027-12-31',
          latitude: 32,
          longitude: 13,
          timezone: 'Africa/Tripoli',
          logoUrl: null,
        ),
        users: [
          StaffMember(
            id: 'u1',
            employeeCode: 'EMP-2',
            fullName: 'محمد',
            username: 'operator',
            email: 'op@station.test',
            jobTitle: 'مشغل',
            roleCode: 'operator',
            roleNameAr: 'مشغل الوردية',
            isActive: true,
            isMaintenance: false,
            lastLoginAt: null,
          ),
        ],
      ),
    );
    final session = SessionCubit(_FakeGateway());

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionCubit>.value(value: session),
          BlocProvider<SettingsCubit>.value(value: settings),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SettingsView()),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('إدارة المستخدمين'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدارة المستخدمين'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تعديل'));
    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'اسم المستخدم'),
      'operator2',
    );
    await tester.tap(find.text('حفظ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('تعديل المستخدم'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
