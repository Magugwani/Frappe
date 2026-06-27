from celery import shared_task
from django.core.mail import send_mail
from django.conf import settings
from .models import User

@shared_task
def send_welcome_email(user_id):
    try:
        user = User.objects.get(id=user_id)
        # One-time reset link logic (use Django password reset or custom token)
        send_mail(
            'Welcome to UTLVA',
            f'Hi {user.full_name}, your account is ready. Role: {user.role}. Reset password link...',
            settings.DEFAULT_FROM_EMAIL,
            [user.email],
            fail_silently=False,
        )
    except Exception:
        pass  # log