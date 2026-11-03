import 'package:flutter/material.dart';
import 'package:frontend/core/layout/responsive_layout.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/core/time/system_clock.dart';

class AttendanceDateBar extends StatelessWidget {
  const AttendanceDateBar({
    super.key,
    required this.date,
    required this.serverToday,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final String date;
  final String serverToday;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final isToday = date == serverToday;
    final clockHint = SystemClock.localTime;
    final tz = SystemClock.timezone;
    final subtitle = clockHint == null
        ? 'التاريخ والوقت من ساعة النظام المركزية'
        : 'ساعة النظام: $clockHint${tz == null ? '' : ' ($tz)'}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520;
          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'اليوم السابق',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              OutlinedButton.icon(
                key: const Key('attendance-date-pick'),
                onPressed: onPick,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(isToday ? 'اليوم — $date' : date),
              ),
              IconButton(
                tooltip: 'اليوم التالي',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تاريخ العرض',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 8),
                Align(alignment: Alignment.center, child: controls),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تاريخ العرض',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              controls,
            ],
          );
        },
      ),
    );
  }
}

Future<void> pickAttendanceDate(
  BuildContext context, {
  required String current,
  required String serverToday,
  required ValueChanged<String> onSelected,
}) async {
  final initial = DateTime.tryParse(current) ?? DateTime.tryParse(serverToday) ?? SystemClock.nowUtc();
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.tryParse(serverToday) ?? initial,
  );
  if (picked == null || !context.mounted) {
    return;
  }
  final month = picked.month.toString().padLeft(2, '0');
  final day = picked.day.toString().padLeft(2, '0');
  onSelected('${picked.year}-$month-$day');
}
