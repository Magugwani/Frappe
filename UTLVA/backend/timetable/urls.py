from django.urls import path
from rest_framework.routers import DefaultRouter
from .views import TimetableEntryViewSet, TimetableGenerateView, TimetableValidateView

router = DefaultRouter()
router.register('entries', TimetableEntryViewSet, basename='timetable-entry')

urlpatterns = router.urls + [
    path('generate/', TimetableGenerateView.as_view(), name='timetable-generate'),
    path('validate/', TimetableValidateView.as_view(), name='timetable-validate'),
]
