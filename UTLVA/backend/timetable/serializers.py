from rest_framework import serializers
from academics.models import AcademicYear, Semester
from .models import TimetableEntry, DayOfWeek, TimetableStatus


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

    class Meta:
        model = TimetableEntry
        fields = [
            'id',
            # Write fields (FK IDs)
            'academic_year', 'semester', 'programme', 'student_group',
            'course', 'lecturer', 'venue',
            'day_of_week', 'date', 'start_time', 'end_time', 'status',
            # Read display fields
            'academic_year_name', 'semester_name',
            'programme_name', 'programme_code',
            'student_group_name',
            'course_code', 'course_name',
            'lecturer_name', 'lecturer_staff_number',
            'venue_code', 'venue_name',
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
            'status_display', 'day_display', 'duration_minutes', 'created_by_name',
        ]

    def get_student_group_name(self, obj):
        return str(obj.student_group) if obj.student_group else None

    def get_venue_code(self, obj):
        return obj.venue.code if obj.venue else None

    def get_venue_name(self, obj):
        return obj.venue.name if obj.venue else None

    def get_created_by_name(self, obj):
        return obj.created_by.full_name if obj.created_by else None

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
    from academics.models import Programme
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
    """
    Request body for POST /api/timetable/validate/

    Fields
    ------
    academic_year   int   required
    semester        int   required
    """
    academic_year = serializers.PrimaryKeyRelatedField(queryset=AcademicYear.objects.all())
    semester = serializers.PrimaryKeyRelatedField(queryset=Semester.objects.all())

    def validate(self, data):
        if data['semester'].academic_year_id != data['academic_year'].pk:
            raise serializers.ValidationError(
                {'semester': 'Semester does not belong to the selected academic year.'}
            )
        return data
