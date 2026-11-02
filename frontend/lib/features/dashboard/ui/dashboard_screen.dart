import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/dashboard/data/models/dashboard_models.dart';
import 'package:frontend/features/dashboard/data/repos/dashboard_repository.dart';
import 'package:frontend/features/dashboard/logic/cubit/dashboard_cubit.dart';
import 'package:frontend/features/shifts/data/models/shift_models.dart';
import 'package:frontend/features/shifts/logic/reconcile.dart';
import 'package:frontend/core/reporting/dashboard_pdf.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

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
    if (state.error != null && state.loaded) {
      return Center(
        child: Text(state.error!, key: const Key('dashboard-error'), style: const TextStyle(color: AppColors.error)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'مرحباً بك مجدداً، مدير المحطة. إليك ملخص أداء اليوم.',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 16),
            ),
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
                key: const Key('dashboard-export'),
                onPressed: () => _export(context, state),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('تصدير التقرير'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                _MetricCard(
                  icon: Icons.point_of_sale,
                  title: 'المبيعات اليومية',
                  value: '${groupThousands(state.revenue)} د.ل',
                  detail: '${groupThousands(state.liters)} لتر',
                ),
                _MetricCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'إجمالي المخزون الحالي',
                  value: '${groupThousands(state.inventoryLiters)} لتر',
                ),
                _MetricCard(
                  icon: Icons.badge_outlined,
                  title: 'الموظفون المناوبون',
                  value: '${state.staffOnDuty}',
                  detail: 'نشط الآن',
                ),
                if (state.alert != null) _AlertCard(alert: state.alert!),
              ];
              final columns = constraints.maxWidth < 760 ? 2 : cards.length;
              return Column(
                children: [
                  for (var start = 0; start < cards.length; start += columns) ...[
                    if (start > 0) const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = start; index < start + columns && index < cards.length; index++) ...[
                          if (index > start) const SizedBox(width: 12),
                          Expanded(child: cards[index]),
                        ],
                      ],
                    ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = _WeekCard(days: state.week);
              final tanks = _TankPanel(tanks: state.tanks);
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [
                    chart,
                    const SizedBox(height: 16),
                    tanks,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(flex: 2, child: chart),
                  const SizedBox(width: 16),
                  Expanded(child: tanks),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _ShiftSummary(sessions: state.sessions),
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

  Future<void> _export(BuildContext context, DashboardState state) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final bytes = await buildDashboardPdf(
        date: state.date,
        revenue: state.revenue,
        liters: state.liters,
        inventoryLiters: state.inventoryLiters,
        staffOnDuty: state.staffOnDuty,
        sessions: state.sessions,
        week: state.week,
      );
      if (!context.mounted) {
        return;
      }
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'daily-report-${state.date}.pdf');
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text('تعذر إنشاء ملف PDF. $error')));
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.title, required this.value, this.detail});

  final IconData icon;
  final String title;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 156),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFE7EEFF), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 8),
          Text(detail ?? ' ', style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
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
      constraints: const BoxConstraints(minHeight: 156),
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.days});

  final List<DashboardWeekDay> days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text('مقارنة مبيعات الورديات الأسبوعية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primary)),
              Wrap(
                spacing: 16,
                children: [
                  _Legend(color: AppColors.primary, label: 'الوردية الصباحية'),
                  _Legend(color: Color(0xFFFFB693), label: 'الوردية المسائية'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _WeekChart(days: days),
        ],
      ),
    );
  }
}

class _TankPanel extends StatelessWidget {
  const _TankPanel({required this.tanks});

  final List<DashboardTank> tanks;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('مستويات الخزانات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primary)),
          const SizedBox(height: 16),
          if (tanks.isEmpty)
            const Text('لا توجد خزانات مسجلة.', style: TextStyle(color: AppColors.onSurfaceVariant))
          else
            for (final tank in tanks) _TankLine(tank: tank),
          const Divider(),
          TextButton(
            onPressed: () => GoRouter.maybeOf(context)?.go('/manager/assets'),
            child: const Text('عرض كافة التفاصيل الفنية'),
          ),
        ],
      ),
    );
  }
}

class _ShiftSummary extends StatelessWidget {
  const _ShiftSummary({required this.sessions});

  final List<ShiftLogRow> sessions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.table_chart, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'سجل ملخص ومطابقة الورديات اليومية',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: () => GoRouter.maybeOf(context)?.go('/manager/attendance'),
                  child: const Text('سجل كافة الورديات', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد ورديات في هذا اليوم', key: Key('dashboard-empty')),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1.6),
                2: FlexColumnWidth(1.3),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1.1),
                5: FlexColumnWidth(1.3),
                6: FlexColumnWidth(1.2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFFF0F3FF)),
                  children: [
                    _HeadCell('رقم الوردية'),
                    _HeadCell('الفترة / الوردية'),
                    _HeadCell('مشرف الوردية'),
                    _HeadCell('إجمالي اللترات المباعة'),
                    _HeadCell('إجمالي الإيراد'),
                    _HeadCell('الفائض / العجز'),
                    _HeadCell('حالة الوردية'),
                  ],
                ),
                for (final row in sessions)
                  TableRow(
                    children: [
                      _BodyCell(Text(row.code, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))),
                      _BodyCell(Text(row.window)),
                      _BodyCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.supervisor.isEmpty ? '—' : row.supervisor),
                            if (row.operators.isNotEmpty)
                              Text(row.operators, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      _BodyCell(Text(row.liters ?? '—')),
                      _BodyCell(Text(row.revenue ?? '—')),
                      _BodyCell(
                        Text(
                          row.varianceLabel ?? '—',
                          key: Key('dashboard-variance-${row.id}'),
                          style: TextStyle(color: _varianceColor(row.varianceLabel), fontWeight: FontWeight.w700),
                        ),
                      ),
                      _BodyCell(Text(row.statusLabel)),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: child,
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
    final scale = _niceScale(peak);
    const ticks = [1.0, 0.75, 0.5, 0.25, 0.0];
    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final tick in ticks)
                  Text(
                    _axisLabel(scale * tick),
                    style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
                  ),
                const SizedBox(height: 18),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var index = 0; index < ticks.length; index++)
                              Container(height: 1, color: const Color(0xFFC5C6CF)),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final day in days)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _Bar(
                                        amount: _money(day.morning),
                                        scale: scale,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: _Bar(
                                        amount: _money(day.evening),
                                        scale: scale,
                                        color: const Color(0xFFFFB693),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final day in days)
                      Expanded(
                        child: Text(
                          day.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _money(String raw) => double.tryParse(raw) ?? 0;

  double _niceScale(double peak) {
    if (peak <= 1) {
      return 1;
    }
    final magnitude = _pow10((peak).toString().split('.').first.length - 1);
    final step = magnitude / 2;
    final scaled = (peak / step).ceil() * step;
    return scaled < peak ? scaled + step : scaled;
  }

  double _pow10(int exponent) {
    var value = 1.0;
    for (var index = 0; index < exponent; index++) {
      value *= 10;
    }
    return value;
  }

  String _axisLabel(double value) {
    if (value >= 1000) {
      final compact = value / 1000;
      final text = compact == compact.roundToDouble() ? compact.toStringAsFixed(0) : compact.toStringAsFixed(1);
      return '$text ألف';
    }
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.amount, required this.scale, required this.color});

  final double amount;
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final factor = amount <= 0 ? 0.0 : (amount / scale).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final plot = (constraints.maxHeight - 16).clamp(0.0, constraints.maxHeight);
        final height = plot * factor;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (amount > 0)
              Text(
                _axisAmount(amount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: AppColors.onSurfaceVariant),
              ),
            const SizedBox(height: 2),
            Container(
              height: height < 2 && amount > 0 ? 2 : height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ],
        );
      },
    );
  }

  String _axisAmount(double value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}أ';
    }
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(0);
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
          Row(
            children: [
              Expanded(
                child: Text('${tank.productName} - ${tank.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(
                '${_wholeLiters(tank.currentLiters)} / ${_wholeLiters(tank.capacityLiters)} لتر',
                style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: (tank.percent / 100).clamp(0, 1),
              color: _tankFill(tank.percent),
              backgroundColor: const Color(0xFFDEE8FF),
            ),
          ),
        ],
      ),
    );
  }
}

String _wholeLiters(String raw) {
  final trimmed = raw.endsWith('.000') ? raw.substring(0, raw.length - 4) : raw;
  return groupThousands(trimmed.isEmpty ? '0' : trimmed);
}

Color _tankFill(int percent) {
  if (percent <= 15) {
    return AppColors.error;
  }
  if (percent < 40) {
    return const Color(0xFFFFB693);
  }
  if (percent < 75) {
    return AppColors.success;
  }
  return AppColors.primary;
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
