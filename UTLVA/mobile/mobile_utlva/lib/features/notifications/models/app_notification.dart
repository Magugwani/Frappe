/// In-app notification record returned from GET /api/notifications/
class AppNotification {
  final int id;
  final String notificationType;
  final String typeDisplay;
  final String title;
  final String body;
  final String relatedObjectType;
  final String relatedObjectId;
  final int? senderId;
  final String? senderName;
  final bool isRead;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.notificationType,
    required this.typeDisplay,
    required this.title,
    required this.body,
    this.relatedObjectType = '',
    this.relatedObjectId = '',
    this.senderId,
    this.senderName,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        notificationType: j['notification_type'] as String? ?? '',
        typeDisplay: j['type_display'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        relatedObjectType: j['related_object_type'] as String? ?? '',
        relatedObjectId: j['related_object_id'] as String? ?? '',
        senderId: j['sender'] as int?,
        senderName: j['sender_name'] as String?,
        isRead: j['is_read'] as bool? ?? false,
        createdAt: j['created_at'] as String? ?? '',
      );

  bool get isEmergencyCreated => notificationType == 'EMERGENCY_CREATED';
  bool get isEmergencyApproved => notificationType == 'EMERGENCY_APPROVED';
  bool get isEmergencyRejected => notificationType == 'EMERGENCY_REJECTED';

  int? get relatedId {
    final id = int.tryParse(relatedObjectId);
    return id;
  }
}
