from rest_framework import viewsets
from accounts.permissions import IsAdminOrCoordinatorOrReadOnly
from .models import Building, Venue
from .serializers import BuildingSerializer, VenueSerializer


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
        building_id = self.request.query_params.get('building')
        venue_type = self.request.query_params.get('venue_type')
        status_filter = self.request.query_params.get('status')
        active = self.request.query_params.get('is_active')
        search = self.request.query_params.get('search')

        if building_id:
            qs = qs.filter(building_id=building_id)
        if venue_type:
            qs = qs.filter(venue_type=venue_type)
        if status_filter:
            qs = qs.filter(status=status_filter)
        if active is not None:
            qs = qs.filter(is_active=active.lower() == 'true')
        if search:
            qs = qs.filter(name__icontains=search) | qs.filter(code__icontains=search)
        return qs
