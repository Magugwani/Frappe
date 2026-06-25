"""
UTLVA — Venue module Django admin.

Buildings and venues are editable; status history is read-only.
"""

from django.contrib import admin

from .models import Building, Venue, VenueStatusHistory


class VenueInline(admin.TabularInline):
    model = Venue
    extra = 0
    fields = ('code', 'name', 'venue_type', 'capacity', 'status', 'is_active')
    readonly_fields = ('status',)
    show_change_link = True


class VenueStatusHistoryInline(admin.TabularInline):
    model = VenueStatusHistory
    extra = 0
    fields = (
        'previous_status', 'new_status', 'triggered_by_event',
        'triggered_by_user', 'reason', 'changed_at',
    )
    readonly_fields = fields
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Building)
class BuildingAdmin(admin.ModelAdmin):
    list_display = ('code', 'name', 'is_active', 'venue_count')
    list_filter = ('is_active',)
    search_fields = ('code', 'name', 'address')
    ordering = ('name',)
    inlines = [VenueInline]

    def venue_count(self, obj):
        return obj.venues.count()
    venue_count.short_description = 'Venues'


@admin.register(Venue)
class VenueAdmin(admin.ModelAdmin):
    list_display = (
        'code', 'name', 'building', 'venue_type',
        'capacity', 'status', 'is_active',
    )
    list_filter = ('status', 'venue_type', 'is_active', 'building')
    search_fields = ('code', 'name', 'description')
    ordering = ('building__name', 'code')
    readonly_fields = ('status', 'created_at', 'updated_at')
    inlines = [VenueStatusHistoryInline]
    fieldsets = (
        ('Identity', {
            'fields': ('code', 'name', 'description', 'building'),
        }),
        ('Location', {
            'fields': ('floor', 'indoor_identifier', 'latitude', 'longitude'),
        }),
        ('Capacity & Type', {
            'fields': ('capacity', 'venue_type'),
        }),
        ('Resources & Accessibility', {
            'fields': ('resources', 'accessibility'),
        }),
        ('State', {
            'fields': ('status', 'is_active'),
            'description': 'Status is managed by the state machine. '
                           'Use the admin action "Send to maintenance" if you need '
                           'to take a venue offline; deactivation should go through '
                           'the API which performs the future-booking safety check.',
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )


@admin.register(VenueStatusHistory)
class VenueStatusHistoryAdmin(admin.ModelAdmin):
    list_display = (
        'venue', 'previous_status', 'new_status',
        'triggered_by_event', 'triggered_by_user', 'changed_at',
    )
    list_filter = ('new_status', 'triggered_by_event', 'previous_status')
    search_fields = ('venue__code', 'venue__name', 'reason')
    ordering = ('-changed_at',)
    readonly_fields = (
        'venue', 'previous_status', 'new_status',
        'triggered_by_event', 'triggered_by_user',
        'related_object_type', 'related_object_id',
        'reason', 'metadata', 'changed_at',
    )

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False