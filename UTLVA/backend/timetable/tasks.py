"""
UTLVA Timetable Celery Tasks — SRS §3.5 Session Confirmation and Postponement

Tasks
-----
check_confirmation_expiry()   (FR-35)
    Runs every 60 s. Finds PUBLISHED sessions whose confirmation window has
    passed without the lecturer confirming.  Transitions venue BOOKED → EXPIRED
    → FREE, creates/updates SessionConfirmation(EXPIRED), and emails enrolled
    students.

release_ended_sessions()   (FR-16, FR-47)
    Runs every 60 s. Finds sessions where end_time has passed and venue is
    IN_USE → FREE.

send_session_reminders()   (FR-31)
    Runs every 60 s.  Finds PUBLISHED sessions starting within the next
    REMINDER_LEAD_MINUTES window that have not yet had a reminder dispatched.
    Emails the assigned lecturer with session details and a prompt to confirm.
    Marks SessionConfirmation.reminder_sent_at to prevent duplicate sends.

Requirements
------------
Redis on localhost:6379 (CELERY_BROKER_URL).
  celery -A UTLVA worker -l info
  celery -A UTLVA beat   -l info \
    --scheduler django_celery_beat.schedulers:DatabaseScheduler
"""

from celery import shared_task
from django.utils import timezone
import logging

logger = logging.getLogger(__name__)


# ── FR-35: BOOKED → EXPIRED → FREE + student notification ─────────────────────

@shared_task(name='timetable.check_confirmation_expiry', ignore_result=True)
def check_confirmation_expiry():
    """
    FR-35: Mark unconfirmed sessions EXPIRED, release venue, notify students.
    """
    from datetime import datetime, timedelta
    from timetable.models import TimetableEntry, TimetableStatus, SystemConfiguration, SessionConfirmation
    from venues.models import VenueStatus, TransitionEvent
    from venues.services import VenueStateMachine

    now_local = timezone.localtime()
    today     = now_local.date()
    day_name  = now_local.strftime('%A').upper()

    config = SystemConfiguration.get()
    window  = config.confirmation_window_minutes

    # Published entries happening today whose venue is still BOOKED
    entries = (
        TimetableEntry.objects
        .select_related('venue', 'course', 'lecturer__user', 'student_group')
        .filter(
            status=TimetableStatus.PUBLISHED,
            day_of_week=day_name,
            venue__isnull=False,
            venue__status=VenueStatus.BOOKED,
        )
    )

    expired_count = 0
    for entry in entries:
        deadline = datetime.combine(today, entry.start_time) + timedelta(minutes=window)
        if now_local < timezone.make_aware(deadline, now_local.tzinfo):
            continue  # window still open

        # Skip if already confirmed for today
        existing = SessionConfirmation.objects.filter(
            timetable_entry=entry,
            session_date=today,
            status=SessionConfirmation.Status.CONFIRMED,
        ).exists()
        if existing:
            continue

        venue = entry.venue
        try:
            machine = VenueStateMachine(venue)
            machine.transition(
                to_status=VenueStatus.EXPIRED,
                event=TransitionEvent.CONFIRMATION_WINDOW_EXPIRED,
                user=None,
                reason=(
                    f'Confirmation window of {window} min expired. '
                    f'{entry.course.course_code} {entry.day_of_week} '
                    f'{entry.start_time:%H:%M}–{entry.end_time:%H:%M}.'
                ),
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
            )
            machine.transition(
                to_status=VenueStatus.FREE,
                event=TransitionEvent.AUTO_RELEASE,
                user=None,
                reason='Automatic release after EXPIRED transient state.',
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
            )
        except Exception as exc:
            logger.error('Failed to expire venue %s for entry %s: %s', venue.code, entry.id, exc)
            continue

        # FR-35: Record EXPIRED confirmation
        confirmation, _ = SessionConfirmation.objects.update_or_create(
            timetable_entry=entry,
            session_date=today,
            defaults={
                'status': SessionConfirmation.Status.EXPIRED,
                'expired_at': timezone.now(),
            },
        )

        # FR-35: Notify enrolled students
        _notify_expiry_email(entry)

        expired_count += 1
        logger.info(
            'Session expired: %s %s %s–%s (venue %s released)',
            entry.course.course_code, entry.day_of_week,
            entry.start_time.strftime('%H:%M'), entry.end_time.strftime('%H:%M'),
            venue.code,
        )

    return {'expired': expired_count, 'checked_at': now_local.isoformat()}


# ── FR-16 / FR-47: IN_USE → FREE when end_time passes ─────────────────────────

@shared_task(name='timetable.release_ended_sessions', ignore_result=True)
def release_ended_sessions():
    """
    FR-47: Release venues whose sessions have reached end_time.
    """
    from datetime import datetime
    from timetable.models import TimetableEntry, TimetableStatus
    from venues.models import VenueStatus, TransitionEvent
    from venues.services import VenueStateMachine

    now_local = timezone.localtime()
    day_name  = now_local.strftime('%A').upper()
    now_time  = now_local.time()

    entries = (
        TimetableEntry.objects
        .select_related('venue', 'course')
        .filter(
            status=TimetableStatus.PUBLISHED,
            day_of_week=day_name,
            end_time__lte=now_time,
            venue__isnull=False,
            venue__status=VenueStatus.IN_USE,
        )
    )

    released_count = 0
    for entry in entries:
        try:
            VenueStateMachine(entry.venue).transition(
                to_status=VenueStatus.FREE,
                event=TransitionEvent.SESSION_ENDED,
                user=None,
                reason=f'Session reached end_time {entry.end_time:%H:%M}. {entry.course.course_code}.',
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
                force=True,
            )
            released_count += 1
            logger.info('Venue %s released: session %s ended.', entry.venue.code, entry.course.course_code)
        except Exception as exc:
            logger.error('Failed to release venue %s: %s', entry.venue.code, exc)

    return {'released': released_count, 'checked_at': now_local.isoformat()}


# ── FR-31: Reminder emails to lecturers before session ─────────────────────────

@shared_task(name='timetable.send_session_reminders', ignore_result=True)
def send_session_reminders():
    """
    FR-31: Send reminder to the assigned lecturer REMINDER_LEAD_MINUTES
    before the session starts, prompting them to confirm via the app.
    """
    from datetime import datetime, timedelta
    from timetable.models import TimetableEntry, TimetableStatus, SystemConfiguration, SessionConfirmation

    now_local = timezone.localtime()
    today     = now_local.date()
    day_name  = now_local.strftime('%A').upper()

    config        = SystemConfiguration.get()
    lead_minutes  = config.reminder_lead_minutes

    # Target window: sessions starting in the next lead_minutes ± 1 minute
    window_start = (now_local + timedelta(minutes=lead_minutes - 1)).time()
    window_end   = (now_local + timedelta(minutes=lead_minutes + 1)).time()

    entries = (
        TimetableEntry.objects
        .select_related('course', 'lecturer__user', 'venue__building', 'student_group')
        .filter(
            status=TimetableStatus.PUBLISHED,
            day_of_week=day_name,
            start_time__gte=window_start,
            start_time__lte=window_end,
        )
    )

    sent_count = 0
    for entry in entries:
        # Avoid sending twice for the same occurrence
        confirmation, created = SessionConfirmation.objects.get_or_create(
            timetable_entry=entry,
            session_date=today,
            defaults={'status': SessionConfirmation.Status.PENDING},
        )
        if not created and confirmation.reminder_sent_at:
            continue  # already sent

        # Send reminder to lecturer
        _notify_reminder_email(entry, config.confirmation_window_minutes)

        confirmation.reminder_sent_at = timezone.now()
        if created:
            confirmation.status = SessionConfirmation.Status.PENDING
        confirmation.save(update_fields=['reminder_sent_at', 'status', 'updated_at'])
        sent_count += 1
        logger.info('Reminder sent to %s for %s %s', entry.lecturer.user.email, entry.course.course_code, entry.start_time)

    return {'reminders_sent': sent_count, 'checked_at': now_local.isoformat()}


# ── Email helpers ──────────────────────────────────────────────────────────────

def _student_emails_for_entry(entry) -> list:
    from academics.models import StudentProfile
    group = entry.student_group
    if not group:
        return []
    return list(
        StudentProfile.objects.filter(student_group=group)
        .select_related('user').values_list('user__email', flat=True)
    )


def _notify_expiry_email(entry) -> None:
    """FR-35: Email students when a session expires without confirmation."""
    from django.core.mail import send_mail
    from django.conf import settings

    emails = _student_emails_for_entry(entry)
    if not emails:
        return
    venue_name = f'{entry.venue.code} — {entry.venue.name}' if entry.venue else 'TBA'
    try:
        send_mail(
            subject=f'[UTLVA] Session Not Confirmed — {entry.course.course_code}',
            message=(
                f'Dear Student,\n\n'
                f'The {entry.course.course_name} session scheduled for today has NOT been confirmed '
                f'by the lecturer within the required time window.\n\n'
                f'Details:\n'
                f'  Day: {entry.day_of_week} {entry.start_time:%H:%M}–{entry.end_time:%H:%M}\n'
                f'  Venue: {venue_name}\n\n'
                f'Status: EXPIRED — venue has been released.\n\n'
                f'Please check with your coordinator or lecturer for further instructions.\n\n'
                f'— UTLVA Timetable System'
            ),
            from_email=getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@utlva.local'),
            recipient_list=list(emails),
            fail_silently=True,
        )
    except Exception:
        pass


def _notify_reminder_email(entry, window_minutes: int) -> None:
    """
    FR-31 / SRS §3.11: Email the lecturer a reminder with action links.
    The email includes three action links that open the UTLVA app to the
    correct screen:
      • Confirm   — opens lecturer timetable at the confirm action
      • Postpone  — opens the postpone dialog for this entry
      • Cancel    — opens the cancel confirmation dialog

    After tapping Postpone the app offers to create an alternative session.
    """
    from django.core.mail import send_mail
    from django.conf import settings

    lecturer_email = entry.lecturer.user.email
    lecturer_name  = entry.lecturer.user.full_name
    course_text    = f'{entry.course.course_name} ({entry.course.course_code})'
    session_time   = f'{entry.day_of_week}  {entry.start_time:%H:%M}–{entry.end_time:%H:%M}'
    venue_text = (
        f'{entry.venue.code} — {entry.venue.name}, '
        f'{entry.venue.building.name}, Floor {entry.venue.floor}'
        if entry.venue else 'No venue assigned'
    )

    # Deep-link style action URLs — each opens the app to the correct screen.
    # The mobile router handles these paths.
    frontend = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
    confirm_url  = f'{frontend}/action/confirm?entry_id={entry.id}'
    postpone_url = f'{frontend}/action/postpone?entry_id={entry.id}'
    cancel_url   = f'{frontend}/action/cancel?entry_id={entry.id}'

    separator = '-' * 52

    try:
        send_mail(
            subject=f'[UTLVA] Reminder: Session starting soon — {entry.course.course_code}',
            message=(
                f'Dear {lecturer_name},\n\n'
                f'You have a session starting in approximately {window_minutes} minutes.\n\n'
                f'{separator}\n'
                f'  Course : {course_text}\n'
                f'  Time   : {session_time}\n'
                f'  Venue  : {venue_text}\n'
                f'{separator}\n\n'
                f'PLEASE TAKE ONE OF THE FOLLOWING ACTIONS:\n\n'
                f'  [1] CONFIRM SESSION\n'
                f'  Tap the link below or open the UTLVA app → My Sessions → Confirm:\n'
                f'  {confirm_url}\n\n'
                f'  [2] POSTPONE SESSION\n'
                f'  If you cannot attend at this time, tap below to reschedule.\n'
                f'  You will be asked to set a new date/time and may optionally\n'
                f'  create an alternative emergency session for your students.\n'
                f'  {postpone_url}\n\n'
                f'  [3] CANCEL SESSION\n'
                f'  If the session will not take place, tap below to cancel.\n'
                f'  Students in your group will be notified automatically.\n'
                f'  {cancel_url}\n\n'
                f'{separator}\n'
                f'IMPORTANT: You have {window_minutes} minutes from the start time\n'
                f'to confirm. If no action is taken, the session will be marked\n'
                f'EXPIRED and the venue will be released.\n\n'
                f'— UTLVA Timetable System\n'
                f'  University Timetable & Local Venue Arrangement'
            ),
            from_email=getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@utlva.local'),
            recipient_list=[lecturer_email],
            fail_silently=True,
        )
    except Exception:
        pass
