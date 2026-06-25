from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView
from accounts.permissions import IsAdminOrCoordinatorOrReadOnly, IsSystemAdminOrCoordinator, IsSystemAdmin
from accounts.models import Role
from academics.models import Lecturer
from .models import TimetableEntry, TimetableConflict, TimetableStatus, EmergencySession, SystemConfiguration
from .serializers import (
    TimetableEntrySerializer, GenerateRequestSerializer,
    ValidateRequestSerializer, PublishRequestSerializer,
    StatusRequestSerializer, ConflictResolveSerializer,
    VenueRecommendationRequestSerializer,
    EmergencySessionSerializer, EmergencySessionCreateSerializer,
    EmergencySessionReviewSerializer,
    SystemConfigSerializer, SystemConfigUpdateSerializer,
)
from .generator import TimetableGenerator
from .services.validator import TimetableValidationService
from .services.publisher import (
    get_timetable_status, publish_timetable,
    unpublish_timetable, resolve_conflict,
)
from .services.venue_recommender import VenueRecommendationService
from .services.emergency_service import EmergencySessionService


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
        ).filter(
            lecturer=lecturer,
            status=TimetableStatus.PUBLISHED,   # Lecturers see only PUBLISHED entries
        )

        p = request.query_params
        if p.get('academic_year'):
            qs = qs.filter(academic_year_id=p['academic_year'])
        if p.get('semester'):
            qs = qs.filter(semester_id=p['semester'])

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


class TimetableStatusView(APIView):
    """
    GET /api/timetable/status/?academic_year=1&semester=1

    Returns current lifecycle state of the timetable for the semester.
    All authenticated roles can query this.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        s = StatusRequestSerializer(data=request.query_params)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        data = s.validated_data
        result = get_timetable_status(data['academic_year'], data['semester'])
        return Response(result, status=status.HTTP_200_OK)


class TimetablePublishView(APIView):
    """
    POST /api/timetable/publish/

    Promotes all VALIDATED entries → PUBLISHED.
    Rejected if any OPEN conflicts exist.
    Permission: SYSTEM_ADMIN or COORDINATOR.
    """
    permission_classes = [IsSystemAdminOrCoordinator]

    def post(self, request):
        s = PublishRequestSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        data = s.validated_data
        result = publish_timetable(data['academic_year'], data['semester'], request.user)
        http_status = status.HTTP_200_OK if result['success'] else status.HTTP_422_UNPROCESSABLE_ENTITY
        return Response(result, status=http_status)


class TimetableUnpublishView(APIView):
    """
    POST /api/timetable/unpublish/

    Reverts PUBLISHED → VALIDATED.
    Only SYSTEM_ADMIN.
    """
    permission_classes = [IsSystemAdminOrCoordinator]

    def post(self, request):
        s = PublishRequestSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        data = s.validated_data
        result = unpublish_timetable(data['semester'], request.user)
        http_status = status.HTTP_200_OK if result['success'] else status.HTTP_403_FORBIDDEN
        return Response(result, status=http_status)


class ConflictResolveView(APIView):
    """
    POST /api/timetable/conflicts/{id}/resolve/

    Marks a specific conflict as RESOLVED with a resolution note.
    Permission: SYSTEM_ADMIN or COORDINATOR.
    """
    permission_classes = [IsSystemAdminOrCoordinator]

    def post(self, request, pk):
        s = ConflictResolveSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        result = resolve_conflict(pk, request.user, s.validated_data['resolution_note'])
        http_status = status.HTTP_200_OK if result['success'] else status.HTTP_404_NOT_FOUND
        return Response(result, status=http_status)


class ConflictListView(APIView):
    """
    GET /api/timetable/conflicts/?academic_year=1&semester=1&status=OPEN

    Lists conflicts for a semester. Used by Conflict Resolution screen.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = TimetableConflict.objects.select_related(
            'timetable_entry_a__course', 'timetable_entry_b__course',
            'resolved_by',
        ).all()
        if request.query_params.get('semester'):
            qs = qs.filter(timetable_entry_a__semester_id=request.query_params['semester'])
        if request.query_params.get('status'):
            qs = qs.filter(status=request.query_params['status'])
        data = [
            {
                'id': c.id,
                'conflict_type': c.conflict_type,
                'type_display': c.get_conflict_type_display(),
                'message': c.message,
                'status': c.status,
                'entry_a': {
                    'id': c.timetable_entry_a_id,
                    'course': c.timetable_entry_a.course.course_code,
                    'day': c.timetable_entry_a.day_of_week,
                    'time': f'{c.timetable_entry_a.start_time.strftime("%H:%M")}–{c.timetable_entry_a.end_time.strftime("%H:%M")}',
                },
                'entry_b': {
                    'id': c.timetable_entry_b_id,
                    'course': c.timetable_entry_b.course.course_code,
                    'day': c.timetable_entry_b.day_of_week,
                    'time': f'{c.timetable_entry_b.start_time.strftime("%H:%M")}–{c.timetable_entry_b.end_time.strftime("%H:%M")}',
                },
                'resolved_by': c.resolved_by.full_name if c.resolved_by else None,
                'resolved_at': str(c.resolved_at) if c.resolved_at else None,
                'resolution_note': c.resolution_note,
                'created_at': str(c.created_at),
            }
            for c in qs
        ]
        return Response(data)


# ── Phase 8: Venue Recommendation ─────────────────────────────────────────────

class VenueRecommendationView(APIView):
    """
    POST /api/timetable/venue-recommendations/

    Returns up to 3 suitable venues for the given student count and slot.
    Permission: any authenticated user (coordinators and lecturers use this).
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        s = VenueRecommendationRequestSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)

        data = s.validated_data
        semester = data.get('semester')
        service = VenueRecommendationService(
            students_count=data['students_count'],
            day_of_week=data['day_of_week'],
            start_time=data['start_time'],
            end_time=data['end_time'],
            venue_type=data.get('venue_type'),
            required_resources=data.get('required_resources', []),
            semester_id=semester.pk if semester else None,
        )
        result = service.recommend()
        return Response(result, status=status.HTTP_200_OK)


# ── Phase 8: Emergency Session ────────────────────────────────────────────────

class EmergencySessionViewSet(viewsets.ViewSet):
    """
    GET  /api/sessions/emergency/          — list sessions
    POST /api/sessions/emergency/          — create (Lecturer or Coordinator)
    GET  /api/sessions/emergency/{id}/     — retrieve single
    POST /api/sessions/emergency/{id}/approve/ — Coordinator/Admin
    POST /api/sessions/emergency/{id}/reject/  — Coordinator/Admin
    """
    permission_classes = [IsAuthenticated]

    def _get_object_or_404(self, pk):
        try:
            return EmergencySession.objects.select_related(
                'course', 'lecturer__user', 'venue', 'requested_by', 'reviewed_by',
            ).get(pk=pk)
        except EmergencySession.DoesNotExist:
            return None

    def list(self, request):
        qs = EmergencySession.objects.select_related(
            'course', 'lecturer__user', 'venue', 'requested_by', 'reviewed_by',
        ).all()

        # Coordinators and admins see all; lecturers see only their own requests
        if request.user.role == Role.LECTURER:
            qs = qs.filter(requested_by=request.user)

        # Optional filters
        p = request.query_params
        if p.get('status'):
            qs = qs.filter(status=p['status'])

        serializer = EmergencySessionSerializer(qs, many=True)
        return Response(serializer.data)

    def retrieve(self, request, pk=None):
        session = self._get_object_or_404(pk)
        if session is None:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        # Lecturers can only see their own
        if request.user.role == Role.LECTURER and session.requested_by != request.user:
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = EmergencySessionSerializer(session)
        return Response(serializer.data)

    def create(self, request):
        s = EmergencySessionCreateSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)

        data = s.validated_data
        service = EmergencySessionService(
            course_id=data['course'].pk,
            lecturer_id=data['lecturer'].pk,
            requested_date=data['requested_date'],
            day_of_week=data['day_of_week'],
            start_time=data['start_time'],
            end_time=data['end_time'],
            reason=data['reason'],
            requested_by_user=request.user,
            venue_id=data['venue'].pk if data.get('venue') else None,
            student_group_ids=[g.pk for g in data.get('student_groups', [])],
        )
        session = service.check_and_create()
        out = EmergencySessionSerializer(session)
        return Response(out.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], url_path='approve',
            permission_classes=[IsSystemAdminOrCoordinator])
    def approve(self, request, pk=None):
        session = self._get_object_or_404(pk)
        if session is None:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        if session.status != EmergencySession.Status.PENDING:
            return Response(
                {'detail': f'Cannot approve a session with status {session.status}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        s = EmergencySessionReviewSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        updated = EmergencySessionService.approve(session, request.user, s.validated_data['note'])
        return Response(EmergencySessionSerializer(updated).data)

    @action(detail=True, methods=['post'], url_path='reject',
            permission_classes=[IsSystemAdminOrCoordinator])
    def reject(self, request, pk=None):
        session = self._get_object_or_404(pk)
        if session is None:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        if session.status != EmergencySession.Status.PENDING:
            return Response(
                {'detail': f'Cannot reject a session with status {session.status}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        s = EmergencySessionReviewSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        updated = EmergencySessionService.reject(session, request.user, s.validated_data['note'])
        return Response(EmergencySessionSerializer(updated).data)


# ── Phase 8: System Configuration ─────────────────────────────────────────────

class SystemConfigView(APIView):
    """
    GET  /api/system/config/ — all authenticated users (read capacity_overhead)
    PATCH /api/system/config/ — Admin only
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        config = SystemConfiguration.get()
        return Response(SystemConfigSerializer(config).data)

    def patch(self, request):
        if request.user.role != Role.SYSTEM_ADMIN:
            return Response({'detail': 'Admin only.'}, status=status.HTTP_403_FORBIDDEN)
        s = SystemConfigUpdateSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        config = SystemConfiguration.get()
        config.capacity_overhead = s.validated_data['capacity_overhead']
        config.updated_by = request.user
        config.save()
        return Response(SystemConfigSerializer(config).data)
