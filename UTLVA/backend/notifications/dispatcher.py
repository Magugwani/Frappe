"""
UTLVA Notification Dispatcher — SRS §3.8

The dispatcher is the single entry point for ALL notification delivery.
It enforces:
  1. Deduplication  — NotificationLog.claim() prevents double-delivery
  2. User preferences — UserNotificationPreference controls which channels/events
  3. Channel routing — in-app, email, SMS, push
  4. SMS protections — +255 validation, daily cap, bulk approval threshold

Usage
-----
    from notifications.dispatcher import dispatch

    dispatch(
        event_id          = 'confirm:42:2026-07-01',
        recipients        = [user1, user2, ...],
        notification_type = Notification.Type.SESSION_CONFIRMED,
        title             = 'Session Confirmed',
        body              = 'Your lecture in Hall A has been confirmed.',
        sender            = coordinator_user,          # optional
        related_object_type = 'TimetableEntry',        # optional
        related_object_id   = '42',                    # optional
        email_subject     = 'UTLVA — Session Confirmed',  # optional override
        sms_message       = 'UTLVA: Session confirmed …',  # optional shorter SMS text
        data              = {'entry_id': '42'},        # optional FCM data payload
    )
"""
import logging
from django.core.mail import send_mail
from django.conf import settings as dj_settings

from .models import Notification, UserNotificationPreference, NotificationLog
from .sms_service import send_sms, create_bulk_sms_job
from .fcm_service import send_push

logger = logging.getLogger(__name__)


def dispatch(
    event_id: str,
    recipients,              # iterable of User objects
    notification_type: str,
    title: str,
    body: str,
    sender=None,
    related_object_type: str = '',
    related_object_id: str = '',
    email_subject: str = '',
    sms_message: str = '',
    data: dict = None,
    bulk_sms_requested_by=None,
):
    """
    Dispatch a notification to every recipient across all channels,
    applying deduplication, preference checks, and SMS protections.
    """
    recipients = list(recipients)
    if not recipients:
        return

    email_subject = email_subject or title
    sms_text      = sms_message or f'UTLVA: {title}. {body[:80]}'
    data          = data or {}

    # Collect SMS-eligible users for bulk threshold check
    sms_eligible = []

    for user in recipients:
        pref = UserNotificationPreference.get_or_create_for_user(user)

        # Skip if this event type is disabled for this user
        if not pref.is_event_enabled(notification_type):
            continue

        # ── In-app ───────────────────────────────────────────────────────────
        if pref.in_app_enabled:
            if NotificationLog.claim(event_id, user, NotificationLog.Channel.IN_APP):
                try:
                    Notification.create_for_user(
                        recipient=user,
                        notification_type=notification_type,
                        title=title,
                        body=body,
                        sender=sender,
                        related_object_type=related_object_type,
                        related_object_id=str(related_object_id),
                    )
                except Exception as exc:
                    logger.error('In-app dispatch error for user %s: %s', user.pk, exc)

        # ── Email ─────────────────────────────────────────────────────────────
        if pref.email_enabled and user.email:
            if NotificationLog.claim(event_id, user, NotificationLog.Channel.EMAIL):
                try:
                    send_mail(
                        subject=f'[UTLVA] {email_subject}',
                        message=body,
                        from_email=getattr(dj_settings, 'DEFAULT_FROM_EMAIL', 'noreply@utlva.local'),
                        recipient_list=[user.email],
                        fail_silently=True,
                    )
                except Exception as exc:
                    logger.error('Email dispatch error for user %s: %s', user.pk, exc)

        # ── Push (FCM) ────────────────────────────────────────────────────────
        if pref.push_enabled and pref.fcm_token:
            if NotificationLog.claim(event_id, user, NotificationLog.Channel.PUSH):
                try:
                    send_push(user, title=title, body=body, data=data)
                except Exception as exc:
                    logger.error('Push dispatch error for user %s: %s', user.pk, exc)

        # ── SMS eligibility (collected for bulk check below) ───────────────────
        if pref.sms_enabled:
            sms_eligible.append(user)

    # ── SMS dispatch (single or bulk) ─────────────────────────────────────────
    if sms_eligible:
        try:
            from timetable.models import SystemConfiguration
            threshold = SystemConfiguration.get().sms_bulk_approval_threshold
        except Exception:
            threshold = getattr(dj_settings, 'SMS_BULK_APPROVAL_THRESHOLD', 50)
        if len(sms_eligible) > threshold:
            # Create a bulk job awaiting coordinator approval
            create_bulk_sms_job(
                event_id=event_id,
                notification_type=notification_type,
                title=title,
                message=sms_text,
                recipients=sms_eligible,
                requested_by=bulk_sms_requested_by,
            )
        else:
            for user in sms_eligible:
                if NotificationLog.claim(event_id, user, NotificationLog.Channel.SMS):
                    ok = send_sms(
                        user=user,
                        message=sms_text,
                        event_id=event_id,
                        notification_type=notification_type,
                    )
                    if not ok:
                        # Fall back to push/in-app (already sent above if enabled)
                        logger.info(
                            'SMS fallback: user %s capped/failed — push already sent.',
                            user.pk,
                        )
