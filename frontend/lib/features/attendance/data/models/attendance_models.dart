class AttendanceAssignment {
  const AttendanceAssignment({
    this.nozzleId = '',
    required this.nozzleCode,
    required this.label,
    required this.pumpCode,
    required this.productName,
  });

  final String nozzleId;
  final String nozzleCode;
  final String label;
  final String pumpCode;
  final String productName;

  factory AttendanceAssignment.fromJson(Map<String, dynamic> json) {
    return AttendanceAssignment(
      nozzleId: json['nozzle_id'] as String? ?? '',
      nozzleCode: json['nozzle_code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      pumpCode: json['pump_code'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
    );
  }
}

class AttendanceRow {
  const AttendanceRow({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.jobTitle,
    required this.employeeCode,
    required this.status,
    required this.statusLabel,
    required this.note,
    required this.checkInLabel,
    required this.checkOutLabel,
    required this.assignments,
  });

  final String id;
  final String userId;
  final String fullName;
  final String jobTitle;
  final String employeeCode;
  final String status;
  final String statusLabel;
  final String? note;
  final String? checkInLabel;
  final String? checkOutLabel;
  final List<AttendanceAssignment> assignments;

  factory AttendanceRow.fromJson(Map<String, dynamic> json) {
    final raw = json['assignments'] as List<dynamic>? ?? const [];
    return AttendanceRow(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      jobTitle: json['job_title'] as String? ?? '',
      employeeCode: json['employee_code'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusLabel: json['status_label'] as String? ?? '',
      note: json['note'] as String?,
      checkInLabel: json['check_in_label'] as String?,
      checkOutLabel: json['check_out_label'] as String?,
      assignments: raw
          .map((item) => AttendanceAssignment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WeekDayStat {
  const WeekDayStat({required this.date, required this.label, required this.percent});

  final String date;
  final String label;
  final int? percent;

  factory WeekDayStat.fromJson(Map<String, dynamic> json) {
    return WeekDayStat(
      date: json['date'] as String,
      label: json['label'] as String,
      percent: json['percent'] as int?,
    );
  }
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.templateName,
    required this.showed,
    required this.total,
    required this.percent,
    required this.covered,
    required this.active,
    required this.lateCount,
    required this.week,
  });

  final String templateName;
  final int showed;
  final int total;
  final int percent;
  final int covered;
  final int active;
  final int lateCount;
  final List<WeekDayStat> week;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    final morning = json['morning'] as Map<String, dynamic>? ?? const {};
    final coverage = json['coverage'] as Map<String, dynamic>? ?? const {};
    final week = json['week'] as List<dynamic>? ?? const [];
    return AttendanceSummary(
      templateName: json['template_name'] as String? ?? '',
      showed: morning['showed'] as int? ?? 0,
      total: morning['total'] as int? ?? 0,
      percent: morning['percent'] as int? ?? 0,
      covered: coverage['covered'] as int? ?? 0,
      active: coverage['active'] as int? ?? 0,
      lateCount: json['late_count'] as int? ?? 0,
      week: week.map((item) => WeekDayStat.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class AttendanceUserOption {
  const AttendanceUserOption({
    required this.id,
    required this.fullName,
    required this.jobTitle,
    required this.employeeCode,
  });

  final String id;
  final String fullName;
  final String jobTitle;
  final String employeeCode;

  factory AttendanceUserOption.fromJson(Map<String, dynamic> json) {
    return AttendanceUserOption(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      jobTitle: json['job_title'] as String? ?? '',
      employeeCode: json['employee_code'] as String? ?? '',
    );
  }
}

class AttendanceNozzleOption {
  const AttendanceNozzleOption({
    required this.id,
    required this.code,
    required this.label,
    required this.pumpCode,
    required this.pumpStatus,
    required this.productName,
  });

  final String id;
  final String code;
  final String label;
  final String pumpCode;
  final String pumpStatus;
  final String productName;

  factory AttendanceNozzleOption.fromJson(Map<String, dynamic> json) {
    return AttendanceNozzleOption(
      id: json['id'] as String,
      code: json['code'] as String,
      label: json['label'] as String? ?? '',
      pumpCode: json['pump_code'] as String? ?? '',
      pumpStatus: json['pump_status'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
    );
  }
}

class AttendanceTemplateOption {
  const AttendanceTemplateOption({required this.id, required this.nameAr});

  final String id;
  final String nameAr;

  factory AttendanceTemplateOption.fromJson(Map<String, dynamic> json) {
    return AttendanceTemplateOption(id: json['id'] as String, nameAr: json['name_ar'] as String);
  }
}

String attendanceCsv(List<AttendanceRow> rows) {
  final buffer = StringBuffer()
    ..writeln('الاسم,المسمى,الرقم الوظيفي,المضخة,المسدس,الحضور,الانصراف,الحالة,ملاحظة');
  for (final row in rows) {
    final pumps = row.assignments.map((item) => item.pumpCode).join(' / ');
    final nozzles = row.assignments.map((item) => item.nozzleCode).join(' / ');
    buffer.writeln(
      [
        row.fullName,
        row.jobTitle,
        row.employeeCode,
        pumps,
        nozzles,
        row.checkInLabel ?? '',
        row.checkOutLabel ?? '',
        row.statusLabel,
        row.note ?? '',
      ].map(_csvCell).join(','),
    );
  }
  return buffer.toString();
}

String _csvCell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
