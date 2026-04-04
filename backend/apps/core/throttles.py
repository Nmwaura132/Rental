from rest_framework.throttling import AnonRateThrottle, UserRateThrottle


class MpesaWebhookThrottle(AnonRateThrottle):
    """High rate for Safaricom webhook callbacks."""
    rate = "300/minute"
    scope = "mpesa_webhook"


class STKPushThrottle(UserRateThrottle):
    """Limit STK push initiations per user to prevent spam charges."""
    rate = "10/minute"
    scope = "stk_push"
