from rest_framework import serializers
from .models import Notification, UserNotificationPreference, BulkSMSJob, SMSRetryJob


class NotificationSerializer(serializers.ModelSerializer):
    sender_name  = serializers.SerializerMethodField()
    type_display = serializers.CharField(source='get_notification_type_display', read_only=True)

    class Meta:
        model  = Notification
        fields = [
            'id', 'notification_type', 'type_display',
            'title', 'body',
            'related_object_type', 'related_object_id',
            'sender', 'sender_name',
            'is_read', 'created_at',
        ]
        read_only_fields = fields

    def get_sender_name(self, obj):
        return obj.sender.full_name if obj.sender else None


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model  = UserNotificationPreference
        fields = [
            'in_app_enabled', 'email_enabled', 'sms_enabled', 'push_enabled',
            'fcm_token',
            'notify_timetable_changes', 'notify_venue_changes',
            'notify_emergency_sessions', 'notify_session_confirmation',
            'notify_session_postponement', 'notify_session_cancellation',
            'updated_at',
        ]
        read_only_fields = ['updated_at']


class BulkSMSJobSerializer(serializers.ModelSerializer):
    requested_by_name = serializers.SerializerMethodField()
    approved_by_name  = serializers.SerializerMethodField()
    status_display    = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model  = BulkSMSJob
        fields = [
            'id', 'event_id', 'notification_type', 'title', 'message',
            'recipient_count', 'status', 'status_display',
            'requested_by', 'requested_by_name',
            'approved_by', 'approved_by_name', 'approved_at',
            'created_at',
        ]
        read_only_fields = fields

    def get_requested_by_name(self, obj):
        return obj.requested_by.full_name if obj.requested_by else None

    def get_approved_by_name(self, obj):
        return obj.approved_by.full_name if obj.approved_by else None


class SMSRetryJobSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model  = SMSRetryJob
        fields = [
            'id', 'phone_number', 'notification_type', 'attempts', 'max_attempts',
            'status', 'status_display', 'error_message',
            'next_retry_at', 'created_at', 'last_attempt_at',
        ]
        read_only_fields = fields
