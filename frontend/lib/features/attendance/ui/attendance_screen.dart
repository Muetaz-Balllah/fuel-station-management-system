import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/constants/safety_instructions.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/layout/responsive_layout.dart';
import 'package:frontend/core/reporting/attendance_pdf.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/core/widgets/app_dialog.dart';
import 'package:frontend/core/widgets/dispose_controllers.dart';
import 'package:frontend/core/widgets/horizontal_data_table.dart';
import 'package:frontend/core/widgets/pagination_bar.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';
import 'package:frontend/features/attendance/logic/cubit/attendance_cubit.dart';
import 'package:frontend/features/shifts/data/repos/shift_repository.dart';
import 'package:frontend/features/shifts/ui/duty_approval_panel.dart';
import 'package:frontend/features/settings/data/repos/settings_repository.dart';
import 'package:frontend/features/settings/logic/cubit/settings_cubit.dart';
import 'package:frontend/core/time/system_clock.dart';
import 'package:frontend/features/attendance/ui/widgets/attendance_date_bar.dart';
import 'package:frontend/features/settings/ui/widgets/shift_templates_panel.dart';
import 'package:printing/printing.dart';

const _green = Color(0xFF15803D);

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key, this.cubit});

  final AttendanceCubit? cubit;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit!),
          BlocProvider(
            create: (_) => SettingsCubit(getIt<SettingsRepository>())..load(),
          ),
        ],
        child: const AttendanceView(),
      );
    }
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AttendanceCubit(
            getIt<AttendanceRepository>(),
            getIt<ShiftRepository>(),
          )..load(),
        ),
        BlocProvider(
          create: (_) => SettingsCubit(getIt<SettingsRepository>())..load(),
        ),
      ],
      child: const AttendanceView(),
    );
  }
}

class AttendanceView extends StatelessWidget {
  const AttendanceView({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabBar(
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.outline,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(key: Key('tab-attendance-ops'), text: 'الحضور والتكليف'),
                Tab(
                  key: Key('tab-shift-config'),
                  text: 'إعداد الورديات ومواعيد المناوبات',
                ),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [AttendanceOperationsTab(), ShiftTemplatesPanel()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AttendanceOperationsTab extends StatefulWidget {
  const AttendanceOperationsTab({super.key});

  @override
  State<AttendanceOperationsTab> createState() =>
      _AttendanceOperationsTabState();
}

class _AttendanceOperationsTabState extends State<AttendanceOperationsTab> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) {
        context.read<AttendanceCubit>().load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttendanceCubit>().state;
    final summary = state.summary;
    final cubit = context.read<AttendanceCubit>();
    final serverToday = state.serverToday.isEmpty
        ? SystemClock.todayIso()
        : state.serverToday;
    return ListView(
      padding: managerPagePadding(context),
      children: [
        AttendanceDateBar(
          date: state.date,
          serverToday: serverToday,
          onPrevious: cubit.goToPreviousDay,
          onNext: cubit.goToNextDay,
          onPick: () => pickAttendanceDate(
            context,
            current: state.date,
            serverToday: serverToday,
            onSelected: cubit.pickDate,
          ),
        ),
        const SizedBox(height: 12),
        if (summary == null && state.loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (summary != null)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                title: 'حضور الوردية الصباحية',
                value: '${summary.showed} / ${summary.total}',
                caption: 'نسبة الاكتمال ${summary.percent}%',
              ),
              _StatCard(
                title: 'تغطية المضخات والمسدسات',
                value: '${summary.covered} / ${summary.active}',
                caption: 'مسدس نشط',
              ),
              _StatCard(
                title: 'المناوبة والوردية النشطة',
                value: summary.templateName.isEmpty
                    ? 'لا توجد وردية'
                    : summary.templateName,
                caption:
                    'المتأخرون عن الوردية: ${summary.lateCount.toString().padLeft(2, '0')} موظف',
              ),
            ],
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              state.error!,
              key: const Key('attendance-error'),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            const heading = Text(
              'الحضور المرتبط بالوردية وتوزيع المضخات',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: state.sessionId == null
                      ? null
                      : () => _register(context, state),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('تسجيل حضور وتكليف يدوي'),
                ),
                OutlinedButton.icon(
                  key: const Key('attendance-export'),
                  onPressed: () => _export(context, state.rows),
                  icon: const Icon(Icons.download),
                  label: const Text('تصدير تقرير التكليفات'),
                ),
              ],
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 12), actions],
              );
            }
            return Row(
              children: [
                const Expanded(child: heading),
                actions,
              ],
            );
          },
        ),
        if (state.sessions.length > 1) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final session in state.sessions)
                ChoiceChip(
                  label: Text('${session.templateName} (${session.code})'),
                  selected: session.id == state.sessionId,
                  onSelected: (_) =>
                      context.read<AttendanceCubit>().selectSession(session.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _Table(rows: state.rows),
        PaginationBar(
          page: state.attendancePage,
          pageCount: state.attendancePageCount,
          total: state.attendanceTotal,
          onPage: (page) =>
              context.read<AttendanceCubit>().setAttendancePage(page),
        ),
        const SizedBox(height: 20),
        DutyApprovalPanel(
          key: const Key('attendance-duty-approval'),
          title: 'سجل الورديات واعتماد الإغلاق (مباشر)',
          duties: state.sessionDuties,
          onApprove: (id) => context.read<AttendanceCubit>().approveDuty(id),
          onReject: (id, reason) =>
              context.read<AttendanceCubit>().rejectDuty(id, reason),
        ),
        PaginationBar(
          page: state.dutiesPage,
          pageCount: state.dutiesPageCount,
          total: state.dutiesTotal,
          onPage: (page) => context.read<AttendanceCubit>().setDutiesPage(page),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            const panelHeight = 220.0;
            final chart = SizedBox(
              height: panelHeight,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تحليل الالتزام الأسبوعي',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _WeekBars(days: summary?.week ?? const [])),
                  ],
                ),
              ),
            );
            final safety = SizedBox(
              height: panelHeight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openSafetyInstructions(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/safety_instructions.png',
                          fit: BoxFit.cover,
                        ),
                        Container(
                          color: AppColors.primary.withValues(alpha: 0.72),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'تعليمات السلامة',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'تأكد من تسجيل البصمة عند دخول المناطق المحظورة والالتزام بمهمات الوقاية الشخصية.',
                                style: TextStyle(
                                  color: Colors.white,
                                  height: 1.5,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'اضغط لعرض التعليمات كاملة',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            if (constraints.maxWidth < 860) {
              return Column(
                children: [chart, const SizedBox(height: 16), safety],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: TextDirection.rtl,
              children: [
                Expanded(child: chart),
                const SizedBox(width: 16),
                Expanded(child: safety),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              color: _green,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _AttendanceTableLayout {
  /// Column widths plus horizontal row padding (12 + 12).
  static const minWidth = 1126.0;
  static const name = 180.0;
  static const code = 110.0;
  static const assignment = 220.0;
  static const checkIn = 90.0;
  static const checkOut = 90.0;
  static const duty = 120.0;
  static const status = 80.0;
  static const note = 140.0;
  static const actions = 72.0;
}

class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<AttendanceRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('لا يوجد تكليف في هذا اليوم.');
    }
    return HorizontalDataTable(
      minWidth: _AttendanceTableLayout.minWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          for (final row in rows) _AttendanceLine(row: row),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Row(
        children: [
          SizedBox(
            width: _AttendanceTableLayout.name,
            child: Text('اسم الموظف', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.code,
            child: Text('الرقم الوظيفي', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.assignment,
            child: Text('التكليف الميداني', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.checkIn,
            child: Text('بدء الوردية', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.checkOut,
            child: Text('نهاية الوردية', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.duty,
            child: Text('حالة العهدة', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.status,
            child: Text('الحالة', style: style),
          ),
          SizedBox(
            width: _AttendanceTableLayout.note,
            child: Text('ملاحظات التشغيل', style: style),
          ),
          SizedBox(width: _AttendanceTableLayout.actions),
        ],
      ),
    );
  }
}

class _AttendanceLine extends StatelessWidget {
  const _AttendanceLine({required this.row});

  final AttendanceRow row;

  @override
  Widget build(BuildContext context) {
    final late = row.status == 'late';
    final checkIn = row.checkInLabel ?? '—';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _AttendanceTableLayout.name,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  row.jobTitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.code,
            child: Text('#${row.employeeCode}'),
          ),
          SizedBox(
            width: _AttendanceTableLayout.assignment,
            child: row.assignments.isEmpty
                ? const Text('—')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in row.assignments)
                        Text(
                          '${item.pumpCode}  مسدس ${item.nozzleCode}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      Text(
                        row.assignments
                            .map(
                              (item) => '${item.productName} • ${item.label}',
                            )
                            .join('، '),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                    ],
                  ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.checkIn,
            child: Text(
              checkIn,
              key: late ? const Key('late-check-in') : null,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: late ? AppColors.error : AppColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.checkOut,
            child: Text(
              row.checkOutLabel ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.duty,
            child: Text(
              row.duty?.statusLabel ?? '—',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: row.duty?.status == 'pending_approval'
                    ? AppColors.warning
                    : AppColors.onSurface,
              ),
            ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.status,
            child: Text(
              row.statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: late
                    ? AppColors.error
                    : (row.status == 'present' ? _green : AppColors.onSurface),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.note,
            child: Text(
              row.note ?? '—',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          SizedBox(
            width: _AttendanceTableLayout.actions,
            child: TextButton(
              key: Key('attendance-edit-${row.id}'),
              onPressed: () => _edit(context, row),
              child: const Text('تعديل'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});

  final List<WeekDayStat> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      day.percent == null ? '—' : '${day.percent}%',
                      style: const TextStyle(fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 8 + (day.percent ?? 0) * 0.7,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 6),
                    Text(day.label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _export(BuildContext context, List<AttendanceRow> rows) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final bytes = await buildAttendancePdf(rows: rows);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'attendance-report.pdf',
    );
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text('تعذر إنشاء ملف PDF. $error')),
    );
  }
}

Future<void> _register(BuildContext context, AttendanceState state) async {
  final cubit = context.read<AttendanceCubit>();
  String? userId = state.users.isEmpty ? null : state.users.first.id;
  final selected = <String>{};
  final checkIn = TextEditingController(text: '08:00');
  final note = TextEditingController();
  var absent = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return DisposeControllers(
        controllers: [checkIn, note],
        child: StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('تسجيل حضور وتكليف يدوي'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: userId,
                        decoration: const InputDecoration(labelText: 'الموظف'),
                        items: [
                          for (final user in state.users)
                            DropdownMenuItem(
                              value: user.id,
                              child: Text(user.fullName),
                            ),
                        ],
                        onChanged: (value) => setLocal(() => userId = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('غائب'),
                        value: absent,
                        onChanged: (value) => setLocal(() => absent = value),
                      ),
                      if (!absent)
                        for (final nozzle in state.nozzles.where(
                          (item) => item.pumpStatus == 'active',
                        ))
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              '${nozzle.pumpCode} • ${nozzle.code} (${nozzle.label})',
                            ),
                            value: selected.contains(nozzle.id),
                            onChanged: (checked) {
                              setLocal(() {
                                if (checked ?? false) {
                                  selected.add(nozzle.id);
                                } else {
                                  selected.remove(nozzle.id);
                                }
                              });
                            },
                          ),
                      if (!absent)
                        TextField(
                          controller: checkIn,
                          decoration: const InputDecoration(
                            labelText: 'وقت الحضور',
                          ),
                        ),
                      TextField(
                        controller: note,
                        decoration: const InputDecoration(labelText: 'ملاحظة'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: userId == null
                      ? null
                      : () async {
                          final ok = await cubit.register(
                            userId: userId!,
                            nozzleIds: selected.toList(),
                            checkIn: absent ? null : checkIn.text,
                            note: note.text,
                            absent: absent,
                          );
                          if (!dialogContext.mounted) {
                            return;
                          }
                          if (ok) {
                            Navigator.pop(dialogContext);
                          }
                        },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> _edit(BuildContext context, AttendanceRow row) async {
  final cubit = context.read<AttendanceCubit>();
  final state = cubit.state;
  final selected = <String>{
    for (final item in row.assignments)
      if (item.nozzleId.isNotEmpty) item.nozzleId,
  };
  final checkIn = TextEditingController(text: row.checkInLabel ?? '');
  final checkOut = TextEditingController(text: row.checkOutLabel ?? '');
  final note = TextEditingController(text: row.note ?? '');
  var absent = row.status == 'absent';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return DisposeControllers(
        controllers: [checkIn, checkOut, note],
        child: StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('تعديل حضور ${row.fullName}'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('غائب'),
                        value: absent,
                        onChanged: (value) => setLocal(() => absent = value),
                      ),
                      if (!absent)
                        for (final nozzle in state.nozzles.where(
                          (item) => item.pumpStatus == 'active',
                        ))
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              '${nozzle.pumpCode} • ${nozzle.code} (${nozzle.label})',
                            ),
                            value: selected.contains(nozzle.id),
                            onChanged: (checked) {
                              setLocal(() {
                                if (checked ?? false) {
                                  selected.add(nozzle.id);
                                } else {
                                  selected.remove(nozzle.id);
                                }
                              });
                            },
                          ),
                      if (!absent)
                        TextField(
                          controller: checkIn,
                          decoration: const InputDecoration(
                            labelText: 'وقت الحضور',
                          ),
                        ),
                      if (!absent)
                        TextField(
                          controller: checkOut,
                          decoration: const InputDecoration(
                            labelText: 'وقت الانصراف',
                          ),
                        ),
                      TextField(
                        controller: note,
                        decoration: const InputDecoration(labelText: 'ملاحظة'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final ok = await cubit.updateRow(
                      attendanceId: row.id,
                      nozzleIds: selected.toList(),
                      checkIn: absent ? null : checkIn.text,
                      checkOut: absent ? null : checkOut.text,
                      note: note.text,
                      absent: absent,
                    );
                    if (!dialogContext.mounted) {
                      return;
                    }
                    if (ok) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> _openSafetyInstructions(BuildContext context) {
  return showAppDialog<void>(
    context: context,
    title: 'تعليمات السلامة',
    subtitle: 'إرشادات إلزامية لجميع العاملين في المحطة',
    icon: Icons.health_and_safety_outlined,
    width: 520,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in kSafetyInstructionBullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 7, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(height: 1.6, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
    actionsBuilder: (dialogContext) => [
      FilledButton(
        onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
        child: const Text('فهمت'),
      ),
    ],
  );
}
