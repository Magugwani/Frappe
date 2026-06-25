from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from accounts.permissions import IsAdminOrCoordinatorOrReadOnly, IsSystemAdminOrCoordinator
from .models import Building, Venue, VenueStatusHistory
from .serializers import (
    BuildingSerializer, VenueSerializer,
    VenueStatusHistorySerializer, VenueStatusUpdateSerializer,
)


class BuildingViewSet(viewsets.ModelViewSet):
    queryset = Building.objects.prefetch_related('venues').all()
    serializer_class = BuildingSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        search = self.request.query_params.get('search')
        if search:
            qs = qs.filter(name__icontains=search)
        return qs


class VenueViewSet(viewsets.ModelViewSet):
    queryset = Venue.objects.select_related('building').all()
    serializer_class = VenueSerializer
    permission_classes = [IsAdminOrCoordinatorOrReadOnly]

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
        if p.get('search'):
            qs = qs.filter(name__icontains=p['search']) | qs.filter(code__icontains=p['search'])
        # Phase 9: capacity range + accessibility filters
        if p.get('min_capacity'):
            qs = qs.filter(capacity__gte=int(p['min_capacity']))
        if p.get('max_capacity'):
            qs = qs.filter(capacity__lte=int(p['max_capacity']))
        if p.get('accessible', '').lower() == 'true':
            qs = qs.exclude(accessibility=[])

        return qs

    # ── Map data ──────────────────────────────────────────────────────────────

    @action(detail=False, methods=['get'], url_path='map-data',
            permission_classes=[IsAuthenticated])
    def map_data(self, request):
        """
        GET /api/venues/venues/map-data/

        Lightweight list for the Flutter map view. Every venue in the response
        has a resolved lat/lng: the venue's own coordinates if set, otherwise
        the parent building's coordinates. Venues without any coordinates are
        silently omitted (nothing to pin on the map).
        """
        venues = Venue.objects.select_related('building').filter(is_active=True)
        data = []
        for v in venues:
            lat = (float(v.latitude) if v.latitude
                   else (float(v.building.latitude) if v.building.latitude else None))
            lng = (float(v.longitude) if v.longitude
                   else (float(v.building.longitude) if v.building.longitude else None))
            if lat is None or lng is None:
                continue
            data.append({
                'id': v.id,
                'code': v.code,
                'name': v.name,
                'building_name': v.building.name,
                'floor': v.floor,
                'capacity': v.capacity,
                'venue_type': v.venue_type,
                'venue_type_display': v.get_venue_type_display(),
                'resources': v.resources or [],
                'accessibility': v.accessibility or [],
                'status': v.status,
                'status_display': v.get_status_display(),
                'lat': lat,
                'lng': lng,
            })
        return Response(data)

    # ── Deactivation (with future-booking safety check) ───────────────────────

    @action(detail=True, methods=['post'], url_path='deactivate',
            permission_classes=[IsSystemAdminOrCoordinator])
    def deactivate(self, request, pk=None):
        """
        POST /api/venues/venues/{id}/deactivate/
        Body: { force: bool (default false) }

        Checks for active TimetableEntry records assigned to this venue.
        If force=false and such entries exist → 422 with blocking_entries list.
        If force=true or no entries → deactivates.
        """
        from timetable.models import TimetableEntry
        venue = self.get_object()

        if not venue.is_active:
            return Response({'detail': 'Venue is already inactive.'},
                            status=status.HTTP_400_BAD_REQUEST)

        force = bool(request.data.get('force', False))
        blocking = TimetableEntry.objects.select_related(
            'course', 'lecturer__user', 'student_group',
        ).filter(venue=venue, status__in=['DRAFT', 'VALIDATED', 'PUBLISHED'])

        if blocking.exists() and not force:
            return Response({
                'can_deactivate': False,
                'blocking_entries_count': blocking.count(),
                'blocking_entries': [
                    {
                        'id': e.id,
                        'course_code': e.course.course_code,
                        'course_name': e.course.course_name,
                        'day_of_week': e.day_of_week,
                        'start_time': str(e.start_time),
                        'end_time': str(e.end_time),
                        'status': e.status,
                        'lecturer': e.lecturer.user.full_name,
                    }
                    for e in blocking
                ],
                'message': (
                    f'Cannot deactivate {venue.code}. '
                    f'{blocking.count()} session(s) are assigned to this venue. '
                    'Reassign or cancel them, or send force=true to override.'
                ),
            }, status=status.HTTP_422_UNPROCESSABLE_ENTITY)

        venue.is_active = False
        venue.status = Venue.Status.FREE
        venue.save(update_fields=['is_active', 'status', 'updated_at'])
        return Response({
            'success': True,
            'forced': force and blocking.exists(),
            'message': f'{venue.code} has been deactivated.',
        })

    @action(detail=True, methods=['post'], url_path='reactivate',
            permission_classes=[IsSystemAdminOrCoordinator])
    def reactivate(self, request, pk=None):
        """POST /api/venues/venues/{id}/reactivate/"""
        venue = self.get_object()
        if venue.is_active:
            return Response({'detail': 'Venue is already active.'},
                            status=status.HTTP_400_BAD_REQUEST)
        venue.is_active = True
        venue.save(update_fields=['is_active', 'updated_at'])
        return Response({'success': True, 'message': f'{venue.code} reactivated.'})

    # ── Phase 8: Status history + update ─────────────────────────────────────

    @action(detail=True, methods=['get'], url_path='status-history')
    def status_history(self, request, pk=None):
        """GET /api/venues/venues/{id}/status-history/"""
        venue = self.get_object()
        history = VenueStatusHistory.objects.select_related(
            'changed_by', 'timetable_entry',
        ).filter(venue=venue)
        serializer = VenueStatusHistorySerializer(history, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'], url_path='update-status',
            permission_classes=[IsSystemAdminOrCoordinator])
    def update_status(self, request, pk=None):
        """POST /api/venues/venues/{id}/update-status/ Body: {new_status, reason}"""
        venue = self.get_object()
        s = VenueStatusUpdateSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)

        new_status = s.validated_data['new_status']
        reason = s.validated_data['reason']
        old_status = venue.status

        if old_status == new_status:
            return Response(
                {'detail': f'Venue is already in {new_status} status.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        VenueStatusHistory.objects.create(
            venue=venue, old_status=old_status, new_status=new_status,
            changed_by=request.user, reason=reason,
        )
        venue.status = new_status
        venue.save(update_fields=['status', 'updated_at'])

        return Response({
            'success': True,
            'old_status': old_status,
            'new_status': new_status,
            'message': f'{venue.code} status changed from {old_status} to {new_status}.',
            'venue': VenueSerializer(venue).data,
        })
