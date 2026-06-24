from rest_framework.routers import DefaultRouter
from .views import (
    AcademicYearViewSet, SemesterViewSet, DepartmentViewSet,
    ProgrammeViewSet, StudentGroupViewSet, CourseViewSet, LecturerViewSet,
    StudentProfileViewSet, TeachingPeriodViewSet,
)

router = DefaultRouter()
router.register('years', AcademicYearViewSet, basename='academic-year')
router.register('semesters', SemesterViewSet, basename='semester')
router.register('departments', DepartmentViewSet, basename='department')
router.register('programmes', ProgrammeViewSet, basename='programme')
router.register('groups', StudentGroupViewSet, basename='student-group')
router.register('courses', CourseViewSet, basename='course')
router.register('lecturers', LecturerViewSet, basename='lecturer')
router.register('student-profiles', StudentProfileViewSet, basename='student-profile')
router.register('teaching-periods', TeachingPeriodViewSet, basename='teaching-period')

urlpatterns = router.urls
