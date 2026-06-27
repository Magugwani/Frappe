from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import User
from django.db import transaction
import csv
from io import StringIO
from django.core.mail import send_mail
from django.conf import settings


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


class UserCreateSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)

    class Meta:
        model = User
        fields = ['email', 'full_name', 'role', 'phone_number', 'password']

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user
class UserListSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'email', 'full_name', 'role', 'phone_number', 'is_active', 'date_joined']
        read_only_fields = ['id', 'date_joined']

class BulkUserCreateSerializer(serializers.ModelSerializer):

    class Meta:
        model = User
        fields = [
            "full_name",
            "email",
            "role",
            "phone_number",
        ]

class BulkUserUploadSerializer(serializers.Serializer):
    file = serializers.FileField(required=True)
    import_mode = serializers.ChoiceField(
        choices=['strict', 'partial'], 
        default='strict',
        help_text="strict = fail on first error, partial = skip bad rows"
    )

    def validate_file(self, file):
        if not file.name.lower().endswith('.csv'):
            raise serializers.ValidationError("Only .csv files are allowed.")
        if file.size > 5 * 1024 * 1024:  # 5MB limit
            raise serializers.ValidationError("File too large. Maximum 5MB.")
        return file