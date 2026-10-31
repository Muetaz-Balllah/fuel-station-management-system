import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/networking/api_exception.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';
import 'package:frontend/features/dashboard/logic/cubit/dashboard_cubit.dart';
import 'package:frontend/features/dashboard/ui/dashboard_screen.dart';
import 'package:frontend/features/settings/ui/widgets/license_banner.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';
import 'package:frontend/features/attendance/logic/cubit/attendance_cubit.dart';
import 'package:frontend/features/attendance/ui/attendance_screen.dart';
import 'package:frontend/features/assets/data/models/asset_models.dart';
import 'package:frontend/features/assets/data/repos/assets_repository.dart';
import 'package:frontend/features/assets/logic/cubit/assets_cubit.dart';
import 'package:frontend/features/assets/ui/assets_screen.dart';
import 'package:frontend/features/assets/ui/widgets/tank_form.dart';
import 'package:frontend/core/theming/app_theme.dart';
import 'package:frontend/features/auth/data/models/auth_user.dart';
import 'package:frontend/features/auth/data/repos/auth_repository.dart';
import 'package:frontend/features/auth/logic/cubit/login_cubit.dart';
import 'package:frontend/features/auth/logic/cubit/session_cubit.dart';
import 'package:frontend/features/auth/ui/login_screen.dart';
import 'package:frontend/core/widgets/manager_shell.dart';
import 'package:frontend/core/widgets/operator_shell.dart';
import 'package:frontend/features/settings/data/models/settings_models.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/features/settings/ui/settings_screen.dart';
import 'package:frontend/features/settings/ui/widgets/shift_template_form.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';
import 'package:frontend/features/shifts/logic/cubit/duty_cubit.dart';
import 'package:frontend/features/shifts/logic/cubit/shift_log_cubit.dart';
import 'package:frontend/features/shifts/ui/duty_screen.dart';
import 'package:frontend/features/shifts/ui/shift_log_screen.dart';
import 'package:frontend/features/supply/data/models/supply_models.dart';
import 'package:frontend/features/supply/data/repos/supply_repository.dart';
import 'package:frontend/features/supply/logic/cubit/supply_cubit.dart';
import 'package:frontend/features/supply/ui/supply_screen.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('empty login asks for the username', (tester) async {
    await _pumpLogin(tester, _FakeGateway());
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(find.text('أدخل اسم المستخدم'), findsWidgets);
  });

  testWidgets('wrong password shows the server message', (tester) async {
    await _pumpLogin(
      tester,
      _FakeGateway(error: ApiException('اسم المستخدم أو كلمة المرور غير صحيحة')),
    );
    await tester.enterText(find.byKey(const Key('login-username')), 'manager');
    await tester.enterText(find.byKey(const Key('login-password')), 'bad');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('اسم المستخدم أو كلمة المرور غير صحيحة'), findsOneWidget);
  });

  testWidgets('forgot password explains that the manager resets it', (tester) async {
    await _pumpLogin(tester, _FakeGateway());
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();
    expect(find.textContaining('مدير المحطة'), findsWidgets);
  });

  testWidgets('manager shell shows the dashboard placeholder', (tester) async {
    final session = SessionCubit(_FakeGateway())..signedIn(_manager);
    await tester.pumpWidget(
      BlocProvider.value(
        value: session,
        child: MaterialApp(theme: AppTheme.light(), home: const ManagerShell()),
      ),
    );
    expect(find.text('لوحة القيادة'), findsOneWidget);
    expect(find.text('إعدادات النظام'), findsOneWidget);
    expect(find.text('أحمد المصراتي'), findsOneWidget);
    expect(find.textContaining('مرحباً بك مجدداً'), findsOneWidget);
    expect(find.text('الخزانات والمضخات'), findsOneWidget);
    expect(find.text('سجل الحضور والدوام'), findsOneWidget);
    expect(find.text('التوريدات والموردين'), findsOneWidget);
    expect(find.text('طلب تزويد جديد'), findsOneWidget);
  });

  testWidgets('operator shell does not show the manager sidebar', (tester) async {
    final session = SessionCubit(_FakeGateway())..signedIn(_operator);
    final duty = DutyCubit(
      ShiftRepository(Dio()),
      initial: const DutyState(
        loaded: true,
        reason: 'لا توجد وردية مكلّفة لك اليوم. اطلب من مدير المحطة تسجيل حضورك وتكليفك بمضخة.',
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: session,
        child: MaterialApp(theme: AppTheme.light(), home: OperatorShell(cubit: duty)),
      ),
    );
    expect(find.textContaining('لا توجد وردية'), findsOneWidget);
    expect(find.text('لوحة القيادة'), findsNothing);
    expect(find.text('الخزانات والمضخات'), findsNothing);
    expect(find.text('سجل الحضور والدوام'), findsNothing);
    expect(find.text('إعدادات النظام'), findsNothing);
    expect(find.text('محمد مصطفى القذافي'), findsOneWidget);
  });

  testWidgets('settings screen shows the four tabs', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionCubit(_FakeGateway())..signedIn(_manager);
    final settings = SettingsCubit(
      SettingsRepository(Dio()),
      initial: const SettingsState(
        station: StationProfile(
          id: 's',
          code: 'ST-104',
          name: 'محطة طريق المطار - طرابلس',
          licenseNumber: 'LY-4492-TPS',
          licenseExpiresOn: '2027-12-31',
          latitude: 32.8872,
          longitude: 13.1913,
          timezone: 'Africa/Tripoli',
          logoUrl: null,
        ),
        roles: [
          RoleGrant(id: '1', code: 'system_admin', nameAr: 'مدير النظام', permissions: []),
          RoleGrant(id: '2', code: 'station_manager', nameAr: 'مدير المحطة', permissions: []),
          RoleGrant(id: '3', code: 'operator', nameAr: 'موظف', permissions: ['shifts.operate']),
        ],
        templates: [
          ShiftTemplateItem(
            id: 't',
            nameAr: 'صباحية',
            startsAt: '08:00',
            endsAt: '16:00',
            graceMinutes: 10,
            isActive: true,
            crossesMidnight: false,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: session),
          BlocProvider.value(value: settings),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsView())),
      ),
    );
    expect(find.text('إعدادات المحطة'), findsOneWidget);
    expect(find.text('إدارة المستخدمين'), findsOneWidget);
    expect(find.text('الأدوار والصلاحيات'), findsOneWidget);
    expect(find.text('إعدادات الورديات ومواعيد المناوبات'), findsWidgets);
    await tester.tap(find.text('إدارة المستخدمين'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة مستخدم جديد'), findsOneWidget);
    await tester.tap(find.text('الأدوار والصلاحيات'));
    await tester.pumpAndSettle();
    expect(find.text('فقط مدير النظام يستطيع تعديل الصلاحيات.'), findsOneWidget);
    await tester.tap(find.text('إعدادات الورديات ومواعيد المناوبات').first);
    await tester.pumpAndSettle();
    expect(find.text('صباحية'), findsOneWidget);
  });

  testWidgets('shift form rejects an empty name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShiftTemplateForm(onSubmit: (_) async {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('shift-save')));
    await tester.pump();
    expect(find.byKey(const Key('shift-error')), findsOneWidget);
    expect(find.text('اسم الوردية مطلوب.'), findsOneWidget);
  });

  testWidgets('assets board shows the pump gauge and a tank-link error', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const tank = AssetTank(
      id: 't',
      code: 'T-01',
      name: 'خزان بنزين 95',
      productId: 'p',
      productName: 'بنزين 95',
      capacityLiters: '25000.000',
      currentLiters: '19000.000',
      percent: 76,
      cardBandLabel: 'مستقر',
      lastReceiptLabel: 'أمس، 08:30 م',
      todayLiters: '2850.000',
    );
    final cubit = AssetsCubit(
      AssetsRepository(Dio()),
      initial: AssetsState(
        error: 'هذا الخزان مرتبط بمضخة أخرى. كل مضخة لها خزان مستقل.',
        board: AssetBoard(
          products: const [AssetProduct(id: 'p', code: 'G95', nameAr: 'بنزين 95')],
          freeTanks: const [],
          demo: true,
          cards: [
            PumpCardData(
              pump: const AssetPump(
                id: 'pump',
                code: 'PUMP-01',
                name: 'وحدة مضخة PUMP-01',
                status: 'active',
                statusLabel: 'نشطة',
                tankId: 't',
                tankCode: 'T-01',
              ),
              tank: tank,
              nozzles: const [
                AssetNozzle(
                  id: 'n',
                  code: 'N1',
                  label: 'يمين',
                  status: 'ready',
                  statusLabel: 'جاهز',
                  currentMeter: '680150.000',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: AssetsView())),
      ),
    );
    expect(find.textContaining('PUMP-01'), findsWidgets);
    expect(find.text('76%'), findsOneWidget);
    expect(find.text('هذا الخزان مرتبط بمضخة أخرى. كل مضخة لها خزان مستقل.'), findsOneWidget);
    expect(find.textContaining('680,150'), findsOneWidget);
  });

  testWidgets('tank form rejects an empty name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TankForm(
            products: const [AssetProduct(id: 'p', code: 'G95', nameAr: 'بنزين 95')],
            onSubmit: (_, _, _) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('tank-save')));
    await tester.pump();
    expect(find.byKey(const Key('tank-error')), findsOneWidget);
    expect(find.text('اسم الخزان مطلوب.'), findsOneWidget);
  });

  testWidgets('attendance shows present, late, and absent, and exports the same rows', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rows = [
      AttendanceRow(
        id: '1',
        userId: 'u1',
        fullName: 'محمد',
        jobTitle: 'موظف',
        employeeCode: 'EMP-1001',
        status: 'present',
        statusLabel: 'حاضر',
        note: null,
        checkInLabel: '07:55',
        checkOutLabel: null,
        assignments: [
          AttendanceAssignment(nozzleCode: 'N1', label: 'يمين', pumpCode: 'PUMP-01', productName: 'بنزين 95'),
        ],
      ),
      AttendanceRow(
        id: '2',
        userId: 'u2',
        fullName: 'خالد',
        jobTitle: 'موظف',
        employeeCode: 'EMP-1002',
        status: 'late',
        statusLabel: 'متأخر',
        note: null,
        checkInLabel: '08:45',
        checkOutLabel: null,
        assignments: [
          AttendanceAssignment(nozzleCode: 'N1', label: 'يمين', pumpCode: 'PUMP-02', productName: 'بنزين 95'),
        ],
      ),
      AttendanceRow(
        id: '3',
        userId: 'u3',
        fullName: 'سالم',
        jobTitle: 'موظف',
        employeeCode: 'EMP-1003',
        status: 'absent',
        statusLabel: 'غائب',
        note: 'بدون عذر مسبق',
        checkInLabel: null,
        checkOutLabel: null,
        assignments: [],
      ),
    ];
    final cubit = AttendanceCubit(
      AttendanceRepository(Dio()),
      initial: const AttendanceState(
        date: '2026-10-26',
        sessionId: 's',
        rows: rows,
        summary: AttendanceSummary(
          templateName: 'صباحية',
          showed: 3,
          total: 4,
          percent: 75,
          covered: 3,
          active: 6,
          lateCount: 1,
          week: [WeekDayStat(date: '2026-10-26', label: 'الاثنين', percent: 75)],
        ),
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: AttendanceView())),
      ),
    );
    expect(find.text('حاضر'), findsOneWidget);
    expect(find.text('متأخر'), findsOneWidget);
    expect(find.text('غائب'), findsOneWidget);
    expect(find.text('بدون عذر مسبق'), findsOneWidget);
    final lateText = tester.widget<Text>(find.byKey(const Key('late-check-in')));
    expect(lateText.data, '08:45');
    expect(lateText.style?.color, AppColors.error);
    expect(find.text('3 / 6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('attendance-export')));
    await tester.pumpAndSettle();
    final csv = tester.widget<Text>(find.byKey(const Key('attendance-csv'))).data ?? '';
    expect(csv, contains('محمد'));
    expect(csv, contains('خالد'));
    expect(csv, contains('سالم'));
    expect(csv, contains('حاضر'));
    expect(csv, contains('متأخر'));
    expect(csv, contains('غائب'));
    expect(csv, contains('07:55'));
    expect(csv, isNot(contains('سالم,موظف,EMP-1003, / , / ,07')));
  });

  testWidgets('closing meters preview a match, a shortage, and a surplus', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const duty = DutyRecord(
      id: 'd',
      sessionId: 's',
      fullName: 'محمد',
      employeeCode: 'EMP-0122',
      status: 'open',
      statusLabel: 'مفتوحة',
      openedAt: null,
      liters: null,
      expectedCash: null,
      cashHanded: null,
      variance: null,
      varianceKind: null,
      varianceLabel: null,
      approvedByName: null,
      rejectReason: null,
      businessDate: '2026-11-02',
      lines: [
        DutyLine(
          nozzleId: 'a',
          nozzleCode: 'N1',
          label: 'يمين',
          pumpCode: 'PUMP-01',
          productName: 'بنزين 95',
          openingMeter: '1841200.000',
          closingMeter: null,
          unitPrice: '0.150',
          liters: null,
          lineAmount: null,
        ),
        DutyLine(
          nozzleId: 'b',
          nozzleCode: 'N2',
          label: 'يسار',
          pumpCode: 'PUMP-01',
          productName: 'بنزين 95',
          openingMeter: '1621075.000',
          closingMeter: null,
          unitPrice: '0.150',
          liters: null,
          lineAmount: null,
        ),
      ],
    );
    final cubit = DutyCubit(
      ShiftRepository(Dio()),
      initial: const DutyState(loaded: true, duty: duty, templateName: 'صباحية'),
    );
    final session = SessionCubit(_FakeGateway())..signedIn(_operator);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: session),
          BlocProvider.value(value: cubit),
        ],
        child: const MaterialApp(home: Scaffold(body: DutyView())),
      ),
    );
    await tester.enterText(find.byKey(const Key('close-a')), '1843450.000');
    await tester.enterText(find.byKey(const Key('close-b')), '1623105.000');
    await tester.enterText(find.byKey(const Key('duty-cash')), '642.00');
    await tester.pump();
    expect(find.text('4,280.000'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('duty-variance'))).data, 'مطابق');
    await tester.enterText(find.byKey(const Key('duty-cash')), '637.00');
    await tester.pump();
    final shortage = tester.widget<Text>(find.byKey(const Key('duty-variance')));
    expect(shortage.data, 'عجز −5.00');
    expect(shortage.style?.color, AppColors.error);
    await tester.enterText(find.byKey(const Key('duty-cash')), '647.00');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('duty-variance'))).data, 'فائض +5.00');
  });

  testWidgets('shift log offers approve and reject for a pending duty', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const pending = DutyRecord(
      id: 'd1',
      sessionId: 's1',
      fullName: 'محمد',
      employeeCode: 'EMP-0122',
      status: 'pending_approval',
      statusLabel: 'بانتظار توقيع المشرف',
      openedAt: null,
      liters: '4280.000',
      expectedCash: '642.00',
      cashHanded: '642.00',
      variance: '0.00',
      varianceKind: 'match',
      varianceLabel: '0.00 د.ل (مطابق)',
      approvedByName: null,
      rejectReason: null,
      businessDate: '2026-11-02',
      lines: [],
    );
    final cubit = ShiftLogCubit(
      ShiftRepository(Dio()),
      initial: const ShiftLogState(
        loaded: true,
        selectedId: 's1',
        rows: [
          ShiftLogRow(
            id: 's1',
            code: 'SH-2026-001',
            businessDate: '2026-11-02',
            window: 'صباحية 08:00–16:00',
            supervisor: 'أحمد المصراتي',
            statusLabel: 'جارية الآن',
            liters: null,
            revenue: null,
            varianceLabel: null,
          ),
        ],
        duties: [pending],
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: ShiftLogView())),
      ),
    );
    expect(find.text('اعتماد'), findsOneWidget);
    expect(find.text('رفض'), findsOneWidget);
    expect(find.textContaining('جارية الآن'), findsOneWidget);
  });

  testWidgets('supply form only offers tanks of the chosen product', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = SupplyCubit(
      SupplyRepository(Dio()),
      initial: const SupplyState(
        loaded: true,
        deliveredLiters: '45200.000',
        activeOrders: 13,
        pendingOrders: 5,
        activeSuppliers: 3,
        selectedSupplierId: 'brega',
        suppliers: [
          SupplierRecord(
            id: 'brega',
            name: 'شركة البريقة لتسويق النفط',
            headquarters: 'طريق المطار، طرابلس',
            contactName: 'م. علي صالح',
            phone: '021-3600000',
            maxDailyLiters: '500000.000',
            isActive: true,
            reliability: 98,
          ),
        ],
        products: [
          SupplyProductOption(id: 'g', name: 'بنزين 95'),
          SupplyProductOption(id: 'd', name: 'ديزل'),
        ],
        tanks: [
          SupplyTankOption(id: 'tg', name: 'خزان البنزين', productId: 'g', productName: 'بنزين 95'),
          SupplyTankOption(id: 'td', name: 'خزان الديزل', productId: 'd', productName: 'ديزل'),
        ],
        orders: [
          SupplyOrderRecord(
            id: 'o1',
            code: 'ORD-9921',
            supplierId: 'brega',
            supplierName: 'شركة البريقة لتسويق النفط',
            tankId: 'tg',
            tankName: 'خزان البنزين',
            productId: 'g',
            productName: 'بنزين 95',
            orderedLiters: '15000.000',
            status: 'pending',
            statusLabel: 'قيد الانتظار',
            expectedOn: '2026-11-20',
          ),
          SupplyOrderRecord(
            id: 'o2',
            code: 'ORD-9918',
            supplierId: 'brega',
            supplierName: 'شركة البريقة لتسويق النفط',
            tankId: 'td',
            tankName: 'خزان الديزل',
            productId: 'd',
            productName: 'ديزل',
            orderedLiters: '10000.000',
            status: 'received',
            statusLabel: 'تم الاستلام',
            expectedOn: '2026-11-18',
          ),
          SupplyOrderRecord(
            id: 'o3',
            code: 'ORD-9915',
            supplierId: 'brega',
            supplierName: 'شركة البريقة لتسويق النفط',
            tankId: 'tg',
            tankName: 'خزان البنزين',
            productId: 'g',
            productName: 'بنزين 95',
            orderedLiters: '20000.000',
            status: 'cancelled',
            statusLabel: 'ملغي',
            expectedOn: '2026-11-17',
          ),
        ],
        week: [SupplyWeekDay(date: '2026-10-31', label: 'السبت', liters: '15000.000')],
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: SupplyView())),
      ),
    );
    expect(find.text('45,200'), findsOneWidget);
    expect(find.textContaining('طريق المطار، طرابلس'), findsOneWidget);
    expect(find.textContaining('م. علي صالح'), findsOneWidget);
    expect(find.textContaining('98%'), findsOneWidget);
    expect(find.textContaining('500,000'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('order-status-o1'))).style?.color, AppColors.warning);
    expect(tester.widget<Text>(find.byKey(const Key('order-status-o2'))).style?.color, AppColors.primary);
    expect(tester.widget<Text>(find.byKey(const Key('order-status-o3'))).style?.color, const Color(0xFF75777F));
    expect(find.text('استلام'), findsOneWidget);
    expect(find.text('تحديث بيانات المورد'), findsOneWidget);
    await tester.tap(find.byKey(const Key('supply-create')));
    await tester.pumpAndSettle();
    expect(find.text('خزان البنزين'), findsWidgets);
    expect(find.text('خزان الديزل'), findsNothing);
    await tester.tap(find.byKey(const Key('supply-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ديزل').last);
    await tester.pumpAndSettle();
    expect(find.text('خزان الديزل'), findsOneWidget);
    expect(find.text('خزان البنزين'), findsNothing);
  });

  testWidgets('dashboard shows the day totals and a shortage in red', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = DashboardCubit(
      DashboardRepository(Dio()),
      initial: DashboardState(
        loaded: true,
        date: '2026-12-15',
        revenue: '90.00',
        liters: '600.000',
        inventoryLiters: '1400.000',
        staffOnDuty: 1,
        week: const [DashboardWeekDay(date: '2026-12-15', label: 'الثلاثاء', morning: '90.00', evening: '0.00')],
        tanks: const [
          DashboardTank(name: 'خزان اللوحة', productName: 'بنزين 95', percent: 14, currentLiters: '1400.000', capacityLiters: '10000.000'),
        ],
        sessions: const [
          ShiftLogRow(
            id: 's1',
            code: 'SH-0001',
            businessDate: '2026-12-15',
            window: '08:00–16:00',
            supervisor: 'أحمد المصراتي',
            statusLabel: 'معتمدة ومغلقة',
            liters: '600.000',
            revenue: '90.00',
            varianceLabel: '-5.00 د.ل (عجز)',
          ),
          ShiftLogRow(
            id: 's2',
            code: 'SH-0002',
            businessDate: '2026-12-15',
            window: '16:00–00:00',
            supervisor: 'أحمد المصراتي',
            statusLabel: 'معتمدة ومغلقة',
            liters: '100.000',
            revenue: '15.00',
            varianceLabel: '0.00 د.ل (مطابق)',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: DashboardView())),
      ),
    );
    expect(find.text('نظرة عامة على العمليات'), findsOneWidget);
    expect(find.textContaining('90.00'), findsWidgets);
    expect(find.textContaining('1,400.000'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.byKey(const Key('dashboard-alert')), findsNothing);
    expect(find.text('الوردية الصباحية'), findsOneWidget);
    expect(find.text('الوردية المسائية'), findsOneWidget);
    expect(find.text('عرض كافة التفاصيل الفنية'), findsOneWidget);
    expect(find.text('سجل كافة الورديات'), findsOneWidget);
    final variance = tester.widget<Text>(find.byKey(const Key('dashboard-variance-s1')));
    expect(variance.data, '-5.00 د.ل (عجز)');
    expect(variance.style?.color, AppColors.error);
    final matched = tester.widget<Text>(find.byKey(const Key('dashboard-variance-s2')));
    expect(matched.data, '0.00 د.ل (مطابق)');
    expect(matched.style?.color, isNot(AppColors.error));
    await tester.tap(find.text('تصدير التقرير'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-export')), findsOneWidget);
    expect(find.textContaining('90.00'), findsWidgets);
  });

  testWidgets('dashboard hides the table when the day has no shifts and shows an alert', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cubit = DashboardCubit(
      DashboardRepository(Dio()),
      initial: const DashboardState(
        loaded: true,
        date: '2026-12-16',
        revenue: '0.00',
        inventoryLiters: '0.000',
        alert: DashboardAlert(tankName: 'خزان بنزين 95', productName: 'بنزين 95', percent: 12, message: 'المستوى حرج: أقل من 15%'),
      ),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: DashboardView())),
      ),
    );
    expect(find.byKey(const Key('dashboard-empty')), findsOneWidget);
    expect(find.text('لا توجد ورديات في هذا اليوم'), findsOneWidget);
    expect(find.text('تنبيه الخزانات'), findsOneWidget);
    expect(find.text('خزان بنزين 95'), findsOneWidget);
    expect(find.text('المستوى حرج: أقل من 15%'), findsOneWidget);
    expect(tester.widget<Text>(find.text('المستوى حرج: أقل من 15%')).style?.color, AppColors.error);
  });

  testWidgets('dashboard shows the load error', (tester) async {
    final cubit = DashboardCubit(
      DashboardRepository(Dio()),
      initial: const DashboardState(error: 'تعذر تحميل لوحة القيادة'),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: DashboardView())),
      ),
    );
    expect(find.byKey(const Key('dashboard-error')), findsOneWidget);
  });

  testWidgets('license banner appears only inside the renewal window', (tester) async {
    expect(LicenseRenewalBanner.due('2027-12-31', DateTime(2026, 10, 31)), isFalse);
    final soon = DateTime.now().add(const Duration(days: 10));
    final expires = '${soon.year.toString().padLeft(4, '0')}-${soon.month.toString().padLeft(2, '0')}-${soon.day.toString().padLeft(2, '0')}';
    expect(LicenseRenewalBanner.due(expires), isTrue);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LicenseRenewalBanner(expiresOn: expires))));
    expect(find.byKey(const Key('license-warning')), findsOneWidget);
  });

  testWidgets('phone operator view offers a new shift', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionCubit(_FakeGateway())..signedIn(_operator);
    final duty = DutyCubit(
      ShiftRepository(Dio()),
      initial: const DutyState(loaded: true, canOpen: true),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: session),
          BlocProvider.value(value: duty),
        ],
        child: const MaterialApp(home: Scaffold(body: DutyView())),
      ),
    );
    expect(find.text('فتح وردية جديدة'), findsWidgets);
  });
}

Future<void> _pumpLogin(WidgetTester tester, AuthGateway gateway) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = SessionCubit(gateway);
  final login = LoginCubit(gateway, session);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: LoginScreen(cubit: login),
    ),
  );
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
}

class _FakeGateway implements AuthGateway {
  _FakeGateway({this.error});

  final ApiException? error;

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
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return _manager;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser?> restore() async => null;
}

const _manager = AuthUser(
  id: '1',
  stationId: 's',
  stationName: 'محطة طريق المطار - طرابلس',
  stationCode: 'ST-104',
  employeeCode: 'EMP-0001',
  fullName: 'أحمد المصراتي',
  username: 'manager',
  email: null,
  jobTitle: 'مدير المحطة',
  roleCode: 'station_manager',
  roleNameAr: 'مدير المحطة',
  permissions: ['settings.manage'],
  isMaintenance: false,
  isActive: true,
);

const _operator = AuthUser(
  id: '2',
  stationId: 's',
  stationName: 'محطة طريق المطار - طرابلس',
  stationCode: 'ST-104',
  employeeCode: 'EMP-0122',
  fullName: 'محمد مصطفى القذافي',
  username: 'operator',
  email: null,
  jobTitle: 'فني مضخات ووردية',
  roleCode: 'operator',
  roleNameAr: 'موظف',
  permissions: ['shifts.operate'],
  isMaintenance: false,
  isActive: true,
);
