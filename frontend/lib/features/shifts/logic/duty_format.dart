import 'package:frontend/features/shifts/data/models/shift_models.dart';

/// Human-readable shift hours for history tables (prefers server labels).
String dutyWorkHoursLabel(DutyRecord duty) {
  final labeled = duty.workHoursLabel?.trim();
  if (labeled != null && labeled.isNotEmpty) {
    return labeled;
  }
  final opened = _parseInstant(duty.openedAt);
  final closed = _parseInstant(duty.submittedAt) ?? _parseInstant(duty.approvedAt);
  if (opened == null) {
    return '—';
  }
  final start = _clock(opened.toLocal());
  if (closed == null) {
    return 'من $start';
  }
  final end = _clock(closed.toLocal());
  final delta = closed.difference(opened);
  if (delta.isNegative) {
    return '$start – $end';
  }
  final hours = delta.inHours;
  final minutes = delta.inMinutes.remainder(60);
  final duration = hours > 0 ? '${hours}س ${minutes}د' : '${minutes}د';
  return '$start – $end · $duration';
}

DateTime? _parseInstant(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw.trim());
}

String _clock(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
