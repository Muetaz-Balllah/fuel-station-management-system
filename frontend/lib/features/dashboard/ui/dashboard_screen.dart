import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';
import 'package:frontend/features/dashboard/logic/cubit/dashboard_cubit.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.cubit});

  final DashboardCubit? cubit;

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider.value(value: cubit!, child: const DashboardView());
    }
    return BlocProvider(
      create: (_) => DashboardCubit(getIt<DashboardRepository>())..load(),
      child: const DashboardView(),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardCubit>().state;
    if (!state.loaded && state.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && !state.loaded) {
      return Center(
        child: Text(state.error!, key: const Key('dashboard-error'), style: const TextStyle(color: AppColors.error)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'نظرة عامة على العمليات',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Text(
            'مرحباً بك مجدداً، مدير المحطة. إليك ملخص أداء اليوم.',
            style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickDate(context, state.date),
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(state.date.isEmpty ? 'اليوم' : state.date),
              ),
              FilledButton.icon(
                onPressed: () => _export(context, state.sessions),
                icon: const Icon(Icons.download),
                label: const Text('تصدير التقرير'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(title: 'المبيعات اليومية', value: '${groupThousands(state.revenue)} د.ل', detail: '${groupThousands(state.liters)} لتر'),
              _MetricCard(title: 'إجمالي المخزون الحالي', value: '${groupThousands(state.inventoryLiters)} لتر'),
              _MetricCard(title: 'الموظفون المناوبون', value: '${state.staffOnDuty}'),
              if (state.alert != null) _AlertCard(alert: state.alert!),
            ],
          ),
          const SizedBox(height: 24),
          const Text('مقارنة مبيعات الورديات الأسبوعية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 16,
            children: [
              _Legend(color: AppColors.primary, label: 'الوردية الصباحية'),
              _Legend(color: AppColors.warning, label: 'الوردية المسائية'),
            ],
          ),
          const SizedBox(height: 12),
          _WeekChart(days: state.week),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text('مستويات الخزانات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              TextButton(
                onPressed: () => GoRouter.maybeOf(context)?.go('/manager/assets'),
                child: const Text('عرض كافة التفاصيل الفنية'),
              ),
            ],
          ),
          for (final tank in state.tanks) _TankLine(tank: tank),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('ورديات اليوم', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              TextButton(
                onPressed: () => GoRouter.maybeOf(context)?.go('/manager/shifts'),
                child: const Text('سجل كافة الورديات'),
              ),
            ],
          ),
          if (state.sessions.isEmpty)
            const Text('لا توجد ورديات في هذا اليوم', key: Key('dashboard-empty'))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('رقم الوردية')),
                  DataColumn(label: Text('الفترة / الوردية')),
                  DataColumn(label: Text('مشرف الوردية')),
                  DataColumn(label: Text('إجمالي اللترات المباعة')),
                  DataColumn(label: Text('إجمالي الإيراد')),
                  DataColumn(label: Text('الفائض / العجز')),
                  DataColumn(label: Text('حالة الوردية')),
                ],
                rows: [
                  for (final row in state.sessions)
                    DataRow(
                      cells: [
                        DataCell(Text(row.code)),
                        DataCell(Text(row.window)),
                        DataCell(Text(row.supervisor)),
                        DataCell(Text(row.liters ?? '—')),
                        DataCell(Text(row.revenue ?? '—')),
                        DataCell(
                          Text(
                            row.varianceLabel ?? '—',
                            key: Key('dashboard-variance-${row.id}'),
                            style: TextStyle(color: _varianceColor(row.varianceLabel)),
                          ),
                        ),
                        DataCell(Text(row.statusLabel)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, String current) async {
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    await context.read<DashboardCubit>().load(date: '${picked.year}-$month-$day');
  }

  void _export(BuildContext context, List<ShiftLogRow> rows) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصدير التقرير'),
        content: SingleChildScrollView(child: Text(dashboardCsv(rows), key: const Key('dashboard-export'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, this.detail});

  final String title;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
          if (detail != null) Text(detail!, style: const TextStyle(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final DashboardAlert alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('dashboard-alert'),
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('تنبيه الخزانات', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(alert.tankName, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(alert.productName),
          Text(alert.message, style: const TextStyle(color: AppColors.error)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<DashboardWeekDay> days;

  @override
  Widget build(BuildContext context) {
    final peak = days.fold<double>(1, (highest, day) {
      final morning = _money(day.morning);
      final evening = _money(day.evening);
      return [highest, morning, evening].reduce((a, b) => a > b ? a : b);
    });
    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Bar(amount: _money(day.morning), peak: peak, color: AppColors.primary),
                        const SizedBox(width: 4),
                        _Bar(amount: _money(day.evening), peak: peak, color: AppColors.warning),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(day.label, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  double _money(String raw) => double.tryParse(raw) ?? 0;
}

class _Bar extends StatelessWidget {
  const _Bar({required this.amount, required this.peak, required this.color});

  final double amount;
  final double peak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: amount <= 0 ? 0.02 : (amount / peak).clamp(0.02, 1),
      child: Container(width: 10, color: color),
    );
  }
}

class _TankLine extends StatelessWidget {
  const _TankLine({required this.tank});

  final DashboardTank tank;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${tank.name} • ${tank.productName} • ${tank.percent}%'),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (tank.percent / 100).clamp(0, 1),
            color: tank.percent <= 15 ? AppColors.error : AppColors.primary,
            backgroundColor: AppColors.outlineVariant,
          ),
        ],
      ),
    );
  }
}

Color _varianceColor(String? label) {
  if (label == null) {
    return AppColors.onSurface;
  }
  if (label.contains('عجز')) {
    return AppColors.error;
  }
  if (label.contains('فائض')) {
    return AppColors.success;
  }
  return AppColors.onSurface;
}
