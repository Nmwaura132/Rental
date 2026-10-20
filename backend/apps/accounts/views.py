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
    TenantPickerSerializer,
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


def _code_digest(purpose, phone_number, code):
    # Salted by purpose, so a code sent to sign up cannot be used to sign in
    # (or the reverse), nor a password-reset code for either.
    return salted_hmac(f"kasa.{purpose}", f"{phone_number}:{code}").hexdigest()


CODE_COOLDOWN_SECONDS = 60
CODES_PER_HOUR = 5


def _may_text(purpose, phone_number):
    """Whether another code may be texted to this number for this purpose.

    WHY per number and not only per IP: the IP limit stops one device, but
    someone rotating IPs could still flood a stranger's phone with codes and
    run up the SMS bill. One a minute and five an hour per number also caps
    guessing at 25 tries an hour against a million combinations.
    """
    from django.core.cache import cache

    if not cache.add(f"{purpose}_cooldown:{phone_number}", True, timeout=CODE_COOLDOWN_SECONDS):
        return False
    hourly = f"{purpose}_hourly:{phone_number}"
    cache.add(hourly, 0, timeout=3600)
    try:
        return cache.incr(hourly) <= CODES_PER_HOUR
    except ValueError:
        cache.set(hourly, 1, timeout=3600)
        return True


def _issue_code(purpose, phone_number):
    """A fresh 6-digit code for [phone_number], valid 5 minutes. Only its
    salted hash is kept."""
    import secrets
    from django.core.cache import cache

    code = f"{secrets.randbelow(900000) + 100000}"
    cache.set(f"{purpose}_otp:{phone_number}", _code_digest(purpose, phone_number, code), timeout=300)
    cache.delete(f"{purpose}_attempts:{phone_number}")
    return code


def _code_matches(purpose, phone_number, code):
    """Whether [code] is the one last sent, without using it up. Five wrong
    tries burn it, so it cannot be guessed."""
    from django.core.cache import cache

    stored = cache.get(f"{purpose}_otp:{phone_number}")
    if stored and constant_time_compare(stored, _code_digest(purpose, phone_number, code)):
        return True
    attempts_key = f"{purpose}_attempts:{phone_number}"
    try:
        attempts = cache.incr(attempts_key)
    except ValueError:
        cache.set(attempts_key, 1, timeout=300)
        attempts = 1
    if attempts >= 5:
        cache.delete(f"{purpose}_otp:{phone_number}")
    return False


def _use_code(purpose, phone_number):
    """Spend the code. False if another request spent it first."""
    from django.core.cache import cache

    stored = cache.get(f"{purpose}_otp:{phone_number}")
    if not stored or not cache.add(f"{purpose}_consumed:{phone_number}:{stored}", True, timeout=300):
        return False
    cache.delete(f"{purpose}_otp:{phone_number}")
    cache.delete(f"{purpose}_attempts:{phone_number}")
    return True


def _session_for(user):
    """What a successful sign-in returns, by password or by code."""
    from django.contrib.auth.models import update_last_login
    from rest_framework_simplejwt.tokens import RefreshToken

    update_last_login(None, user)
    refresh = RefreshToken.for_user(user)
    return {
        "access": str(refresh.access_token),
        "refresh": str(refresh),
        "role": user.role,
        "name": user.get_full_name(),
        "phone_number": user.phone_number,
    }


def _tenant_qs_for_manager(user):
    tenants = User.objects.filter(role=User.Role.TENANT, is_active=True)
    if user.is_landlord:
        return tenants.filter(
            Q(created_by=user) | Q(tenancies__unit__property__owner=user)
        ).distinct()
    if user.is_caretaker:
        return tenants.filter(
            Q(created_by=user) | Q(tenancies__unit__property__caretaker=user)
        ).distinct()
    return User.objects.none()


class CaretakerListView(generics.ListAPIView):
    """Caretakers this landlord has taken on, for assigning to a property.

    Scoped to created_by: a landlord should see the people they hired, not
    every caretaker account on the platform.
    """

    serializer_class = TenantPickerSerializer
    permission_classes = [IsLandlordOrCaretaker]
    queryset = User.objects.none()  # for drf-spectacular schema introspection

    def get_queryset(self):
        if not self.request.user.is_landlord:
            return User.objects.none()
        return User.objects.filter(
            role=User.Role.CARETAKER,
            is_active=True,
            created_by=self.request.user,
        ).order_by("first_name", "last_name")


class TenantListView(generics.ListAPIView):
    """List all active tenants — for landlords/caretakers to select when creating tenancies."""
    serializer_class = TenantPickerSerializer
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


SIGNUP_CODE_SENT = "If this number can sign up, a code has been sent to it."


@extend_schema(exclude=True)  # WHY: ad-hoc body, no serializer
class SignupCodeView(APIView):
    """
    Step 1 of a landlord signing themselves up.
    POST { phone_number } → texts a 6-digit code, valid 5 minutes.

    A number that already has an account is told so by SMS instead. The
    response is the same either way, so the endpoint cannot be used to find
    out who has an account.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [__import__('apps.core.throttles', fromlist=['SignupCodeThrottle']).SignupCodeThrottle]

    def post(self, request):
        from apps.core.utils.phone import normalize_phone
        from apps.notifications.tasks import send_sms

        try:
            phone_number = normalize_phone(request.data.get("phone_number", "").strip())
        except Exception:
            return Response({"error": "Enter a valid Kenyan phone number."}, status=400)

        if request.user.is_authenticated:
            return Response({"error": "You are already signed in. Sign out to create another account."}, status=403)

        # The same answer when the number is rate-limited, so the limit cannot
        # be used to tell which numbers have accounts.
        if not _may_text("signup", phone_number):
            return Response({"message": SIGNUP_CODE_SENT})

        existing = User.objects.filter(phone_number=phone_number).first()
        if existing:
            send_sms.delay(
                existing.id,
                "This number already has a Kasa account. Open Kasa and sign in with a code instead.",
            )
            return Response({"message": SIGNUP_CODE_SENT})

        otp = _issue_code("signup", phone_number)
        send_sms.delay(
            None,
            f"Your Kasa sign-up code is {otp}. Valid for 5 minutes. Do not share it.",
            phone_number=phone_number,
        )
        return Response({"message": SIGNUP_CODE_SENT})


@extend_schema(exclude=True)
class SignupView(APIView):
    """
    Step 2: POST { phone_number, code, first_name, last_name[, password] }.
    Creates a landlord account and signs them in, returning the same tokens as
    login. Without a password they sign in with a code from then on.
    Tenants and caretakers are still added by their landlord.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [__import__('apps.core.throttles', fromlist=['RegisterThrottle']).RegisterThrottle]

    def post(self, request):
        from django.contrib.auth.password_validation import validate_password
        from django.core.exceptions import ValidationError
        from django.db import IntegrityError

        from apps.core.utils.phone import normalize_phone

        # One person, one account: someone already signed in cannot mint a
        # second one, even by calling this directly with another number.
        if request.user.is_authenticated:
            return Response({"error": "You are already signed in. Sign out to create another account."}, status=403)

        data = request.data
        code = str(data.get("code", "")).strip()
        first_name = str(data.get("first_name", "")).strip()[:150]
        last_name = str(data.get("last_name", "")).strip()[:150]
        password = data.get("password", "")
        try:
            phone_number = normalize_phone(str(data.get("phone_number", "")).strip())
        except Exception:
            return Response({"error": "Enter a valid Kenyan phone number."}, status=400)
        if not (code and first_name and last_name):
            return Response({"error": "Code, first name and last name are all needed."}, status=400)

        if not _code_matches("signup", phone_number, code):
            return Response({"error": "That code is wrong or has expired."}, status=400)

        if password:
            candidate = User(phone_number=phone_number, first_name=first_name, last_name=last_name)
            try:
                validate_password(password, candidate)
            except ValidationError as exc:
                return Response({"error": " ".join(exc.messages)}, status=400)

        # A code is good for one account, even if two requests race with it.
        if not _use_code("signup", phone_number):
            return Response({"error": "That code is wrong or has expired."}, status=400)

        try:
            user = User.objects.create_user(
                phone_number=phone_number,
                # None leaves the account with no usable password: code only.
                password=password or None,
                first_name=first_name,
                last_name=last_name,
                role=User.Role.LANDLORD,
            )
        except IntegrityError:
            return Response({"error": "This number already has an account. Sign in instead."}, status=409)

        return Response(_session_for(user), status=status.HTTP_201_CREATED)


LOGIN_CODE_SENT = "If this number has a Kasa account, a code has been sent to it."


@extend_schema(exclude=True)  # WHY: ad-hoc body, no serializer
class LoginCodeView(APIView):
    """
    Sign in with a code, step 1: POST { phone_number } texts a 6-digit code to
    an active account's number. Nothing is sent to a number with no account,
    and the response is the same either way.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes = [__import__('apps.core.throttles', fromlist=['SignupCodeThrottle']).SignupCodeThrottle]

    def post(self, request):
        from apps.core.utils.phone import normalize_phone
        from apps.notifications.tasks import send_sms

        try:
            phone_number = normalize_phone(request.data.get("phone_number", "").strip())
        except Exception:
            return Response({"error": "Enter a valid Kenyan phone number."}, status=400)

        user = User.objects.filter(phone_number=phone_number, is_active=True).first()
        if user and _may_text("login", phone_number):
            code = _issue_code("login", phone_number)
            send_sms.delay(user.id, f"Your Kasa sign-in code is {code}. Valid for 5 minutes. Do not share it.")
        return Response({"message": LOGIN_CODE_SENT})


@extend_schema(exclude=True)
class CodeLoginView(APIView):
    """Step 2: POST { phone_number, code } returns the same session as a
    password sign-in."""
    permission_classes = [permissions.AllowAny]
    throttle_classes = [__import__('apps.core.throttles', fromlist=['RegisterThrottle']).RegisterThrottle]

    def post(self, request):
        from apps.core.utils.phone import normalize_phone

        code = str(request.data.get("code", "")).strip()
        try:
            phone_number = normalize_phone(str(request.data.get("phone_number", "")).strip())
        except Exception:
            return Response({"error": "Enter a valid Kenyan phone number."}, status=400)

        wrong = Response({"error": "That code is wrong or has expired."}, status=400)
        if not code or not _code_matches("login", phone_number, code):
            return wrong
        user = User.objects.filter(phone_number=phone_number, is_active=True).first()
        if user is None or not _use_code("login", phone_number):
            return wrong
        return Response(_session_for(user))
