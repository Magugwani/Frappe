"""
UTLVA SMS Service — SRS §3.8 FR-51-B

Architecture
------------
This module is the single point of SMS dispatch. It handles:
  1. +255 (Tanzania) phone number validation
  2. Per-user daily cap enforcement
  3. Bulk-SMS threshold detection (> SMS_BULK_APPROVAL_THRESHOLD recipients)
  4. Africa's Talking gateway integration (STUB — activate by setting credentials)
  5. Retry-queue insertion on failure
  6. Fallback to push + in-app when cap or max retries exceeded

Africa's Talking Integration
----------------------------
To activate, install the SDK and set env vars:

    pip install africastalking
    # .env additions:
    AT_USERNAME=your_sandbox_or_live_username
    AT_API_KEY=your_api_key
    SMS_GATEWAY=africastalking

When SMS_GATEWAY is not set (or 'stub'), messages are logged to console only —
all other SMS logic (caps, deduplication, retry) still runs in full.
"""
import logging
import re
from django.conf import settings
from django.utils import timezone

logger = logging.getLogger(__name__)

# ── Tanzania number validation ─────────────────────────────────────────────────

_TZ_PATTERN = re.compile(r'^\+255[67]\d{8}$')

def is_valid_tz_number(phone: str) -> bool:
    """
    FR-51-B: Only +255 Tanzania numbers are eligible for SMS.
    Accepts +255 followed by 6 or 7 (mobile prefixes) then 8 more digits.
    """
    return bool(_TZ_PATTERN.match(phone.strip()))

def normalize_phone(phone: str) -> str:
    """Strip spaces and ensure international format."""
    cleaned = re.sub(r'\s', '', phone.strip())
    if cleaned.startswith('0') and len(cleaned) == 10:
        cleaned = '+255' + cleaned[1:]
    return cleaned


# ── Africa's Talking gateway ───────────────────────────────────────────────────

def _get_at_sms():
    """
    Lazily initialise the Africa's Talking SMS client.
    Returns the africastalking SMS object, or None if not configured.
    """
    gateway = getattr(settings, 'SMS_GATEWAY', 'stub')
    if gateway != 'africastalking':
        return None

    try:
        import africastalking
        username = getattr(settings, 'AT_USERNAME', '')
        api_key  = getattr(settings, 'AT_API_KEY', '')
        if not username or not api_key:
            logger.warning('SMS_GATEWAY=africastalking but AT_USERNAME/AT_API_KEY not set.')
            return None
        africastalking.initialize(username, api_key)
        return africastalking.SMS
    except ImportError:
        logger.warning(
            'africastalking package not installed. '
            'Run: pip install africastalking'
        )
        return None


def _send_via_gateway(phone: str, message: str) -> bool:
    """
    Send a single SMS via Africa's Talking (or stub to console).
    Returns True on success.
    """
    at_sms = _get_at_sms()
    if at_sms is None:
        # STUB: log the message so manual testing works
        logger.info('[SMS STUB] To %s: %s', phone, message[:80])
        print(f'\n[SMS STUB] → {phone}\n{message}\n')
        return True  # stub always succeeds

    try:
        response = at_sms.send(message=message, recipients=[phone])
        logger.info('AT SMS response: %s', response)
        sms_data = response.get('SMSMessageData', {})
        recipients = sms_data.get('Recipients', [])
        if recipients:
            status = recipients[0].get('status', '')
            return status.lower() == 'success'
        return False
    except Exception as exc:
        logger.error('AT SMS error to %s: %s', phone, exc)
        return False


# ── Per-user cap helper ────────────────────────────────────────────────────────

def _within_daily_cap(user) -> bool:
    from .models import SMSDailyLog
    try:
        from timetable.models import SystemConfiguration
        cap = SystemConfiguration.get().sms_daily_cap_per_user
    except Exception:
        cap = getattr(settings, 'SMS_DAILY_CAP_PER_USER', 5)
    return SMSDailyLog.today_count(user) < cap


# ── Public API ─────────────────────────────────────────────────────────────────

def send_sms(user, message: str, event_id: str = '', notification_type: str = '') -> bool:
    """
    Attempt to send one SMS to a single user.

    Flow:
      1. Validate phone format (+255)
      2. Check daily cap (FR-51-B)
      3. Send via gateway
      4. On failure → queue SMSRetryJob

    Returns True if SMS was sent (or queued for retry), False if permanently skipped.
    """
    from .models import SMSDailyLog, SMSRetryJob

    phone = normalize_phone(getattr(user, 'phone_number', '') or '')
    if not phone or not is_valid_tz_number(phone):
        logger.debug('Skipping SMS to %s — no valid +255 number.', user.pk)
        return False

    if not _within_daily_cap(user):
        logger.info(
            'Daily SMS cap reached for user %s — using push/in-app fallback.', user.pk
        )
        return False  # caller should fall back to push/in-app

    success = _send_via_gateway(phone, message)

    if success:
        SMSDailyLog.increment(user)
        return True

    # Queue retry job on failure
    next_retry = timezone.now() + timezone.timedelta(seconds=60)  # first attempt in 60s
    SMSRetryJob.objects.create(
        recipient_user=user,
        phone_number=phone,
        message=message,
        event_id=event_id,
        notification_type=notification_type,
        attempts=1,
        status=SMSRetryJob.Status.RETRYING,
        next_retry_at=next_retry,
        last_attempt_at=timezone.now(),
        error_message='Initial send failed — queued for retry.',
    )
    return False


def create_bulk_sms_job(
    event_id: str,
    notification_type: str,
    title: str,
    message: str,
    recipients: list,       # list of User objects
    requested_by=None,
) -> 'BulkSMSJob | None':
    """
    FR-51-B: If recipient count > SMS_BULK_APPROVAL_THRESHOLD, create a
    BulkSMSJob that requires coordinator approval before dispatch.
    Otherwise dispatch immediately.

    Returns the BulkSMSJob if pending approval, None if immediately dispatched.
    """
    import json
    from .models import BulkSMSJob

    try:
        from timetable.models import SystemConfiguration
        threshold = SystemConfiguration.get().sms_bulk_approval_threshold
    except Exception:
        threshold = getattr(settings, 'SMS_BULK_APPROVAL_THRESHOLD', 50)

    # Build recipient payload — only +255 numbers
    eligible = []
    for user in recipients:
        phone = normalize_phone(getattr(user, 'phone_number', '') or '')
        if phone and is_valid_tz_number(phone):
            eligible.append({'user_id': user.pk, 'phone': phone})

    if not eligible:
        return None

    if len(eligible) > threshold:
        # Hold for coordinator approval
        job = BulkSMSJob.objects.create(
            event_id=event_id,
            notification_type=notification_type,
            title=title,
            message=message,
            recipient_count=len(eligible),
            recipients_json=json.dumps(eligible),
            status=BulkSMSJob.Status.PENDING,
            requested_by=requested_by,
        )
        logger.info(
            'BulkSMSJob #%s created for %d recipients (threshold=%d) — awaiting approval.',
            job.pk, len(eligible), threshold,
        )
        return job

    # Under threshold — dispatch immediately
    for item in eligible:
        user_qs = __import__('accounts.models', fromlist=['User'])
        try:
            from accounts.models import User
            user = User.objects.get(pk=item['user_id'])
            send_sms(user, message, event_id=event_id, notification_type=notification_type)
        except Exception as exc:
            logger.error('Bulk SMS send error for user %s: %s', item['user_id'], exc)
    return None


def dispatch_approved_bulk_sms_job(job):
    """Dispatch an already-approved BulkSMSJob."""
    from .models import BulkSMSJob
    from accounts.models import User

    job.status = BulkSMSJob.Status.DISPATCHED
    job.save(update_fields=['status'])

    for item in job.recipients():
        try:
            user = User.objects.get(pk=item['user_id'])
            send_sms(user, job.message, event_id=job.event_id,
                     notification_type=job.notification_type)
        except Exception as exc:
            logger.error('Bulk SMS dispatch error user %s: %s', item.get('user_id'), exc)
