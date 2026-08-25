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

        # WHY keyed on the creator's role: this endpoint is not self-service —
        # it requires an authenticated landlord or caretaker and stamps
        # created_by. A landlord runs the property, so they may take on a
        # caretaker; a caretaker may only add tenants, since letting them mint
        # peers would let one hire another behind the owner's back.
        creator = getattr(self.context.get("request"), "user", None)
        allowed = {User.Role.TENANT}
        if creator is not None and getattr(creator, "is_landlord", False):
            allowed.add(User.Role.CARETAKER)

        role = attrs.get("role", User.Role.TENANT)
        if role not in allowed:
            raise serializers.ValidationError(
                {"role": f"You cannot create a {role} account."}
            )

        attrs.pop("password_confirm", None)
        return attrs

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class TenantPickerSerializer(serializers.ModelSerializer):
    """Just enough to choose a tenant when creating a tenancy.

    WHY separate from UserProfileSerializer: that one carries national_id and
    kra_pin, and this list is readable by every caretaker on the property. A
    caretaker has no reason to see either, and the two together are exactly the
    pair used for SIM-swap and identity fraud. No client reads them back here.
    """

    class Meta:
        model = User
        fields = ["id", "phone_number", "first_name", "last_name", "is_verified"]


class UserProfileSerializer(serializers.ModelSerializer):
    id_front_photo_url = serializers.SerializerMethodField()
    id_back_photo_url = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id", "phone_number", "email", "first_name", "last_name",
            "role", "national_id", "kra_pin", "is_verified", "date_joined",
            "id_front_photo_url", "id_back_photo_url",
        ]
        read_only_fields = ["id", "phone_number", "role", "is_verified", "date_joined"]

    def get_id_front_photo_url(self, obj) -> str | None:
        return self._document_url(obj.id_front_photo)

    def get_id_back_photo_url(self, obj) -> str | None:
        return self._document_url(obj.id_back_photo)

    def _document_url(self, key):
        if not key:
            return None
        from django.conf import settings

        if not settings.USE_S3:
            return None
        from apps.core.private_files import private_file_url

        return private_file_url(key)


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
