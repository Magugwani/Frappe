from rest_framework import serializers
from .models import Building, Venue, VenueStatusHistory


class BuildingSerializer(serializers.ModelSerializer):
    venue_count = serializers.SerializerMethodField()

    class Meta:
        model = Building
        fields = ['id', 'name', 'address', 'latitude', 'longitude', 'venue_count', 'created_at']
        read_only_fields = ['id', 'venue_count', 'created_at']

    def get_venue_count(self, obj):
        return obj.venues.filter(is_active=True).count()


class VenueSerializer(serializers.ModelSerializer):
    building_name = serializers.CharField(source='building.name', read_only=True)
    venue_type_display = serializers.CharField(source='get_venue_type_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = Venue
        fields = [
            'id', 'code', 'name',
            'building', 'building_name',
            'floor', 'capacity',
            'venue_type', 'venue_type_display',
            'resources', 'accessibility',
            'status', 'status_display',
            'is_active', 'latitude', 'longitude',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'building_name', 'venue_type_display', 'status_display',
            'created_at', 'updated_at',
        ]


# ── Phase 8: Venue Status History ─────────────────────────────────────────────

class VenueStatusHistorySerializer(serializers.ModelSerializer):
    changed_by_name = serializers.SerializerMethodField()
    old_status_display = serializers.SerializerMethodField()
    new_status_display = serializers.SerializerMethodField()

    class Meta:
        model = VenueStatusHistory
        fields = [
            'id', 'venue', 'old_status', 'old_status_display',
            'new_status', 'new_status_display',
            'changed_by', 'changed_by_name',
            'changed_at', 'reason', 'timetable_entry',
        ]
        read_only_fields = fields

    def get_changed_by_name(self, obj):
        return obj.changed_by.full_name if obj.changed_by else None

    def get_old_status_display(self, obj):
        return dict(Venue.Status.choices).get(obj.old_status, obj.old_status)

    def get_new_status_display(self, obj):
        return dict(Venue.Status.choices).get(obj.new_status, obj.new_status)


class VenueStatusUpdateSerializer(serializers.Serializer):
    """Request body for POST /api/venues/venues/{id}/update-status/"""
    new_status = serializers.ChoiceField(choices=Venue.Status.choices)
    reason = serializers.CharField(allow_blank=True, default='')
