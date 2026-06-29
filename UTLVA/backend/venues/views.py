"""
UTLVA — Venue module API views.

Public read endpoints (any authenticated user):
  GET  /api/venues/buildings/
  GET  /api/venues/buildings/{id}/
  GET  /api/venues/buildings/{id}/venues/
  GET  /api/venues/venues/
  GET  /api/venues/venues/{id}/
  GET  /api/venues/venues/dashboard/
  GET  /api/venues/venues/search/
  GET  /api/venues/venues/nearby/?lat=...&lng=...&radius_km=2
  GET  /api/venues/venues/{id}/history/
  POST /api/venues/venues/alternatives/

Admin / Coordinator write endpoints:
  POST    /api/venues/buildings/ (and PUT/PATCH/DELETE)
  POST    /api/venues/venues/    (and PUT/PATCH/DELETE)
  POST    /api/venues/venues/{id}/transition/
  POST    /api/venues/venues/{id}/deactivate/
  POST    /api/venues/venues/{id}/reactivate/
  POST    /api/venues/venues/{id}/maintenance/
  POST    /api/venues/venues/{id}/end-maintenance/

History (admin + coordinator only — full read):
  GET     /api/venues/history/
"""

from math import radians, cos, sin, asin, sqrt
from decimal import Decimal, InvalidOperation

from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import (
    IsAdminOrCoordinatorOrReadOnly,
    IsSystemAdminOrCoordinator,
    IsSystemAdmin,
)

from .models import (
    Building,
    Venue,
    VenueStatusHistory,
    VenueStatus,
    VenueType,
    TransitionEvent,
)
from .serializers import (
    BuildingSerializer,
    VenueListSerializer,
    VenueDetailSerializer,
    VenueWriteSerializer,
    VenueStatusHistorySerializer,
    TransitionInputSerializer,
    DeactivateInputSerializer,
    MaintenanceInputSerializer,
    AlternativeSearchSerializer,
    DashboardBuildingSerializer,
)
from .services import (
    VenueStateMachine,
    VenueServiceError,
    IllegalTransition,
    TransitionRequiresForce,
    VenueHasFutureBookings,
    deactivate_venue_safely,
    reactivate_venue,
    find_alternative_venues,
    find_future_bookings,
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _service_error_response(exc: VenueServiceError) -> Response:
    """Render a VenueServiceError as a structured DRF 4xx response."""
    if isinstance(exc, IllegalTransition):
        http = status.HTTP_409_CONFLICT
    elif isinstance(exc, TransitionRequiresForce):
        http = status.HTTP_403_FORBIDDEN
    elif isinstance(exc, VenueHasFutureBookings):
        http = status.HTTP_409_CONFLICT
    else:
        http = status.HTTP_400_BAD_REQUEST
    return Response(
        {
            'code': exc.code,
            'message': exc.message,
            'details': exc.details,
        },
        status=http,
    )


def _parse_decimal(value, field_name: str):
    if value in (None, ''):
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError):
        raise ValueError(f'Invalid decimal for {field_name}: {value!r}')


def _haversine_km(lat1, lon1, lat2, lon2) -> float:
    """Great-circle distance between two WGS84 points in kilometres."""
    lat1, lon1, lat2, lon2 = map(radians, [float(lat1), float(lon1), float(lat2), float(lon2)])
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 2 * asin(sqrt(a)) * 6371.0  # mean Earth radius in km


# ── Building viewset ──────────────────────────────────────────────────────────

class BuildingViewSet(viewsets.ModelViewSet):
    queryset = Building.objects.prefetch_related('venues').all()
    serializer_class = BuildingSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        p = self.request.query_params
        if p.get('search'):
            q = p['search']
            qs = qs.filter(Q(name__icontains=q) | Q(code__icontains=q))
        if p.get('is_active') is not None:
            qs = qs.filter(is_active=p['is_active'].lower() == 'true')
        return qs

    @action(detail=True, methods=['get'], url_path='venues',
            permission_classes=[IsAuthenticated])
    def list_venues(self, request, pk=None):
        """GET /api/venues/buildings/{id}/venues/ — list this building's venues."""
        building = self.get_object()
        qs = building.venues.select_related('building')
        if request.query_params.get('is_active') is not None:
            qs = qs.filter(
                is_active=request.query_params['is_active'].lower() == 'true'
            )
        if request.query_params.get('status'):
            qs = qs.filter(status=request.query_params['status'])
        serializer = VenueListSerializer(qs, many=True)
        return Response(serializer.data)


# ── Venue viewset ─────────────────────────────────────────────────────────────

class VenueViewSet(viewsets.ModelViewSet):
    queryset = Venue.objects.select_related('building').all()
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    # Different serializers per action
    def get_serializer_class(self):
        if self.action == 'list':
            return VenueListSerializer
        if self.action == 'retrieve':
            return VenueDetailSerializer
        if self.action in ('create', 'update', 'partial_update'):
            return VenueWriteSerializer
        return VenueDetailSerializer

    # ── Query-param filtering ──────────────────────────────────────────────
    def get_queryset(self):
        qs = super().get_queryset()
        p = self.request.query_params

        if p.get('building'):
            qs = qs.filter(building_id=p['building'])
        if p.get('venue_type'):
            qs = qs.filter(venue_type=p['venue_type'])
        if p.get('status'):
            qs = qs.filter(status=p['status'])
        if p.get('is_active') is not None:
            qs = qs.filter(is_active=p['is_active'].lower() == 'true')
        if p.get('floor') is not None:
            qs = qs.filter(floor=p['floor'])
        if p.get('min_capacity'):
            qs = qs.filter(capacity__gte=int(p['min_capacity']))
        if p.get('max_capacity'):
            qs = qs.filter(capacity__lte=int(p['max_capacity']))
        if p.get('search'):
            q = p['search']
            qs = qs.filter(
                Q(name__icontains=q)
                | Q(code__icontains=q)
                | Q(building__name__icontains=q)
                | Q(building__code__icontains=q)
            )

        # Resource filter: ?resources=projector,whiteboard (all must be present)
        required_resources = [
            r.strip() for r in p.get('resources', '').split(',') if r.strip()
        ]
        # Accessibility filter: ?accessibility=wheelchair_access,hearing_loop
        required_accessibility = [
            a.strip() for a in p.get('accessibility', '').split(',') if a.strip()
        ]
        # Shorthand: ?accessible=true → venue has at least one accessibility feature
        if p.get('accessible', '').lower() == 'true':
            qs = qs.exclude(accessibility=[])

        if required_resources or required_accessibility:
            ids = [
                v.id for v in qs
                if v.has_resources(required_resources)
                and v.has_accessibility(required_accessibility)
            ]
            qs = Venue.objects.select_related('building').filter(id__in=ids)
        return qs

    @action(detail=True, methods=['get'], url_path='check-availability',
            permission_classes=[IsAuthenticated])
    def check_availability(self, request, pk=None):
        """
        GET /api/venues/venues/{id}/check-availability/
            ?day_of_week=MONDAY&start_time=10:00:00&end_time=12:00:00&semester=1

        Returns whether the venue is free at the given slot (FR-18).
        Overlap rule: A_start < B_end AND A_end > B_start.
        """
        from timetable.models import TimetableEntry
        venue = self.get_object()
        p = request.query_params
        day = p.get('day_of_week', '').upper()
        start = p.get('start_time')
        end   = p.get('end_time')

        if not (day and start and end):
            return Response(
                {'detail': 'day_of_week, start_time and end_time are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        conflicts_qs = TimetableEntry.objects.filter(
            venue=venue,
            day_of_week=day,
            start_time__lt=end,
            end_time__gt=start,
            status__in=['DRAFT', 'VALIDATED', 'PUBLISHED'],
        ).select_related('course', 'lecturer__user')

        semester_id = p.get('semester')
        if semester_id:
            conflicts_qs = conflicts_qs.filter(semester_id=semester_id)

        is_available = not conflicts_qs.exists()
        conflicts_data = [
            {
                'id': e.id,
                'course_code': e.course.course_code,
                'day': e.day_of_week,
                'start': str(e.start_time),
                'end': str(e.end_time),
                'status': e.status,
                'lecturer': e.lecturer.user.full_name if e.lecturer else None,
            }
            for e in conflicts_qs
        ]

        return Response({
            'venue_id': venue.id,
            'venue_code': venue.code,
            'day_of_week': day,
            'start_time': start,
            'end_time': end,
            'available': is_available,
            'current_venue_status': venue.status,
            'conflicts': conflicts_data,
        })

    # ── Dashboard (map + summary) ──────────────────────────────────────────
    @action(detail=False, methods=['get'], url_path='dashboard',
            permission_classes=[IsAuthenticated])
    def dashboard(self, request):
        """
        GET /api/venues/venues/dashboard/

        Returns everything the Flutter dashboard needs in a single round-trip:
          • summary counts by status
          • buildings (with coordinates for the map)
          • all active venues with current status and marker colour
        """
        from .models import STATUS_MARKER_COLOR

        active_venues = Venue.objects.filter(is_active=True).select_related('building')
        buildings = Building.objects.filter(is_active=True).prefetch_related('venues')

        summary = {s.value: 0 for s in VenueStatus}
        for v in active_venues:
            summary[v.status] = summary.get(v.status, 0) + 1

        return Response({
            'summary': {
                'total_active_venues': active_venues.count(),
                'by_status': summary,
                'status_colors': {
                    s.value: STATUS_MARKER_COLOR.get(s, '#9ca3af')
                    for s in VenueStatus
                },
            },
            'buildings': DashboardBuildingSerializer(buildings, many=True).data,
            'venues': VenueListSerializer(active_venues, many=True).data,
        })

    # ── Advanced search ────────────────────────────────────────────────────
    @action(detail=False, methods=['get'], url_path='search',
            permission_classes=[IsAuthenticated])
    def search(self, request):
        """
        GET /api/venues/venues/search/?...

        Combinable query parameters:
          q                 free-text search over code/name/building
          building          building id
          venue_type        LECTURE_HALL | CLASSROOM | LABORATORY | ...
          status            FREE | BOOKED | IN_USE | EXPIRED | MAINTENANCE
          min_capacity      int
          max_capacity      int
          floor             int
          resources         comma-separated, e.g. "projector,whiteboard"
          accessibility     comma-separated, e.g. "wheelchair_access"
          only_bookable     "true" → status=FREE AND is_active=True
        """
        # Reuse get_queryset for the standard filters, then add q/only_bookable.
        qs = self.get_queryset()

        if request.query_params.get('q'):
            q = request.query_params['q']
            qs = qs.filter(
                Q(name__icontains=q)
                | Q(code__icontains=q)
                | Q(description__icontains=q)
                | Q(building__name__icontains=q)
            )
        if request.query_params.get('only_bookable', '').lower() == 'true':
            qs = qs.filter(is_active=True, status=VenueStatus.FREE)

        return Response({
            'count': len(qs) if isinstance(qs, list) else qs.count(),
            'results': VenueListSerializer(qs, many=True).data,
        })

    # ── Nearby (Haversine radius search) ───────────────────────────────────
    @action(detail=False, methods=['get'], url_path='nearby',
            permission_classes=[IsAuthenticated])
    def nearby(self, request):
        """
        GET /api/venues/venues/nearby/?lat=-6.77&lng=39.27&radius_km=1.5

        Returns active venues within `radius_km` of the given point, sorted
        by distance ascending. Venues without coordinates are excluded.
        """
        try:
            lat = _parse_decimal(request.query_params.get('lat'), 'lat')
            lng = _parse_decimal(request.query_params.get('lng'), 'lng')
        except ValueError as e:
            return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        if lat is None or lng is None:
            return Response(
                {'detail': 'Both `lat` and `lng` query parameters are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            radius_km = float(request.query_params.get('radius_km', 1.0))
        except ValueError:
            return Response(
                {'detail': '`radius_km` must be a number.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        qs = Venue.objects.filter(is_active=True).select_related('building')
        out = []
        for v in qs:
            vlat = v.effective_latitude
            vlng = v.effective_longitude
            if vlat is None or vlng is None:
                continue
            distance_km = _haversine_km(lat, lng, vlat, vlng)
            if distance_km <= radius_km:
                data = VenueListSerializer(v).data
                data['distance_km'] = round(distance_km, 3)
                out.append(data)
        out.sort(key=lambda r: r['distance_km'])
        return Response({'count': len(out), 'results': out})

    # ── Status history per venue ───────────────────────────────────────────
    @action(detail=True, methods=['get'], url_path='history',
            permission_classes=[IsAuthenticated])
    def history(self, request, pk=None):
        venue = self.get_object()
        qs = venue.status_history.select_related('triggered_by_user').all()
        limit = int(request.query_params.get('limit', 100))
        return Response(
            VenueStatusHistorySerializer(qs[:limit], many=True).data
        )

    # ── Manual transition ──────────────────────────────────────────────────
    @action(detail=True, methods=['post'], url_path='transition',
            permission_classes=[IsSystemAdminOrCoordinator])
    def transition(self, request, pk=None):
        """
        POST /api/venues/venues/{id}/transition/
        Body: { "to_status": "BOOKED", "event": "...", "reason": "...", "force": false }

        Manual transitions are intended for testing and exceptional cases.
        Normal operations should go through the session lifecycle (once Sessions land).
        """
        venue = self.get_object()
        s = TransitionInputSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        data = s.validated_data

        try:
            result = VenueStateMachine(venue).transition(
                to_status=data['to_status'],
                event=data.get('event') or TransitionEvent.MANUAL_OVERRIDE,
                user=request.user,
                reason=data.get('reason', ''),
                force=data.get('force', False),
            )
        except VenueServiceError as e:
            return _service_error_response(e)

        venue.refresh_from_db()
        return Response({
            'success': True,
            'transition': result.to_dict(),
            'venue': VenueDetailSerializer(venue).data,
        })

    # ── Safe deactivation ──────────────────────────────────────────────────
    @action(detail=True, methods=['post'], url_path='deactivate',
            permission_classes=[IsSystemAdminOrCoordinator])
    def deactivate(self, request, pk=None):
        """
        POST /api/venues/venues/{id}/deactivate/

        Refuses with HTTP 409 + a list of affected bookings if any future
        bookings reference this venue (SRS §3.12).
        """
        venue = self.get_object()
        s = DeactivateInputSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        try:
            result = deactivate_venue_safely(
                venue, user=request.user, reason=s.validated_data.get('reason', '')
            )
        except VenueHasFutureBookings as e:
            return _service_error_response(e)
        return Response(result)

    @action(detail=True, methods=['get'], url_path='affected-bookings',
            permission_classes=[IsSystemAdminOrCoordinator])
    def affected_bookings(self, request, pk=None):
        """
        GET /api/venues/venues/{id}/affected-bookings/
        Lists future bookings that would be impacted by deactivating this venue.
        """
        venue = self.get_object()
        affected = find_future_bookings(venue)
        return Response({
            'venue_id': venue.id,
            'venue_code': venue.code,
            'count': len(affected),
            'affected_bookings': [b.to_dict() for b in affected],
        })

    @action(detail=True, methods=['post'], url_path='reassign-booking',
            permission_classes=[IsSystemAdminOrCoordinator])
    def reassign_booking(self, request, pk=None):
        """
        SRS §3.12 — Venue deactivation with future bookings.
        POST /api/venues/venues/{id}/reassign-booking/
        Body: {"entry_id": N, "new_venue_id": M}

        Moves a TimetableEntry from this venue to new_venue, transitioning
        venue statuses appropriately. Once all affected bookings are reassigned,
        the coordinator can call /deactivate/ again.
        """
        from timetable.models import TimetableEntry, TimetableStatus
        from venues.models import VenueStatus, TransitionEvent
        from venues.services import VenueStateMachine

        venue = self.get_object()
        entry_id    = request.data.get('entry_id')
        new_venue_id = request.data.get('new_venue_id')

        if not entry_id or not new_venue_id:
            return Response(
                {'detail': 'Both entry_id and new_venue_id are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            entry = TimetableEntry.objects.select_related('venue', 'course').get(
                pk=entry_id, venue=venue,
            )
        except TimetableEntry.DoesNotExist:
            return Response({'detail': 'Entry not found for this venue.'}, status=status.HTTP_404_NOT_FOUND)

        try:
            new_venue = Venue.objects.get(pk=new_venue_id, is_active=True)
        except Venue.DoesNotExist:
            return Response({'detail': 'New venue not found or inactive.'}, status=status.HTTP_404_NOT_FOUND)

        if new_venue.status != VenueStatus.FREE:
            return Response(
                {'detail': f'New venue {new_venue.code} is not FREE (status: {new_venue.status}).'},
                status=status.HTTP_409_CONFLICT,
            )

        # Release old venue
        if venue.status == VenueStatus.BOOKED:
            try:
                VenueStateMachine(venue).transition(
                    to_status=VenueStatus.FREE,
                    event=TransitionEvent.SESSION_CANCELLED,
                    user=request.user,
                    reason=f'Booking reassigned to {new_venue.code} (deactivation prep).',
                    related_object_type='TimetableEntry',
                    related_object_id=str(entry.id),
                )
            except Exception:
                pass

        # Book new venue
        try:
            VenueStateMachine(new_venue).transition(
                to_status=VenueStatus.BOOKED,
                event=TransitionEvent.TIMETABLE_ENTRY_CREATED,
                user=request.user,
                reason=f'Reassigned from {venue.code} during deactivation.',
                related_object_type='TimetableEntry',
                related_object_id=str(entry.id),
            )
        except Exception as exc:
            return Response({'detail': f'Could not book new venue: {exc}'}, status=status.HTTP_409_CONFLICT)

        # Update entry
        entry.venue = new_venue
        entry.save(update_fields=['venue'])

        # Check if venue is now clear to deactivate
        remaining = find_future_bookings(venue)
        return Response({
            'success': True,
            'entry_id': entry.id,
            'old_venue': venue.code,
            'new_venue': new_venue.code,
            'remaining_bookings': len(remaining),
            'can_deactivate_now': len(remaining) == 0,
        })

    @action(detail=True, methods=['post'], url_path='reactivate',
            permission_classes=[IsSystemAdminOrCoordinator])
    def reactivate(self, request, pk=None):
        venue = self.get_object()
        s = DeactivateInputSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        result = reactivate_venue(
            venue, user=request.user, reason=s.validated_data.get('reason', '')
        )
        return Response(result)

    # ── Maintenance ────────────────────────────────────────────────────────
    @action(detail=True, methods=['post'], url_path='maintenance',
            permission_classes=[IsSystemAdmin])
    def maintenance(self, request, pk=None):
        """
        POST /api/venues/venues/{id}/maintenance/
        Body: { "reason": "...", "force": false }

        Force is required when the venue is currently BOOKED or IN_USE.
        """
        venue = self.get_object()
        s = MaintenanceInputSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        try:
            result = VenueStateMachine(venue).transition(
                to_status=VenueStatus.MAINTENANCE,
                event=TransitionEvent.MAINTENANCE_STARTED,
                user=request.user,
                reason=s.validated_data['reason'],
                force=s.validated_data.get('force', False),
            )
        except VenueServiceError as e:
            return _service_error_response(e)
        venue.refresh_from_db()
        return Response({
            'success': True,
            'transition': result.to_dict(),
            'venue': VenueDetailSerializer(venue).data,
        })

    @action(detail=True, methods=['post'], url_path='end-maintenance',
            permission_classes=[IsSystemAdmin])
    def end_maintenance(self, request, pk=None):
        venue = self.get_object()
        try:
            result = VenueStateMachine(venue).transition(
                to_status=VenueStatus.FREE,
                event=TransitionEvent.MAINTENANCE_ENDED,
                user=request.user,
                reason=request.data.get('reason', 'Maintenance ended.'),
            )
        except VenueServiceError as e:
            return _service_error_response(e)
        venue.refresh_from_db()
        return Response({
            'success': True,
            'transition': result.to_dict(),
            'venue': VenueDetailSerializer(venue).data,
        })

    # ── Alternative finder ─────────────────────────────────────────────────
    @action(detail=False, methods=['post'], url_path='alternatives',
            permission_classes=[IsAuthenticated])
    def alternatives(self, request):
        """
        POST /api/venues/venues/alternatives/
        Body: AlternativeSearchSerializer

        Used by the postponement and emergency-session workflows to suggest
        currently-FREE venues that satisfy capacity / resource / accessibility
        constraints. Same-building results rank first, then tightest capacity fit.
        """
        s = AlternativeSearchSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        data = s.validated_data
        results = find_alternative_venues(
            capacity_needed=data['capacity_needed'],
            venue_type=data.get('venue_type'),
            required_resources=data.get('required_resources', []),
            required_accessibility=data.get('required_accessibility', []),
            exclude_venue_id=data.get('exclude_venue_id'),
            same_building_id=data.get('same_building_id'),
            limit=data.get('limit', 10),
        )
        return Response({
            'count': len(results),
            'results': VenueListSerializer(results, many=True).data,
        })

    # ── Choice metadata ────────────────────────────────────────────────────
    @action(detail=False, methods=['get'], url_path='choices',
            permission_classes=[IsAuthenticated])
    def choices(self, request):
        """
        GET /api/venues/venues/choices/

        Returns the enum values + display labels the Flutter app needs for
        dropdowns and chip filters.
        """
        return Response({
            'venue_types': [
                {'value': v.value, 'label': v.label}
                for v in VenueType
            ],
            'statuses': [
                {'value': s.value, 'label': s.label}
                for s in VenueStatus
            ],
            'events': [
                {'value': e.value, 'label': e.label}
                for e in TransitionEvent
            ],
        })


# ── Global history viewset ────────────────────────────────────────────────────

class VenueStatusHistoryViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Read-only audit log across all venues.
    Admin and Coordinator only (matches FR-5 audit-log access).
    """
    queryset = VenueStatusHistory.objects.select_related(
        'venue', 'venue__building', 'triggered_by_user',
    ).all()
    serializer_class = VenueStatusHistorySerializer
    permission_classes = [IsSystemAdminOrCoordinator]

    def get_queryset(self):
        qs = super().get_queryset()
        p = self.request.query_params
        if p.get('venue'):
            qs = qs.filter(venue_id=p['venue'])
        if p.get('building'):
            qs = qs.filter(venue__building_id=p['building'])
        if p.get('event'):
            qs = qs.filter(triggered_by_event=p['event'])
        if p.get('new_status'):
            qs = qs.filter(new_status=p['new_status'])
        if p.get('from'):
            qs = qs.filter(changed_at__gte=p['from'])
        if p.get('to'):
            qs = qs.filter(changed_at__lte=p['to'])
        if p.get('user'):
            qs = qs.filter(triggered_by_user_id=p['user'])
        return qs


# ── Module status (sanity check endpoint) ─────────────────────────────────────

class VenueModuleStatusView(APIView):
    """
    GET /api/venues/status/
    Lightweight health/info endpoint for the Flutter splash screen and
    integration tests.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({
            'module': 'venues',
            'building_count': Building.objects.count(),
            'venue_count': Venue.objects.count(),
            'active_venue_count': Venue.objects.filter(is_active=True).count(),
            'history_count': VenueStatusHistory.objects.count(),
        })