"""
Management command: simulate a C2B Paybill payment in sandbox.

Safaricom C2B registration (registerurl) does not work with the STK Push
shortcode 174379 — that shortcode is for Lipa na M-Pesa Express only.
In sandbox, use this command to directly trigger a simulated Paybill payment
that hits your confirmation webhook, so you can test the payment recording flow.

Usage:
    python manage.py simulate_mpesa_c2b --unit 101 --amount 25000 --phone 254708374149

Safaricom will POST a C2B confirmation to your MPESA_CALLBACK_URL confirm/ endpoint.
Make sure ngrok is running and MPESA_CALLBACK_URL is set correctly in .env.
"""
from django.core.management.base import BaseCommand, CommandError
from django.conf import settings


class Command(BaseCommand):
    help = "Simulate a C2B Paybill payment in sandbox (Safaricom simulate endpoint)."

    def add_arguments(self, parser):
        parser.add_argument("--unit", required=True, help="Unit number (BillRefNumber) e.g. 101")
        parser.add_argument("--amount", type=int, default=1, help="Amount in KES (default: 1)")
        parser.add_argument("--phone", default="254708374149",
                            help="Sender phone in 2547XXXXXXXX format (default: Safaricom test number)")

    def handle(self, *args, **options):
        if settings.MPESA_ENVIRONMENT != "sandbox":
            raise CommandError("This command only works in sandbox mode (MPESA_ENVIRONMENT=sandbox).")

        unit = options["unit"].strip().upper()
        amount = options["amount"]
        phone = options["phone"].strip()

        self.stdout.write(f"Simulating C2B payment:")
        self.stdout.write(f"  Shortcode  : {settings.MPESA_SHORTCODE}")
        self.stdout.write(f"  Phone      : {phone}")
        self.stdout.write(f"  Amount     : KES {amount}")
        self.stdout.write(f"  Unit (ref) : {unit}")
        self.stdout.write(f"  Confirm URL: {settings.MPESA_CALLBACK_URL}confirm/")
        self.stdout.write("")

        try:
            from apps.payments.mpesa import simulate_c2b_payment
            result = simulate_c2b_payment(phone=phone, amount=amount, account_ref=unit)
        except Exception as exc:
            raise CommandError(f"Simulate failed: {exc}")

        response_code = result.get("ResponseCode") or result.get("errorCode", "?")
        response_desc = result.get("ResponseDescription") or result.get("CustomerMessage") \
                        or result.get("errorMessage", "")

        if str(response_code) == "0":
            self.stdout.write(self.style.SUCCESS(
                f"Simulation sent. Safaricom will POST the confirmation to your webhook.\n"
                f"  {response_desc}"
            ))
            self.stdout.write(
                "\nCheck the API logs with: docker compose logs -f api celery"
            )
        else:
            raise CommandError(
                f"Daraja returned an error.\n"
                f"  Code: {response_code}\n"
                f"  Desc: {response_desc}\n"
                f"  Full response: {result}"
            )
