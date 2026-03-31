from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

User = get_user_model()


class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, validators=[validate_password])
    password_confirm = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = [
            "phone_number", "email", "first_name", "last_name",
            "role", "national_id", "kra_pin",
            "occupation", "next_of_kin_name", "next_of_kin_phone",
            "password", "password_confirm",
        ]

    def validate(self, attrs):
        if attrs.get("password") != attrs.get("password_confirm"):
            raise serializers.ValidationError({"password": "Passwords do not match."})
        attrs.pop("password_confirm", None)
        return attrs

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            "id", "phone_number", "email", "first_name", "last_name",
            "role", "national_id", "kra_pin", "is_verified", "date_joined",
        ]
        read_only_fields = ["id", "phone_number", "role", "is_verified", "date_joined"]


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Includes user role and name in the token response."""

    def validate(self, attrs):
        from apps.core.utils.phone import normalize_phone
        phone = attrs.get("phone_number", "").strip()
        if phone:
            attrs["phone_number"] = normalize_phone(phone)

        data = super().validate(attrs)
        data["role"] = self.user.role
        data["name"] = self.user.get_full_name()
        data["phone_number"] = self.user.phone_number
        return data
