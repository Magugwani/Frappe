import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';
import '../models/admin_user.dart';
import '../models/audit_log.dart';

class UserManagementService {
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String get _base => '${AppConfig.baseUrl}/api/auth';

  // ── Users ─────────────────────────────────────────────────────────────────

  Future<List<AdminUser>> getUsers({
    String? role,
    bool? isActive,
    String? search,
  }) async {
    final params = <String>[];
    if (role != null) params.add('role=$role');
    if (isActive != null) params.add('is_active=$isActive');
    if (search != null && search.isNotEmpty) params.add('search=$search');
    final q = params.isNotEmpty ? '?${params.join('&')}' : '';
    final r = await http
        .get(Uri.parse('$_base/users/$q'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load users: ${r.statusCode}');
  }

  Future<UserStats> getUserStats() async {
    final r = await http
        .get(Uri.parse('$_base/users/stats/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return UserStats.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception('Failed to load stats');
  }

  Future<AdminUser> createUser({
    required String email,
    required String fullName,
    required String role,
    required String password,
    String phoneNumber = '',
  }) async {
    final r = await http
        .post(
          Uri.parse('$_base/users/'),
          headers: await _headers(),
          body: jsonEncode({
            'email': email,
            'full_name': fullName,
            'role': role,
            'phone_number': phoneNumber,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 201) return AdminUser.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(jsonDecode(r.body).toString());
  }

  Future<AdminUser> updateUser(AdminUser user) async {
    final r = await http
        .patch(
          Uri.parse('$_base/users/${user.id}/'),
          headers: await _headers(),
          body: jsonEncode(user.toUpdateJson()),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return AdminUser.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(jsonDecode(r.body).toString());
  }

  /// Returns the response body which may include `needs_reassignment_count`
  /// (SRS §3.12) for lecturer deactivations.
  Future<Map<String, dynamic>> deactivateUser(int id) async {
    final r = await http
        .post(Uri.parse('$_base/users/$id/deactivate/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body).toString());
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> activateUser(int id) async {
    final r = await http
        .post(Uri.parse('$_base/users/$id/activate/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body).toString());
  }

  Future<void> deleteUser(int id) async {
    final r = await http
        .delete(Uri.parse('$_base/users/$id/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 204) throw Exception(jsonDecode(r.body).toString());
  }

  Future<Map<String, dynamic>> getSystemStats() async {
    final r = await http
        .get(Uri.parse('$_base/users/system_stats/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    throw Exception('Failed to load system stats: ${r.statusCode}');
  }

  Future<void> changePassword(int id, String newPassword) async {
    final r = await http
        .post(
          Uri.parse('$_base/users/$id/change_password/'),
          headers: await _headers(),
          body: jsonEncode({'password': newPassword}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body).toString());
  }

  // ── Audit logs ────────────────────────────────────────────────────────────

  Future<List<AuditLogEntry>> getAuditLogs({
    String? action,
    String? entityType,
    int? userId,
  }) async {
    final params = <String>[];
    if (action != null) params.add('action=$action');
    if (entityType != null) params.add('entity_type=$entityType');
    if (userId != null) params.add('user=$userId');
    final q = params.isNotEmpty ? '?${params.join('&')}' : '';
    final r = await http
        .get(Uri.parse('$_base/audit-logs/$q'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List).map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load audit logs: ${r.statusCode}');
  }
}
