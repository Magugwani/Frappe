"""
UTLVA FCM Push Notification Service — SRS §3.8 FR-48

STUB — ready for Firebase integration.

To activate:
  1. Install SDK: pip install firebase-admin
  2. Place your serviceAccountKey.json in the backend root.
  3. Add to .env:
       FCM_CREDENTIALS_PATH=serviceAccountKey.json
       PUSH_GATEWAY=firebase

When PUSH_GATEWAY is not set the stub logs to console and returns True
(no-op push) so all other notification logic continues unaffected.
"""
import logging
from django.conf import settings

logger = logging.getLogger(__name__)


def _get_messaging():
    """Lazily initialise Firebase Admin SDK. Returns None if not configured."""
    if getattr(settings, 'PUSH_GATEWAY', 'stub') != 'firebase':
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials, messaging
        if not firebase_admin._apps:
            cred_path = getattr(settings, 'FCM_CREDENTIALS_PATH', 'serviceAccountKey.json')
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        return messaging
    except ImportError:
        logger.warning('firebase-admin not installed. Run: pip install firebase-admin')
        return None
    except Exception as exc:
        logger.error('Firebase init error: %s', exc)
        return None


def send_push(user, title: str, body: str, data: dict = None) -> bool:
    """
    Send a push notification to a single user using their stored FCM token.

    Returns True if sent (or stub), False if no token or send failed.
    """
    try:
        from .models import UserNotificationPreference
        pref = UserNotificationPreference.get_or_create_for_user(user)
        fcm_token = pref.fcm_token
    except Exception:
        fcm_token = ''

    if not fcm_token:
        return False

    messaging = _get_messaging()
    if messaging is None:
        # STUB — log to console
        logger.info('[PUSH STUB] To user %s (token: %s...): %s', user.pk, fcm_token[:20], title)
        print(f'\n[PUSH STUB] → {user.pk} | {title}\n{body}\n')
        return True

    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
        )
        messaging.send(message)
        return True
    except Exception as exc:
        logger.error('FCM send error for user %s: %s', user.pk, exc)
        return False
