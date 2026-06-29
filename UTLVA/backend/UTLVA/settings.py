from pathlib import Path
from datetime import timedelta
from decouple import config, Csv

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = config('SECRET_KEY')
DEBUG = config('DEBUG', default=False, cast=bool)
ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='localhost,127.0.0.1', cast=Csv())

# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # Third-party
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    # djabgo_celery_beat
    'django_celery_beat',
    # Local apps
    'accounts',
    'academics',
    'venues',
    'timetable',
    'notifications',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'UTLVA.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'UTLVA.wsgi.application'

# Database — PostgreSQL
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': config('DB_NAME', default='utlva_db'),
        'USER': config('DB_USER', default='utlva_user'),
        'PASSWORD': config('DB_PASSWORD', default=''),
        'HOST': config('DB_HOST', default='localhost'),
        'PORT': config('DB_PORT', default='5432'),
    }
}

# Custom User model
AUTH_USER_MODEL = 'accounts.User'

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Django REST Framework
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_RENDERER_CLASSES': (
        'rest_framework.renderers.JSONRenderer',
    ),
    'DEFAULT_THROTTLE_CLASSES': [
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'anon': '20/minute',
        'user': '100/minute',
    },
}

# JWT Configuration
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(
        minutes=config('ACCESS_TOKEN_LIFETIME_MINUTES', default=60, cast=int)
    ),
    'REFRESH_TOKEN_LIFETIME': timedelta(
        days=config('REFRESH_TOKEN_LIFETIME_DAYS', default=7, cast=int)
    ),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'AUTH_HEADER_NAME': 'HTTP_AUTHORIZATION',
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
    'TOKEN_OBTAIN_SERIALIZER': 'accounts.serializers.CustomTokenObtainPairSerializer',
}

# Celery Configuration
CELERY_BROKER_URL = 'redis://localhost:6379/0'
CELERY_RESULT_BACKEND = 'redis://localhost:6379/0'
CELERY_ACCEPT_CONTENT = ['application/json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = 'UTC'
CELERY_ENABLE_UTC = True
# CORS
CORS_ALLOWED_ORIGINS = config(
    'CORS_ALLOWED_ORIGINS',
    default='http://localhost:3000,http://127.0.0.1:3000',
    cast=Csv(),
)
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOW_ALL_ORIGINS = DEBUG  # allows any origin in DEBUG mode (Flutter web)

# ── Email configuration (SMTP via Gmail App Password) ────────────────────────
# Rules:
#   • EMAIL_USE_TLS = True  and EMAIL_USE_SSL = False  → port 587 (STARTTLS) ✓
#   • EMAIL_USE_TLS = False and EMAIL_USE_SSL = True   → port 465 (implicit SSL)
#   • Never set both to True — Django raises an error.
# Gmail App Password contains spaces (groups of 4). Keep it in .env quoted:
#   EMAIL_HOST_PASSWORD="xxxx xxxx xxxx xxxx"
# DEFAULT_FROM_EMAIL must be a plain address or RFC 2822 display name:
#   DEFAULT_FROM_EMAIL=UTLVA System <maduhumagugwani@gmail.com>

EMAIL_HOST          = config('EMAIL_HOST',          default='')
EMAIL_PORT          = config('EMAIL_PORT',          default=587, cast=int)
EMAIL_HOST_USER     = config('EMAIL_HOST_USER',     default='')
EMAIL_HOST_PASSWORD = config('EMAIL_HOST_PASSWORD', default='')
EMAIL_USE_TLS       = config('EMAIL_USE_TLS',       default=True,  cast=bool)
EMAIL_USE_SSL       = config('EMAIL_USE_SSL',       default=False, cast=bool)
EMAIL_TIMEOUT       = 20   # seconds — fail fast on bad host

# Sanitise DEFAULT_FROM_EMAIL: if the .env value has a bare name without
# angle brackets (e.g. "UTLVA maduhumagugwani@gmail.com") we use the email
# part only to avoid RFC 2822 parse errors in Django's SMTP backend.
_raw_from = config('DEFAULT_FROM_EMAIL', default='noreply@utlva.local')
if '<' not in _raw_from and ' ' in _raw_from:
    # e.g. "UTLVA maduhumagugwani@gmail.com" → take the last token
    _from_parts = _raw_from.strip().split()
    DEFAULT_FROM_EMAIL = _from_parts[-1]
else:
    DEFAULT_FROM_EMAIL = _raw_from

SERVER_EMAIL = DEFAULT_FROM_EMAIL

# Frontend URL used in password-reset emails
FRONTEND_URL = config('FRONTEND_URL', default='http://localhost:46063')

# SRS configuration parameters
PASSWORD_RESET_LINK_HOURS        = config('PASSWORD_RESET_LINK_HOURS',        default=72,  cast=int)
CONFIRMATION_WINDOW_MINUTES      = config('CONFIRMATION_WINDOW_MINUTES',      default=40,  cast=int)
REMINDER_LEAD_MINUTES            = config('REMINDER_LEAD_MINUTES',            default=120, cast=int)
SMS_DAILY_CAP_PER_USER           = config('SMS_DAILY_CAP_PER_USER',           default=5,   cast=int)
SMS_BULK_APPROVAL_THRESHOLD      = config('SMS_BULK_APPROVAL_THRESHOLD',      default=50,  cast=int)
MAX_BULK_UPLOAD_ROWS             = config('MAX_BULK_UPLOAD_ROWS',             default=5000,cast=int)
VENUE_STATUS_CHECK_INTERVAL_SECS = config('VENUE_STATUS_CHECK_INTERVAL_SECS', default=60,  cast=int)

if EMAIL_HOST:
    EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
else:
    # No SMTP host → print emails to the runserver console (dev fallback).
    EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'