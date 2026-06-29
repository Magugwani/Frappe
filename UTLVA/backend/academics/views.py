from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from accounts.permissions import IsAdminOrCoordinatorOrReadOnly
from .models import (
    AcademicYear, Semester, Department, Programme,
    StudentGroup, Course, Lecturer, LecturerCourse, StudentProfile,
    TeachingPeriod,
)
from .serializers import (
    AcademicYearSerializer, SemesterSerializer, DepartmentSerializer,
    ProgrammeSerializer, StudentGroupSerializer, CourseSerializer,
    LecturerSerializer, LecturerCourseSerializer, AssignCourseSerializer,
    StudentProfileSerializer, TeachingPeriodSerializer,
)


class AcademicYearViewSet(viewsets.ModelViewSet):
    queryset = AcademicYear.objects.all()
    serializer_class = AcademicYearSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        status_filter = self.request.query_params.get('status')
        if status_filter:
            qs = qs.filter(status=status_filter)
        return qs


class SemesterViewSet(viewsets.ModelViewSet):
    queryset = Semester.objects.select_related('academic_year').all()
    serializer_class = SemesterSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        year_id = self.request.query_params.get('academic_year')
        if year_id:
            qs = qs.filter(academic_year_id=year_id)
        return qs


class DepartmentViewSet(viewsets.ModelViewSet):
    queryset = Department.objects.all()
    serializer_class = DepartmentSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        search = self.request.query_params.get('search')
        if search:
            qs = qs.filter(name__icontains=search) | qs.filter(code__icontains=search)
        return qs


class ProgrammeViewSet(viewsets.ModelViewSet):
    queryset = Programme.objects.select_related('department').all()
    serializer_class = ProgrammeSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        dept_id = self.request.query_params.get('department')
        search = self.request.query_params.get('search')
        if dept_id:
            qs = qs.filter(department_id=dept_id)
        if search:
            qs = qs.filter(name__icontains=search) | qs.filter(code__icontains=search)
        return qs


class StudentGroupViewSet(viewsets.ModelViewSet):
    queryset = StudentGroup.objects.select_related('programme', 'academic_year').all()
    serializer_class = StudentGroupSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        prog_id = self.request.query_params.get('programme')
        year = self.request.query_params.get('year_of_study')
        academic_year = self.request.query_params.get('academic_year')
        if prog_id:
            qs = qs.filter(programme_id=prog_id)
        if year:
            qs = qs.filter(year_of_study=year)
        if academic_year:
            qs = qs.filter(academic_year_id=academic_year)
        return qs


class CourseViewSet(viewsets.ModelViewSet):
    queryset = Course.objects.select_related('programme', 'semester').all()
    serializer_class = CourseSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        prog_id = self.request.query_params.get('programme')
        sem_id = self.request.query_params.get('semester')
        year = self.request.query_params.get('year_of_study')
        search = self.request.query_params.get('search')
        if prog_id:
            qs = qs.filter(programme_id=prog_id)
        if sem_id:
            qs = qs.filter(semester_id=sem_id)
        if year:
            qs = qs.filter(year_of_study=year)
        if search:
            qs = qs.filter(course_name__icontains=search) | qs.filter(course_code__icontains=search)
        return qs


class LecturerViewSet(viewsets.ModelViewSet):
    queryset = Lecturer.objects.select_related('user', 'department').prefetch_related('course_assignments').all()
    serializer_class = LecturerSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        dept_id = self.request.query_params.get('department')
        search = self.request.query_params.get('search')
        if dept_id:
            qs = qs.filter(department_id=dept_id)
        if search:
            qs = qs.filter(user__full_name__icontains=search) | qs.filter(staff_number__icontains=search)
        return qs

    @action(detail=True, methods=['post'], url_path='assign-course')
    def assign_course(self, request, pk=None):
        """POST /api/academics/lecturers/{id}/assign-course/"""
        lecturer = self.get_object()
        serializer = AssignCourseSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        course_id = serializer.validated_data['course_id']
        academic_year_id = serializer.validated_data.get('academic_year_id')

        assignment, created = LecturerCourse.objects.get_or_create(
            lecturer=lecturer,
            course_id=course_id,
            academic_year_id=academic_year_id,
        )
        return Response(
            LecturerCourseSerializer(assignment).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @action(detail=True, methods=['delete'], url_path='remove-course/(?P<assignment_id>[^/.]+)')
    def remove_course(self, request, pk=None, assignment_id=None):
        """DELETE /api/academics/lecturers/{id}/remove-course/{assignment_id}/"""
        lecturer = self.get_object()
        try:
            assignment = LecturerCourse.objects.get(pk=assignment_id, lecturer=lecturer)
            assignment.delete()
            return Response(status=status.HTTP_204_NO_CONTENT)
        except LecturerCourse.DoesNotExist:
            return Response({'detail': 'Assignment not found.'}, status=status.HTTP_404_NOT_FOUND)

    @action(detail=False, methods=['get'], url_path='my-courses',
            permission_classes=[IsAuthenticated])
    def my_courses(self, request):
        """
        GET /api/academics/lecturers/my-courses/
        Returns courses assigned to the authenticated lecturer (FR-20).
        """
        try:
            lecturer = Lecturer.objects.get(user=request.user)
        except Lecturer.DoesNotExist:
            return Response(
                {'detail': 'No lecturer profile found for this account.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        assignments = (
            LecturerCourse.objects
            .select_related('course__programme', 'academic_year')
            .filter(lecturer=lecturer)
            .order_by('academic_year__name', 'course__course_code')
        )

        data = [
            {
                'assignment_id': a.id,
                'course_id': a.course.id,
                'course_code': a.course.course_code,
                'course_name': a.course.course_name,
                'programme_code': a.course.programme.code,
                'programme_name': a.course.programme.name,
                'year_of_study': a.course.year_of_study,
                'weekly_hours': a.course.weekly_hours,
                'credit_hours': a.course.credit_hours,
                'required_venue_type': a.course.required_venue_type,
                'academic_year': a.academic_year.name if a.academic_year else None,
                'assigned_at': str(a.assigned_at) if hasattr(a, 'assigned_at') else None,
            }
            for a in assignments
        ]
        return Response({'count': len(data), 'courses': data})


class StudentProfileViewSet(viewsets.ModelViewSet):
    """
    Minimal student profile — links a student user to their programme and group.
    Enables automatic timetable filtering without manual selection each time.
    """
    serializer_class = StudentProfileSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        # Coordinator/Admin sees all profiles; student sees only own
        if user.role in ('SYSTEM_ADMIN', 'COORDINATOR'):
            return StudentProfile.objects.select_related('user', 'programme', 'student_group').all()
        return StudentProfile.objects.select_related('user', 'programme', 'student_group').filter(user=user)

    @action(detail=False, methods=['get'], url_path='me')
    def me(self, request):
        """GET /api/academics/student-profiles/me/ — returns the calling student's profile."""
        try:
            profile = StudentProfile.objects.select_related(
                'user', 'programme', 'student_group'
            ).get(user=request.user)
            return Response(StudentProfileSerializer(profile).data)
        except StudentProfile.DoesNotExist:
            return Response({'detail': 'No student profile found.'}, status=404)

    @action(detail=False, methods=['put', 'patch'], url_path='me/update')
    def me_update(self, request):
        """PUT /api/academics/student-profiles/me/update/ — update own profile."""
        try:
            profile = StudentProfile.objects.get(user=request.user)
        except StudentProfile.DoesNotExist:
            return Response({'detail': 'No student profile found.'}, status=404)
        serializer = StudentProfileSerializer(profile, data=request.data, partial=request.method == 'PATCH')
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=400)


class TeachingPeriodViewSet(viewsets.ModelViewSet):
    """
    CRUD for teaching periods (candidate timetable slots).

    Coordinator defines these per semester before timetable generation.
    The Phase 5 generator will iterate over active periods to place courses.

    Filters:
      ?semester=N       — periods for a specific semester
      ?day_of_week=X    — filter by day
      ?is_active=true   — only active periods
    """
    serializer_class = TeachingPeriodSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = TeachingPeriod.objects.select_related(
            'semester__academic_year'
        ).all()
        p = self.request.query_params
        if p.get('semester'):
            qs = qs.filter(semester_id=p['semester'])
        if p.get('day_of_week'):
            qs = qs.filter(day_of_week=p['day_of_week'])
        if p.get('is_active') is not None:
            qs = qs.filter(is_active=p['is_active'].lower() == 'true')
        if p.get('academic_year'):
            qs = qs.filter(semester__academic_year_id=p['academic_year'])
        return qs
