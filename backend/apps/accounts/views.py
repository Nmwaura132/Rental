import logging

from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils.crypto import constant_time_compare, salted_hmac
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView
from drf_spectacular.utils import extend_schema

logger = logging.getLogger(__name__)

from apps.core.permissions import IsLandlordOrCaretaker

from .serializers import (
    CustomTokenObtainPairSerializer,
    UserProfileSerializer,
    UserRegistrationSerializer,
)

User = get_user_model()


def _password_reset_otp_digest(phone_number, otp):
    return salted_hmac(
        "kasa.password-reset",
        f"{phone_number}:{otp}",
    ).hexdigest()


def _tenant_qs_for_manager(user):
    tenants = User.objects.filter(role=User.Role.TENANT, is_active=True)
    if user.is_landlord:
        return tenants.filter(
            Q(created_by=user) | Q(leases__unit__property__owner=user)
        ).distinct()
    if user.is_caretaker:
        return tenants.filter(
            Q(created_by=user) | Q(leases__unit__property__caretaker=user)
        ).distinct()
    return User.objects.none()


class TenantListView(generics.ListAPIView):
    """List all active tenants — for landlords/caretakers to select when creating leases."""
    serializer_class = UserProfileSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = User.objects.none()  # for drf-spectacular schema introspection

    def get_queryset(self):
        return _tenant_qs_for_manager(self.request.user).order_by(
            "first_name", "last_name"
        )


class RegisterView(generics.CreateAPIView):
    serializer_class = UserRegistrationSerializer
    permission_classes = [IsLandlordOrCaretaker]
    # WHY: cap account creation per IP to slow bulk-account abuse.
    throttle_classes = [__import__('apps.core.throttles', fromlist=['RegisterThrottle']).RegisterThrottle]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save(created_by=request.user)
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


@extend_schema(exclude=True)  # WHY: ad-hoc body, no serializer; flow documented in handoff.md
class PasswordResetRequestView(APIView):
    """
    Step 1 — Request a reset OTP.
    POST { phone_number } → sends a 6-digit OTP via SMS, stores in Redis (5 min TTL).
    Returns same message regardless of whether the number exists (anti-enumeration).
    """
    permission_classes = [permissions.AllowAny]
    # WHY: each request triggers a real SMS at ~Ksh 0.20-1.50. Without a tight
    # cap per IP, an attacker could burn SMS credits at 20/min anon limit.
    throttle_classes = [__import__('apps.core.throttles', fromlist=['PasswordResetThrottle']).PasswordResetThrottle]

    def post(self, request):
        import secrets
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

        # WHY: secrets.randbelow is CSPRNG-backed; random.randint is Mersenne Twister
        # whose state can be recovered from ~624 outputs, making OTPs predictable
        # after enough password-reset requests.
        otp = f"{secrets.randbelow(900000) + 100000}"
        cache_key = f"pwd_reset_otp:{phone_number}"
        cache.set(
            cache_key,
            _password_reset_otp_digest(phone_number, otp),
            timeout=300,
        )
        cache.delete(f"pwd_reset_attempts:{phone_number}")

        from apps.notifications.tasks import send_sms
        send_sms.delay(
            user.id,
            f"Your Kasa password reset code is {otp}. Valid for 5 minutes. Do not share it.",
        )

        return Response({"message": "If that number is registered, an OTP has been sent."})


@extend_schema(exclude=True)
class PasswordResetView(APIView):
    """
    Step 2 — Confirm OTP and set new password.
    POST { phone_number, otp, new_password }
    """
    permission_classes = [permissions.AllowAny]
    # WHY: cap OTP-confirmation attempts per IP to slow brute-force of the
    # 6-digit code window. Step 1 also caps requests so refilling OTPs is bounded.
    throttle_classes = [__import__('apps.core.throttles', fromlist=['PasswordResetThrottle']).PasswordResetThrottle]

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

        submitted_digest = _password_reset_otp_digest(phone_number, otp)
        if not stored_otp or not constant_time_compare(stored_otp, submitted_digest):
            attempts_key = f"pwd_reset_attempts:{phone_number}"
            try:
                attempts = cache.incr(attempts_key)
            except ValueError:
                cache.set(attempts_key, 1, timeout=300)
                attempts = 1
            if attempts >= 5:
                cache.delete(cache_key)
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

        consume_key = f"pwd_reset_consumed:{phone_number}:{stored_otp}"
        if not cache.add(consume_key, True, timeout=300):
            return Response({"error": "Invalid or expired OTP."}, status=status.HTTP_400_BAD_REQUEST)
        cache.delete(cache_key)
        cache.delete(f"pwd_reset_attempts:{phone_number}")
        user.set_password(new_password)
        user.save(update_fields=["password"])
        return Response({"message": "Password reset successfully."})


@extend_schema(exclude=True)  # multipart upload — document in handoff.md
class UploadIdPhotoView(APIView):
    """
    Upload tenant ID photo (front or back) to MinIO.
    POST /api/v1/auth/upload-id/
    Multipart form: side=front|back, photo=<file>, tenant_phone=<phone>
    Only landlords/caretakers can upload on behalf of a tenant.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from apps.core.private_files import private_file_url, upload_private_file

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
            tenant = _tenant_qs_for_manager(user).get(phone_number=tenant_phone)
        except User.DoesNotExist:
            return Response({"error": "Tenant not found."}, status=404)
        except Exception:
            return Response({"error": "Invalid phone number."}, status=400)

        # Determine file extension
        ext = photo.name.rsplit('.', 1)[-1].lower() if '.' in photo.name else 'jpg'
        phone_clean = tenant_phone.replace('+', '')
        key = f"tenant-ids/{phone_clean}/id_{side}.{ext}"

        try:
            stored_key = upload_private_file(
                key,
                photo,
                photo.content_type,
            )
            photo_url = private_file_url(stored_key)
        except Exception:
            # WHY: never expose boto3/S3 exception text to clients — it leaks
            # endpoint URLs, bucket names, and IAM identifiers. Log the full
            # traceback for ops; return a generic message.
            logger.exception("ID photo upload failed (tenant=%s side=%s)", tenant_phone, side)
            return Response(
                {"error": "Upload failed. Please try again or contact support."},
                status=500,
            )

        if side == "front":
            tenant.id_front_photo = stored_key
        else:
            tenant.id_back_photo = stored_key
        tenant.save(update_fields=[f"id_{side}_photo"])

        return Response({"url": photo_url, "side": side})


@extend_schema(exclude=True)
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
