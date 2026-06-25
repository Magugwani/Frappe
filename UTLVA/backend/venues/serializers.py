"""
UTLVA — Venue module serializers.

Three tiers of venue serialization:
  • VenueListSerializer   — lightweight list / dashboard / map markers
  • VenueDetailSerializer — full detail (one venue at a time)
  • VenueWriteSerializer  — write operations (create / update)

Status is read-only at the serializer level. All transitions go through the
dedicated `/transition/` endpoint, which calls VenueStateMachine; this prevents
direct edits to `venue.status` via PATCH.
"""

from rest_framework import serializers

from .models import (
    Building,
    Venue,
    VenueStatus,
    VenueStatusHistory,
    VenueType,
    TransitionEvent,
    STATUS_MARKER_COLOR,
)


# ── Building ──────────────────────────────────────────────────────────────────

class BuildingSerializer(serializers.ModelSerializer):
    venue_count = serializers.SerializerMethodField()
    active_venue_count = serializers.SerializerMethodField()

    class Meta:
        model = Building
        fields = [
            'id', 'code', 'name', 'description',
            'address', 'latitude', 'longitude',
            'is_active',
            'venue_count', 'active_venue_count',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'venue_count', 'active_venue_count', 'created_at', 'updated_at',
        ]

    def get_venue_count(self, obj):
        return obj.venues.count()

    def get_active_venue_count(self, obj):
        return obj.venues.filter(is_active=True).count()


# ── Venue list (light) ────────────────────────────────────────────────────────

class VenueListSerializer(serializers.ModelSerializer):
    """Compact projection used by dashboards, map markers, and list pages."""

    building_id = serializers.IntegerField(source='building.id', read_only=True)
    building_name = serializers.CharField(source='building.name', read_only=True)
    building_code = serializers.CharField(source='building.code', read_only=True)
    venue_type_display = serializers.CharField(source='get_venue_type_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    marker_color = serializers.CharField(source='status_marker_color', read_only=True)
    is_bookable = serializers.BooleanField(read_only=True)
    effective_latitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, read_only=True
    )
    effective_longitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, read_only=True
    )

    class Meta:
        model = Venue
        fields = [
            'id', 'code', 'name',
            'building_id', 'building_name', 'building_code',
            'floor', 'indoor_identifier',
            'capacity',
            'venue_type', 'venue_type_display',
            'status', 'status_display', 'marker_color',
            'is_active', 'is_bookable',
            'latitude', 'longitude',
            'effective_latitude', 'effective_longitude',
        ]
        read_only_fields = fields


# ── Venue detail (full) ───────────────────────────────────────────────────────

class VenueDetailSerializer(serializers.ModelSerializer):
    """Full projection for a single venue."""

    building = BuildingSerializer(read_only=True)
    venue_type_display = serializers.CharField(source='get_venue_type_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    marker_color = serializers.CharField(source='status_marker_color', read_only=True)
    is_bookable = serializers.BooleanField(read_only=True)
    effective_latitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, read_only=True
    )
    effective_longitude = serializers.DecimalField(
        max_digits=9, decimal_places=6, read_only=True
    )
    last_transition = serializers.SerializerMethodField()

    class Meta:
        model = Venue
        fields = [
            'id', 'code', 'name', 'description',
            'building',
            'floor', 'indoor_identifier',
            'capacity',
            'venue_type', 'venue_type_display',
            'resources', 'accessibility',
            'status', 'status_display', 'marker_color',
            'is_active', 'is_bookable',
            'latitude', 'longitude',
            'effective_latitude', 'effective_longitude',
            'last_transition',
            'created_at', 'updated_at',
        ]
        read_only_fields = fields

    def get_last_transition(self, obj):
        h = obj.status_history.first()
        if not h:
            return None
        return {
            'previous_status': h.previous_status,
            'new_status': h.new_status,
            'event': h.triggered_by_event,
            'changed_at': h.changed_at.isoformat(),
            'triggered_by': h.triggered_by_user.full_name if h.triggered_by_user else None,
        }


# ── Venue write ───────────────────────────────────────────────────────────────

class VenueWriteSerializer(serializers.ModelSerializer):
    """
    Used for POST / PUT / PATCH. Status is NOT writable here — use the
    `/transition/` endpoint. `is_active` is also not writable directly;
    use `/deactivate/` and `/reactivate/` so the safety checks run.
    """

    class Meta:
        model = Venue
        fields = [
            'id', 'code', 'name', 'description',
            'building',
            'floor', 'indoor_identifier',
            'capacity',
            'venue_type',
            'resources', 'accessibility',
            'latitude', 'longitude',
        ]
        read_only_fields = ['id']

    def validate_resources(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError('resources must be a JSON list of strings.')
        for item in value:
            if not isinstance(item, str):
                raise serializers.ValidationError('Every resource must be a string.')
        return value

    def validate_accessibility(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError('accessibility must be a JSON list of strings.')
        for item in value:
            if not isinstance(item, str):
                raise serializers.ValidationError('Every accessibility entry must be a string.')
        return value

    def validate_capacity(self, value):
        if value <= 0:
            raise serializers.ValidationError('capacity must be greater than 0.')
        return value


# ── Status history ────────────────────────────────────────────────────────────

class VenueStatusHistorySerializer(serializers.ModelSerializer):
    venue_code = serializers.CharField(source='venue.code', read_only=True)
    venue_name = serializers.CharField(source='venue.name', read_only=True)
    triggered_by_event_display = serializers.CharField(
        source='get_triggered_by_event_display', read_only=True
    )
    triggered_by_user_name = serializers.SerializerMethodField()

    class Meta:
        model = VenueStatusHistory
        fields = [
            'id', 'venue', 'venue_code', 'venue_name',
            'previous_status', 'new_status',
            'triggered_by_event', 'triggered_by_event_display',
            'triggered_by_user', 'triggered_by_user_name',
            'related_object_type', 'related_object_id',
            'reason', 'metadata',
            'changed_at',
        ]
        read_only_fields = fields

    def get_triggered_by_user_name(self, obj):
        u = obj.triggered_by_user
        if not u:
            return None
        return getattr(u, 'full_name', None) or u.email


# ── Action input serializers ──────────────────────────────────────────────────

class TransitionInputSerializer(serializers.Serializer):
    """Input for POST /api/venues/venues/{id}/transition/."""
    to_status = serializers.ChoiceField(choices=VenueStatus.choices)
    event = serializers.ChoiceField(
        choices=TransitionEvent.choices, required=False,
        default=TransitionEvent.MANUAL_OVERRIDE,
    )
    reason = serializers.CharField(required=False, allow_blank=True, default='')
    force = serializers.BooleanField(required=False, default=False)


class DeactivateInputSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, default='')


class MaintenanceInputSerializer(serializers.Serializer):
    reason = serializers.CharField(required=True)
    force = serializers.BooleanField(
        required=False, default=False,
        help_text='Required when the venue is currently BOOKED or IN_USE.',
    )


class AlternativeSearchSerializer(serializers.Serializer):
    capacity_needed = serializers.IntegerField(min_value=1)
    venue_type = serializers.ChoiceField(choices=VenueType.choices, required=False)
    required_resources = serializers.ListField(
        child=serializers.CharField(), required=False, default=list,
    )
    required_accessibility = serializers.ListField(
        child=serializers.CharField(), required=False, default=list,
    )
    exclude_venue_id = serializers.IntegerField(required=False)
    same_building_id = serializers.IntegerField(required=False)
    limit = serializers.IntegerField(required=False, default=10, min_value=1, max_value=50)


# ── Dashboard projection ──────────────────────────────────────────────────────

class DashboardBuildingSerializer(serializers.ModelSerializer):
    venue_count_by_status = serializers.SerializerMethodField()
    has_coordinates = serializers.BooleanField(read_only=True)

    class Meta:
        model = Building
        fields = [
            'id', 'code', 'name', 'address',
            'latitude', 'longitude', 'has_coordinates',
            'venue_count_by_status',
        ]

    def get_venue_count_by_status(self, obj):
        out = {s.value: 0 for s in VenueStatus}
        for v in obj.venues.filter(is_active=True):
            out[v.status] = out.get(v.status, 0) + 1
        return out