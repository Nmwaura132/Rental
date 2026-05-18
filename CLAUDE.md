# Kasa — Rental Management System

## Project

Kasa is a Kenya-focused rental property management system. Django REST API + Flutter mobile app.
Three roles: **Landlord**, **Caretaker**, **Tenant**. Auth uses phone number (E.164) as username, not email.

**Status**: In development. NOT YET LIVE. `DevPickerScreen` is the currently-routed login — must be swapped to `LoginScreen` before any real user.

## Stack

- Backend: Django 5.1, DRF, MySQL, Redis, Celery (worker + beat), MinIO (S3-compatible)
- Mobile: Flutter 3.22+, Dart 3.3+, Riverpod, GoRouter, Dio
- Integrations: M-Pesa Daraja (C2B Paybill + STK Push), Africa's Talking (SMS), Jenga API (KCB/Equity bank — dormant)
- Deployment: Docker Compose + Coolify on a single VPS

## Common commands

```bash
# Dev
docker compose up -d
docker compose exec api python manage.py migrate
docker compose exec api python manage.py createsuperuser

# Prod
docker compose -f docker-compose.prod.yml up -d

# Mobile
cd mobile && flutter pub get && flutter run
cd mobile && flutter build apk --release

# Backend tests (NONE EXIST YET — see Known Issues)
cd backend && pytest
```

## Code conventions

- Phone numbers ALWAYS normalized to E.164 via `apps.core.utils.phone.normalize_phone`. Never store raw input.
- Money ALWAYS as `Decimal`. Never `float()` on monetary values — precision loss.
- Webhooks MUST return HTTP 200 immediately; defer processing to Celery via `.delay()`.
- SMS dispatch via `apps.notifications.tasks.send_sms.delay(user_id, message)` — never call the AT SDK directly.
- DRF response shapes: aim for `{"error": "message"}` for client errors. (Currently inconsistent — see autoplan report.)

## Critical paths — handle with care

- `apps/payments/tasks.py` — money path. Known race condition in `process_mpesa_payment` and `process_stk_callback` (non-atomic `invoice.amount_paid` updates). Fix before scaling.
- `apps/payments/views.py` — M-Pesa webhook contract. Do NOT change response shape; Safaricom expects `{"ResultCode": 0, "ResultDesc": "..."}`.
- `apps/core/middleware.py` — Safaricom IP allowlist. Skipped when `DEBUG=True`. Production-critical.
- `mobile/lib/core/api/api_client.dart` — JWT refresh has a known rotation bug at line ~109 (new refresh token not persisted after rotation). Every user gets logged out after first 30-min expiry.

## Skill routing

- Product ideas/brainstorming → `/office-hours`
- Strategy/scope → `/plan-ceo-review`
- Architecture → `/plan-eng-review`
- Design system/plan review → `/design-consultation` or `/plan-design-review`
- Full review pipeline → `/autoplan`
- Security audit (infra) → `/cso`
- Tooling status → `/health`
- Bugs/errors → `/investigate`
- QA/testing → `/qa` or `/qa-only`
- Code review/diff → `/review`
- Visual polish → `/design-review`
- Ship/deploy → `/ship` or `/land-and-deploy`
- Save progress → `/context-save`
- Resume context → `/context-restore`

When the user's request matches a skill, invoke it. When in doubt, invoke the skill.

## Known critical issues (see `handoff.md` for full list)

1. Mobile uses `DevPickerScreen` instead of `LoginScreen` — `mobile/lib/core/router.dart`
2. Refresh token rotation bug — `mobile/lib/core/api/api_client.dart:109` doesn't save new refresh token
3. Invoice `amount_paid` race condition — `backend/apps/payments/tasks.py` (two functions)
4. OTP uses `random.randint` (not crypto-secure) — `backend/apps/accounts/views.py:PasswordResetRequestView`
5. Raw exceptions in 500 responses — `UploadIdPhotoView`, `send_lease`
6. MinIO console port 9001 publicly exposed — `docker-compose.prod.yml`
7. Hardcoded credentials in mobile — `mobile/lib/core/constants.dart`
8. Swagger `/api/docs/` accessible in production — `backend/config/urls.py`

Full review: `~/.gstack/projects/Nmwaura132-Rental/main-autoplan-20260516.md`

## Don't

- Don't add `Co-Authored-By: Claude` or any Claude/Anthropic authorship to commit messages.
- Don't ship `DevPickerScreen` — swap to `LoginScreen` first.
- Don't expose Swagger (`/api/docs/`) in production — gate behind `if settings.DEBUG`.
- Don't use `float()` on monetary values. Use `Decimal(str(value))`.
- Don't bypass the storage backend — use `default_storage` or the `PublicMediaStorage` class, not inline `boto3.client(...)`.
- Don't modify existing migrations — always create new ones.
- Don't commit `.env` files (already in `.gitignore`).
- Don't bind MinIO port 9001 publicly in production.
