from rest_framework.permissions import BasePermission, SAFE_METHODS
from .models import Role


class IsSystemAdmin(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == Role.SYSTEM_ADMIN


class IsCoordinator(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == Role.COORDINATOR


class IsLecturer(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == Role.LECTURER


class IsStudent(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == Role.STUDENT


class IsSystemAdminOrCoordinator(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role in (
            Role.SYSTEM_ADMIN, Role.COORDINATOR
        )


class IsAnyAuthenticatedRole(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role in Role.values


class IsAdminOrCoordinatorOrReadOnly(BasePermission):
    """Admin/Coordinator: full CRUD. Authenticated others: read-only."""
    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        if request.method in SAFE_METHODS:
            return True
        return request.user.role in (Role.SYSTEM_ADMIN, Role.COORDINATOR)
