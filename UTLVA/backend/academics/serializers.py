from rest_framework import serializers
from .models import (
    AcademicYear, Semester, Department, Programme,
    StudentGroup, Course, Lecturer, LecturerCourse,
    StudentProfile, TeachingPeriod,
)
from accounts.models import User


class AcademicYearSerializer(serializers.ModelSerializer):
    is_active = serializers.BooleanField(read_only=True)  # computed from status

    class Meta:
        model = AcademicYear
        fields = ['id', 'name', 'start_date', 'end_date', 'status', 'is_active', 'created_at', 'updated_at']
        read_only_fields = ['id', 'is_active', 'created_at', 'updated_at']


class SemesterSerializer(serializers.ModelSerializer):
    academic_year_name = serializers.CharField(source='academic_year.name', read_only=True)
    teaching_period_count = serializers.SerializerMethodField()

    class Meta:
        model = Semester
        fields = [
            'id', 'academic_year', 'academic_year_name',
            'name', 'start_date', 'end_date', 'is_active',
            'teaching_period_count',
        ]
        read_only_fields = ['id', 'academic_year_name', 'teaching_period_count']

    def get_teaching_period_count(self, obj):
        return obj.teaching_periods.filter(is_active=True).count()


class DepartmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Department
        fields = ['id', 'name', 'code']
        read_only_fields = ['id']


class ProgrammeSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(source='department.name', read_only=True)
    department_code = serializers.CharField(source='department.code', read_only=True)

    class Meta:
        model = Programme
        fields = ['id', 'department', 'department_name', 'department_code', 'name', 'code', 'duration_years']
        read_only_fields = ['id', 'department_name', 'department_code']


class StudentGroupSerializer(serializers.ModelSerializer):
    programme_name = serializers.CharField(source='programme.name', read_only=True)
    programme_code = serializers.CharField(source='programme.code', read_only=True)
    academic_year_name = serializers.CharField(source='academic_year.name', read_only=True)
    display_name = serializers.ReadOnlyField()

    class Meta:
        model = StudentGroup
        fields = [
            'id', 'programme', 'programme_name', 'programme_code',
            'academic_year', 'academic_year_name',
            'year_of_study', 'group_name', 'student_count', 'display_name',
        ]
        read_only_fields = ['id', 'programme_name', 'programme_code', 'academic_year_name', 'display_name']


class CourseSerializer(serializers.ModelSerializer):
    programme_name = serializers.CharField(source='programme.name', read_only=True)
    programme_code = serializers.CharField(source='programme.code', read_only=True)
    semester_name = serializers.SerializerMethodField()

    class Meta:
        model = Course
        fields = [
            'id', 'course_code', 'course_name',
            'programme', 'programme_name', 'programme_code',
            'semester', 'semester_name',
            'year_of_study', 'credit_hours', 'weekly_hours',
            'required_venue_type', 'required_resources',
        ]
        read_only_fields = ['id', 'programme_name', 'programme_code', 'semester_name']

    def get_semester_name(self, obj):
        return str(obj.semester) if obj.semester else None


class LecturerCourseSerializer(serializers.ModelSerializer):
    course_code = serializers.CharField(source='course.course_code', read_only=True)
    course_name = serializers.CharField(source='course.course_name', read_only=True)
    academic_year_name = serializers.CharField(source='academic_year.name', read_only=True)

    class Meta:
        model = LecturerCourse
        fields = [
            'id', 'lecturer', 'course', 'course_code', 'course_name',
            'academic_year', 'academic_year_name', 'assigned_at',
        ]
        read_only_fields = ['id', 'course_code', 'course_name', 'academic_year_name', 'assigned_at']


class LecturerSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(source='user.full_name', read_only=True)
    email = serializers.CharField(source='user.email', read_only=True)
    department_name = serializers.CharField(source='department.name', read_only=True)
    department_code = serializers.CharField(source='department.code', read_only=True)
    course_assignments = LecturerCourseSerializer(many=True, read_only=True)

    class Meta:
        model = Lecturer
        fields = [
            'id', 'user', 'full_name', 'email',
            'staff_number', 'department', 'department_name', 'department_code',
            'course_assignments',
        ]
        read_only_fields = ['id', 'full_name', 'email', 'department_name', 'department_code', 'course_assignments']


class StudentProfileSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(source='user.full_name', read_only=True)
    email = serializers.CharField(source='user.email', read_only=True)
    programme_name = serializers.CharField(source='programme.name', read_only=True)
    programme_code = serializers.CharField(source='programme.code', read_only=True)
    student_group_name = serializers.SerializerMethodField()

    class Meta:
        model = StudentProfile
        fields = [
            'id', 'user', 'full_name', 'email',
            'registration_number',
            'programme', 'programme_name', 'programme_code',
            'student_group', 'student_group_name',
        ]
        read_only_fields = ['id', 'full_name', 'email', 'programme_name', 'programme_code', 'student_group_name']

    def get_student_group_name(self, obj):
        return str(obj.student_group) if obj.student_group else None


class AssignCourseSerializer(serializers.Serializer):
    course_id = serializers.IntegerField()
    academic_year_id = serializers.IntegerField(required=False, allow_null=True)

    def validate_course_id(self, value):
        if not Course.objects.filter(pk=value).exists():
            raise serializers.ValidationError('Course not found.')
        return value


class TeachingPeriodSerializer(serializers.ModelSerializer):
    semester_name = serializers.CharField(source='semester.name', read_only=True)
    academic_year_name = serializers.CharField(source='semester.academic_year.name', read_only=True)
    day_display = serializers.CharField(source='get_day_of_week_display', read_only=True)
    duration_minutes = serializers.ReadOnlyField()

    class Meta:
        model = TeachingPeriod
        fields = [
            'id',
            'semester', 'semester_name', 'academic_year_name',
            'day_of_week', 'day_display',
            'start_time', 'end_time',
            'label', 'is_active', 'duration_minutes',
        ]
        read_only_fields = ['id', 'semester_name', 'academic_year_name', 'day_display', 'duration_minutes']

    def validate(self, data):
        start = data.get('start_time') or (self.instance.start_time if self.instance else None)
        end = data.get('end_time') or (self.instance.end_time if self.instance else None)
        if start and end and start >= end:
            raise serializers.ValidationError({'end_time': 'End time must be after start time.'})
        return data
