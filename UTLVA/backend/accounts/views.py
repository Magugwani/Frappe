from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.tokens import RefreshToken
from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.mail import send_mail
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
import csv
from io import StringIO

from .models import Role, User, AuditLog, PasswordResetToken
from .serializers import (
    CustomTokenObtainPairSerializer,
    UserProfileSerializer,
    UserListSerializer,
    UserCreateSerializer,
    UserUpdateSerializer,
    ChangePasswordSerializer,
    BulkUserCreateSerializer,
    BulkUserUploadSerializer,
    AuditLogSerializer,
)
from .permissions import IsSystemAdminOrCoordinator, IsSystemAdmin


def _get_client_ip(request):
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    return xff.split(',')[0].strip() if xff else request.META.get('REMOTE_ADDR')


# ── Auth ──────────────────────────────────────────────────────────────────────

class LoginView(TokenObtainPairView):
    permission_classes = [AllowAny]
    serializer_class = CustomTokenObtainPairSerializer

    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            AuditLog.objects.create(
                action='LOGIN',
                entity_type='User',
                ip_address=_get_client_ip(request),
                extra={'email': request.data.get('email', '')},
            )
        return response


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')
            if not refresh_token:
                return Response({'detail': 'Refresh token required.'},
                                status=status.HTTP_400_BAD_REQUEST)
            RefreshToken(refresh_token).blacklist()
            AuditLog.objects.create(
                action='LOGOUT',
                entity_type='User',
                user=request.user,
                ip_address=_get_client_ip(request),
            )
            return Response({'detail': 'Successfully logged out.'})
        except Exception:
            return Response({'detail': 'Invalid token.'}, status=status.HTTP_400_BAD_REQUEST)


class UserProfileView(APIView):
    """Logged-in user's own profile — GET/PATCH."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserProfileSerializer(request.user).data)

    def patch(self, request):
        serializer = UserProfileSerializer(request.user, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class TokenVerifyView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({
            'valid': True,
            'user_id': str(request.user.id),
            'email': request.user.email,
            'full_name': request.user.full_name,
            'role': request.user.role,
        })


# ── User management ───────────────────────────────────────────────────────────

class UserViewSet(viewsets.ModelViewSet):
    """
    Admin and Coordinator: full user CRUD + deactivate/activate/change-password.
    Every mutation writes an AuditLog entry.
    """
    permission_classes = [IsSystemAdminOrCoordinator]

    def get_queryset(self):
        qs = User.objects.all().order_by('-date_joined')
        p = self.request.query_params
        if p.get('role'):
            qs = qs.filter(role=p['role'])
        if p.get('is_active') is not None:
            qs = qs.filter(is_active=p['is_active'].lower() == 'true')
        if p.get('search'):
            q = p['search']
            qs = qs.filter(Q(full_name__icontains=q) | Q(email__icontains=q))
        return qs

    def get_serializer_class(self):
        if self.action == 'create':
            return UserCreateSerializer
        if self.action in ('update', 'partial_update'):
            return UserUpdateSerializer
        return UserListSerializer

    def perform_create(self, serializer):
        user = serializer.save()
        AuditLog.objects.create(
            user=self.request.user,
            action='CREATE_USER',
            entity_type='User',
            entity_id=str(user.id),
            ip_address=_get_client_ip(self.request),
            after_state={'email': user.email, 'role': user.role, 'full_name': user.full_name},
        )

    def perform_update(self, serializer):
        instance = serializer.instance
        before_state = {
            'full_name': instance.full_name,
            'role': instance.role,
            'phone_number': instance.phone_number,
            'is_active': instance.is_active,
        }
        user = serializer.save()
        AuditLog.objects.create(
            user=self.request.user,
            action='UPDATE_USER',
            entity_type='User',
            entity_id=str(user.id),
            ip_address=_get_client_ip(self.request),
            before_state=before_state,
            after_state={
                'full_name': user.full_name,
                'role': user.role,
                'phone_number': user.phone_number,
                'is_active': user.is_active,
            },
        )

    @action(detail=True, methods=['post'])
    def deactivate(self, request, pk=None):
        user = self.get_object()
        if not user.is_active:
            return Response({'detail': 'User is already inactive.'},
                            status=status.HTTP_400_BAD_REQUEST)

        needs_reassignment_count = 0

        # SRS §3.12: Lecturer deactivation → NEEDS_REASSIGNMENT for future sessions
        if user.role == Role.LECTURER:
            from django.utils import timezone as tz
            from timetable.models import TimetableEntry, TimetableStatus
            from notifications.models import Notification

            now = tz.now()
            future_entries = (
                TimetableEntry.objects
                .select_related('course', 'semester', 'lecturer')
                .filter(
                    lecturer__user=user,
                    status=TimetableStatus.PUBLISHED,
                )
            )

            if future_entries.exists():
                ids = list(future_entries.values_list('id', flat=True))
                future_entries.update(status=TimetableStatus.NEEDS_REASSIGNMENT)
                needs_reassignment_count = len(ids)

                # Notify all active Coordinators about sessions needing reassignment
                session_list = '\n'.join(
                    f'  • {e.course.course_code} {e.day_of_week} '
                    f'{e.start_time:%H:%M}–{e.end_time:%H:%M}'
                    for e in future_entries.select_related('course')[:20]
                )
                Notification.broadcast_to_role(
                    role=Role.COORDINATOR,
                    notification_type=Notification.Type.GENERAL,
                    title=f'[URGENT] Lecturer Deactivated — Sessions Need Reassignment',
                    body=(
                        f'Lecturer {user.full_name} has been deactivated by '
                        f'{request.user.full_name}.\n\n'
                        f'{needs_reassignment_count} session(s) moved to NEEDS_REASSIGNMENT:\n'
                        f'{session_list}\n\n'
                        f'Please assign a replacement lecturer or cancel these sessions.'
                    ),
                    sender=request.user,
                    related_object_type='User',
                    related_object_id=user.pk,
                )

        user.is_active = False
        user.save(update_fields=['is_active'])
        AuditLog.objects.create(
            user=request.user, action='DEACTIVATE_USER',
            entity_type='User', entity_id=str(user.id),
            ip_address=_get_client_ip(request),
            before_state={'is_active': True}, after_state={'is_active': False},
            extra={'needs_reassignment_count': needs_reassignment_count},
        )
        return Response({
            'message': f'{user.full_name} deactivated.',
            'is_active': False,
            'needs_reassignment_count': needs_reassignment_count,
        })

    @action(detail=True, methods=['post'])
    def activate(self, request, pk=None):
        user = self.get_object()
        if user.is_active:
            return Response({'detail': 'User is already active.'},
                            status=status.HTTP_400_BAD_REQUEST)
        user.is_active = True
        user.save(update_fields=['is_active'])
        AuditLog.objects.create(
            user=request.user, action='ACTIVATE_USER',
            entity_type='User', entity_id=str(user.id),
            ip_address=_get_client_ip(request),
            before_state={'is_active': False}, after_state={'is_active': True},
        )
        return Response({'message': f'{user.full_name} activated.', 'is_active': True})

    @action(detail=True, methods=['post'])
    def change_password(self, request, pk=None):
        user = self.get_object()
        s = ChangePasswordSerializer(data=request.data)
        if not s.is_valid():
            return Response(s.errors, status=status.HTTP_400_BAD_REQUEST)
        user.set_password(s.validated_data['password'])
        user.save()
        AuditLog.objects.create(
            user=request.user, action='PASSWORD_UPDATED',
            entity_type='User', entity_id=str(user.id),
            ip_address=_get_client_ip(request),
        )
        return Response({'message': 'Password updated successfully.'})

    @action(detail=False, methods=['post'],
            parser_classes=[MultiPartParser, FormParser])
    def bulk_upload(self, request):
        serializer = BulkUserUploadSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        file = request.FILES['file']
        import_mode = serializer.validated_data.get('import_mode', 'strict')
        success_count = 0
        errors = []
        created_users = []

        try:
            with transaction.atomic():
                reader = csv.DictReader(StringIO(file.read().decode('utf-8')))
                for row_num, row in enumerate(reader, start=2):
                    try:
                        missing = [f for f in ('full_name', 'email', 'role')
                                   if not str(row.get(f, '')).strip()]
                        if missing:
                            raise ValueError(f"Missing: {', '.join(missing)}")

                        role = str(row['role']).strip().upper()
                        if role not in Role.values:
                            raise ValueError(f"Invalid role '{role}'")

                        user_data = {
                            'email': str(row['email']).strip().lower(),
                            'full_name': str(row['full_name']).strip(),
                            'role': role,
                            'phone_number': str(row.get('phone_number', '')).strip(),
                        }
                        user_ser = BulkUserCreateSerializer(data=user_data)
                        if not user_ser.is_valid():
                            raise ValueError(str(user_ser.errors))

                        user = user_ser.save()

                        # FR-52–56: create role-specific profiles when columns present
                        _create_role_profile(user, row, errors, row_num)

                        created_users.append({
                            'email': user.email,
                            'full_name': user.full_name,
                            'role': user.role,
                        })
                        success_count += 1
                        AuditLog.objects.create(
                            user=request.user, action='BULK_CREATE_USER',
                            entity_type='User', entity_id=str(user.id),
                            ip_address=_get_client_ip(request),
                            after_state=user_data,
                        )
                    except Exception as e:
                        errors.append(f'Row {row_num}: {e}')
                        if import_mode == 'strict':
                            raise
        except Exception as e:
            return Response(
                {'detail': str(e), 'errors': errors, 'success_count': success_count},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response({
            'success_count': success_count,
            'errors': errors,
            'created_users': created_users,
            'message': f'Imported {success_count} user(s) successfully.',
        })

    def perform_destroy(self, instance):
        """
        Security principle: users are NEVER hard-deleted.
        DELETE is re-routed to deactivation so audit trails, foreign-key
        references, and timetable history remain intact.
        """
        if instance == self.request.user:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('You cannot deactivate your own account.')
        if not instance.is_active:
            return  # already inactive — no-op
        before = {'is_active': True}
        instance.is_active = False
        instance.save(update_fields=['is_active'])
        AuditLog.objects.create(
            user=self.request.user, action='DEACTIVATE_USER',
            entity_type='User', entity_id=str(instance.id),
            ip_address=_get_client_ip(self.request),
            before_state=before, after_state={'is_active': False},
            extra={'via': 'DELETE endpoint redirected to deactivate (security policy)'},
        )

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """GET /api/auth/users/stats/ — counts for the admin dashboard tiles."""
        total = User.objects.count()
        active = User.objects.filter(is_active=True).count()
        by_role = {r: User.objects.filter(role=r).count() for r in Role.values}
        return Response({
            'total': total,
            'active': active,
            'inactive': total - active,
            'by_role': by_role,
        })

    @action(detail=False, methods=['get'])
    def system_stats(self, request):
        """GET /api/auth/users/system-stats/ — FR-4 performance monitoring."""
        from timetable.models import TimetableEntry
        from venues.models import Venue

        users_total = User.objects.count()
        users_active = User.objects.filter(is_active=True).count()
        by_role = {r: User.objects.filter(role=r).count() for r in Role.values}

        audit_total = AuditLog.objects.count()
        today_start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        audit_today = AuditLog.objects.filter(timestamp__gte=today_start).count()
        recent = list(
            AuditLog.objects.select_related('user')
            .order_by('-timestamp')[:10]
            .values('action', 'user__full_name', 'timestamp')
        )

        tt_total = TimetableEntry.objects.count()
        tt_published = TimetableEntry.objects.filter(status='PUBLISHED').count()

        venues_total = Venue.objects.count()
        venues_active = Venue.objects.filter(is_active=True).count()
        venue_by_status = {
            v: Venue.objects.filter(status=v, is_active=True).count()
            for v in ('FREE', 'BOOKED', 'IN_USE', 'EXPIRED', 'MAINTENANCE')
        }

        return Response({
            'users': {'total': users_total, 'active': users_active,
                      'inactive': users_total - users_active, 'by_role': by_role},
            'audit_log': {'total': audit_total, 'today': audit_today, 'recent': recent},
            'timetable': {'total_entries': tt_total, 'published': tt_published},
            'venues': {'total': venues_total, 'active': venues_active, 'by_status': venue_by_status},
        })


# ── Role-specific profile creation for bulk CSV (FR-52–56) ───────────────────

def _extract_year_of_study(registration_number: str) -> int:
    """
    Auto-compute year_of_study from registration number.
    Expects format: YYYY/PROG/NNN  e.g. 2022/BIT/001 → joined 2022 → year 3 in 2024/25.
    Falls back to 1 if pattern not found.
    """
    import re
    from datetime import date
    m = re.match(r'^(\d{4})', registration_number.strip())
    if m:
        enroll_year = int(m.group(1))
        current_year = date.today().year
        return max(1, current_year - enroll_year + 1)
    return 1


def _create_role_profile(user: User, row: dict, errors: list, row_num: int):
    """
    After a bulk-created user is saved, create role-specific profile records
    from extra CSV columns (FR-52–56).
    """
    role = user.role

    if role == Role.STUDENT:
        reg_num = str(row.get('registration_number', '')).strip()
        programme_code = str(row.get('programme_code', '')).strip()
        if reg_num and programme_code:
            try:
                from academics.models import Programme, StudentProfile
                prog = Programme.objects.get(code__iexact=programme_code)
                year = _extract_year_of_study(reg_num)
                StudentProfile.objects.update_or_create(
                    user=user,
                    defaults={
                        'registration_number': reg_num,
                        'programme': prog,
                        'year_of_study': year,
                    },
                )
            except Exception as exc:
                errors.append(f'Row {row_num} (StudentProfile): {exc}')

    elif role == Role.LECTURER:
        staff_number = str(row.get('staff_number', '')).strip()
        dept_code = str(row.get('department_code', '')).strip()
        if staff_number:
            try:
                from academics.models import Lecturer, Department
                dept = None
                if dept_code:
                    try:
                        dept = Department.objects.get(code__iexact=dept_code)
                    except Department.DoesNotExist:
                        errors.append(f'Row {row_num}: Department code "{dept_code}" not found — lecturer created without dept.')
                Lecturer.objects.update_or_create(
                    user=user,
                    defaults={
                        'staff_number': staff_number,
                        'department': dept,
                    },
                )
            except Exception as exc:
                errors.append(f'Row {row_num} (Lecturer profile): {exc}')


# ── Audit log ─────────────────────────────────────────────────────────────────

class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    """Read-only audit trail — System Admin only (FR-5)."""
    permission_classes = [IsSystemAdmin]
    serializer_class = AuditLogSerializer

    def get_queryset(self):
        qs = AuditLog.objects.select_related('user').all().order_by('-timestamp')
        p = self.request.query_params
        if p.get('action'):
            qs = qs.filter(action=p['action'])
        if p.get('entity_type'):
            qs = qs.filter(entity_type=p['entity_type'])
        if p.get('user'):
            qs = qs.filter(user_id=p['user'])
        if p.get('from'):
            qs = qs.filter(timestamp__gte=p['from'])
        if p.get('to'):
            qs = qs.filter(timestamp__lte=p['to'])
        return qs


# ── Password Reset (FR-1, FR-57) ──────────────────────────────────────────────

class ForgotPasswordView(APIView):
    """
    POST /api/auth/forgot-password/
    Body: {"email": "user@example.com"}

    Dev mode:   token returned in response body (no email configured).
    Production: sends email when EMAIL_HOST is set in settings; response
                only returns {"message": "..."} without the token.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        email = str(request.data.get('email', '')).strip().lower()
        if not email:
            return Response({'detail': 'Email is required.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            user = User.objects.get(email=email, is_active=True)
        except User.DoesNotExist:
            # Security: don't reveal whether the email exists
            return Response({
                'message': 'If that email exists in the system, a reset link has been generated.',
            })

        try:
            from timetable.models import SystemConfiguration
            reset_hours = SystemConfiguration.get().password_reset_link_hours
        except Exception:
            reset_hours = getattr(settings, 'PASSWORD_RESET_LINK_HOURS', 48)
        token_obj = PasswordResetToken.create_for_user(user, hours=reset_hours)

        AuditLog.objects.create(
            action='PASSWORD_RESET_REQUESTED',
            entity_type='User',
            entity_id=str(user.id),
            ip_address=_get_client_ip(request),
            extra={'email': email},
        )

        # Try to send email; fall back to dev-mode response
        email_sent = False
        if getattr(settings, 'EMAIL_HOST', None):
            try:
                reset_url = f"{getattr(settings, 'FRONTEND_URL', 'http://localhost:46063')}/#/reset-password?token={token_obj.token}"
                send_mail(
                    subject='UTLVA — Password Reset Request',
                    message=(
                        f'Hi {user.full_name},\n\n'
                        f'Click the link below to reset your password (valid {reset_hours} hours):\n\n'
                        f'{reset_url}\n\n'
                        'If you did not request this, ignore this email.\n\n— UTLVA System'
                    ),
                    from_email=getattr(settings, 'DEFAULT_FROM_EMAIL', 'noreply@utlva.ac.tz'),
                    recipient_list=[user.email],
                    fail_silently=False,
                )
                email_sent = True
            except Exception:
                pass  # fall through to dev-mode response

        response_data = {
            'message': (
                'Reset link sent to your email address.'
                if email_sent
                else 'Reset token generated (email not configured — use token directly in development).'
            ),
        }
        # Dev mode: expose token so it can be used without email
        if not email_sent:
            response_data['reset_token'] = token_obj.token
            response_data['expires_in_hours'] = reset_hours
            response_data['dev_note'] = (
                'Configure EMAIL_HOST in .env to send this via email in production.'
            )

        return Response(response_data)


class ResetPasswordView(APIView):
    """
    POST /api/auth/reset-password/
    Body: {"token": "...", "password": "NewPass@123"}
    """
    permission_classes = [AllowAny]

    def post(self, request):
        token_str = str(request.data.get('token', '')).strip()
        password = str(request.data.get('password', '')).strip()

        if not token_str or not password:
            return Response({'detail': 'token and password are required.'},
                            status=status.HTTP_400_BAD_REQUEST)

        try:
            token_obj = PasswordResetToken.objects.select_related('user').get(token=token_str)
        except PasswordResetToken.DoesNotExist:
            return Response({'detail': 'Invalid or expired reset token.'},
                            status=status.HTTP_400_BAD_REQUEST)

        if not token_obj.is_valid:
            return Response({'detail': 'Reset token has expired or already been used.'},
                            status=status.HTTP_400_BAD_REQUEST)

        try:
            validate_password(password, token_obj.user)
        except DjangoValidationError as e:
            return Response({'detail': list(e.messages)}, status=status.HTTP_400_BAD_REQUEST)

        token_obj.user.set_password(password)
        token_obj.user.save()
        token_obj.mark_used()

        AuditLog.objects.create(
            user=token_obj.user,
            action='PASSWORD_RESET_COMPLETED',
            entity_type='User',
            entity_id=str(token_obj.user.id),
            ip_address=_get_client_ip(request),
        )

        return Response({'message': 'Password reset successfully. You can now log in.'})


# ── SRS §3.9: Bulk Enrollment (FR-52 to FR-57) ────────────────────────────────

class BulkEnrollmentViewSet(viewsets.ViewSet):
    """
    POST /api/accounts/bulk-enroll/              — upload CSV and process
    GET  /api/accounts/bulk-enroll/              — list jobs (newest first)
    GET  /api/accounts/bulk-enroll/{id}/         — job detail + counts
    GET  /api/accounts/bulk-enroll/{id}/error-report/ — download CSV error report
    GET  /api/accounts/bulk-enroll/template/{role}/   — download blank CSV template
    """
    permission_classes = [IsSystemAdminOrCoordinator]
    parser_classes     = [MultiPartParser, FormParser]

    def list(self, request):
        from .models import BulkEnrollmentJob
        qs = BulkEnrollmentJob.objects.filter(
            uploaded_by=request.user
        ).values(
            'id', 'role', 'mode', 'status', 'filename',
            'total_rows', 'valid_rows', 'created_rows',
            'skipped_rows', 'error_count', 'created_at', 'completed_at',
        )[:50]
        return Response(list(qs))

    def create(self, request):
        """
        FR-52: Accept a CSV file and a role parameter.
        Query params:
          ?role=STUDENT|LECTURER   (required)
          ?mode=REJECT_ALL|IMPORT_VALID  (default: REJECT_ALL per FR-55)
        """
        from .models import BulkEnrollmentJob
        from .services.bulk_enrollment_service import BulkEnrollmentProcessor

        csv_file = request.FILES.get('file')
        if not csv_file:
            return Response({'detail': 'No file uploaded. Field name: "file".'}, status=status.HTTP_400_BAD_REQUEST)

        role = request.data.get('role', '').upper()
        if role not in ('STUDENT', 'LECTURER'):
            return Response(
                {'detail': 'Query param "role" must be STUDENT or LECTURER.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        mode = request.data.get('mode', BulkEnrollmentJob.Mode.REJECT_ALL).upper()
        if mode not in (BulkEnrollmentJob.Mode.REJECT_ALL, BulkEnrollmentJob.Mode.IMPORT_VALID):
            mode = BulkEnrollmentJob.Mode.REJECT_ALL

        csv_content = csv_file.read()
        if not csv_content:
            return Response({'detail': 'Uploaded file is empty.'}, status=status.HTTP_400_BAD_REQUEST)

        # FR-52 / SRS §3.11: enforce max rows limit from DB config
        try:
            from timetable.models import SystemConfiguration
            max_rows = SystemConfiguration.get().max_bulk_upload_rows
        except Exception:
            max_rows = getattr(settings, 'MAX_BULK_UPLOAD_ROWS', 5000)
        row_estimate = csv_content.count(b'\n')
        if row_estimate > max_rows:
            return Response(
                {'detail': f'File exceeds the maximum of {max_rows} rows (found ~{row_estimate} rows).'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        processor = BulkEnrollmentProcessor(
            csv_content=csv_content,
            role=role,
            mode=mode,
            uploaded_by=request.user,
            filename=csv_file.name,
        )
        job = processor.run()

        return Response({
            'job_id':       job.pk,
            'status':       job.status,
            'role':         job.role,
            'mode':         job.mode,
            'filename':     job.filename,
            'total_rows':   job.total_rows,
            'valid_rows':   job.valid_rows,
            'created_rows': job.created_rows,
            'skipped_rows': job.skipped_rows,
            'error_count':  job.error_count,
            'has_errors':   job.error_count > 0,
            'error_report_url': (
                f'/api/accounts/bulk-enroll/{job.pk}/error-report/'
                if job.error_count > 0 else None
            ),
            'message': _job_summary_message(job),
        }, status=status.HTTP_201_CREATED if job.created_rows > 0 else status.HTTP_200_OK)

    def retrieve(self, request, pk=None):
        from .models import BulkEnrollmentJob
        try:
            job = BulkEnrollmentJob.objects.get(pk=pk, uploaded_by=request.user)
        except BulkEnrollmentJob.DoesNotExist:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        return Response({
            'job_id':       job.pk,
            'status':       job.status,
            'role':         job.role,
            'mode':         job.mode,
            'filename':     job.filename,
            'total_rows':   job.total_rows,
            'valid_rows':   job.valid_rows,
            'created_rows': job.created_rows,
            'skipped_rows': job.skipped_rows,
            'error_count':  job.error_count,
            'created_at':   str(job.created_at),
            'completed_at': str(job.completed_at) if job.completed_at else None,
            'message':      _job_summary_message(job),
        })

    @action(detail=True, methods=['get'], url_path='error-report')
    def error_report(self, request, pk=None):
        """FR-55: Download the CSV error report for a job."""
        from django.http import HttpResponse
        from .models import BulkEnrollmentJob
        try:
            job = BulkEnrollmentJob.objects.get(pk=pk, uploaded_by=request.user)
        except BulkEnrollmentJob.DoesNotExist:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)

        if not job.error_report:
            return Response({'detail': 'No errors for this job.'}, status=status.HTTP_404_NOT_FOUND)

        response = HttpResponse(job.error_report, content_type='text/csv')
        response['Content-Disposition'] = f'attachment; filename="errors_job_{pk}.csv"'
        return response

    @action(detail=False, methods=['get'], url_path=r'template/(?P<role_name>STUDENT|LECTURER)')
    def csv_template(self, request, role_name=None):
        """Download a blank CSV template for the given role."""
        from django.http import HttpResponse
        from accounts.services.bulk_enrollment_service import STUDENT_COLUMNS, LECTURER_COLUMNS

        role_name = (role_name or '').upper()
        if role_name == 'STUDENT':
            headers = ['full_name', 'email', 'registration_number', 'programme_code', 'phone_number']
            example = ['John Mushi', 'john@example.com', '2021/CS/001', 'BSc-CS', '+255712345678']
        else:
            role_name = 'LECTURER'
            headers = ['full_name', 'email', 'staff_number_id', 'lecturer_department', 'phone_number']
            example = ['Dr. Jane Doe', 'jane@example.com', 'STAFF-0042', 'Computer Science', '+255787654321']

        buf = StringIO()
        writer = csv.writer(buf)
        writer.writerow(headers)
        writer.writerow(example)
        content = buf.getvalue()

        response = HttpResponse(content, content_type='text/csv')
        response['Content-Disposition'] = f'attachment; filename="utlva_{role_name.lower()}_template.csv"'
        return response

    @action(detail=True, methods=['get'], url_path='chunks')
    def chunk_list(self, request, pk=None):
        """
        SRS §3.12: GET /api/accounts/bulk-enroll/{id}/chunks/
        Returns chunk status for oversized-file imports.
        """
        from .models import BulkEnrollmentJob, BulkEnrollmentChunk
        try:
            job = BulkEnrollmentJob.objects.get(pk=pk, uploaded_by=request.user)
        except BulkEnrollmentJob.DoesNotExist:
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
        chunks = BulkEnrollmentChunk.objects.filter(job=job).values(
            'id', 'chunk_index', 'row_start', 'row_end',
            'status', 'created_rows', 'error_count', 'created_at', 'completed_at',
        )
        return Response({'job_id': job.pk, 'chunks': list(chunks)})

    @action(detail=True, methods=['post'], url_path=r'retry-chunk/(?P<chunk_pk>\d+)')
    def retry_chunk(self, request, pk=None, chunk_pk=None):
        """
        SRS §3.12: POST /api/accounts/bulk-enroll/{id}/retry-chunk/{chunk_id}/
        Retries only the FAILED chunk. Already-successful chunks are NOT re-imported.
        """
        from .models import BulkEnrollmentJob, BulkEnrollmentChunk
        from .services.bulk_enrollment_service import BulkEnrollmentProcessor
        try:
            job = BulkEnrollmentJob.objects.get(pk=pk, uploaded_by=request.user)
            chunk = BulkEnrollmentChunk.objects.get(pk=chunk_pk, job=job)
        except (BulkEnrollmentJob.DoesNotExist, BulkEnrollmentChunk.DoesNotExist):
            return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)

        if chunk.status == BulkEnrollmentChunk.Status.SUCCESS:
            return Response({'detail': 'Chunk already succeeded — not re-imported.', 'chunk_id': chunk.pk})
        if chunk.status == BulkEnrollmentChunk.Status.RETRYING:
            return Response({'detail': 'Chunk is already being retried.'}, status=status.HTTP_409_CONFLICT)

        # Retry requires the raw CSV to be re-uploaded (or stored); for now return 501
        return Response(
            {'detail': 'Chunk retry requires re-uploading the original CSV with ?retry_chunk=chunk_id.',
             'chunk_id': chunk.pk, 'row_start': chunk.row_start, 'row_end': chunk.row_end},
            status=status.HTTP_501_NOT_IMPLEMENTED,
        )


def _job_summary_message(job) -> str:
    from .models import BulkEnrollmentJob
    if job.status == BulkEnrollmentJob.Status.FAILED:
        return f'Import failed. {job.error_report[:200]}'
    if job.error_count > 0 and job.mode == BulkEnrollmentJob.Mode.REJECT_ALL:
        return (
            f'File rejected: {job.error_count} row(s) failed validation. '
            f'Download the error report, fix issues, and re-upload.'
        )
    parts = [f'{job.created_rows} account(s) created successfully.']
    if job.skipped_rows:
        parts.append(f'{job.skipped_rows} row(s) skipped (invalid).')
    if job.created_rows > 0:
        parts.append('Welcome emails dispatched via background task.')
    return ' '.join(parts)
