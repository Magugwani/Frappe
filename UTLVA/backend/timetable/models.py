from django.db import models
from accounts.models import User
from academics.models import AcademicYear, Semester, Programme, StudentGroup, Course, Lecturer
from venues.models import Venue


class DayOfWeek(models.TextChoices):
    MONDAY = 'MONDAY', 'Monday'
    TUESDAY = 'TUESDAY', 'Tuesday'
    WEDNESDAY = 'WEDNESDAY', 'Wednesday'
    THURSDAY = 'THURSDAY', 'Thursday'
    FRIDAY = 'FRIDAY', 'Friday'
    SATURDAY = 'SATURDAY', 'Saturday'


class TimetableStatus(models.TextChoices):
    DRAFT              = 'DRAFT',              'Draft'
    VALIDATED          = 'VALIDATED',          'Validated'
    PUBLISHED          = 'PUBLISHED',          'Published'
    # SRS §3.12: set when the assigned lecturer's account is deactivated mid-term
    NEEDS_REASSIGNMENT = 'NEEDS_REASSIGNMENT', 'Needs Reassignment'
    ARCHIVED = 'ARCHIVED', 'Archived'   # Phase 7: future-ready


class TimetableEntry(models.Model):
    academic_year = models.ForeignKey(
        AcademicYear, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    semester = models.ForeignKey(
        Semester, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    programme = models.ForeignKey(
        Programme, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    student_group = models.ForeignKey(
        StudentGroup, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='timetable_entries'
    )
    course = models.ForeignKey(
        Course, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    lecturer = models.ForeignKey(
        Lecturer, on_delete=models.CASCADE, related_name='timetable_entries'
    )
    venue = models.ForeignKey(
        Venue, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='timetable_entries'
    )
    day_of_week = models.CharField(max_length=10, choices=DayOfWeek.choices)
    date = models.DateField(null=True, blank=True)
    start_time = models.TimeField()
    end_time = models.TimeField()
    status = models.CharField(
        max_length=20, choices=TimetableStatus.choices, default=TimetableStatus.DRAFT
    )
    # Phase 8: venue recommendation + override tracking
    expected_student_count = models.PositiveIntegerField(null=True, blank=True)
    venue_override_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='venue_overrides',
    )
    venue_override_reason = models.TextField(blank=True)
    venue_override_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='created_timetable_entries'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'timetable_entries'
        ordering = ['day_of_week', 'start_time']

    def __str__(self):
        return f'{self.course.course_code} | {self.day_of_week} {self.start_time}-{self.end_time} | {self.status}'

    @property
    def duration_minutes(self):
        start = self.start_time.hour * 60 + self.start_time.minute
        end = self.end_time.hour * 60 + self.end_time.minute
        return end - start


class TimetableConflict(models.Model):
    class ConflictType(models.TextChoices):
        VENUE = 'VENUE_CONFLICT', 'Venue Conflict'
        LECTURER = 'LECTURER_CONFLICT', 'Lecturer Conflict'
        STUDENT_GROUP = 'STUDENT_GROUP_CONFLICT', 'Student Group Conflict'

    class Status(models.TextChoices):
        OPEN = 'OPEN', 'Open'
        RESOLVED = 'RESOLVED', 'Resolved'

    conflict_type = models.CharField(max_length=30, choices=ConflictType.choices)
    timetable_entry_a = models.ForeignKey(
        TimetableEntry, on_delete=models.CASCADE, related_name='conflicts_as_a'
    )
    timetable_entry_b = models.ForeignKey(
        TimetableEntry, on_delete=models.CASCADE, related_name='conflicts_as_b'
    )
    message = models.TextField()
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.OPEN
    )
    # Phase 7: conflict resolution tracking
    resolved_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='resolved_conflicts'
    )
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolution_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'timetable_conflicts'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.conflict_type} | {self.status}'


class TimetablePublication(models.Model):
    """Records each time a timetable is published for a semester."""

    class PubStatus(models.TextChoices):
        ACTIVE = 'ACTIVE', 'Active'
        SUPERSEDED = 'SUPERSEDED', 'Superseded'  # replaced by a newer publication

    academic_year = models.ForeignKey(
        AcademicYear, on_delete=models.CASCADE, related_name='publications'
    )
    semester = models.ForeignKey(
        Semester, on_delete=models.CASCADE, related_name='publications'
    )
    published_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name='published_timetables'
    )
    published_at = models.DateTimeField(auto_now_add=True)
    published_entries_count = models.PositiveIntegerField(default=0)
    status = models.CharField(
        max_length=20, choices=PubStatus.choices, default=PubStatus.ACTIVE
    )
    notes = models.TextField(blank=True)

    class Meta:
        db_table = 'timetable_publications'
        ordering = ['-published_at']

    def __str__(self):
        return f'{self.academic_year.name} {self.semester.name} — published by {self.published_by} at {self.published_at}'


# ── Phase 8: System-wide configuration ────────────────────────────────────────

class SystemConfiguration(models.Model):
    """
    Singleton — one row holds all configurable system-wide parameters.
    Editable via /api/system/config/ (Admin only) and the System Settings screen.
    All eight SRS §3.11 parameters are stored here so admins can tune behaviour
    without code changes.
    """
    # FR-19 / SRS §3.11 — venue auto-allocation upper-bound
    capacity_overhead = models.FloatField(
        default=1.5,
        help_text='Multiplier on expected_students for venue upper-bound. Default: 1.5',
    )
    # FR-32 / SRS §3.11 — confirmation window
    confirmation_window_minutes = models.PositiveIntegerField(
        default=40,
        help_text='Minutes after start_time within which lecturer must confirm. Default: 40',
    )
    # FR-31 / SRS §3.11 — reminder lead time
    reminder_lead_minutes = models.PositiveIntegerField(
        default=120,
        help_text='Minutes before start_time to send the pre-session reminder. Default: 120',
    )
    # FR-51-B / SRS §3.11 — per-user daily SMS cap
    sms_daily_cap_per_user = models.PositiveIntegerField(
        default=5,
        help_text='Maximum SMS messages a single user may receive per calendar day. Default: 5',
    )
    # FR-51-B / SRS §3.11 — bulk SMS approval threshold
    sms_bulk_approval_threshold = models.PositiveIntegerField(
        default=50,
        help_text='Recipients above which bulk SMS requires coordinator approval. Default: 50',
    )
    # FR-57 / SRS §3.11 — welcome / password reset link validity
    password_reset_link_hours = models.PositiveIntegerField(
        default=48,
        help_text='Hours until a welcome/reset link expires. Default: 48',
    )
    # FR-52 / SRS §3.11 — maximum CSV rows per upload
    max_bulk_upload_rows = models.PositiveIntegerField(
        default=5000,
        help_text='Max rows in a single CSV upload. Default: 5000',
    )
    # SRS §3.11 — Celery Beat venue status check interval
    venue_status_check_interval_seconds = models.PositiveIntegerField(
        default=60,
        help_text='How often Celery Beat checks for ended sessions (seconds). Default: 60',
    )

    updated_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'system_configuration'

    @classmethod
    def get(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


# ── Phase 8: Emergency Sessions ────────────────────────────────────────────────

class EmergencySession(models.Model):
    class Status(models.TextChoices):
        PENDING   = 'PENDING',   'Pending Review'
        APPROVED  = 'APPROVED',  'Approved'
        REJECTED  = 'REJECTED',  'Rejected'
        CANCELLED = 'CANCELLED', 'Cancelled'

    # FR-23 required fields
    title             = models.CharField(max_length=200, blank=True, help_text='Short descriptive title, e.g. "Makeup Lab Session".')
    course            = models.ForeignKey('academics.Course',   on_delete=models.CASCADE, related_name='emergency_sessions')
    lecturer          = models.ForeignKey('academics.Lecturer', on_delete=models.CASCADE, related_name='emergency_sessions')
    expected_students = models.PositiveIntegerField(null=True, blank=True, help_text='Number of students expected to attend.')
    required_resources= models.JSONField(default=list, blank=True, help_text='e.g. ["projector","whiteboard"]')
    venue             = models.ForeignKey('venues.Venue',        on_delete=models.SET_NULL, null=True, blank=True, related_name='emergency_sessions')
    student_groups    = models.ManyToManyField('academics.StudentGroup', blank=True, related_name='emergency_sessions')

    requested_date = models.DateField()
    day_of_week    = models.CharField(max_length=10, choices=DayOfWeek.choices)
    start_time     = models.TimeField()
    end_time       = models.TimeField()
    reason         = models.TextField(help_text='Why this emergency session is needed.')
    comments       = models.TextField(blank=True, help_text='Additional notes or instructions.')

    status       = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    requested_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='requested_emergency_sessions')
    reviewed_by  = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='reviewed_emergency_sessions')
    reviewed_at  = models.DateTimeField(null=True, blank=True)
    review_note  = models.TextField(blank=True)
    created_at   = models.DateTimeField(auto_now_add=True)

    # FR-24 availability/capacity check results (advisory — coordinator approves despite flags)
    lecturer_conflict = models.BooleanField(default=False)
    venue_conflict    = models.BooleanField(default=False)
    group_conflict    = models.BooleanField(default=False)
    capacity_conflict = models.BooleanField(default=False, help_text='True when expected_students > venue.capacity.')

    class Meta:
        db_table = 'emergency_sessions'
        ordering = ['-created_at']

    def __str__(self):
        label = self.title or self.course.course_code
        return f'{label} emergency — {self.requested_date} | {self.status}'


# ── Session Postponement (FR-26, FR-27) ──────────────────────────────────────

class SessionPostponement(models.Model):
    """
    Records a single postponed occurrence of a published TimetableEntry.

    A TimetableEntry is a weekly recurring session. When a lecturer needs to
    move ONE specific occurrence (e.g., this Monday's lecture) to another
    time or venue, a SessionPostponement is created rather than modifying the
    master entry — preserving the original schedule for all other weeks.

    Side effects (handled by postpone_session service):
      • Original venue: BOOKED → FREE  (venue_status_history written)
      • New venue (if different): FREE → BOOKED  (venue_status_history written)
      • Email notification sent to enrolled students  (FR-28)
    """
    original_entry  = models.ForeignKey(
        TimetableEntry, on_delete=models.CASCADE, related_name='postponements',
    )
    new_date        = models.DateField()
    new_day_of_week = models.CharField(max_length=10, choices=DayOfWeek.choices)
    new_start_time  = models.TimeField()
    new_end_time    = models.TimeField()
    new_venue       = models.ForeignKey(
        'venues.Venue', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='session_postponements',
    )
    reason          = models.TextField()
    postponed_by    = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name='postponed_sessions',
    )
    postponed_at    = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'session_postponements'
        ordering = ['-postponed_at']

    def __str__(self):
        return (
            f'{self.original_entry.course.course_code} postponed '
            f'→ {self.new_date} {self.new_start_time:%H:%M}'
        )


# ── Session Confirmation tracking (FR-29, FR-32, FR-33, FR-35) ───────────────

class SessionConfirmation(models.Model):
    """
    Tracks the confirmation status of ONE specific occurrence of a
    recurring TimetableEntry.

    A TimetableEntry defines a weekly recurring session (e.g. "BIT101 every Monday
    08:00–10:00"). This model records whether the lecturer confirmed, let it expire,
    or it was cancelled for a particular calendar date (e.g. 2025-11-17).

    Lifecycle
    ---------
      PENDING   → created when the session is scheduled for today / reminder sent
      CONFIRMED → lecturer taps "Confirm Session" within the confirmation window
      EXPIRED   → Celery task fires at start_time + window with no confirmation
      CANCELLED → session was cancelled before it started

    Only one record per (timetable_entry, session_date) pair is allowed.
    """

    class Status(models.TextChoices):
        PENDING   = 'PENDING',   'Pending Confirmation'
        CONFIRMED = 'CONFIRMED', 'Confirmed'
        EXPIRED   = 'EXPIRED',   'Expired — No Confirmation Received'
        CANCELLED = 'CANCELLED', 'Cancelled'

    timetable_entry  = models.ForeignKey(
        TimetableEntry, on_delete=models.CASCADE, related_name='confirmations',
    )
    session_date     = models.DateField(
        help_text='Calendar date of this specific occurrence.',
    )
    status           = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING,
    )

    # FR-33: timestamp written when lecturer confirms
    confirmed_at     = models.DateTimeField(null=True, blank=True)
    confirmed_by     = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='confirmed_sessions',
    )

    # FR-31: set when the reminder email/notification is dispatched to the lecturer
    reminder_sent_at = models.DateTimeField(null=True, blank=True)

    # FR-35: set when the expiry task fires and no confirmation was recorded
    expired_at       = models.DateTimeField(null=True, blank=True)

    created_at       = models.DateTimeField(auto_now_add=True)
    updated_at       = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'session_confirmations'
        unique_together = [('timetable_entry', 'session_date')]
        ordering = ['-session_date', 'timetable_entry']

    def __str__(self):
        return (
            f'{self.timetable_entry.course.course_code} '
            f'{self.session_date} — {self.status}'
        )

    @property
    def is_confirmed(self):
        return self.status == self.Status.CONFIRMED

    @property
    def is_expired(self):
        return self.status == self.Status.EXPIRED
