from rest_framework.throttling import AnonRateThrottle, UserRateThrottle


class MpesaWebhookThrottle(AnonRateThrottle):
    """High rate for Safaricom webhook callbacks."""
    rate = "300/minute"
    scope = "mpesa_webhook"


class STKPushThrottle(UserRateThrottle):
    """Limit STK push initiations per user to prevent spam charges."""
    rate = "10/minute"
    scope = "stk_push"


class PasswordResetThrottle(AnonRateThrottle):
    """Limit password-reset OTP requests per IP. SMS dispatch costs real money;
    the global 20/min anon limit is too generous for a write-heavy endpoint."""
    rate = "3/minute"
    scope = "password_reset"


class RegisterThrottle(AnonRateThrottle):
    """Limit account creation per IP to slow bulk-account-creation abuse."""
    rate = "5/minute"
    scope = "register"
