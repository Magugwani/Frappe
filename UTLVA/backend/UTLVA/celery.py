"""
UTLVA Celery configuration.

Workers:
  celery -A UTLVA worker -l info

Beat (scheduled tasks — requires Redis):
  celery -A UTLVA beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler
"""
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'UTLVA.settings')

app = Celery('UTLVA')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

# ── SRS §3.3 Venue Status Automation ─────────────────────────────────────────
# Both tasks run every 60 seconds. They are no-ops when Redis is unavailable;
# the venue transitions simply happen manually until Redis is running.
app.conf.beat_schedule = {
    # FR-35: BOOKED → EXPIRED → FREE when confirmation window expires + notify students
    'check-confirmation-expiry': {
        'task': 'timetable.check_confirmation_expiry',
        'schedule': 60.0,
    },
    # FR-47: IN_USE → FREE when session end_time is reached
    'release-ended-sessions': {
        'task': 'timetable.release_ended_sessions',
        'schedule': 60.0,
    },
    # FR-31: Send reminder email to lecturer REMINDER_LEAD_MINUTES before start_time
    'send-session-reminders': {
        'task': 'timetable.send_session_reminders',
        'schedule': 60.0,
    },
    # FR-51-B: Retry failed SMS with exponential backoff
    'retry-failed-sms': {
        'task': 'notifications.retry_failed_sms',
        'schedule': 120.0,  # every 2 minutes
    },
}
app.conf.timezone = 'UTC'


@app.task(bind=True)
def debug_task(self):
    print(f'Request: {self.request!r}')
