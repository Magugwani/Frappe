from rest_framework import serializers
from .models import Building, Venue


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
