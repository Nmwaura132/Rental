# Kasa — Developer Handoff

Last updated: 2026-05-16 | Branch: main | Commit: 893d930

## What is this?

Kasa is a rental property management system for the Kenyan informal landlord market. Multi-unit landlords (and their caretakers) collect rent from tenants via M-Pesa Paybill or STK Push, track invoices and maintenance requests, and send SMS reminders.

**Three roles**: Landlord (owner), Caretaker (manages on behalf of landlord), Tenant.
**Primary identifier**: phone number in E.164 format (e.g., `+254712345678`). Email is optional.

## Current state

**In development. NOT YET LIVE in production for real users.**

A staging instance runs on a single VPS at `37.221.93.219` via Coolify + Docker Compose. The mobile app currently routes `/login` to `DevPickerScreen` (one-tap login as landlord or tenant using hardcoded dev credentials) — this is the biggest launch blocker.

## Critical issues blocking launch

Severity-ordered list (consolidated from `/autoplan` review on 2026-05-16):

1. **[CRITICAL]** Mobile login is `DevPickerScreen`, not `LoginScreen` — `mobile/lib/core/router.dart` line 41. Swap before any user touches the app.
2. **[CRITICAL]** Refresh token rotation bug — `mobile/lib/core/api/api_client.dart` line ~109. `_tryRefreshToken()` saves `access_token` but never persists the new `refresh_token`. Backend has `ROTATE_REFRESH_TOKENS = True` — every user is silently logged out after first 30-minute expiry.
3. **[CRITICAL]** Invoice `amount_paid` race condition — `backend/apps/payments/tasks.py`. Both `process_mpesa_payment` and `process_stk_callback` do non-atomic read-modify-write on `invoice.amount_paid`. Two simultaneous payments corrupt the balance. Fix with `F()` expressions or `select_for_update()`.
4. **[HIGH]** OTP uses `random.randint` (Mersenne Twister, not cryptographically secure) — `backend/apps/accounts/views.py:PasswordResetRequestView`. Replace with `secrets.randbelow(900000) + 100000`.
5. **[HIGH]** Raw exceptions in 500 responses — `UploadIdPhotoView` (`accounts/views.py`) and `send_lease` (`tenants/views.py`). Exposes S3 endpoint URLs and bucket names. Log + return generic message.
6. **[HIGH]** MinIO admin console port 9001 publicly exposed in prod — `docker-compose.prod.yml`. Remove `9001:9001` port mapping.
7. **[HIGH]** Hardcoded dev credentials + production IP in mobile — `mobile/lib/core/constants.dart`. Move to `--dart-define` build args.
8. **[HIGH]** No automated tests on money/auth paths. `pytest-django` and `factory-boy` are in `requirements.txt` but never used.
9. **[MEDIUM]** No rate limiting on `RegisterView`, `PasswordResetRequestView`, `PasswordResetView` — auth endpoints inherit global `anon: 20/min` only.
10. **[MEDIUM]** Float arithmetic with money — `record_payment` view does `float(amount)` before `Decimal` conversion.
11. **[MEDIUM]** `send_payment_receipt_sms` has no retry/error handling.
12. **[MEDIUM]** `PublicMediaStorage()` instantiated at class-definition time — `tenants/models.py:MaintenanceRequest`. Crashes Django import when S3 env vars unset.
13. **[LOW]** Swagger `/api/docs/` not gated by `DEBUG` — `backend/config/urls.py`.
14. **[LOW]** Invoices created on 1st with `due_date` = 1st — no advance warning; reminders fire before invoice exists.
15. **[LOW]** Dual unit-status sync (signal + viewset hooks) in lease save path.

Full details and fixes: `~/.gstack/projects/Nmwaura132-Rental/main-autoplan-20260516.md`

## Setup (new developer)

```bash
# 1. Clone
git clone https://github.com/Nmwaura132/Rental.git
cd Rental

# 2. Configure environment
cp .env.example .env
# Fill in: SECRET_KEY, DB_*, REDIS_*, MPESA_*, AT_*, MINIO_*

# 3. Bring up dev stack
docker compose up -d

# 4. Wait for MySQL healthcheck (~60s on first boot), then:
docker compose exec api python manage.py migrate
docker compose exec api python manage.py createsuperuser
# Username = phone number in E.164 format

# 5. Mobile
cd mobile
flutter pub get
flutter run
```

Sandbox M-Pesa credentials are at https://developer.safaricom.co.ke. The default `.env.example` includes placeholder values.

## Key file map

### Backend (`backend/`)
- `config/settings.py` — Django settings (JWT, CORS, throttles, security headers, Celery Beat schedule)
- `config/urls.py` — top-level URL routing
- `apps/accounts/` — User model (phone as username), auth, OTP, profile, ID upload
- `apps/properties/` — Property, Unit, PropertyCharge models
- `apps/tenants/` — Lease, MaintenanceRequest, MaintenanceNote, lease PDF generation
- `apps/payments/` — Invoice, Payment, M-Pesa C2B + STK Push, bank reconciliation (KCB/Equity via Jenga), reports
- `apps/notifications/` — Notification model, SMS + WhatsApp dispatch, rent reminders
- `apps/core/middleware.py` — Safaricom webhook IP allowlist
- `apps/core/storage_backends.py` — MinIO/S3 public + private storage classes
- `apps/core/throttles.py` — `MpesaWebhookThrottle`, `STKPushThrottle`
- `apps/core/utils/phone.py` — phone normalization (E.164)

### Mobile (`mobile/lib/`)
- `main.dart` — app entry, providers, MaterialApp
- `core/api/api_client.dart` — Dio instance + JWT interceptor (refresh token bug here)
- `core/router.dart` — GoRouter; routes `/login` to `DevPickerScreen` currently
- `core/constants.dart` — hardcoded API base URL + dev credentials (must be removed before release)
- `core/theme/kasa_tokens.dart` — design tokens
- `features/auth/` — `login_screen.dart` (NOT wired) + `dev_picker_screen.dart` (currently wired)
- `features/dashboard/`, `features/properties/`, `features/tenants/`, `features/payments/`, `features/maintenance/`, `features/profile/`, `features/notifications/` — UI screens

### Infrastructure
- `docker-compose.yml` — dev stack
- `docker-compose.prod.yml` — prod stack (remove 9001 port before deploy)
- `backend/Dockerfile` — non-root `django` user, mysqlclient build deps
- `backend/entrypoint.sh` — waits for MySQL, runs migrations + collectstatic for API container only
- `mysql/Dockerfile` — custom MySQL image

## External dependencies and contracts

- **Safaricom Daraja API** — sandbox + production. Production URLs registered via `MpesaRegisterC2BView`. Webhook IP allowlist hardcoded in `core/middleware.py:SAFARICOM_IPS` — verify list against developer.safaricom.co.ke at least annually.
- **Africa's Talking** — SMS dispatch. Custom sender ID requires AT support ticket; defaults to shared sandbox sender.
- **Jenga API** (KCB, Equity) — currently dormant. `apps/payments/jenga.py`, `bank_views.py`, `bank_reconcile.py` are written but no live credentials. Plan to keep dormant until commercial agreement is in hand.
- **MinIO** — bucket `kasa-media` must have a `public/` prefix with anonymous read access for tenant ID photos and lease PDFs to resolve from the mobile app.

## Cron jobs (Celery Beat)

| Task | Schedule | Purpose |
|------|----------|---------|
| `generate_monthly_invoices` | 1st of month, 06:00 EAT | Create invoices for all active leases |
| `send_rent_reminders` | Daily, 08:00 EAT | SMS reminders 7/3/0 days before due date |
| `reconcile_pending_stk_transactions` | Every 5 min | Query Daraja for unfulfilled STK callbacks |

## Roadmap (deferred — see `TODOS.md`)

- Push notifications (FCM/APNs)
- Late fee / penalty logic on overdue invoices
- KYC review workflow for uploaded ID photos
- Bank reconciliation activation (Jenga API)
- Landlord credit scoring layer
- Tenant payment history as portable credit reference
- Rent receipt PDF for tenants

## Backup strategy

**NONE YET — critical gap.** The `mysql_data` Docker volume on a single VPS is the only copy of payment and tenant data. Plan:
- Daily MySQL dump to MinIO (separate bucket)
- Weekly MinIO snapshot off-site (S3 or rclone to remote)
- Document restore procedure

## Who to ask

Project owner: **Peter Mwaura** — kanielpeter132@gmail.com

## Useful local commands

```bash
# Inspect Celery queue
docker compose exec redis redis-cli -a "$REDIS_PASSWORD" LLEN celery

# Tail Celery worker logs
docker compose logs -f celery

# Open Django shell
docker compose exec api python manage.py shell

# Run a one-off task manually
docker compose exec api python manage.py shell -c "from apps.payments.tasks import generate_monthly_invoices; generate_monthly_invoices.delay()"

# Trigger an STK push for testing (sandbox)
docker compose exec api python manage.py shell -c "from apps.payments.mpesa import simulate_c2b_payment; print(simulate_c2b_payment('254708374149', 100, 'UNIT-XXXX'))"
```
