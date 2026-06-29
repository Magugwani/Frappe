import secrets
from datetime import timedelta
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone


class Role(models.TextChoices):
    SYSTEM_ADMIN = 'SYSTEM_ADMIN', 'System Administrator'
    COORDINATOR = 'COORDINATOR', 'Timetable Master / Coordinator'
    LECTURER = 'LECTURER', 'Lecturer'
    STUDENT = 'STUDENT', 'Student'


class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('role', Role.SYSTEM_ADMIN)
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=255)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.STUDENT)
    phone_number = models.CharField(max_length=20, blank=True)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    date_joined = models.DateTimeField(default=timezone.now)
    last_login = models.DateTimeField(null=True, blank=True)

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['full_name']

    class Meta:
        db_table = 'users'
        verbose_name = 'User'
        verbose_name_plural = 'Users'

    def __str__(self):
        return f'{self.full_name} ({self.email}) — {self.role}'

    @property
    def is_system_admin(self):
        return self.role == Role.SYSTEM_ADMIN

    @property
    def is_coordinator(self):
        return self.role == Role.COORDINATOR

    @property
    def is_lecturer(self):
        return self.role == Role.LECTURER

    @property
    def is_student(self):
        return self.role == Role.STUDENT


class AuditLog(models.Model):
    user = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs'
    )
    action = models.CharField(max_length=100)
    entity_type = models.CharField(max_length=100, blank=True)
    entity_id = models.CharField(max_length=100, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    before_state = models.JSONField(null=True, blank=True)
    after_state = models.JSONField(null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True)
    extra = models.JSONField(null=True, blank=True)

    class Meta:
        db_table = 'audit_logs'
        ordering = ['-timestamp']

    def __str__(self):
        return f'{self.action} by {self.user} at {self.timestamp}'


class PasswordResetToken(models.Model):
    """
    Short-lived token for password reset (FR-1, FR-57).

    Dev mode: token returned in API response.
    Production: token sent via email when EMAIL_HOST is configured.
    Tokens are single-use and expire after PASSWORD_RESET_LINK_HOURS (default 72 h).
    """
    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='reset_tokens',
    )
    token = models.CharField(max_length=64, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used = models.BooleanField(default=False)

    class Meta:
        db_table = 'password_reset_tokens'
        ordering = ['-created_at']

    @classmethod
    def create_for_user(cls, user, hours: int = 72) -> 'PasswordResetToken':
        """Invalidate all previous tokens for this user and issue a new one."""
        cls.objects.filter(user=user, used=False).delete()
        return cls.objects.create(
            user=user,
            token=secrets.token_urlsafe(48),
            expires_at=timezone.now() + timedelta(hours=hours),
        )

    @property
    def is_valid(self) -> bool:
        return not self.used and timezone.now() < self.expires_at

    def mark_used(self):
        self.used = True
        self.save(update_fields=['used'])


# ── FR-52–57: Bulk Enrollment Job ─────────────────────────────────────────────

class BulkEnrollmentJob(models.Model):
    """
    Tracks one CSV bulk-enrollment run.
    One job = one uploaded file for one role (STUDENT or LECTURER).
    """
    class Status(models.TextChoices):
        PROCESSING = 'PROCESSING', 'Processing'
        COMPLETED  = 'COMPLETED',  'Completed'
        FAILED     = 'FAILED',     'Failed'

    class Mode(models.TextChoices):
        REJECT_ALL    = 'REJECT_ALL',    'Reject entire file on any error (default)'
        IMPORT_VALID  = 'IMPORT_VALID',  'Import valid rows, skip invalid'

    uploaded_by   = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, related_name='bulk_jobs',
    )
    role          = models.CharField(max_length=10)   # 'STUDENT' or 'LECTURER'
    mode          = models.CharField(
        max_length=15, choices=Mode.choices, default=Mode.REJECT_ALL,
    )
    status        = models.CharField(
        max_length=12, choices=Status.choices, default=Status.PROCESSING,
    )
    filename      = models.CharField(max_length=255, blank=True)
    total_rows    = models.PositiveIntegerField(default=0)
    valid_rows    = models.PositiveIntegerField(default=0)
    created_rows  = models.PositiveIntegerField(default=0)
    skipped_rows  = models.PositiveIntegerField(default=0)
    error_count   = models.PositiveIntegerField(default=0)
    # CSV-format error report stored inline (small files ≤ 5000 rows)
    error_report  = models.TextField(blank=True)
    created_at    = models.DateTimeField(auto_now_add=True)
    completed_at  = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'bulk_enrollment_jobs'
        ordering = ['-created_at']

    def __str__(self):
        return f'BulkJob #{self.pk} {self.role} by {self.uploaded_by_id} ({self.status})'


# ── SRS §3.12: Chunked bulk enrollment (oversized files) ──────────────────────

class BulkEnrollmentChunk(models.Model):
    """
    SRS §3.12 — Partial failure recovery for bulk imports exceeding MAX_BULK_UPLOAD_ROWS.
    Each chunk is processed inside its own `@transaction.atomic` block.
    Successfully imported chunks are NOT re-imported on retry.
    """
    class Status(models.TextChoices):
        PENDING   = 'PENDING',   'Pending'
        SUCCESS   = 'SUCCESS',   'Succeeded'
        FAILED    = 'FAILED',    'Failed'
        RETRYING  = 'RETRYING',  'Retrying'

    job           = models.ForeignKey(BulkEnrollmentJob, on_delete=models.CASCADE, related_name='chunks')
    chunk_index   = models.PositiveIntegerField()           # 0-based
    row_start     = models.PositiveIntegerField()           # inclusive, relative to data rows (header=0)
    row_end       = models.PositiveIntegerField()           # inclusive
    status        = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING)
    created_rows  = models.PositiveIntegerField(default=0)
    error_count   = models.PositiveIntegerField(default=0)
    error_report  = models.TextField(blank=True)
    created_at    = models.DateTimeField(auto_now_add=True)
    completed_at  = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table        = 'bulk_enrollment_chunks'
        unique_together = [('job', 'chunk_index')]
        ordering        = ['chunk_index']

    def __str__(self):
        return f'Chunk {self.chunk_index} of Job #{self.job_id} ({self.status})'
