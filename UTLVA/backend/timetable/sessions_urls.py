"""
URL configuration for Emergency Sessions.
Mounted at /api/sessions/ in UTLVA/urls.py
"""
from django.urls import path
from rest_framework.routers import DefaultRouter
from .views import EmergencySessionViewSet

router = DefaultRouter()
router.register('emergency', EmergencySessionViewSet, basename='emergency-session')

urlpatterns = router.urls
