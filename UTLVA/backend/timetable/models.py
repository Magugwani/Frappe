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
    DRAFT = 'DRAFT', 'Draft'
    VALIDATED = 'VALIDATED', 'Validated'
    PUBLISHED = 'PUBLISHED', 'Published'
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
    """Singleton: one row holds all system-wide numeric parameters."""
    capacity_overhead = models.FloatField(
        default=1.5,
        help_text='Multiplier for maximum venue capacity. '
                  'Example: 100 students → allow up to 150-capacity venues.',
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

    course         = models.ForeignKey('academics.Course',   on_delete=models.CASCADE, related_name='emergency_sessions')
    lecturer       = models.ForeignKey('academics.Lecturer', on_delete=models.CASCADE, related_name='emergency_sessions')
    venue          = models.ForeignKey('venues.Venue',        on_delete=models.SET_NULL, null=True, blank=True, related_name='emergency_sessions')
    student_groups = models.ManyToManyField('academics.StudentGroup', blank=True, related_name='emergency_sessions')

    requested_date = models.DateField()
    day_of_week    = models.CharField(max_length=10, choices=DayOfWeek.choices)
    start_time     = models.TimeField()
    end_time       = models.TimeField()
    reason         = models.TextField(help_text='Why this emergency session is needed.')

    status       = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    requested_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='requested_emergency_sessions')
    reviewed_by  = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='reviewed_emergency_sessions')
    reviewed_at  = models.DateTimeField(null=True, blank=True)
    review_note  = models.TextField(blank=True)
    created_at   = models.DateTimeField(auto_now_add=True)

    # Availability check results stored at creation time
    lecturer_conflict = models.BooleanField(default=False)
    venue_conflict    = models.BooleanField(default=False)
    group_conflict    = models.BooleanField(default=False)

    class Meta:
        db_table = 'emergency_sessions'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.course.course_code} emergency — {self.requested_date} | {self.status}'
