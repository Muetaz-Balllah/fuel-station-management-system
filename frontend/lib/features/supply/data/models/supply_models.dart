class SupplierRecord {
  const SupplierRecord({
    required this.id,
    required this.name,
    required this.headquarters,
    required this.contactName,
    required this.phone,
    required this.maxDailyLiters,
    required this.isActive,
    required this.reliability,
  });

  final String id;
  final String name;
  final String headquarters;
  final String contactName;
  final String phone;
  final String maxDailyLiters;
  final bool isActive;
  final int? reliability;

  factory SupplierRecord.fromJson(Map<String, dynamic> json) {
    return SupplierRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      headquarters: json['headquarters'] as String? ?? '',
      contactName: json['contact_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      maxDailyLiters: json['max_daily_liters'] as String? ?? '0.000',
      isActive: json['is_active'] as bool? ?? true,
      reliability: json['reliability'] as int?,
    );
  }
}

class SupplyOrderRecord {
  const SupplyOrderRecord({
    required this.id,
    required this.code,
    required this.supplierId,
    required this.supplierName,
    required this.tankId,
    required this.tankName,
    required this.productId,
    required this.productName,
    required this.orderedLiters,
    required this.status,
    required this.statusLabel,
    required this.expectedOn,
  });

  final String id;
  final String code;
  final String supplierId;
  final String supplierName;
  final String tankId;
  final String tankName;
  final String productId;
  final String productName;
  final String orderedLiters;
  final String status;
  final String statusLabel;
  final String expectedOn;

  factory SupplyOrderRecord.fromJson(Map<String, dynamic> json) {
    return SupplyOrderRecord(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      supplierId: json['supplier_id'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      tankId: json['tank_id'] as String? ?? '',
      tankName: json['tank_name'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      orderedLiters: json['ordered_liters'] as String? ?? '0.000',
      status: json['status'] as String? ?? '',
      statusLabel: json['status_label'] as String? ?? '',
      expectedOn: json['expected_on'] as String? ?? '',
    );
  }
}

class SupplyTankOption {
  const SupplyTankOption({
    required this.id,
    required this.name,
    required this.productId,
    required this.productName,
  });

  final String id;
  final String name;
  final String productId;
  final String productName;

  factory SupplyTankOption.fromJson(Map<String, dynamic> json) {
    return SupplyTankOption(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
    );
  }
}

class SupplyProductOption {
  const SupplyProductOption({required this.id, required this.name});

  final String id;
  final String name;

  factory SupplyProductOption.fromJson(Map<String, dynamic> json) {
    return SupplyProductOption(
      id: json['id'] as String,
      name: json['name_ar'] as String? ?? '',
    );
  }
}

class SupplyWeekDay {
  const SupplyWeekDay({required this.date, required this.label, required this.liters});

  final String date;
  final String label;
  final String liters;

  factory SupplyWeekDay.fromJson(Map<String, dynamic> json) {
    return SupplyWeekDay(
      date: json['date'] as String? ?? '',
      label: json['label'] as String? ?? '',
      liters: json['liters'] as String? ?? '0.000',
    );
  }
}
