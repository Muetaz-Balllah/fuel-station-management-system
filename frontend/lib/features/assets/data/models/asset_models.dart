class AssetProduct {
  const AssetProduct({required this.id, required this.code, required this.nameAr});

  final String id;
  final String code;
  final String nameAr;

  factory AssetProduct.fromJson(Map<String, dynamic> json) {
    return AssetProduct(
      id: json['id'] as String,
      code: json['code'] as String,
      nameAr: json['name_ar'] as String,
    );
  }
}

class AssetNozzle {
  const AssetNozzle({
    required this.id,
    required this.code,
    required this.label,
    required this.status,
    required this.statusLabel,
    required this.currentMeter,
  });

  final String id;
  final String code;
  final String label;
  final String status;
  final String statusLabel;
  final String currentMeter;

  factory AssetNozzle.fromJson(Map<String, dynamic> json) {
    return AssetNozzle(
      id: json['id'] as String,
      code: json['code'] as String,
      label: json['label'] as String,
      status: json['status'] as String,
      statusLabel: json['status_label'] as String,
      currentMeter: json['current_meter'] as String,
    );
  }
}

class AssetTank {
  const AssetTank({
    required this.id,
    required this.code,
    required this.name,
    required this.productId,
    required this.productName,
    required this.capacityLiters,
    required this.currentLiters,
    required this.percent,
    required this.cardBandLabel,
    required this.lastReceiptLabel,
    required this.todayLiters,
  });

  final String id;
  final String code;
  final String name;
  final String productId;
  final String productName;
  final String capacityLiters;
  final String currentLiters;
  final int percent;
  final String cardBandLabel;
  final String? lastReceiptLabel;
  final String todayLiters;

  factory AssetTank.fromJson(Map<String, dynamic> json) {
    return AssetTank(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? '',
      capacityLiters: json['capacity_liters'] as String,
      currentLiters: json['current_liters'] as String,
      percent: json['percent'] as int? ?? 0,
      cardBandLabel: (json['card_band_label'] ?? json['level_band_label'] ?? '') as String,
      lastReceiptLabel: json['last_receipt_label'] as String?,
      todayLiters: json['today_liters'] as String? ?? '0.000',
    );
  }
}

class AssetPump {
  const AssetPump({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.statusLabel,
    required this.tankId,
    required this.tankCode,
  });

  final String id;
  final String code;
  final String name;
  final String status;
  final String statusLabel;
  final String tankId;
  final String tankCode;

  factory AssetPump.fromJson(Map<String, dynamic> json) {
    return AssetPump(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      statusLabel: json['status_label'] as String,
      tankId: json['tank_id'] as String,
      tankCode: json['tank_code'] as String? ?? '',
    );
  }
}

class PumpCardData {
  const PumpCardData({required this.pump, required this.tank, required this.nozzles});

  final AssetPump pump;
  final AssetTank tank;
  final List<AssetNozzle> nozzles;

  factory PumpCardData.fromJson(Map<String, dynamic> json) {
    final raw = json['nozzles'] as List<dynamic>? ?? const [];
    return PumpCardData(
      pump: AssetPump.fromJson(json['pump'] as Map<String, dynamic>),
      tank: AssetTank.fromJson(json['tank'] as Map<String, dynamic>),
      nozzles: raw.map((item) => AssetNozzle.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class InventoryEvent {
  const InventoryEvent({
    required this.id,
    required this.createdAt,
    required this.path,
    required this.movementLabel,
    required this.litersDelta,
    required this.actorName,
    required this.productId,
  });

  final String id;
  final String createdAt;
  final String path;
  final String movementLabel;
  final String litersDelta;
  final String actorName;
  final String? productId;

  factory InventoryEvent.fromJson(Map<String, dynamic> json) {
    return InventoryEvent(
      id: json['id'] as String,
      createdAt: json['created_at']?.toString() ?? '',
      path: json['path'] as String? ?? '',
      movementLabel: json['movement_label'] as String? ?? '',
      litersDelta: json['liters_delta'] as String? ?? '0.000',
      actorName: json['actor_name'] as String? ?? '',
      productId: json['product_id'] as String?,
    );
  }
}

class AssetBoard {
  const AssetBoard({
    required this.products,
    required this.cards,
    required this.freeTanks,
  });

  final List<AssetProduct> products;
  final List<PumpCardData> cards;
  final List<AssetTank> freeTanks;

  factory AssetBoard.fromJson(Map<String, dynamic> json) {
    List<T> read<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = json[key] as List<dynamic>? ?? const [];
      return raw.map((item) => parse(Map<String, dynamic>.from(item as Map))).toList();
    }

    return AssetBoard(
      products: read('products', AssetProduct.fromJson),
      cards: read('cards', PumpCardData.fromJson),
      freeTanks: read('free_tanks', AssetTank.fromJson),
    );
  }
}

String formatQty(String raw) {
  final trimmed = raw.trim();
  final negative = trimmed.startsWith('-');
  final text = negative ? trimmed.substring(1) : trimmed;
  final parts = text.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  final digits = whole.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  final fraction = parts.length > 1 ? parts[1].replaceFirst(RegExp(r'0+$'), '') : '';
  final shown = fraction.isEmpty ? buffer.toString() : '${buffer.toString()}.$fraction';
  return negative ? '-$shown' : shown;
}
