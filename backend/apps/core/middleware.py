"""
Core middleware — Safaricom IP allowlist for webhook endpoints.
"""
from django.http import HttpResponse


# Safaricom production IPs (as of 2025 — verify at developer.safaricom.co.ke)
SAFARICOM_IPS = {
    "196.201.214.200",
    "196.201.214.206",
    "196.201.213.114",
    "196.201.214.207",
    "196.201.214.208",
    "196.201.213.44",
    "196.201.212.127",
    "196.201.212.138",
    "196.201.212.129",
    "196.201.212.136",
    "196.201.212.74",
    "196.201.212.69",
}

WEBHOOK_PATHS = {
    "/api/v1/payments/mpesa/validate/",
    "/api/v1/payments/mpesa/confirm/",
    "/api/v1/payments/stk/callback/",
}


class SafaricomWebhookIPMiddleware:
    """
    In production, restrict Safaricom webhook endpoints to known Safaricom IPs.
    In DEBUG (development/sandbox) mode this check is skipped so ngrok works.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        from django.conf import settings

        if not settings.DEBUG and request.path in WEBHOOK_PATHS:
            ip = self._get_client_ip(request)
            if ip not in SAFARICOM_IPS:
                return HttpResponse("Forbidden", status=403)

        return self.get_response(request)

    @staticmethod
    def _get_client_ip(request) -> str:
        forwarded = request.META.get("HTTP_X_FORWARDED_FOR")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return request.META.get("REMOTE_ADDR", "")
