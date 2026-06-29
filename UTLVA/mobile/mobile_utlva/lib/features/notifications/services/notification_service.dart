import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../features/auth/services/auth_service.dart';
import '../models/app_notification.dart';
import '../models/notification_preference.dart';

class NotificationService {
  final AuthService _auth = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String get _base => '${AppConfig.baseUrl}/api/notifications';

  /// Returns the last 50 notifications for the current user.
  Future<List<AppNotification>> getNotifications() async {
    final r = await http
        .get(Uri.parse('$_base/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      final list = data is List ? data : (data['results'] ?? data);
      return (list as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load notifications: ${r.statusCode}');
  }

  /// Returns the number of unread notifications.
  Future<int> getUnreadCount() async {
    try {
      final r = await http
          .get(Uri.parse('$_base/unread-count/'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        return (jsonDecode(r.body)['count'] as int?) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Mark a single notification as read.
  Future<void> markRead(int id) async {
    await http
        .post(Uri.parse('$_base/$id/mark-read/'), headers: await _headers())
        .timeout(const Duration(seconds: 10));
  }

  /// Mark all notifications as read.
  Future<int> markAllRead() async {
    final r = await http
        .post(Uri.parse('$_base/mark-all-read/'), headers: await _headers())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 200) {
      return (jsonDecode(r.body)['marked'] as int?) ?? 0;
    }
    return 0;
  }

  // ── FR-50: Notification preferences ─────────────────────────────────────────

  Future<NotificationPreference> getPreferences() async {
    final r = await http
        .get(Uri.parse('$_base/preferences/'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      return NotificationPreference.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to load preferences: ${r.statusCode}');
  }

  Future<NotificationPreference> updatePreferences(
      NotificationPreference prefs) async {
    final r = await http
        .patch(
          Uri.parse('$_base/preferences/'),
          headers: await _headers(),
          body: jsonEncode(prefs.toJson()),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      return NotificationPreference.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>);
    }
    throw Exception(jsonDecode(r.body).toString());
  }

  // ── Lecturer triggers student notifications after an emergency session is approved.
  Future<Map<String, dynamic>> notifyStudents(int emergencySessionId) async {
    final r = await http
        .post(
          Uri.parse(
              '${AppConfig.baseUrl}/api/sessions/emergency/$emergencySessionId/notify-students/'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 20));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}
