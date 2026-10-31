import 'package:frontend/features/shifts/data/models/shift_models.dart';

class DashboardAlert {
  const DashboardAlert({
    required this.tankName,
    required this.productName,
    required this.percent,
    required this.message,
  });

  final String tankName;
  final String productName;
  final int percent;
  final String message;

  factory DashboardAlert.fromJson(Map<String, dynamic> json) {
    return DashboardAlert(
      tankName: json['tank_name'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      percent: json['percent'] as int? ?? 0,
      message: json['message'] as String? ?? '',
    );
  }
}

class DashboardWeekDay {
  const DashboardWeekDay({
    required this.date,
    required this.label,
    required this.morning,
    required this.evening,
  });

  final String date;
  final String label;
  final String morning;
  final String evening;

  factory DashboardWeekDay.fromJson(Map<String, dynamic> json) {
    return DashboardWeekDay(
      date: json['date'] as String? ?? '',
      label: json['label'] as String? ?? '',
      morning: json['morning'] as String? ?? '0.00',
      evening: json['evening'] as String? ?? '0.00',
    );
  }
}

class DashboardTank {
  const DashboardTank({
    required this.name,
    required this.productName,
    required this.percent,
    required this.currentLiters,
    required this.capacityLiters,
  });

  final String name;
  final String productName;
  final int percent;
  final String currentLiters;
  final String capacityLiters;

  factory DashboardTank.fromJson(Map<String, dynamic> json) {
    return DashboardTank(
      name: json['name'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      percent: json['percent'] as int? ?? 0,
      currentLiters: json['current_liters'] as String? ?? '0.000',
      capacityLiters: json['capacity_liters'] as String? ?? '0.000',
    );
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.date,
    required this.revenue,
    required this.liters,
    required this.inventoryLiters,
    required this.staffOnDuty,
    required this.alert,
    required this.week,
    required this.tanks,
    required this.sessions,
    required this.licenseExpiresOn,
    required this.licenseDue,
  });

  final String date;
  final String revenue;
  final String liters;
  final String inventoryLiters;
  final int staffOnDuty;
  final DashboardAlert? alert;
  final List<DashboardWeekDay> week;
  final List<DashboardTank> tanks;
  final List<ShiftLogRow> sessions;
  final String? licenseExpiresOn;
  final bool licenseDue;

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final week = json['week'] as List<dynamic>? ?? const [];
    final tanks = json['tanks'] as List<dynamic>? ?? const [];
    final sessions = json['sessions'] as List<dynamic>? ?? const [];
    final alert = json['alert'];
    return DashboardSnapshot(
      date: json['date'] as String? ?? '',
      revenue: json['revenue'] as String? ?? '0.00',
      liters: json['liters'] as String? ?? '0.000',
      inventoryLiters: json['inventory_liters'] as String? ?? '0.000',
      staffOnDuty: json['staff_on_duty'] as int? ?? 0,
      alert: alert is Map ? DashboardAlert.fromJson(Map<String, dynamic>.from(alert)) : null,
      week: week.map((item) => DashboardWeekDay.fromJson(item as Map<String, dynamic>)).toList(),
      tanks: tanks.map((item) => DashboardTank.fromJson(item as Map<String, dynamic>)).toList(),
      sessions: sessions.map((item) => ShiftLogRow.fromJson(item as Map<String, dynamic>)).toList(),
      licenseExpiresOn: json['license_expires_on'] as String?,
      licenseDue: json['license_due'] as bool? ?? false,
    );
  }
}

class StationNotice {
  const StationNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.readAt,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final String? readAt;

  bool get unread => readAt == null;

  factory StationNotice.fromJson(Map<String, dynamic> json) {
    return StationNotice(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      readAt: json['read_at'] as String?,
    );
  }
}

String dashboardCsv(List<ShiftLogRow> rows) {
  final lines = <String>['الرمز,الفترة,المشرف,اللترات,الإيراد,العجز,الحالة'];
  for (final row in rows) {
    lines.add(
      [
        row.code,
        row.window,
        row.supervisor,
        row.liters ?? '',
        row.revenue ?? '',
        row.varianceLabel ?? '',
        row.statusLabel,
      ].join(','),
    );
  }
  return lines.join('\n');
}
