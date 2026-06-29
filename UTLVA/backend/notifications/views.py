from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.utils import timezone

from .models import Notification, UserNotificationPreference, BulkSMSJob, SMSRetryJob
from .serializers import (
    NotificationSerializer,
    NotificationPreferenceSerializer,
    BulkSMSJobSerializer,
    SMSRetryJobSerializer,
)


class NotificationViewSet(viewsets.ViewSet):
    """
    GET  /api/notifications/              — list current user's notifications
    GET  /api/notifications/unread-count/ — returns {count: N}
    POST /api/notifications/{id}/mark-read/
    POST /api/notifications/mark-all-read/
    GET  /api/notifications/preferences/  — get user's channel/event preferences (FR-50)
    PATCH /api/notifications/preferences/ — update preferences (FR-50)
    GET  /api/notifications/bulk-sms/     — list pending BulkSMSJobs (coordinator)
    POST /api/notifications/bulk-sms/{id}/approve/ — approve bulk SMS (coordinator)
    POST /api/notifications/bulk-sms/{id}/reject/  — reject bulk SMS (coordinator)
    GET  /api/notifications/sms-retry/    — list SMS retry jobs (admin)
    """
    permission_classes = [IsAuthenticated]

    # ── In-app notifications ───────────────────────────────────────────────────

    def list(self, request):
        qs = (
            Notification.objects
            .filter(recipient=request.user)
            .select_related('sender')
            .order_by('-created_at')[:50]
        )
        return Response(NotificationSerializer(qs, many=True).data)

    @action(detail=False, methods=['get'], url_path='unread-count')
    def unread_count(self, request):
        count = Notification.objects.filter(
            recipient=request.user, is_read=False
        ).count()
        return Response({'count': count})

    @action(detail=True, methods=['post'], url_path='mark-read')
    def mark_read(self, request, pk=None):
        updated = Notification.objects.filter(
            pk=pk, recipient=request.user
        ).update(is_read=True)
        if not updated:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        return Response({'success': True})

    @action(detail=False, methods=['post'], url_path='mark-all-read')
    def mark_all_read(self, request):
        count = Notification.objects.filter(
            recipient=request.user, is_read=False
        ).update(is_read=True)
        return Response({'marked': count})

    # ── FR-50: Notification preferences ───────────────────────────────────────

    @action(detail=False, methods=['get', 'patch'], url_path='preferences')
    def preferences(self, request):
        pref = UserNotificationPreference.get_or_create_for_user(request.user)
        if request.method == 'GET':
            return Response(NotificationPreferenceSerializer(pref).data)

        # PATCH
        serializer = NotificationPreferenceSerializer(
            pref, data=request.data, partial=True
        )
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    # ── FR-51-B: Bulk SMS coordinator approval ─────────────────────────────────

    @action(detail=False, methods=['get'], url_path='bulk-sms')
    def bulk_sms_list(self, request):
        """List BulkSMSJobs (coordinator/admin only)."""
        from accounts.models import Role
        if request.user.role not in (Role.COORDINATOR, Role.SYSTEM_ADMIN):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        qs = BulkSMSJob.objects.filter(
            status=BulkSMSJob.Status.PENDING
        ).select_related('requested_by', 'approved_by').order_by('-created_at')
        return Response(BulkSMSJobSerializer(qs, many=True).data)

    @action(detail=False, methods=['post'], url_path=r'bulk-sms/(?P<job_pk>\d+)/approve')
    def bulk_sms_approve(self, request, job_pk=None):
        from accounts.models import Role
        if request.user.role not in (Role.COORDINATOR, Role.SYSTEM_ADMIN):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        try:
            job = BulkSMSJob.objects.get(pk=job_pk, status=BulkSMSJob.Status.PENDING)
        except BulkSMSJob.DoesNotExist:
            return Response({'detail': 'Not found or not pending.'}, status=status.HTTP_404_NOT_FOUND)

        job.status = BulkSMSJob.Status.APPROVED
        job.approved_by = request.user
        job.approved_at = timezone.now()
        job.save(update_fields=['status', 'approved_by', 'approved_at'])

        # Dispatch asynchronously via Celery
        from notifications.tasks import dispatch_bulk_sms_job
        dispatch_bulk_sms_job.delay(job.pk)

        return Response({
            'success': True,
            'job_id': job.pk,
            'recipient_count': job.recipient_count,
            'message': f'Approved. Dispatching SMS to {job.recipient_count} recipients.',
        })

    @action(detail=False, methods=['post'], url_path=r'bulk-sms/(?P<job_pk>\d+)/reject')
    def bulk_sms_reject(self, request, job_pk=None):
        from accounts.models import Role
        if request.user.role not in (Role.COORDINATOR, Role.SYSTEM_ADMIN):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        try:
            job = BulkSMSJob.objects.get(pk=job_pk, status=BulkSMSJob.Status.PENDING)
        except BulkSMSJob.DoesNotExist:
            return Response({'detail': 'Not found or not pending.'}, status=status.HTTP_404_NOT_FOUND)

        job.status = BulkSMSJob.Status.REJECTED
        job.approved_by = request.user
        job.approved_at = timezone.now()
        job.save(update_fields=['status', 'approved_by', 'approved_at'])

        return Response({'success': True, 'message': 'Bulk SMS job rejected.'})

    # ── SMS retry jobs (admin diagnostic) ─────────────────────────────────────

    @action(detail=False, methods=['get'], url_path='sms-retry')
    def sms_retry_list(self, request):
        from accounts.models import Role
        if request.user.role != Role.SYSTEM_ADMIN:
            return Response({'detail': 'Admin only.'}, status=status.HTTP_403_FORBIDDEN)
        qs = SMSRetryJob.objects.select_related('recipient_user').order_by('-created_at')[:100]
        return Response(SMSRetryJobSerializer(qs, many=True).data)
