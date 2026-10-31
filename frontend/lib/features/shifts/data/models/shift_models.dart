class AssignedNozzle {
  const AssignedNozzle({
    required this.id,
    required this.code,
    required this.label,
    required this.pumpCode,
    required this.productName,
    required this.currentMeter,
    required this.unitPrice,
    required this.selectable,
  });

  final String id;
  final String code;
  final String label;
  final String pumpCode;
  final String productName;
  final String currentMeter;
  final String? unitPrice;
  final bool selectable;

  factory AssignedNozzle.fromJson(Map<String, dynamic> json) {
    return AssignedNozzle(
      id: json['nozzle_id'] as String,
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      pumpCode: json['pump_code'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      currentMeter: json['current_meter'] as String? ?? '0.000',
      unitPrice: json['unit_price'] as String?,
      selectable: json['selectable'] as bool? ?? false,
    );
  }
}

class DutyLine {
  const DutyLine({
    required this.nozzleId,
    required this.nozzleCode,
    required this.label,
    required this.pumpCode,
    required this.productName,
    required this.openingMeter,
    required this.closingMeter,
    required this.unitPrice,
    required this.liters,
    required this.lineAmount,
  });

  final String nozzleId;
  final String nozzleCode;
  final String label;
  final String pumpCode;
  final String productName;
  final String openingMeter;
  final String? closingMeter;
  final String unitPrice;
  final String? liters;
  final String? lineAmount;

  factory DutyLine.fromJson(Map<String, dynamic> json) {
    return DutyLine(
      nozzleId: json['nozzle_id'] as String,
      nozzleCode: json['nozzle_code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      pumpCode: json['pump_code'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      openingMeter: json['opening_meter'] as String? ?? '0.000',
      closingMeter: json['closing_meter'] as String?,
      unitPrice: json['unit_price'] as String? ?? '0.000',
      liters: json['liters'] as String?,
      lineAmount: json['line_amount'] as String?,
    );
  }
}

class DutyRecord {
  const DutyRecord({
    required this.id,
    required this.sessionId,
    required this.fullName,
    required this.employeeCode,
    required this.status,
    required this.statusLabel,
    required this.openedAt,
    required this.liters,
    required this.expectedCash,
    required this.cashHanded,
    required this.variance,
    required this.varianceKind,
    required this.varianceLabel,
    required this.approvedByName,
    required this.rejectReason,
    required this.businessDate,
    required this.lines,
  });

  final String id;
  final String sessionId;
  final String fullName;
  final String employeeCode;
  final String status;
  final String statusLabel;
  final String? openedAt;
  final String? liters;
  final String? expectedCash;
  final String? cashHanded;
  final String? variance;
  final String? varianceKind;
  final String? varianceLabel;
  final String? approvedByName;
  final String? rejectReason;
  final String businessDate;
  final List<DutyLine> lines;

  bool get canClose => status == 'open' || status == 'rejected';

  factory DutyRecord.fromJson(Map<String, dynamic> json) {
    final raw = json['lines'] as List<dynamic>? ?? const [];
    return DutyRecord(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      employeeCode: json['employee_code'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusLabel: json['status_label'] as String? ?? '',
      openedAt: json['opened_at'] as String?,
      liters: json['liters'] as String?,
      expectedCash: json['expected_cash'] as String?,
      cashHanded: json['cash_handed'] as String?,
      variance: json['variance'] as String?,
      varianceKind: json['variance_kind'] as String?,
      varianceLabel: json['variance_label'] as String?,
      approvedByName: json['approved_by_name'] as String?,
      rejectReason: json['reject_reason'] as String?,
      businessDate: json['business_date'] as String? ?? '',
      lines: raw.map((item) => DutyLine.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class ShiftLogRow {
  const ShiftLogRow({
    required this.id,
    required this.code,
    required this.businessDate,
    required this.window,
    required this.supervisor,
    required this.statusLabel,
    required this.liters,
    required this.revenue,
    required this.varianceLabel,
  });

  final String id;
  final String code;
  final String businessDate;
  final String window;
  final String supervisor;
  final String statusLabel;
  final String? liters;
  final String? revenue;
  final String? varianceLabel;

  factory ShiftLogRow.fromJson(Map<String, dynamic> json) {
    return ShiftLogRow(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      businessDate: json['business_date'] as String? ?? '',
      window: json['window'] as String? ?? '',
      supervisor: json['supervisor'] as String? ?? '',
      statusLabel: json['status_label'] as String? ?? '',
      liters: json['liters'] as String?,
      revenue: json['revenue'] as String?,
      varianceLabel: json['variance_label'] as String?,
    );
  }
}
