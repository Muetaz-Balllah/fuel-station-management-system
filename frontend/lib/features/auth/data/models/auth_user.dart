class AuthUser {
  const AuthUser({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.stationCode,
    required this.employeeCode,
    required this.fullName,
    required this.username,
    required this.email,
    required this.jobTitle,
    required this.roleCode,
    required this.roleNameAr,
    required this.permissions,
    required this.isMaintenance,
    required this.isActive,
    this.photoUrl,
  });

  final String id;
  final String stationId;
  final String stationName;
  final String stationCode;
  final String employeeCode;
  final String fullName;
  final String username;
  final String? email;
  final String jobTitle;
  final String roleCode;
  final String roleNameAr;
  final List<String> permissions;
  final bool isMaintenance;
  final bool isActive;
  final String? photoUrl;

  bool get isOperator => roleCode == 'operator';

  bool get isManager => roleCode == 'station_manager' || roleCode == 'system_admin';

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '؟';
    }
    String first(String value) => String.fromCharCode(value.runes.first);
    if (parts.length == 1) {
      return first(parts.first);
    }
    return '${first(parts.first)}.${first(parts[1])}';
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['permissions'];
    return AuthUser(
      id: json['id'] as String,
      stationId: json['station_id'] as String,
      stationName: json['station_name'] as String,
      stationCode: json['station_code'] as String,
      employeeCode: json['employee_code'] as String,
      fullName: json['full_name'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      jobTitle: (json['job_title'] as String?) ?? '',
      roleCode: json['role_code'] as String,
      roleNameAr: json['role_name_ar'] as String,
      permissions: rawPermissions is List
          ? rawPermissions.map((item) => item.toString()).toList()
          : const [],
      isMaintenance: json['is_maintenance'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      photoUrl: json['photo_url'] as String?,
    );
  }
}
