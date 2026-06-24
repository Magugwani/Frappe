from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from accounts.permissions import IsAdminOrCoordinatorOrReadOnly, IsSystemAdminOrCoordinator
from accounts.models import Role
from academics.models import Lecturer
from .models import TimetableEntry
from .serializers import TimetableEntrySerializer, GenerateRequestSerializer, ValidateRequestSerializer
from .generator import TimetableGenerator
from .services.validator import TimetableValidationService


class TimetableEntryViewSet(viewsets.ModelViewSet):
    serializer_class = TimetableEntrySerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = TimetableEntry.objects.select_related(
            'academic_year', 'semester', 'programme', 'student_group',
            'course', 'lecturer__user', 'venue__building',
        ).all()

        # Filters (all optional, used by all roles for display)
        p = self.request.query_params
        if p.get('academic_year'):
            qs = qs.filter(academic_year_id=p['academic_year'])
        if p.get('semester'):
            qs = qs.filter(semester_id=p['semester'])
        if p.get('programme'):
            qs = qs.filter(programme_id=p['programme'])
        if p.get('student_group'):
            qs = qs.filter(student_group_id=p['student_group'])
        if p.get('status'):
            qs = qs.filter(status=p['status'])
        if p.get('day_of_week'):
            qs = qs.filter(day_of_week=p['day_of_week'])
        if p.get('lecturer'):
            qs = qs.filter(lecturer_id=p['lecturer'])

        return qs

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

    # ── Lecturer: view own timetable ────────────────────────────────────────
    @action(detail=False, methods=['get'], url_path='my-lecturer-timetable',
            permission_classes=[IsAuthenticated])
    def my_lecturer_timetable(self, request):
        """Returns all timetable entries for the authenticated lecturer."""
        if request.user.role != Role.LECTURER:
            return Response(
                {'detail': 'Only lecturers can access this endpoint.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        try:
            lecturer = Lecturer.objects.get(user=request.user)
        except Lecturer.DoesNotExist:
            return Response({'detail': 'Lecturer profile not found.'}, status=status.HTTP_404_NOT_FOUND)

        qs = TimetableEntry.objects.select_related(
            'academic_year', 'semester', 'programme', 'student_group',
            'course', 'lecturer__user', 'venue',
        ).filter(lecturer=lecturer)

        p = request.query_params
        if p.get('academic_year'):
            qs = qs.filter(academic_year_id=p['academic_year'])
        if p.get('semester'):
            qs = qs.filter(semester_id=p['semester'])
        if p.get('status'):
            qs = qs.filter(status=p['status'])

        serializer = self.get_serializer(qs, many=True)
        return Response(serializer.data)

    # ── Student: view timetable ────────────────────────────────────────────
    @action(detail=False, methods=['get'], url_path='my-student-timetable',
            permission_classes=[IsAuthenticated])
    def my_student_timetable(self, request):
        """
        Returns published timetable entries for a student.

        Programme and group are resolved in priority order:
          1. Query params (?programme=N, ?student_group=M) — explicit override.
          2. StudentProfile linked to the requesting user — automatic detection.
        If neither resolves a programme, returns 400 with guidance.
        """
        from academics.models import StudentProfile

        # Explicit query params take priority (allows override by student)
        programme_id = request.query_params.get('programme')
        group_id = request.query_params.get('student_group')

        # Auto-detect from StudentProfile when params not provided
        if not programme_id:
            try:
                profile = StudentProfile.objects.select_related(
                    'programme', 'student_group'
                ).get(user=request.user)
                programme_id = profile.programme_id
                if not group_id and profile.student_group_id:
                    group_id = profile.student_group_id
            except StudentProfile.DoesNotExist:
                pass

        if not programme_id:
            return Response(
                {
                    'detail': 'Programme not found. Set up your student profile '
                              'or pass ?programme=ID as a query parameter.',
                    'requires_profile': True,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        qs = TimetableEntry.objects.select_related(
            'academic_year', 'semester', 'programme', 'student_group',
            'course', 'lecturer__user', 'venue',
        ).filter(programme_id=programme_id, status='PUBLISHED')

        if group_id:
            qs = qs.filter(student_group_id=group_id)

        p = request.query_params
        if p.get('academic_year'):
            qs = qs.filter(academic_year_id=p['academic_year'])
        if p.get('semester'):
            qs = qs.filter(semester_id=p['semester'])

        serializer = self.get_serializer(qs, many=True)
        return Response(serializer.data)


class TimetableGenerateView(APIView):
    """
    POST /api/timetable/generate/

    Triggers the automatic timetable generation engine for a given
    academic year and semester.

    Body:
        academic_year   int       required
        semester        int       required
        programme_ids   [int]     optional — restrict to specific programmes
        dry_run         bool      default false — compute without writing

    Returns a GenerationResult with generated_count, failed_count,
    and per-entry details so the coordinator can review before publishing.

    Permission: SYSTEM_ADMIN or COORDINATOR only.
    """
    permission_classes = [IsSystemAdminOrCoordinator]

    def post(self, request):
        serializer = GenerateRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        data = serializer.validated_data
        academic_year = data['academic_year']
        semester = data['semester']
        programme = data['programme']
        dry_run = data.get('dry_run', False)

        generator = TimetableGenerator(
            academic_year=academic_year,
            semester=semester,
            programme=programme,
            dry_run=dry_run,
            created_by=request.user,
        )

        result = generator.generate()
        return Response(result.to_dict(), status=status.HTTP_200_OK)


class TimetableValidateView(APIView):
    """
    POST /api/timetable/validate/

    Runs the conflict detection engine over all DRAFT/VALIDATED/PUBLISHED
    entries in the given semester.

    If zero conflicts are found, all DRAFT entries are promoted to VALIDATED.
    If conflicts exist, they are persisted as TimetableConflict records and
    returned in the response for the coordinator to review.

    Permission: SYSTEM_ADMIN or COORDINATOR only.
    """
    permission_classes = [IsSystemAdminOrCoordinator]

    def post(self, request):
        serializer = ValidateRequestSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        data = serializer.validated_data
        validator = TimetableValidationService(
            academic_year=data['academic_year'],
            semester=data['semester'],
        )
        result = validator.validate()
        return Response(result.to_dict(), status=status.HTTP_200_OK)
