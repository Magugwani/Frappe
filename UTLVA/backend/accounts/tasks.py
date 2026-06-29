"""
UTLVA Accounts Celery Tasks — SRS §3.9 FR-57

send_welcome_emails_for_job  — sends a welcome email with a 48-hour password
  reset link to every newly created user in a BulkEnrollmentJob.
  Dispatched asynchronously; the import is considered complete as soon as
  accounts are created, regardless of email delivery status.
"""
from celery import shared_task
import logging

logger = logging.getLogger(__name__)


@shared_task(name='accounts.send_welcome_emails_for_job', ignore_result=True)
def send_welcome_emails_for_job(job_id: int, user_ids: list):
    """
    FR-57: Send welcome email with 48-hour password reset link.
    Runs asynchronously after bulk account creation completes.
    """
    from django.conf import settings
    from django.core.mail import send_mail
    from accounts.models import User, PasswordResetToken

    frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
    from_email   = getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@utlva.local')

    users = User.objects.filter(pk__in=user_ids).only('email', 'full_name', 'role')
    sent = 0

    for user in users:
        try:
            token_obj = PasswordResetToken.create_for_user(user, hours=48)
            reset_url = f'{frontend_url}/reset-password?token={token_obj.token}'

            send_mail(
                subject='Welcome to UTLVA — Set Your Password',
                message=(
                    f'Dear {user.full_name},\n\n'
                    f'Your UTLVA account has been created.\n\n'
                    f'  Email:  {user.email}\n'
                    f'  Role:   {user.role}\n\n'
                    f'Set your password using the link below (valid for 48 hours):\n\n'
                    f'  {reset_url}\n\n'
                    f'If you did not expect this account, please contact your coordinator.\n\n'
                    f'— UTLVA Timetable System'
                ),
                from_email=from_email,
                recipient_list=[user.email],
                fail_silently=True,
            )
            sent += 1
        except Exception as exc:
            logger.error('Welcome email failed for user %s: %s', user.pk, exc)

    logger.info(
        'BulkEnrollmentJob #%s: sent %d/%d welcome emails.',
        job_id, sent, len(user_ids),
    )
