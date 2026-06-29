/// Data model for an audit log entry from /api/auth/audit-logs/.
class AuditLogEntry {
  final int id;
  final int? userId;
  final String userName;
  final String? userEmail;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? beforeState;
  final Map<String, dynamic>? afterState;
  final String? ipAddress;
  final String timestamp;
  final Map<String, dynamic>? extra;

  const AuditLogEntry({
    required this.id,
    this.userId,
    required this.userName,
    this.userEmail,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.beforeState,
    this.afterState,
    this.ipAddress,
    required this.timestamp,
    this.extra,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) => AuditLogEntry(
        id: j['id'],
        userId: j['user'],
        userName: j['user_name'] ?? 'System',
        userEmail: j['user_email'],
        action: j['action'] ?? '',
        entityType: j['entity_type'] ?? '',
        entityId: j['entity_id'] ?? '',
        beforeState: j['before_state'] as Map<String, dynamic>?,
        afterState: j['after_state'] as Map<String, dynamic>?,
        ipAddress: j['ip_address'],
        timestamp: j['timestamp'] ?? '',
        extra: j['extra'] as Map<String, dynamic>?,
      );

  String get actionLabel => action.replaceAll('_', ' ');

  String get formattedTime {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp;
    }
  }
}
