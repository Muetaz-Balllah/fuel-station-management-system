import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';
import 'package:frontend/features/attendance/logic/cubit/attendance_cubit.dart';

const _green = Color(0xFF15803D);

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key, this.cubit});

  final AttendanceCubit? cubit;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(value: cubit!, child: const AttendanceView());
    }
    final today = DateTime.now();
    final date = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return BlocProvider(
      create: (_) => AttendanceCubit(getIt<AttendanceRepository>())..load(date: date),
      child: const AttendanceView(),
    );
  }
}

class AttendanceView extends StatelessWidget {
  const AttendanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AttendanceCubit>().state;
    final summary = state.summary;
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('تاريخ اليوم: ${state.date}', style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (summary == null && state.loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
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
                  value: summary.templateName.isEmpty ? 'لا توجد وردية' : summary.templateName,
                  caption: 'المتأخرون عن الوردية: ${summary.lateCount.toString().padLeft(2, '0')} موظف',
                ),
              ],
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(state.error!, key: const Key('attendance-error'), style: const TextStyle(color: AppColors.error)),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'سجل تفصيلي وتوزيع المضخات',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
              FilledButton.icon(
                onPressed: state.sessionId == null ? null : () => _register(context, state),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('تسجيل حضور وتكليف يدوي'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('attendance-export'),
                onPressed: () => _export(context, state.rows),
                icon: const Icon(Icons.download),
                label: const Text('تصدير تقرير التكليفات'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Table(rows: state.rows),
          const SizedBox(height: 24),
          const Text('الالتزام الأسبوعي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _WeekBars(days: summary?.week ?? const []),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: const EdgeInsets.all(16),
            child: const Text(
              'تأكد من تسجيل البصمة عند دخول المناطق المحظورة والالتزام بمهمات الوقاية الشخصية.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.caption});

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(caption, style: const TextStyle(color: _green, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<AttendanceRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('لا يوجد تكليف في هذا اليوم.');
    }
    return Column(
      children: [
        const _Header(),
        for (final row in rows) _AttendanceLine(row: row),
      ],
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
          SizedBox(width: 180, child: Text('اسم الموظف', style: style)),
          SizedBox(width: 110, child: Text('الرقم الوظيفي', style: style)),
          SizedBox(width: 220, child: Text('التكليف الميداني', style: style)),
          SizedBox(width: 90, child: Text('وقت الحضور', style: style)),
          SizedBox(width: 90, child: Text('وقت الانصراف', style: style)),
          SizedBox(width: 80, child: Text('الحالة', style: style)),
          SizedBox(width: 140, child: Text('ملاحظات التشغيل', style: style)),
          SizedBox(width: 72),
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
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.fullName, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text(row.jobTitle, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(width: 110, child: Text('#${row.employeeCode}')),
          SizedBox(
            width: 220,
            child: row.assignments.isEmpty
                ? const Text('—')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in row.assignments)
                        Text('${item.pumpCode}  مسدس ${item.nozzleCode}'),
                      Text(
                        row.assignments.map((item) => '${item.productName} • ${item.label}').join('، '),
                        style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              checkIn,
              key: late ? const Key('late-check-in') : null,
              style: TextStyle(color: late ? AppColors.error : AppColors.onSurface, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: 90, child: Text(row.checkOutLabel ?? '—')),
          SizedBox(
            width: 80,
            child: Text(
              row.statusLabel,
              style: TextStyle(
                color: late ? AppColors.error : (row.status == 'present' ? _green : AppColors.onSurface),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 140, child: Text(row.note ?? '—')),
          SizedBox(
            width: 72,
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
                    Text(day.percent == null ? '—' : '${day.percent}%', style: const TextStyle(fontSize: 11)),
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
  final csv = attendanceCsv(rows);
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('تصدير تقرير التكليفات'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Text(csv, key: const Key('attendance-csv'))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      );
    },
  );
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
      return StatefulBuilder(
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
                          DropdownMenuItem(value: user.id, child: Text(user.fullName)),
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
                      for (final nozzle in state.nozzles.where((item) => item.pumpStatus == 'active'))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('${nozzle.pumpCode} • ${nozzle.code} (${nozzle.label})'),
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
                      TextField(controller: checkIn, decoration: const InputDecoration(labelText: 'وقت الحضور')),
                    TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
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
      );
    },
  );
  checkIn.dispose();
  note.dispose();
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
      return StatefulBuilder(
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
                      for (final nozzle in state.nozzles.where((item) => item.pumpStatus == 'active'))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('${nozzle.pumpCode} • ${nozzle.code} (${nozzle.label})'),
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
                      TextField(controller: checkIn, decoration: const InputDecoration(labelText: 'وقت الحضور')),
                    if (!absent)
                      TextField(controller: checkOut, decoration: const InputDecoration(labelText: 'وقت الانصراف')),
                    TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
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
      );
    },
  );
  checkIn.dispose();
  checkOut.dispose();
  note.dispose();
}
