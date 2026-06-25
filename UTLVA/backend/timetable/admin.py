from django.contrib import admin
from .models import TimetableEntry, TimetableConflict, TimetablePublication

@admin.register(TimetableEntry)
class TimetableEntryAdmin(admin.ModelAdmin):
    list_display = ['course', 'day_of_week', 'start_time', 'end_time', 'lecturer', 'venue', 'status']
    list_filter = ['status', 'day_of_week', 'academic_year', 'semester']
    search_fields = ['course__course_code', 'course__course_name', 'lecturer__user__full_name']
    ordering = ['day_of_week', 'start_time']

@admin.register(TimetableConflict)
class TimetableConflictAdmin(admin.ModelAdmin):
    list_display = ['conflict_type', 'timetable_entry_a', 'timetable_entry_b', 'status', 'resolved_by', 'created_at']
    list_filter = ['conflict_type', 'status']
    ordering = ['-created_at']
    readonly_fields = ['created_at', 'resolved_at']

@admin.register(TimetablePublication)
class TimetablePublicationAdmin(admin.ModelAdmin):
    list_display = ['academic_year', 'semester', 'published_by', 'published_entries_count', 'status', 'published_at']
    list_filter = ['status', 'academic_year']
    ordering = ['-published_at']
    readonly_fields = ['published_at']
