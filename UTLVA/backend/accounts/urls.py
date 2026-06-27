from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import LoginView, LogoutView, UserProfileView, TokenVerifyView

# Import from local views (not simplejwt)
from .views import (
    LoginView, 
    LogoutView, 
    UserProfileView, 
    TokenVerifyView,
    UserViewSet   # ← This is the one causing the error
)
router = DefaultRouter()
router.register('users', UserViewSet, basename='user')

urlpatterns = [
    path('login/', LoginView.as_view(), name='auth-login'),
    path('logout/', LogoutView.as_view(), name='auth-logout'),
    path('token/refresh/', TokenRefreshView.as_view(), name='auth-token-refresh'),
    path('profile/', UserProfileView.as_view(), name='auth-profile'),
    path('verify/', TokenVerifyView.as_view(), name='auth-verify'),
    path('', include(router.urls)), # Bulk is under /api/auth/users/bulk_upload/
]
