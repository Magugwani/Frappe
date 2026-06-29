"""
UTLVA Notification Celery Tasks — SRS §3.8

retry_failed_sms      — exponential-backoff retry for failed SMS (FR-51-B)
dispatch_bulk_sms_job — dispatch a BulkSMSJob after coordinator approval
"""
from celery import shared_task
from django.utils import timezone
import logging

logger = logging.getLogger(__name__)


@shared_task(name='notifications.retry_failed_sms', ignore_result=True)
def retry_failed_sms():
    """
    FR-51-B: Retry SMS jobs that are due for their next attempt.
    On success: mark SENT.
    On failure after max_attempts: mark FALLEN_BACK, create push/in-app fallback.
    """
    from .models import SMSRetryJob, SMSDailyLog
    from .sms_service import _send_via_gateway, is_valid_tz_number

    now = timezone.now()
    jobs = SMSRetryJob.objects.filter(
        status=SMSRetryJob.Status.RETRYING,
        next_retry_at__lte=now,
    ).select_related('recipient_user')

    for job in jobs:
        if not is_valid_tz_number(job.phone_number):
            job.status = SMSRetryJob.Status.FAILED
            job.error_message = 'Invalid +255 number'
            job.save(update_fields=['status', 'error_message'])
            continue

        job.attempts += 1
        job.last_attempt_at = now

        success = _send_via_gateway(job.phone_number, job.message)

        if success:
            if job.recipient_user:
                SMSDailyLog.increment(job.recipient_user)
            job.status = SMSRetryJob.Status.SENT
            job.save(update_fields=['status', 'attempts', 'last_attempt_at'])
            logger.info('SMS retry succeeded: job #%s → %s', job.pk, job.phone_number)
        elif job.attempts >= job.max_attempts:
            # Max retries exceeded → fall back to push/in-app
            job.status = SMSRetryJob.Status.FALLEN_BACK
            job.save(update_fields=['status', 'attempts', 'last_attempt_at', 'error_message'])
            logger.warning('SMS max retries exceeded: job #%s — falling back.', job.pk)

            # Trigger push fallback notification
            if job.recipient_user:
                try:
                    from .fcm_service import send_push
                    send_push(
                        job.recipient_user,
                        title='UTLVA Notification',
                        body=job.message[:200],
                    )
                except Exception:
                    pass
        else:
            # Schedule next retry with exponential backoff
            backoff = job.next_backoff_seconds()
            job.next_retry_at = now + timezone.timedelta(seconds=backoff)
            job.save(update_fields=['attempts', 'last_attempt_at', 'next_retry_at'])
            logger.info(
                'SMS retry #%s failed: job #%s — next retry in %ds.',
                job.attempts, job.pk, backoff,
            )


@shared_task(name='notifications.dispatch_bulk_sms_job', ignore_result=True)
def dispatch_bulk_sms_job(bulk_job_id: int):
    """
    FR-51-B: Dispatch a BulkSMSJob that has been approved by a coordinator.
    """
    from .models import BulkSMSJob
    from .sms_service import dispatch_approved_bulk_sms_job
    try:
        job = BulkSMSJob.objects.get(pk=bulk_job_id, status=BulkSMSJob.Status.APPROVED)
        dispatch_approved_bulk_sms_job(job)
        logger.info('BulkSMSJob #%s dispatched.', bulk_job_id)
    except BulkSMSJob.DoesNotExist:
        logger.warning('BulkSMSJob #%s not found or not APPROVED.', bulk_job_id)
    except Exception as exc:
        logger.error('BulkSMSJob #%s dispatch error: %s', bulk_job_id, exc)
