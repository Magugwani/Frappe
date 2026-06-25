from django.urls import path
from rest_framework.routers import DefaultRouter
from .views import (
    TimetableEntryViewSet,
    TimetableGenerateView,
    TimetableValidateView,
    TimetableStatusView,
    TimetablePublishView,
    TimetableUnpublishView,
    ConflictResolveView,
    ConflictListView,
)

router = DefaultRouter()
router.register('entries', TimetableEntryViewSet, basename='timetable-entry')

urlpatterns = router.urls + [
    path('generate/', TimetableGenerateView.as_view(), name='timetable-generate'),
    path('validate/', TimetableValidateView.as_view(), name='timetable-validate'),
    path('status/', TimetableStatusView.as_view(), name='timetable-status'),
    path('publish/', TimetablePublishView.as_view(), name='timetable-publish'),
    path('unpublish/', TimetableUnpublishView.as_view(), name='timetable-unpublish'),
    path('conflicts/', ConflictListView.as_view(), name='conflict-list'),
    path('conflicts/<int:pk>/resolve/', ConflictResolveView.as_view(), name='conflict-resolve'),
]
