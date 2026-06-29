"""
UTLVA Bulk Enrollment Service — SRS §3.9

Processes a validated CSV upload for bulk student or lecturer account creation.

FR-53  Column requirements per role
FR-54  Row validation: email format, reg-number pattern, programme/department existence
FR-55  Two modes: REJECT_ALL (default) | IMPORT_VALID (skip bad rows)
FR-56  year_of_study auto-computed from registration_number
FR-57  Welcome email with 48-hour password reset link dispatched via Celery
"""

import csv
import io
import re
import logging
from datetime import date
from django.contrib.auth.hashers import make_password
from django.db import transaction

from accounts.models import User, Role, BulkEnrollmentJob

logger = logging.getLogger(__name__)

# ── Required CSV columns per role ─────────────────────────────────────────────

STUDENT_COLUMNS  = {'full_name', 'email', 'registration_number', 'programme_code', 'phone_number'}
LECTURER_COLUMNS = {'full_name', 'email', 'staff_number_id', 'lecturer_department', 'phone_number'}

# ── Email validation (RFC 5322 simplified) ────────────────────────────────────

_EMAIL_RE = re.compile(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')

def _valid_email(email: str) -> bool:
    return bool(_EMAIL_RE.match(email.strip()))

# ── Registration number validation and year extraction (FR-56) ────────────────

_REG_RE = re.compile(r'[\d]{2,4}')

def _extract_enrollment_year(reg_number: str) -> int | None:
    """
    Extract enrollment year from registration number.
    Supports:
      - "2021/CS/001"   → 2021
      - "21/CS/001"     → 2021 (2-digit → prefix 20)
      - "UD2022001"     → 2022
      - "21CS00123"     → 2021
    Returns None if no year can be extracted.
    """
    matches = _REG_RE.findall(reg_number)
    if not matches:
        return None
    first = matches[0]
    if len(first) == 4:
        return int(first)
    if len(first) == 2:
        year = int(first)
        return 2000 + year if year <= 50 else 1900 + year
    return None


def compute_year_of_study(reg_number: str) -> int:
    """
    FR-56: Compute year_of_study from registration_number.
    Academic year starts in October; clamp result to [1, 6].
    """
    enrollment_year = _extract_enrollment_year(reg_number)
    if enrollment_year is None:
        return 1

    today = date.today()
    # Academic year runs Oct–Sep: if we're before October the academic year hasn't ticked
    academic_year = today.year if today.month >= 10 else today.year - 1
    year_of_study = academic_year - enrollment_year + 1
    return max(1, min(6, year_of_study))


def _valid_reg_number(reg_number: str) -> bool:
    """Basic pattern: must contain at least 4 digits and 4+ characters total."""
    digits = re.findall(r'\d', reg_number)
    return len(digits) >= 4 and len(reg_number) >= 4


# ── Core processor ─────────────────────────────────────────────────────────────

class BulkEnrollmentProcessor:
    """
    Parse + validate + create accounts from a CSV upload.

    Usage:
        proc = BulkEnrollmentProcessor(csv_content, role='STUDENT',
                                       mode='REJECT_ALL', uploaded_by=user)
        job = proc.run()
    """

    def __init__(self, csv_content: bytes, role: str, mode: str, uploaded_by, filename: str = ''):
        self.csv_content = csv_content
        self.role        = role.upper()
        self.mode        = mode          # 'REJECT_ALL' | 'IMPORT_VALID'
        self.uploaded_by = uploaded_by
        self.filename    = filename

    def run(self) -> BulkEnrollmentJob:
        job = BulkEnrollmentJob.objects.create(
            uploaded_by=self.uploaded_by,
            role=self.role,
            mode=self.mode,
            filename=self.filename,
            status=BulkEnrollmentJob.Status.PROCESSING,
        )
        try:
            self._process(job)
        except Exception as exc:
            logger.exception('BulkEnrollmentJob #%s failed: %s', job.pk, exc)
            job.status = BulkEnrollmentJob.Status.FAILED
            job.error_report = f'Internal error: {exc}'
            job.save(update_fields=['status', 'error_report'])
        return job

    def _process(self, job: BulkEnrollmentJob):
        from django.utils import timezone

        text   = self.csv_content.decode('utf-8-sig').strip()  # strip BOM
        reader = csv.DictReader(io.StringIO(text))
        headers = {h.strip().lower() for h in (reader.fieldnames or [])}

        required = STUDENT_COLUMNS if self.role == 'STUDENT' else LECTURER_COLUMNS
        missing  = required - headers
        if missing:
            job.status = BulkEnrollmentJob.Status.FAILED
            job.error_report = f'Missing required columns: {", ".join(sorted(missing))}'
            job.save(update_fields=['status', 'error_report'])
            return

        rows         = [
            {k.strip().lower(): v.strip() for k, v in row.items()}
            for row in reader
        ]
        total        = len(rows)
        errors       = []   # list of (row_num, email, reason)
        valid_rows   = []

        # ── Validate every row ─────────────────────────────────────────────────
        if self.role == 'STUDENT':
            programmes = self._load_programmes()
            for i, row in enumerate(rows, start=2):  # row 1 = header
                errs = self._validate_student_row(row, i, programmes)
                if errs:
                    errors.extend(errs)
                else:
                    valid_rows.append(row)
        else:
            departments = self._load_departments()
            for i, row in enumerate(rows, start=2):
                errs = self._validate_lecturer_row(row, i, departments)
                if errs:
                    errors.extend(errs)
                else:
                    valid_rows.append(row)

        # ── FR-55: Decide import strategy ──────────────────────────────────────
        if errors and self.mode == BulkEnrollmentJob.Mode.REJECT_ALL:
            job.status      = BulkEnrollmentJob.Status.COMPLETED
            job.total_rows  = total
            job.valid_rows  = len(valid_rows)
            job.created_rows = 0
            job.error_count = len(errors)
            job.skipped_rows = len(errors)
            job.error_report = self._build_error_csv(errors)
            job.completed_at = timezone.now()
            job.save()
            return

        rows_to_create = valid_rows  # IMPORT_VALID: create only valid rows
        created_ids    = []

        # ── SRS §3.12: Use chunked processing for large files ──────────────────
        try:
            from timetable.models import SystemConfiguration
            max_rows = SystemConfiguration.get().max_bulk_upload_rows
        except Exception:
            max_rows = 5000

        if len(rows_to_create) > max_rows:
            created_ids = self._process_in_chunks(job, rows_to_create, errors, max_rows)
        else:
            # ── Create accounts in a single transaction (small file) ───────────
            if self.role == 'STUDENT':
                programmes = self._load_programmes()
                created_ids = self._create_students(rows_to_create, programmes, errors)
            else:
                departments = self._load_departments()
                created_ids = self._create_lecturers(rows_to_create, departments, errors)

        job.status       = BulkEnrollmentJob.Status.COMPLETED
        job.total_rows   = total
        job.valid_rows   = len(valid_rows)
        job.created_rows = len(created_ids)
        job.error_count  = len(errors)
        job.skipped_rows = total - len(valid_rows)
        job.error_report = self._build_error_csv(errors)
        job.completed_at = timezone.now()
        job.save()

        # ── FR-57: dispatch welcome emails asynchronously ──────────────────────
        if created_ids:
            from accounts.tasks import send_welcome_emails_for_job
            send_welcome_emails_for_job.delay(job.pk, created_ids)

    def _process_in_chunks(self, job, rows: list, all_errors: list, chunk_size: int) -> list:
        """
        SRS §3.12: Process an oversized file in chunks, each in its own
        @transaction.atomic. Creates BulkEnrollmentChunk records so the
        operator can retry only failed chunks. Already-successful chunks
        are never re-imported.
        """
        from accounts.models import BulkEnrollmentChunk
        from django.utils import timezone as tz

        created_ids = []
        chunks = [rows[i:i + chunk_size] for i in range(0, len(rows), chunk_size)]

        for idx, chunk_rows in enumerate(chunks):
            # Skip already-successful chunks (idempotency on retry)
            existing = BulkEnrollmentChunk.objects.filter(
                job=job, chunk_index=idx, status=BulkEnrollmentChunk.Status.SUCCESS
            ).first()
            if existing:
                continue

            chunk_obj, _ = BulkEnrollmentChunk.objects.get_or_create(
                job=job, chunk_index=idx,
                defaults={
                    'row_start': idx * chunk_size + 1,
                    'row_end': min((idx + 1) * chunk_size, len(rows)),
                    'status': BulkEnrollmentChunk.Status.RETRYING,
                },
            )
            chunk_obj.status = BulkEnrollmentChunk.Status.RETRYING
            chunk_obj.save(update_fields=['status'])

            chunk_errors = []
            try:
                if self.role == 'STUDENT':
                    programmes = self._load_programmes()
                    ids = self._create_students(chunk_rows, programmes, chunk_errors)
                else:
                    departments = self._load_departments()
                    ids = self._create_lecturers(chunk_rows, departments, chunk_errors)

                created_ids.extend(ids)
                chunk_obj.status = BulkEnrollmentChunk.Status.SUCCESS
                chunk_obj.created_rows = len(ids)
                chunk_obj.error_count = len(chunk_errors)
                chunk_obj.error_report = self._build_error_csv(chunk_errors)
                chunk_obj.completed_at = tz.now()
                chunk_obj.save()
                all_errors.extend(chunk_errors)

            except Exception as exc:
                chunk_obj.status = BulkEnrollmentChunk.Status.FAILED
                chunk_obj.error_report = str(exc)
                chunk_obj.completed_at = tz.now()
                chunk_obj.save()
                all_errors.append((0, '', f'Chunk {idx} failed: {exc}'))

        return created_ids

    # ── Validators ─────────────────────────────────────────────────────────────

    def _validate_student_row(self, row: dict, row_num: int, programmes: dict) -> list:
        errors = []
        email    = row.get('email', '')
        reg_num  = row.get('registration_number', '')
        prog_code = row.get('programme_code', '').upper()
        full_name = row.get('full_name', '').strip()

        if not full_name:
            errors.append((row_num, email, 'full_name is empty'))
        if not _valid_email(email):
            errors.append((row_num, email, f'Invalid email format: "{email}"'))
        if not _valid_reg_number(reg_num):
            errors.append((row_num, email, f'Invalid registration_number: "{reg_num}"'))
        if prog_code not in programmes:
            errors.append((row_num, email, f'Unknown programme_code: "{prog_code}"'))
        if User.objects.filter(email__iexact=email).exists():
            errors.append((row_num, email, f'Email already registered: "{email}"'))
        return errors

    def _validate_lecturer_row(self, row: dict, row_num: int, departments: dict) -> list:
        errors = []
        email     = row.get('email', '')
        staff_num = row.get('staff_number_id', '')
        dept_name = row.get('lecturer_department', '').strip()
        full_name = row.get('full_name', '').strip()

        if not full_name:
            errors.append((row_num, email, 'full_name is empty'))
        if not _valid_email(email):
            errors.append((row_num, email, f'Invalid email format: "{email}"'))
        if not staff_num:
            errors.append((row_num, email, 'staff_number_id is empty'))
        if dept_name.lower() not in departments:
            errors.append((row_num, email, f'Unknown lecturer_department: "{dept_name}"'))
        if User.objects.filter(email__iexact=email).exists():
            errors.append((row_num, email, f'Email already registered: "{email}"'))
        return errors

    # ── Account creators ───────────────────────────────────────────────────────

    @transaction.atomic
    def _create_students(self, rows: list, programmes: dict, errors: list) -> list:
        from academics.models import StudentProfile
        created_ids = []
        for row in rows:
            try:
                email    = row['email'].lower().strip()
                prog_code = row.get('programme_code', '').upper()
                reg_num   = row.get('registration_number', '')
                phone     = row.get('phone_number', '')

                user = User.objects.create(
                    email=email,
                    full_name=row['full_name'].strip(),
                    role=Role.STUDENT,
                    phone_number=phone,
                    is_active=True,
                    password=make_password(None),  # unusable password — reset link required
                )

                prog = programmes.get(prog_code)
                year = compute_year_of_study(reg_num)

                StudentProfile.objects.create(
                    user=user,
                    registration_number=reg_num,
                    programme=prog,
                    year_of_study=year,
                )
                created_ids.append(user.pk)
            except Exception as exc:
                errors.append((0, row.get('email', ''), f'Creation failed: {exc}'))
        return created_ids

    @transaction.atomic
    def _create_lecturers(self, rows: list, departments: dict, errors: list) -> list:
        from academics.models import Lecturer
        created_ids = []
        for row in rows:
            try:
                email     = row['email'].lower().strip()
                dept_name = row.get('lecturer_department', '').strip().lower()
                staff_num = row.get('staff_number_id', '').strip()
                phone     = row.get('phone_number', '')

                user = User.objects.create(
                    email=email,
                    full_name=row['full_name'].strip(),
                    role=Role.LECTURER,
                    phone_number=phone,
                    is_active=True,
                    password=make_password(None),
                )

                dept = departments.get(dept_name)
                Lecturer.objects.create(
                    user=user,
                    staff_number=staff_num,
                    department=dept,
                )
                created_ids.append(user.pk)
            except Exception as exc:
                errors.append((0, row.get('email', ''), f'Creation failed: {exc}'))
        return created_ids

    # ── Reference data loaders ─────────────────────────────────────────────────

    @staticmethod
    def _load_programmes() -> dict:
        from academics.models import Programme
        return {p.code.upper(): p for p in Programme.objects.all()}

    @staticmethod
    def _load_departments() -> dict:
        from academics.models import Department
        return {d.name.lower(): d for d in Department.objects.all()}

    # ── Error CSV builder ──────────────────────────────────────────────────────

    @staticmethod
    def _build_error_csv(errors: list) -> str:
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(['row_number', 'email', 'error_reason'])
        for row_num, email, reason in errors:
            writer.writerow([row_num, email, reason])
        return buf.getvalue()
