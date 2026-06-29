/// Data model for a user record returned by /api/auth/users/.
/// Used by the user management screen — not a UI widget.
class AdminUser {
  final int id;
  final String email;
  final String fullName;
  final String role;
  final String roleDisplay;
  final String phoneNumber;
  final bool isActive;
  final String dateJoined;
  final String? lastLogin;

  const AdminUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.roleDisplay,
    required this.phoneNumber,
    required this.isActive,
    required this.dateJoined,
    this.lastLogin,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'],
        email: j['email'] ?? '',
        fullName: j['full_name'] ?? '',
        role: j['role'] ?? '',
        roleDisplay: j['role_display'] ?? j['role'] ?? '',
        phoneNumber: j['phone_number'] ?? '',
        isActive: j['is_active'] ?? true,
        dateJoined: j['date_joined'] ?? '',
        lastLogin: j['last_login'],
      );

  Map<String, dynamic> toUpdateJson() => {
        'full_name': fullName,
        'role': role,
        'phone_number': phoneNumber,
        'is_active': isActive,
      };

  AdminUser copyWith({
    String? fullName,
    String? role,
    String? roleDisplay,
    String? phoneNumber,
    bool? isActive,
  }) =>
      AdminUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        roleDisplay: roleDisplay ?? this.roleDisplay,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        isActive: isActive ?? this.isActive,
        dateJoined: dateJoined,
        lastLogin: lastLogin,
      );
}

/// Aggregate counts returned by /api/auth/users/stats/
class UserStats {
  final int total;
  final int active;
  final int inactive;
  final Map<String, int> byRole;

  const UserStats({
    required this.total,
    required this.active,
    required this.inactive,
    required this.byRole,
  });

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        total: j['total'] ?? 0,
        active: j['active'] ?? 0,
        inactive: j['inactive'] ?? 0,
        byRole: Map<String, int>.from(
          (j['by_role'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num).toInt())),
        ),
      );
}
