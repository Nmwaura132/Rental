"""
Management command: register M-Pesa C2B callback URLs with Safaricom Daraja.

Usage:
    python manage.py register_mpesa_c2b

Run this once after deployment (or whenever the callback base URL changes).
In sandbox mode it uses https://sandbox.safaricom.co.ke; production uses
https://api.safaricom.co.ke — controlled by MPESA_ENVIRONMENT in .env.

The two URLs registered:
  ConfirmationURL  →  {MPESA_CALLBACK_URL}confirm/
  ValidationURL    →  {MPESA_CALLBACK_URL}validate/
"""
from django.core.management.base import BaseCommand, CommandError
from django.conf import settings


class Command(BaseCommand):
    help = "Register M-Pesa C2B (Paybill) confirmation and validation URLs with Daraja."

    def handle(self, *args, **options):
        # Preflight checks
        missing = [
            k for k in ("MPESA_CONSUMER_KEY", "MPESA_CONSUMER_SECRET",
                        "MPESA_SHORTCODE", "MPESA_PASSKEY", "MPESA_CALLBACK_URL")
            if not getattr(settings, k, "")
        ]
        if missing:
            raise CommandError(
                f"Missing required settings: {', '.join(missing)}\n"
                "Fill in .env and restart before running this command."
            )

        env = settings.MPESA_ENVIRONMENT
        confirm_url = f"{settings.MPESA_CALLBACK_URL}confirm/"
        validate_url = f"{settings.MPESA_CALLBACK_URL}validate/"

        self.stdout.write(f"Environment : {env}")
        self.stdout.write(f"Shortcode   : {settings.MPESA_SHORTCODE}")
        self.stdout.write(f"Confirm URL : {confirm_url}")
        self.stdout.write(f"Validate URL: {validate_url}")
        self.stdout.write("")

        try:
            from apps.payments.mpesa import register_c2b_urls
            result = register_c2b_urls()
        except Exception as exc:
            raise CommandError(f"Daraja registration failed: {exc}")

        response_code = result.get("ResponseCode") or result.get("errorCode", "?")
        response_desc = result.get("ResponseDescription") or result.get("errorMessage", "")

        if str(response_code) == "0":
            self.stdout.write(self.style.SUCCESS(
                f"C2B URLs registered successfully. "
                f"({response_desc or 'Success'})"
            ))
        else:
            sandbox_note = ""
            if env == "sandbox":
                sandbox_note = (
                    "\n\nSandbox note: shortcode 174379 is for STK Push (Lipa na M-Pesa) only "
                    "and does not support C2B registerurl in sandbox.\n"
                    "To test C2B payments in sandbox, use:\n"
                    "  python manage.py simulate_mpesa_c2b --unit 101 --amount 25000\n"
                    "This command will skip registerurl and directly trigger a C2B webhook.\n"
                    "C2B URL registration is only needed in production with your real Paybill shortcode."
                )
            raise CommandError(
                f"Daraja returned an error.\n"
                f"  Code: {response_code}\n"
                f"  Desc: {response_desc}\n"
                f"  Full response: {result}"
                f"{sandbox_note}"
            )
