class StationProfile {
  const StationProfile({
    required this.id,
    required this.code,
    required this.name,
    required this.licenseNumber,
    required this.licenseExpiresOn,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.logoUrl,
  });

  final String id;
  final String code;
  final String name;
  final String licenseNumber;
  final String licenseExpiresOn;
  final double? latitude;
  final double? longitude;
  final String timezone;
  final String? logoUrl;

  factory StationProfile.fromJson(Map<String, dynamic> json) {
    return StationProfile(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      licenseNumber: json['license_number'] as String,
      licenseExpiresOn: json['license_expires_on'].toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      timezone: (json['timezone'] as String?) ?? 'Africa/Tripoli',
      logoUrl: json['logo_url'] as String?,
    );
  }
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.employeeCode,
    required this.fullName,
    required this.username,
    required this.email,
    required this.jobTitle,
    required this.roleCode,
    required this.roleNameAr,
    required this.isActive,
    required this.isMaintenance,
    required this.lastLoginAt,
    this.photoUrl,
  });

  final String id;
  final String employeeCode;
  final String fullName;
  final String username;
  final String? email;
  final String jobTitle;
  final String roleCode;
  final String roleNameAr;
  final bool isActive;
  final bool isMaintenance;
  final String? lastLoginAt;
  final String? photoUrl;

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as String,
      employeeCode: json['employee_code'] as String,
      fullName: json['full_name'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      jobTitle: (json['job_title'] as String?) ?? '',
      roleCode: json['role_code'] as String,
      roleNameAr: json['role_name_ar'] as String,
      isActive: json['is_active'] as bool? ?? true,
      isMaintenance: json['is_maintenance'] as bool? ?? false,
      lastLoginAt: json['last_login_at']?.toString(),
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class RoleGrant {
  const RoleGrant({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.permissions,
  });

  final String id;
  final String code;
  final String nameAr;
  final List<String> permissions;

  factory RoleGrant.fromJson(Map<String, dynamic> json) {
    final raw = json['permissions'];
    return RoleGrant(
      id: json['id'] as String,
      code: json['code'] as String,
      nameAr: json['name_ar'] as String,
      permissions: raw is List ? raw.map((item) => item.toString()).toList() : const [],
    );
  }
}

class FuelProductItem {
  const FuelProductItem({
    required this.id,
    required this.code,
    required this.nameAr,
    required this.isActive,
    required this.activePrice,
  });

  final String id;
  final String code;
  final String nameAr;
  final bool isActive;
  final String? activePrice;

  factory FuelProductItem.fromJson(Map<String, dynamic> json) {
    return FuelProductItem(
      id: json['id'] as String,
      code: json['code'] as String,
      nameAr: json['name_ar'] as String,
      isActive: json['is_active'] as bool? ?? true,
      activePrice: json['active_price'] as String?,
    );
  }
}

class ShiftTemplateItem {
  const ShiftTemplateItem({
    required this.id,
    required this.nameAr,
    required this.startsAt,
    required this.endsAt,
    required this.graceMinutes,
    required this.isActive,
    required this.crossesMidnight,
    required this.businessDate,
  });

  final String id;
  final String nameAr;
  final String startsAt;
  final String endsAt;
  final int graceMinutes;
  final bool isActive;
  final bool crossesMidnight;
  final String businessDate;

  factory ShiftTemplateItem.fromJson(Map<String, dynamic> json) {
    return ShiftTemplateItem(
      id: json['id'] as String,
      nameAr: json['name_ar'] as String,
      startsAt: json['starts_at'] as String,
      endsAt: json['ends_at'] as String,
      graceMinutes: json['grace_minutes'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      crossesMidnight: json['crosses_midnight'] as bool? ?? false,
      businessDate: json['business_date'] as String? ?? '',
    );
  }
}

class ShiftDraft {
  const ShiftDraft({
    required this.nameAr,
    required this.startsAt,
    required this.endsAt,
    required this.graceMinutes,
    required this.isActive,
  });

  final String nameAr;
  final String startsAt;
  final String endsAt;
  final int graceMinutes;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'name_ar': nameAr,
        'starts_at': startsAt,
        'ends_at': endsAt,
        'grace_minutes': graceMinutes,
        'is_active': isActive,
      };
}

const permissionLabels = <String, String>{
  'dashboard.view': 'عرض لوحة القيادة',
  'assets.manage': 'إدارة الخزانات والمضخات',
  'supply.manage': 'إدارة التوريدات',
  'supply.receive': 'استلام التوريدات',
  'attendance.manage': 'إدارة الحضور',
  'shifts.operate': 'تشغيل الوردية',
  'shifts.approve': 'اعتماد الورديات',
  'shifts.view_all': 'عرض كل الورديات',
  'prices.manage': 'إدارة الأسعار',
  'settings.manage': 'تعديل إعدادات النظام',
  'users.manage': 'إدارة المستخدمين',
  'reports.export': 'تصدير التقارير',
  'meter.override': 'تجاوز قراءة العداد',
  'inventory.adjust': 'تسوية المخزون',
};
