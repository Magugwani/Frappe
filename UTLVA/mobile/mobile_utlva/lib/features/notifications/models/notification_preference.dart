/// FR-50 — User notification preferences returned from GET /api/notifications/preferences/
class NotificationPreference {
  // Channels
  final bool inAppEnabled;
  final bool emailEnabled;
  final bool smsEnabled;
  final bool pushEnabled;
  final String fcmToken;

  // Event types
  final bool notifyTimetableChanges;
  final bool notifyVenueChanges;
  final bool notifyEmergencySessions;
  final bool notifySessionConfirmation;
  final bool notifySessionPostponement;
  final bool notifySessionCancellation;

  final String updatedAt;

  const NotificationPreference({
    this.inAppEnabled = true,
    this.emailEnabled = true,
    this.smsEnabled = false,
    this.pushEnabled = true,
    this.fcmToken = '',
    this.notifyTimetableChanges = true,
    this.notifyVenueChanges = true,
    this.notifyEmergencySessions = true,
    this.notifySessionConfirmation = true,
    this.notifySessionPostponement = true,
    this.notifySessionCancellation = true,
    this.updatedAt = '',
  });

  factory NotificationPreference.fromJson(Map<String, dynamic> j) =>
      NotificationPreference(
        inAppEnabled: j['in_app_enabled'] as bool? ?? true,
        emailEnabled: j['email_enabled'] as bool? ?? true,
        smsEnabled: j['sms_enabled'] as bool? ?? false,
        pushEnabled: j['push_enabled'] as bool? ?? true,
        fcmToken: j['fcm_token'] as String? ?? '',
        notifyTimetableChanges: j['notify_timetable_changes'] as bool? ?? true,
        notifyVenueChanges: j['notify_venue_changes'] as bool? ?? true,
        notifyEmergencySessions: j['notify_emergency_sessions'] as bool? ?? true,
        notifySessionConfirmation:
            j['notify_session_confirmation'] as bool? ?? true,
        notifySessionPostponement:
            j['notify_session_postponement'] as bool? ?? true,
        notifySessionCancellation:
            j['notify_session_cancellation'] as bool? ?? true,
        updatedAt: j['updated_at'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'in_app_enabled': inAppEnabled,
        'email_enabled': emailEnabled,
        'sms_enabled': smsEnabled,
        'push_enabled': pushEnabled,
        'fcm_token': fcmToken,
        'notify_timetable_changes': notifyTimetableChanges,
        'notify_venue_changes': notifyVenueChanges,
        'notify_emergency_sessions': notifyEmergencySessions,
        'notify_session_confirmation': notifySessionConfirmation,
        'notify_session_postponement': notifySessionPostponement,
        'notify_session_cancellation': notifySessionCancellation,
      };

  NotificationPreference copyWith({
    bool? inAppEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? pushEnabled,
    String? fcmToken,
    bool? notifyTimetableChanges,
    bool? notifyVenueChanges,
    bool? notifyEmergencySessions,
    bool? notifySessionConfirmation,
    bool? notifySessionPostponement,
    bool? notifySessionCancellation,
  }) =>
      NotificationPreference(
        inAppEnabled: inAppEnabled ?? this.inAppEnabled,
        emailEnabled: emailEnabled ?? this.emailEnabled,
        smsEnabled: smsEnabled ?? this.smsEnabled,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        fcmToken: fcmToken ?? this.fcmToken,
        notifyTimetableChanges:
            notifyTimetableChanges ?? this.notifyTimetableChanges,
        notifyVenueChanges: notifyVenueChanges ?? this.notifyVenueChanges,
        notifyEmergencySessions:
            notifyEmergencySessions ?? this.notifyEmergencySessions,
        notifySessionConfirmation:
            notifySessionConfirmation ?? this.notifySessionConfirmation,
        notifySessionPostponement:
            notifySessionPostponement ?? this.notifySessionPostponement,
        notifySessionCancellation:
            notifySessionCancellation ?? this.notifySessionCancellation,
        updatedAt: updatedAt,
      );
}
