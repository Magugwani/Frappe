"""
UTLVA — Venue module URL routing.

Mounted under /api/venues/ by the project's UTLVA/urls.py.

Final URL space:
    /api/venues/buildings/
    /api/venues/buildings/{id}/
    /api/venues/buildings/{id}/venues/
    /api/venues/venues/
    /api/venues/venues/{id}/
    /api/venues/venues/dashboard/
    /api/venues/venues/search/
    /api/venues/venues/nearby/
    /api/venues/venues/alternatives/   (POST)
    /api/venues/venues/choices/
    /api/venues/venues/{id}/history/
    /api/venues/venues/{id}/transition/        (POST)
    /api/venues/venues/{id}/deactivate/         (POST)
    /api/venues/venues/{id}/reactivate/         (POST)
    /api/venues/venues/{id}/maintenance/        (POST)
    /api/venues/venues/{id}/end-maintenance/    (POST)
    /api/venues/venues/{id}/affected-bookings/
    /api/venues/history/
    /api/venues/status/
"""

from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import (
    BuildingViewSet,
    VenueViewSet,
    VenueStatusHistoryViewSet,
    VenueModuleStatusView,
)

router = DefaultRouter()
router.register('buildings', BuildingViewSet, basename='building')
router.register('venues', VenueViewSet, basename='venue')
router.register('history', VenueStatusHistoryViewSet, basename='venue-history')

urlpatterns = router.urls + [
    path('status/', VenueModuleStatusView.as_view(), name='venues-module-status'),
]