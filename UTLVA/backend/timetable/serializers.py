from rest_framework import serializers
from academics.models import AcademicYear, Semester, Programme, StudentGroup, Course, Lecturer
from venues.models import Venue
from .models import TimetableEntry, DayOfWeek, TimetableStatus, EmergencySession, SystemConfiguration


class TimetableEntrySerializer(serializers.ModelSerializer):
    # Read-only display fields
    academic_year_name = serializers.CharField(source='academic_year.name', read_only=True)
    semester_name = serializers.CharField(source='semester.name', read_only=True)
    programme_name = serializers.CharField(source='programme.name', read_only=True)
    programme_code = serializers.CharField(source='programme.code', read_only=True)
    student_group_name = serializers.SerializerMethodField()
    course_code = serializers.CharField(source='course.course_code', read_only=True)
    course_name = serializers.CharField(source='course.course_name', read_only=True)
    lecturer_name = serializers.CharField(source='lecturer.user.full_name', read_only=True)
    lecturer_staff_number = serializers.CharField(source='lecturer.staff_number', read_only=True)
    venue_code = serializers.SerializerMethodField()
    venue_name = serializers.SerializerMethodField()
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    day_display = serializers.CharField(source='get_day_of_week_display', read_only=True)
    duration_minutes = serializers.ReadOnlyField()
    created_by_name = serializers.SerializerMethodField()
    # Phase 8: venue override read field
    venue_override_by_name = serializers.SerializerMethodField()
    # Live timetable: venue status + GPS for map navigation
    venue_status = serializers.SerializerMethodField()
    venue_status_display = serializers.SerializerMethodField()
    venue_marker_color = serializers.SerializerMethodField()
    venue_latitude = serializers.SerializerMethodField()
    venue_longitude = serializers.SerializerMethodField()
    venue_floor = serializers.SerializerMethodField()
    venue_building_name = serializers.SerializerMethodField()
    venue_indoor_identifier = serializers.SerializerMethodField()

    class Meta:
        model = TimetableEntry
        fields = [
            'id',
            # Write fields (FK IDs)
            'academic_year', 'semester', 'programme', 'student_group',
            'course', 'lecturer', 'venue',
            'day_of_week', 'date', 'start_time', 'end_time', 'status',
            # Phase 8 fields
            'expected_student_count',
            'venue_override_by', 'venue_override_by_name',
            'venue_override_reason', 'venue_override_at',
            # Read display fields
            'academic_year_name', 'semester_name',
            'programme_name', 'programme_code',
            'student_group_name',
            'course_code', 'course_name',
            'lecturer_name', 'lecturer_staff_number',
            'venue_code', 'venue_name',
            # Live timetable venue fields
            'venue_status', 'venue_status_display', 'venue_marker_color',
            'venue_latitude', 'venue_longitude',
            'venue_floor', 'venue_building_name', 'venue_indoor_identifier',
            'status_display', 'day_display', 'duration_minutes',
            'created_by_name',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'created_at', 'updated_at',
            'academic_year_name', 'semester_name', 'programme_name', 'programme_code',
            'student_group_name', 'course_code', 'course_name',
            'lecturer_name', 'lecturer_staff_number',
            'venue_code', 'venue_name',
            'venue_status', 'venue_status_display', 'venue_marker_color',
            'venue_latitude', 'venue_longitude',
            'venue_floor', 'venue_building_name', 'venue_indoor_identifier',
            'status_display', 'day_display', 'duration_minutes', 'created_by_name',
            'venue_override_by_name',
        ]

    def get_student_group_name(self, obj):
        return str(obj.student_group) if obj.student_group else None

    def get_venue_code(self, obj):
        return obj.venue.code if obj.venue else None

    def get_venue_name(self, obj):
        return obj.venue.name if obj.venue else None

    def get_created_by_name(self, obj):
        return obj.created_by.full_name if obj.created_by else None

    def get_venue_override_by_name(self, obj):
        return obj.venue_override_by.full_name if obj.venue_override_by else None

    # ── Live timetable: venue status + location ───────────────────────────────

    def get_venue_status(self, obj):
        return obj.venue.status if obj.venue else None

    def get_venue_status_display(self, obj):
        return obj.venue.get_status_display() if obj.venue else None

    def get_venue_marker_color(self, obj):
        return obj.venue.status_marker_color if obj.venue else None

    def get_venue_latitude(self, obj):
        if not obj.venue:
            return None
        lat = obj.venue.effective_latitude
        return float(lat) if lat is not None else None

    def get_venue_longitude(self, obj):
        if not obj.venue:
            return None
        lng = obj.venue.effective_longitude
        return float(lng) if lng is not None else None

    def get_venue_floor(self, obj):
        return obj.venue.floor if obj.venue else None

    def get_venue_building_name(self, obj):
        return obj.venue.building.name if obj.venue else None

    def get_venue_indoor_identifier(self, obj):
        return obj.venue.indoor_identifier if obj.venue else None

    def validate(self, data):
        start = data.get('start_time') or self.instance.start_time if self.instance else data.get('start_time')
        end = data.get('end_time') or self.instance.end_time if self.instance else data.get('end_time')
        if start and end and start >= end:
            raise serializers.ValidationError({'end_time': 'End time must be after start time.'})
        return data


class GenerateRequestSerializer(serializers.Serializer):
    """
    Request body for POST /api/timetable/generate/

    Fields
    ------
    academic_year   int   required
    semester        int   required
    programme       int   required — single programme to generate for
    dry_run         bool  optional (default false) — preview without writing
    """
    academic_year = serializers.PrimaryKeyRelatedField(queryset=AcademicYear.objects.all())
    semester = serializers.PrimaryKeyRelatedField(queryset=Semester.objects.all())
    programme = serializers.PrimaryKeyRelatedField(
        queryset=Programme.objects.all(),
        required=True,
        help_text='Programme to generate timetable for.',
    )
    dry_run = serializers.BooleanField(
        default=False,
        help_text='When true, computes schedule but writes nothing to the database.',
    )

    def validate(self, data):
        if data['semester'].academic_year_id != data['academic_year'].pk:
            raise serializers.ValidationError(
                {'semester': 'Semester does not belong to the selected academic year.'}
            )
        return data


class ValidateRequestSerializer(serializers.Serializer):
    """Request body for POST /api/timetable/validate/"""
    academic_year = serializers.PrimaryKeyRelatedField(queryset=AcademicYear.objects.all())
    semester = serializers.PrimaryKeyRelatedField(queryset=Semester.objects.all())

    def validate(self, data):
        if data['semester'].academic_year_id != data['academic_year'].pk:
            raise serializers.ValidationError(
                {'semester': 'Semester does not belong to the selected academic year.'}
            )
        return data


# Reuse same shape for publish + status requests
PublishRequestSerializer = ValidateRequestSerializer
StatusRequestSerializer = ValidateRequestSerializer


class ConflictResolveSerializer(serializers.Serializer):
    """Request body for POST /api/timetable/conflicts/{id}/resolve/"""
    resolution_note = serializers.CharField(
        max_length=1000,
        allow_blank=False,
        help_text='Describe how the conflict was resolved.',
    )


# ── Phase 8: Venue Recommendation ─────────────────────────────────────────────

class VenueRecommendationRequestSerializer(serializers.Serializer):
    """Request body for POST /api/timetable/venue-recommendations/"""
    students_count = serializers.IntegerField(min_value=1)
    venue_type = serializers.ChoiceField(
        choices=[
            'LECTURE_HALL', 'CLASSROOM', 'LABORATORY',
            'COMPUTER_LAB', 'SEMINAR_ROOM', 'AUDITORIUM',
        ],
        required=False,
        allow_null=True,
    )
    required_resources = serializers.ListField(
        child=serializers.CharField(), required=False, default=list,
    )
    day_of_week = serializers.ChoiceField(choices=DayOfWeek.choices)
    start_time = serializers.TimeField()
    end_time = serializers.TimeField()
    semester = serializers.PrimaryKeyRelatedField(
        queryset=Semester.objects.all(), required=False, allow_null=True,
    )

    def validate(self, data):
        if data.get('start_time') and data.get('end_time'):
            if data['start_time'] >= data['end_time']:
                raise serializers.ValidationError({'end_time': 'End time must be after start time.'})
        return data


# ── Phase 8: Emergency Session ────────────────────────────────────────────────

class EmergencySessionSerializer(serializers.ModelSerializer):
    """Read serializer for EmergencySession (FR-23)."""
    course_code = serializers.CharField(source='course.course_code', read_only=True)
    course_name = serializers.CharField(source='course.course_name', read_only=True)
    lecturer_name = serializers.CharField(source='lecturer.user.full_name', read_only=True)
    venue_code = serializers.SerializerMethodField()
    venue_name = serializers.SerializerMethodField()
    requested_by_name = serializers.SerializerMethodField()
    reviewed_by_name = serializers.SerializerMethodField()
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    day_display = serializers.CharField(source='get_day_of_week_display', read_only=True)
    student_group_ids = serializers.SerializerMethodField()

    class Meta:
        model = EmergencySession
        fields = [
            'id',
            # FR-23 required session fields
            'title', 'course', 'course_code', 'course_name',
            'lecturer', 'lecturer_name',
            'expected_students', 'required_resources',
            'venue', 'venue_code', 'venue_name',
            'student_group_ids',
            'requested_date', 'day_of_week', 'day_display',
            'start_time', 'end_time',
            'reason', 'comments',
            'status', 'status_display',
            'requested_by', 'requested_by_name',
            'reviewed_by', 'reviewed_by_name',
            'reviewed_at', 'review_note',
            # FR-24 conflict flags
            'lecturer_conflict', 'venue_conflict', 'group_conflict', 'capacity_conflict',
            'created_at',
        ]
        read_only_fields = fields

    def get_venue_code(self, obj):
        return obj.venue.code if obj.venue else None

    def get_venue_name(self, obj):
        return obj.venue.name if obj.venue else None

    def get_requested_by_name(self, obj):
        return obj.requested_by.full_name if obj.requested_by else None

    def get_reviewed_by_name(self, obj):
        return obj.reviewed_by.full_name if obj.reviewed_by else None

    def get_student_group_ids(self, obj):
        return list(obj.student_groups.values_list('id', flat=True))


class EmergencySessionCreateSerializer(serializers.Serializer):
    """Write serializer — used when creating a new emergency session (FR-23)."""
    title             = serializers.CharField(max_length=200, required=False, allow_blank=True, default='')
    course            = serializers.PrimaryKeyRelatedField(queryset=Course.objects.all())
    lecturer          = serializers.PrimaryKeyRelatedField(queryset=Lecturer.objects.all())
    expected_students = serializers.IntegerField(min_value=1, required=False, allow_null=True)
    required_resources= serializers.ListField(child=serializers.CharField(), required=False, default=list)
    venue             = serializers.PrimaryKeyRelatedField(
        queryset=Venue.objects.all(), required=False, allow_null=True,
    )
    student_groups    = serializers.PrimaryKeyRelatedField(
        queryset=StudentGroup.objects.all(), many=True, required=False,
    )
    requested_date = serializers.DateField()
    day_of_week    = serializers.ChoiceField(choices=DayOfWeek.choices)
    start_time     = serializers.TimeField()
    end_time       = serializers.TimeField()
    reason         = serializers.CharField()
    comments       = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, data):
        if data.get('start_time') and data.get('end_time'):
            if data['start_time'] >= data['end_time']:
                raise serializers.ValidationError({'end_time': 'End time must be after start time.'})
        return data


class EmergencySessionReviewSerializer(serializers.Serializer):
    """Request body for approve/reject actions."""
    note = serializers.CharField(allow_blank=True, default='')


# ── Phase 8: System Configuration ────────────────────────────────────────────

class SystemConfigSerializer(serializers.ModelSerializer):
    """Read serializer — returns all SRS §3.11 configuration parameters."""
    updated_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SystemConfiguration
        fields = [
            'id',
            # Session lifecycle
            'capacity_overhead',
            'confirmation_window_minutes',
            'reminder_lead_minutes',
            # SMS protections
            'sms_daily_cap_per_user',
            'sms_bulk_approval_threshold',
            # Account management
            'password_reset_link_hours',
            'max_bulk_upload_rows',
            # Celery Beat
            'venue_status_check_interval_seconds',
            # Audit
            'updated_by', 'updated_by_name', 'updated_at',
        ]
        read_only_fields = ['id', 'updated_by', 'updated_by_name', 'updated_at']

    def get_updated_by_name(self, obj):
        return obj.updated_by.full_name if obj.updated_by else None


class SystemConfigUpdateSerializer(serializers.Serializer):
    """Write serializer — all fields optional; only supplied ones are updated."""
    # Session lifecycle
    capacity_overhead           = serializers.FloatField(min_value=1.0, max_value=5.0,   required=False)
    confirmation_window_minutes = serializers.IntegerField(min_value=1,  max_value=120,   required=False)
    reminder_lead_minutes       = serializers.IntegerField(min_value=1,  max_value=480,   required=False)
    # SMS
    sms_daily_cap_per_user      = serializers.IntegerField(min_value=1,  max_value=100,   required=False)
    sms_bulk_approval_threshold = serializers.IntegerField(min_value=1,  max_value=10000, required=False)
    # Account / enrollment
    password_reset_link_hours   = serializers.IntegerField(min_value=1,  max_value=168,   required=False)
    max_bulk_upload_rows        = serializers.IntegerField(min_value=1,  max_value=50000, required=False)
    # Celery Beat
    venue_status_check_interval_seconds = serializers.IntegerField(min_value=10, max_value=3600, required=False)


# ── SRS 3.4: Session postponement (FR-26, FR-27) ─────────────────────────────

class SessionConfirmationSerializer(serializers.ModelSerializer):
    """FR-33/FR-35: Read serializer for a session occurrence's confirmation record."""
    confirmed_by_name = serializers.SerializerMethodField()
    status_display    = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        from .models import SessionConfirmation
        model = SessionConfirmation
        fields = [
            'id', 'timetable_entry', 'session_date', 'status', 'status_display',
            'confirmed_at', 'confirmed_by', 'confirmed_by_name',
            'reminder_sent_at', 'expired_at',
            'created_at', 'updated_at',
        ]
        read_only_fields = fields

    def get_confirmed_by_name(self, obj):
        return obj.confirmed_by.full_name if obj.confirmed_by else None


class PostponeRequestSerializer(serializers.Serializer):
    """Request body for POST /api/timetable/entries/{id}/postpone/ (FR-27)."""
    new_date        = serializers.DateField()
    new_day_of_week = serializers.ChoiceField(choices=DayOfWeek.choices)
    new_start_time  = serializers.TimeField()
    new_end_time    = serializers.TimeField()
    new_venue       = serializers.PrimaryKeyRelatedField(
        queryset=Venue.objects.all(), required=False, allow_null=True,
    )
    reason          = serializers.CharField()

    def validate(self, data):
        if data.get('new_start_time') and data.get('new_end_time'):
            if data['new_start_time'] >= data['new_end_time']:
                raise serializers.ValidationError({'new_end_time': 'End time must be after start time.'})
        return data


class SessionPostponementSerializer(serializers.ModelSerializer):
    """Read serializer for a SessionPostponement record."""
    from .models import SessionPostponement
    original_course_code = serializers.CharField(
        source='original_entry.course.course_code', read_only=True,
    )
    new_venue_code = serializers.SerializerMethodField()
    postponed_by_name = serializers.SerializerMethodField()
    new_day_display = serializers.CharField(source='get_new_day_of_week_display', read_only=True)

    class Meta:
        from .models import SessionPostponement as SP
        model = SP
        fields = [
            'id', 'original_entry', 'original_course_code',
            'new_date', 'new_day_of_week', 'new_day_display',
            'new_start_time', 'new_end_time',
            'new_venue', 'new_venue_code',
            'reason', 'postponed_by', 'postponed_by_name', 'postponed_at',
        ]
        read_only_fields = fields

    def get_new_venue_code(self, obj):
        return obj.new_venue.code if obj.new_venue else None

    def get_postponed_by_name(self, obj):
        return obj.postponed_by.full_name if obj.postponed_by else None
