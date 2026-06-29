from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    LoginView, LogoutView, UserProfileView, TokenVerifyView,
    UserViewSet, AuditLogViewSet,
    ForgotPasswordView, ResetPasswordView,
    BulkEnrollmentViewSet,
)

router = DefaultRouter()
router.register('users',        UserViewSet,          basename='user')
router.register('audit-logs',   AuditLogViewSet,      basename='audit-log')
router.register('bulk-enroll',  BulkEnrollmentViewSet, basename='bulk-enroll')

urlpatterns = [
    path('login/',           LoginView.as_view(),          name='auth-login'),
    path('logout/',          LogoutView.as_view(),         name='auth-logout'),
    path('token/refresh/',   TokenRefreshView.as_view(),   name='auth-token-refresh'),
    path('profile/',         UserProfileView.as_view(),    name='auth-profile'),
    path('verify/',          TokenVerifyView.as_view(),    name='auth-verify'),
    path('forgot-password/', ForgotPasswordView.as_view(), name='auth-forgot-password'),
    path('reset-password/',  ResetPasswordView.as_view(),  name='auth-reset-password'),
    path('',                 include(router.urls)),
]
