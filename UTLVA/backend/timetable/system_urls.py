"""
URL configuration for system-wide configuration.
Mounted at /api/system/ in UTLVA/urls.py
"""
from django.urls import path
from .views import SystemConfigView

urlpatterns = [
    path('config/', SystemConfigView.as_view(), name='system-config'),
]
