from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import User, AuditLog


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Adds role, full_name, and email to the JWT payload."""

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['role'] = user.role
        token['full_name'] = user.full_name
        token['email'] = user.email
        return token

    def validate(self, attrs):
        data = super().validate(attrs)
        data['role'] = self.user.role
        data['full_name'] = self.user.full_name
        data['email'] = self.user.email
        data['user_id'] = str(self.user.id)
        return data


class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'email', 'full_name', 'role', 'phone_number', 'date_joined', 'last_login']
        read_only_fields = ['id', 'email', 'role', 'date_joined', 'last_login']


class UserListSerializer(serializers.ModelSerializer):
    role_display = serializers.CharField(source='get_role_display', read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'email', 'full_name', 'role', 'role_display',
            'phone_number', 'is_active', 'date_joined', 'last_login',
        ]
        read_only_fields = ['id', 'date_joined', 'last_login', 'role_display']


class UserCreateSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ['id', 'email', 'full_name', 'role', 'phone_number', 'password']
        read_only_fields = ['id']

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user


class UserUpdateSerializer(serializers.ModelSerializer):
    """Admin/Coordinator update — cannot change email or password here."""

    class Meta:
        model = User
        fields = ['full_name', 'role', 'phone_number', 'is_active']


class ChangePasswordSerializer(serializers.Serializer):
    password = serializers.CharField(min_length=8, write_only=True)


class BulkUserCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['full_name', 'email', 'role', 'phone_number']

    def create(self, validated_data):
        user = User(**validated_data)
        user.set_password('UTLVA@2025')   # temporary — real welcome email in notification phase
        user.save()
        return user


class BulkUserUploadSerializer(serializers.Serializer):
    file = serializers.FileField(required=True)
    import_mode = serializers.ChoiceField(
        choices=['strict', 'partial'],
        default='strict',
        help_text='strict = fail entire file on first error; partial = skip bad rows',
    )

    def validate_file(self, file):
        if not file.name.lower().endswith('.csv'):
            raise serializers.ValidationError('Only .csv files are allowed.')
        if file.size > 5 * 1024 * 1024:
            raise serializers.ValidationError('File too large. Maximum 5 MB.')
        return file


class AuditLogSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()
    user_email = serializers.SerializerMethodField()

    class Meta:
        model = AuditLog
        fields = [
            'id', 'user', 'user_name', 'user_email',
            'action', 'entity_type', 'entity_id',
            'before_state', 'after_state',
            'ip_address', 'timestamp', 'extra',
        ]
        read_only_fields = fields

    def get_user_name(self, obj):
        return obj.user.full_name if obj.user else 'System'

    def get_user_email(self, obj):
        return obj.user.email if obj.user else None
