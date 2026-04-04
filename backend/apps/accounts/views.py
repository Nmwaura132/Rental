from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import (
    CustomTokenObtainPairSerializer,
    UserProfileSerializer,
    UserRegistrationSerializer,
)

User = get_user_model()

class TenantListView(generics.ListAPIView):
    """List all active tenants — for landlords/caretakers to select when creating leases."""
    serializer_class = UserProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if not (user.is_landlord or user.is_caretaker):
            return User.objects.none()
        return User.objects.filter(role=User.Role.TENANT, is_active=True).order_by(
            "first_name", "last_name"
        )


class RegisterView(generics.CreateAPIView):
    serializer_class = UserRegistrationSerializer
    permission_classes = [permissions.AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {"message": "Account created successfully.", "phone_number": user.phone_number},
            status=status.HTTP_201_CREATED,
        )


class LoginView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [permissions.AllowAny]


class ProfileView(generics.RetrieveUpdateAPIView):
    serializer_class = UserProfileSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        return self.request.user


class PasswordResetRequestView(APIView):
    """
    Step 1 — Request a reset OTP.
    POST { phone_number } → sends a 6-digit OTP via SMS, stores in Redis (5 min TTL).
    Returns same message regardless of whether the number exists (anti-enumeration).
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        import random
        from django.core.cache import cache

        phone_number = request.data.get("phone_number", "").strip()
        if not phone_number:
            return Response({"error": "phone_number is required."}, status=400)

        from apps.core.utils.phone import normalize_phone
        try:
            phone_number = normalize_phone(phone_number)
        except Exception:
            return Response({"error": "Invalid phone number."}, status=400)

        try:
            user = User.objects.get(phone_number=phone_number)
        except User.DoesNotExist:
            # Same response to prevent phone enumeration
            return Response({"message": "If that number is registered, an OTP has been sent."})

        otp = f"{random.randint(100000, 999999)}"
        cache_key = f"pwd_reset_otp:{phone_number}"
        cache.set(cache_key, otp, timeout=300)  # 5 minutes

        from apps.notifications.tasks import send_sms
        send_sms.delay(
            user.id,
            f"Your Kasa password reset code is {otp}. Valid for 5 minutes. Do not share it.",
        )

        return Response({"message": "If that number is registered, an OTP has been sent."})


class PasswordResetView(APIView):
    """
    Step 2 — Confirm OTP and set new password.
    POST { phone_number, otp, new_password }
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        from django.core.cache import cache

        phone_number = request.data.get("phone_number", "").strip()
        otp = request.data.get("otp", "").strip()
        new_password = request.data.get("new_password", "")

        if not phone_number or not otp or not new_password:
            return Response(
                {"error": "phone_number, otp, and new_password are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        from apps.core.utils.phone import normalize_phone
        try:
            phone_number = normalize_phone(phone_number)
        except Exception:
            return Response({"error": "Invalid phone number."}, status=status.HTTP_400_BAD_REQUEST)

        cache_key = f"pwd_reset_otp:{phone_number}"
        stored_otp = cache.get(cache_key)

        if not stored_otp or stored_otp != otp:
            return Response({"error": "Invalid or expired OTP."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            user = User.objects.get(phone_number=phone_number)
        except User.DoesNotExist:
            return Response({"error": "Invalid or expired OTP."}, status=status.HTTP_400_BAD_REQUEST)

        from django.contrib.auth.password_validation import validate_password
        from django.core.exceptions import ValidationError

        try:
            validate_password(new_password, user)
        except ValidationError as e:
            return Response({"error": e.messages}, status=status.HTTP_400_BAD_REQUEST)

        user.set_password(new_password)
        user.save(update_fields=["password"])
        cache.delete(cache_key)  # invalidate OTP immediately after use
        return Response({"message": "Password reset successfully."})


class UploadIdPhotoView(APIView):
    """
    Upload tenant ID photo (front or back) to MinIO.
    POST /api/v1/auth/upload-id/
    Multipart form: side=front|back, photo=<file>, tenant_phone=<phone>
    Only landlords/caretakers can upload on behalf of a tenant.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        import boto3
        from botocore.client import Config
        from django.conf import settings as django_settings

        user = request.user
        if not (user.is_landlord or user.is_caretaker):
            return Response({"error": "Only landlords can upload tenant IDs."}, status=403)

        side = request.data.get("side", "").strip().lower()
        if side not in ("front", "back"):
            return Response({"error": "side must be 'front' or 'back'."}, status=400)

        photo = request.FILES.get("photo")
        if not photo:
            return Response({"error": "No photo uploaded."}, status=400)

        # Validate file type and size
        allowed_types = {"image/jpeg", "image/png", "image/webp", "image/heic"}
        if photo.content_type not in allowed_types:
            return Response(
                {"error": "Only JPEG, PNG, WEBP, or HEIC images are allowed."},
                status=400,
            )
        if photo.size > 10 * 1024 * 1024:  # 10 MB
            return Response({"error": "Image must be under 10 MB."}, status=400)

        tenant_phone = request.data.get("tenant_phone", "").strip()
        if not tenant_phone:
            return Response({"error": "tenant_phone is required."}, status=400)

        try:
            from apps.core.utils.phone import normalize_phone
            tenant_phone = normalize_phone(tenant_phone)
            tenant = User.objects.get(phone_number=tenant_phone, role=User.Role.TENANT)
        except User.DoesNotExist:
            return Response({"error": "Tenant not found."}, status=404)
        except Exception:
            return Response({"error": "Invalid phone number."}, status=400)

        # Determine file extension
        ext = photo.name.rsplit('.', 1)[-1].lower() if '.' in photo.name else 'jpg'
        phone_clean = tenant_phone.replace('+', '')
        key = f"tenant-ids/{phone_clean}/id_{side}.{ext}"

        try:
            s3 = boto3.client(
                "s3",
                endpoint_url=django_settings.AWS_S3_ENDPOINT_URL,
                aws_access_key_id=django_settings.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=django_settings.AWS_SECRET_ACCESS_KEY,
                config=Config(signature_version="s3v4"),
                region_name="us-east-1",
            )
            bucket = django_settings.AWS_STORAGE_BUCKET_NAME
            s3.upload_fileobj(
                photo,
                bucket,
                key,
                ExtraArgs={"ContentType": photo.content_type},
            )
            endpoint = django_settings.AWS_S3_ENDPOINT_URL.rstrip("/")
            photo_url = f"{endpoint}/{bucket}/{key}"
        except Exception as e:
            return Response({"error": f"Upload failed: {e}"}, status=500)

        # Save URL on tenant
        if side == "front":
            tenant.id_front_photo = photo_url
        else:
            tenant.id_back_photo = photo_url
        tenant.save(update_fields=[f"id_{side}_photo"])

        return Response({"url": photo_url, "side": side})


class ChangePasswordView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user = request.user
        old_password = request.data.get("old_password")
        new_password = request.data.get("new_password")

        if not user.check_password(old_password):
            return Response({"error": "Old password is incorrect."}, status=status.HTTP_400_BAD_REQUEST)

        from django.contrib.auth.password_validation import validate_password
        from django.core.exceptions import ValidationError

        try:
            validate_password(new_password, user)
        except ValidationError as e:
            return Response({"error": e.messages}, status=status.HTTP_400_BAD_REQUEST)

        user.set_password(new_password)
        user.save(update_fields=["password"])
        return Response({"message": "Password updated successfully."})
