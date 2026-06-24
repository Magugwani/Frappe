from django.contrib import admin
from .models import TimetableEntry, TimetableConflict

@admin.register(TimetableEntry)
class TimetableEntryAdmin(admin.ModelAdmin):
    list_display = ['course', 'day_of_week', 'start_time', 'end_time', 'lecturer', 'venue', 'status']
    list_filter = ['status', 'day_of_week', 'academic_year', 'semester']
    search_fields = ['course__course_code', 'course__course_name', 'lecturer__user__full_name']
    ordering = ['day_of_week', 'start_time']

@admin.register(TimetableConflict)
class TimetableConflictAdmin(admin.ModelAdmin):
    list_display = ['conflict_type', 'timetable_entry_a', 'timetable_entry_b', 'status', 'created_at']
    list_filter = ['conflict_type', 'status']
    ordering = ['-created_at']
