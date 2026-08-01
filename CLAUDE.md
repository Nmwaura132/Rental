# Kasa — Rental Management System

## Project

Kasa is a Kenya-focused rental property management system. Django REST API + Flutter mobile app.
Three roles: **Landlord**, **Caretaker**, **Tenant**. Auth uses phone number (E.164) as username, not email.

**Status**: In development. Phone/password login is wired; production release
configuration is documented in `PRODUCTION.md`.

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
ENV_FILE=.env.production docker compose --env-file .env.production -f docker-compose.prod.yml up -d

# Mobile
cd mobile && flutter pub get && flutter run
cd mobile && flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com --dart-define=MEDIA_BASE_URL=https://files.example.com

# Backend tests
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
- `mobile/lib/core/api/api_client.dart` — JWT access and rotated refresh tokens are persisted in secure storage.

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

## Resolved launch blockers (see `handoff.md` for historical context)

The May 2026 blockers covering login, refresh rotation, payment races, OTP
entropy, error leakage, MinIO exposure, embedded credentials, and production
Swagger access have been addressed. Authorization and private signed document
storage were hardened in July 2026.

Full review: `~/.gstack/projects/Nmwaura132-Rental/main-autoplan-20260516.md`

## Don't

- Don't add `Co-Authored-By: Claude` or any Claude/Anthropic authorship to commit messages.
- Don't add development account pickers or embedded credentials to the mobile app.
- Don't expose Swagger (`/api/docs/`) in production — gate behind `if settings.DEBUG`.
- Don't use `float()` on monetary values. Use `Decimal(str(value))`.
- Don't bypass `apps.core.private_files` for identity documents, lease PDFs, reports, or maintenance photos.
- Don't modify existing migrations — always create new ones.
- Don't commit `.env` files (already in `.gitignore`).
- Don't bind MinIO port 9001 publicly in production.
