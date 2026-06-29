"""
UTLVA Notification Models — SRS §3.8

Models
------
Notification              — per-user in-app notification record (from §3.7)
UserNotificationPreference — per-user channel + event-type toggles (FR-50)
NotificationLog           — deduplication log: unique (event_id, user, channel) (FR-51)
SMSDailyLog               — per-user daily SMS count for cap enforcement (FR-51-B)
SMSRetryJob               — failed SMS queued for exponential-backoff retry (FR-51-B)
BulkSMSJob                — bulk SMS > 50 recipients pending coordinator approval (FR-51-B)
"""
import json
from django.db import models
from django.conf import settings


# ── In-app notification record ─────────────────────────────────────────────────

class Notification(models.Model):
    class Type(models.TextChoices):
        EMERGENCY_CREATED  = 'EMERGENCY_CREATED',  'Emergency Session Created'
        EMERGENCY_APPROVED = 'EMERGENCY_APPROVED', 'Emergency Session Approved'
        EMERGENCY_REJECTED = 'EMERGENCY_REJECTED', 'Emergency Session Rejected'
        SESSION_CONFIRMED  = 'SESSION_CONFIRMED',  'Session Confirmed'
        SESSION_POSTPONED  = 'SESSION_POSTPONED',  'Session Postponed'
        SESSION_CANCELLED  = 'SESSION_CANCELLED',  'Session Cancelled'
        SESSION_EXPIRED    = 'SESSION_EXPIRED',    'Session Expired'
        TIMETABLE_UPDATED  = 'TIMETABLE_UPDATED',  'Timetable Updated'
        VENUE_CHANGED      = 'VENUE_CHANGED',      'Venue Changed'
        GENERAL            = 'GENERAL',            'General'

    recipient           = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='notifications',
    )
    sender              = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='sent_notifications',
    )
    notification_type   = models.CharField(max_length=30, choices=Type.choices, default=Type.GENERAL)
    title               = models.CharField(max_length=200)
    body                = models.TextField()
    related_object_type = models.CharField(max_length=50, blank=True)
    related_object_id   = models.CharField(max_length=50, blank=True)
    is_read             = models.BooleanField(default=False)
    created_at          = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'notifications'
        ordering = ['-created_at']

    def __str__(self):
        return f'[{self.notification_type}] → {self.recipient_id}: {self.title[:40]}'

    @classmethod
    def create_for_user(cls, recipient, notification_type, title, body,
                        sender=None, related_object_type='', related_object_id=''):
        return cls.objects.create(
            recipient=recipient, sender=sender,
            notification_type=notification_type, title=title, body=body,
            related_object_type=related_object_type,
            related_object_id=str(related_object_id),
        )

    @classmethod
    def broadcast_to_role(cls, role, notification_type, title, body,
                          sender=None, related_object_type='', related_object_id=''):
        from accounts.models import User
        recipients = User.objects.filter(role=role, is_active=True)
        cls.objects.bulk_create([
            cls(
                recipient=u, sender=sender,
                notification_type=notification_type, title=title, body=body,
                related_object_type=related_object_type,
                related_object_id=str(related_object_id),
            )
            for u in recipients
        ])


# ── FR-50: Per-user notification preferences ──────────────────────────────────

class UserNotificationPreference(models.Model):
    """
    FR-50 — each user controls which channels they receive and for which events.
    A preference row is created on first access (get_or_create_for_user).
    """
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='notification_preference',
    )

    # ── Channel toggles ────────────────────────────────────────────────────────
    in_app_enabled  = models.BooleanField(default=True)
    email_enabled   = models.BooleanField(default=True)
    sms_enabled     = models.BooleanField(default=False)   # opt-in (cost risk)
    push_enabled    = models.BooleanField(default=True)

    # ── FCM device token (set by the mobile app on login) ─────────────────────
    fcm_token       = models.CharField(max_length=500, blank=True)

    # ── Event-type toggles (apply across all channels) ────────────────────────
    notify_timetable_changes    = models.BooleanField(default=True)
    notify_venue_changes        = models.BooleanField(default=True)
    notify_emergency_sessions   = models.BooleanField(default=True)
    notify_session_confirmation = models.BooleanField(default=True)
    notify_session_postponement = models.BooleanField(default=True)
    notify_session_cancellation = models.BooleanField(default=True)

    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'notification_preferences'

    @classmethod
    def get_or_create_for_user(cls, user):
        obj, _ = cls.objects.get_or_create(user=user)
        return obj

    def is_event_enabled(self, notification_type: str) -> bool:
        mapping = {
            'TIMETABLE_UPDATED':  self.notify_timetable_changes,
            'VENUE_CHANGED':      self.notify_venue_changes,
            'EMERGENCY_CREATED':  self.notify_emergency_sessions,
            'EMERGENCY_APPROVED': self.notify_emergency_sessions,
            'EMERGENCY_REJECTED': self.notify_emergency_sessions,
            'SESSION_CONFIRMED':  self.notify_session_confirmation,
            'SESSION_POSTPONED':  self.notify_session_postponement,
            'SESSION_CANCELLED':  self.notify_session_cancellation,
            'SESSION_EXPIRED':    self.notify_session_cancellation,
        }
        return mapping.get(notification_type, True)


# ── FR-51: Notification deduplication log ─────────────────────────────────────

class NotificationLog(models.Model):
    """
    Deduplication guard: unique (event_id, recipient_user, channel).
    Before dispatching any notification the dispatcher calls claim().
    If claim() returns False the notification was already sent — drop it silently.
    The deduplication window is the lifetime of the event_id (>= 24 h).
    """
    class Channel(models.TextChoices):
        IN_APP = 'in_app', 'In-App'
        EMAIL  = 'email',  'Email'
        SMS    = 'sms',    'SMS'
        PUSH   = 'push',   'Push'

    event_id        = models.CharField(max_length=200)
    recipient_user  = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='notification_logs',
    )
    channel         = models.CharField(max_length=10, choices=Channel.choices)
    dispatched_at   = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table        = 'notification_log'
        unique_together = [('event_id', 'recipient_user', 'channel')]

    @classmethod
    def claim(cls, event_id: str, recipient_user, channel: str) -> bool:
        """
        Attempt to claim a slot for (event_id, user, channel).
        Returns True if claimed (first time), False if already dispatched.
        """
        try:
            cls.objects.create(
                event_id=event_id, recipient_user=recipient_user, channel=channel
            )
            return True
        except Exception:
            return False  # unique constraint violation → duplicate


# ── FR-51-B: Per-user daily SMS cap ───────────────────────────────────────────

class SMSDailyLog(models.Model):
    """Tracks how many SMS a user has received today."""
    user  = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='sms_daily_logs',
    )
    date  = models.DateField()
    count = models.PositiveIntegerField(default=0)

    class Meta:
        db_table        = 'sms_daily_log'
        unique_together = [('user', 'date')]

    @classmethod
    def increment(cls, user) -> int:
        """Increment today's count and return the NEW count."""
        from django.utils import timezone
        today = timezone.localdate()
        obj, _ = cls.objects.get_or_create(user=user, date=today, defaults={'count': 0})
        obj.count = models.F('count') + 1
        obj.save(update_fields=['count'])
        obj.refresh_from_db()
        return obj.count

    @classmethod
    def today_count(cls, user) -> int:
        from django.utils import timezone
        today = timezone.localdate()
        try:
            return cls.objects.get(user=user, date=today).count
        except cls.DoesNotExist:
            return 0


# ── FR-51-B: Failed SMS retry queue ───────────────────────────────────────────

class SMSRetryJob(models.Model):
    class Status(models.TextChoices):
        PENDING    = 'PENDING',    'Pending'
        RETRYING   = 'RETRYING',   'Retrying'
        SENT       = 'SENT',       'Sent'
        FAILED     = 'FAILED',     'Failed (max retries exceeded)'
        FALLEN_BACK = 'FALLEN_BACK', 'Fallen back to push/in-app'

    recipient_user  = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='sms_retry_jobs',
    )
    phone_number    = models.CharField(max_length=20)
    message         = models.TextField()
    event_id        = models.CharField(max_length=200, blank=True)
    notification_type = models.CharField(max_length=30, blank=True)
    attempts        = models.PositiveIntegerField(default=0)
    max_attempts    = models.PositiveIntegerField(default=3)
    status          = models.CharField(max_length=15, choices=Status.choices, default=Status.PENDING)
    error_message   = models.TextField(blank=True)
    next_retry_at   = models.DateTimeField(null=True, blank=True)
    created_at      = models.DateTimeField(auto_now_add=True)
    last_attempt_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'sms_retry_jobs'

    def next_backoff_seconds(self) -> int:
        """Exponential backoff: 60s, 300s, 900s for attempts 1, 2, 3."""
        return 60 * (5 ** self.attempts)


# ── FR-51-B: Bulk SMS coordinator approval ────────────────────────────────────

class BulkSMSJob(models.Model):
    """
    When an SMS broadcast targets > SMS_BULK_APPROVAL_THRESHOLD recipients,
    it is held here until a Coordinator confirms via a single button.
    """
    class Status(models.TextChoices):
        PENDING    = 'PENDING',    'Awaiting Coordinator Approval'
        APPROVED   = 'APPROVED',   'Approved — dispatching'
        REJECTED   = 'REJECTED',   'Rejected'
        DISPATCHED = 'DISPATCHED', 'Dispatched'

    event_id          = models.CharField(max_length=200)
    notification_type = models.CharField(max_length=30, blank=True)
    title             = models.CharField(max_length=200)
    message           = models.TextField()
    recipient_count   = models.PositiveIntegerField()
    # JSON list of {"user_id": N, "phone": "+255..."}
    recipients_json   = models.TextField()
    status            = models.CharField(max_length=15, choices=Status.choices, default=Status.PENDING)
    requested_by      = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='bulk_sms_requests',
    )
    approved_by       = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='bulk_sms_approvals',
    )
    approved_at       = models.DateTimeField(null=True, blank=True)
    created_at        = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'bulk_sms_jobs'

    def recipients(self) -> list:
        return json.loads(self.recipients_json)
