import 'package:flutter/material.dart';
import 'package:frontend/core/di/injection.dart';
import 'package:frontend/core/theming/app_colors.dart';
import 'package:frontend/features/attendance/data/models/attendance_models.dart';
import 'package:frontend/features/attendance/data/repos/attendance_repository.dart';

class ShiftDaySchedulePanel extends StatefulWidget {
  const ShiftDaySchedulePanel({super.key});

  @override
  State<ShiftDaySchedulePanel> createState() => _ShiftDaySchedulePanelState();
}

class _ShiftDaySchedulePanelState extends State<ShiftDaySchedulePanel> {
  List<ShiftScheduleDay> _days = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = DateTime.now();
      final end = today.add(const Duration(days: 6));
      final from = _iso(today);
      final to = _iso(end);
      final days = await getIt<AttendanceRepository>().fetchSchedule(dateFrom: from, dateTo: to);
      if (!mounted) {
        return;
      }
      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _toggle(ShiftScheduleSlot slot, String date, bool active) async {
    try {
      await getIt<AttendanceRepository>().setSessionAvailability(
        templateId: slot.templateId,
        businessDate: date,
        active: active,
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تفعيل الورديات حسب اليوم (7 أيام)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'عطّل وردية ليوم محدد (مثل غداً) دون حذف القالب من الإعدادات.',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
            for (final day in _days) ...[
              Text(day.date, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
              const SizedBox(height: 6),
              for (final slot in day.templates)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(slot.templateName),
                  subtitle: slot.sessionStatus == 'cancelled' ? const Text('معطّلة لهذا اليوم') : null,
                  value: slot.enabled,
                  onChanged: (value) => _toggle(slot, day.date, value),
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
