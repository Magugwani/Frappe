class AuthUser {
  final String userId;
  final String email;
  final String fullName;
  final String role;

  const AuthUser({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      userId: json['user_id']?.toString() ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
      role: json['role'] ?? '',
    );
  }

  bool get isSystemAdmin => role == 'SYSTEM_ADMIN';
  bool get isCoordinator => role == 'COORDINATOR';
  bool get isLecturer => role == 'LECTURER';
  bool get isStudent => role == 'STUDENT';

  String get displayRole {
    switch (role) {
      case 'SYSTEM_ADMIN':
        return 'System Administrator';
      case 'COORDINATOR':
        return 'Timetable Coordinator';
      case 'LECTURER':
        return 'Lecturer';
      case 'STUDENT':
        return 'Student';
      default:
        return role;
    }
  }
}
