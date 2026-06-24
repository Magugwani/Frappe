from django.contrib import admin
from .models import AcademicYear, Semester, Department, Programme, StudentGroup, Course, Lecturer, LecturerCourse, StudentProfile, TeachingPeriod

admin.site.register(AcademicYear)
admin.site.register(Semester)
admin.site.register(Department)
admin.site.register(Programme)
admin.site.register(StudentGroup)
admin.site.register(Course)
admin.site.register(Lecturer)
admin.site.register(LecturerCourse)
admin.site.register(StudentProfile)
admin.site.register(TeachingPeriod)
