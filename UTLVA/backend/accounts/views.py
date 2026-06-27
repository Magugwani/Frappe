from rest_framework import viewsets, status, generics
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.tokens import RefreshToken
from .serializers import BulkUserCreateSerializer

from django.db import transaction
import csv
from io import StringIO

from .models import Role, User, AuditLog
from .serializers import (
    CustomTokenObtainPairSerializer, 
    UserProfileSerializer, 
    UserCreateSerializer,
    UserListSerializer,
    BulkUserUploadSerializer
)
from .permissions import IsSystemAdminOrCoordinator
import logging

logger = logging.getLogger(__name__)

def _get_client_ip(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        return x_forwarded_for.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR')


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
                return Response({'detail': 'Refresh token required.'}, status=status.HTTP_400_BAD_REQUEST)
            
            token = RefreshToken(refresh_token)
            token.blacklist()
            
            AuditLog.objects.create(
                action='LOGOUT',
                entity_type='User',
                user=request.user,
                ip_address=_get_client_ip(request),
            )
            return Response({'detail': 'Successfully logged out.'}, status=status.HTTP_200_OK)
        except Exception:
            return Response({'detail': 'Invalid token.'}, status=status.HTTP_400_BAD_REQUEST)


class UserProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data)

    def patch(self, request):
        serializer = UserProfileSerializer(request.user, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    # ==============================
    # ADDED: USER UPDATE TRACKING
    # ==============================
    def update(self, request, *args, **kwargs):

        instance = self.get_object()

        # Store old data before update
        before_state = {
            'email': instance.email,
            'full_name': instance.full_name,
            'role': instance.role,
            'is_active': instance.is_active
        }


        response = super().update(
            request,
            *args,
            **kwargs
        )


        instance.refresh_from_db()


        # Store new data after update
        after_state = {
            'email': instance.email,
            'full_name': instance.full_name,
            'role': instance.role,
            'is_active': instance.is_active
        }


        AuditLog.objects.create(

            user=request.user,

            action='UPDATE_USER',

            entity_type='User',

            entity_id=str(instance.id),

            before_state=before_state,

            after_state=after_state
        )


        return response



    # ==============================
    # ADDED: PASSWORD UPDATE
    # ==============================
    @action(
        detail=True,
        methods=['post']
    )
    def change_password(self, request, pk=None):

        user = self.get_object()

        password = request.data.get('password')


        if not password:
            return Response(
                {
                    "error":
                    "Password required"
                },
                status=status.HTTP_400_BAD_REQUEST
            )


        user.set_password(password)

        user.save()



        AuditLog.objects.create(

            user=request.user,

            action='PASSWORD_UPDATED',

            entity_type='User',

            entity_id=str(user.id)

        )


        return Response(
            {
                "message":
                "Password updated successfully"
            }
        )



    # ==============================
    # ADDED: DEACTIVATE USER
    # ==============================
    @action(
        detail=True,
        methods=['post']
    )
    def deactivate(self, request, pk=None):

        user = self.get_object()


        before_state = {
            "is_active":
            user.is_active
        }


        user.is_active = False

        user.save()



        AuditLog.objects.create(

            user=request.user,

            action='DEACTIVATE_USER',

            entity_type='User',

            entity_id=str(user.id),

            before_state=before_state,

            after_state={
                "is_active":
                False
            }

        )


        return Response(
            {
                "message":
                "User deactivated successfully"
            }
        )

        #ACTIVATE USER==
    @action(
        detail=True,
        methods=['post']
    )
    def activate(self, request, pk=None):
        user = self.get_object()
        before_state = {
            "is_active":
            user.is_active
        }
        user.is_active = True
        user.save()
        AuditLog.objects.create(
            user=request.user,
            action='ACTIVATE_USER',
            entity_type='User',
            entity_id=str(user.id),
            before_state=before_state,
            after_state={
                "is_active":
                True
            }
        )
        return Response(
            {
                "message":
                "User activated successfully"
            }
        )
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


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    permission_classes = [IsSystemAdminOrCoordinator]
    
    def get_serializer_class(self):
        if self.action in ['create']:
            return UserCreateSerializer
        return UserListSerializer

    def perform_create(self, serializer):
        user = serializer.save()
        AuditLog.objects.create(
            user=self.request.user,
            action='CREATE_USER',
            entity_type='User',
            entity_id=str(user.id),
            after_state={'email': user.email, 'role': user.role, 'full_name': user.full_name}
        )
    @action(detail=False, methods=['post'], parser_classes=[MultiPartParser, FormParser])
    def bulk_upload(self, request):
        """Bulk user creation via CSV"""
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
                decoded_file = file.read().decode('utf-8')
                io_string = StringIO(decoded_file)
                reader = csv.DictReader(io_string)

                for row_num, row in enumerate(reader, start=2):
                    try:
                        required = ['full_name', 'email', 'role']
                        if not all(field in row and str(row[field]).strip() for field in required):
                            raise ValueError(f"Missing required fields in row {row_num}")

                        role = str(row['role']).strip().upper()
                        if role not in ['STUDENT', 'LECTURER', 'COORDINATOR', 'SYSTEM_ADMIN']:
                            raise ValueError(f"Invalid role '{role}' in row {row_num}")

                        user_data = {
                            'email': str(row['email']).strip().lower(),
                            'full_name': str(row['full_name']).strip(),
                            'role': role,
                            'phone_number': str(row.get('phone_number', '')).strip()
                        }

                        user_serializer = BulkUserCreateSerializer(data=user_data)
                        if user_serializer.is_valid():
                            user = user_serializer.save()
                            created_users.append({
                                'email': user.email,
                                'full_name': user.full_name,
                                'role': user.role,
                                # 'temp_password': user.temp_password  # You can return this
                            })
                            success_count += 1

                            AuditLog.objects.create(
                                user=request.user,
                                action='BULK_CREATE_USER',
                                entity_type='User',
                                entity_id=str(user.id),
                                after_state=user_data
                            )
                        else:
                            raise ValueError(str(user_serializer.errors))
                    except Exception as e:
                        errors.append(f"Row {row_num}: {str(e)}")
                        if import_mode == 'strict':
                            raise

        except Exception as e:
            return Response({
                'detail': str(e),
                'errors': errors,
                'success_count': success_count
            }, status=status.HTTP_400_BAD_REQUEST)

        return Response({
            'success_count': success_count,
            'errors': errors,
            'created_users': created_users,
            'message': f'Successfully imported {success_count} users.'
        }, status=status.HTTP_200_OK)