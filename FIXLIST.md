# Kasa — Consolidated Fix List (Pre-Launch)

Generated 2026-05-16 from `/autoplan` + `/cso` + `/health`. Branch: main. Status: in development.

Source reports:
- `~/.gstack/projects/Nmwaura132-Rental/main-autoplan-20260516.md`
- `.gstack/security-reports/2026-05-16-cso.md`
- `~/.gstack/projects/Nmwaura132-Rental/health-history.jsonl`

## Progress (last updated 2026-05-16 — end of session)

**Done (24/27 + 1 bonus):**
- P0-3 (refresh token rotation), P0-4 (invoice race × 3 sites), P0-5/6/7 (Django/simplejwt/Pillow CVE bumps), P0-X (requests CVE bump)
- P1-8 (OTP via secrets), P1-9 (KCB/Equity fail-CLOSED), P1-10 (sanitized 500 bodies), P1-11 (MinIO 9001 off), P1-12 (sslip.io gate), P1-13 (16 pytest tests pass), P1-14 (daily mysqldump backup), P1-15 (auth throttles), P1-16 (OpenAPI schema), P1-17 (CI/CD + Dependabot)
- P2-18 (float→Decimal in 3 sites), P2-19 (retry on receipt SMS), P2-20 (PublicMediaStorage lazy), P2-21 (Swagger DEBUG-only), P2-22 (Redis port off), P2-23 (MFA plan doc), P2-24 (single source for unit-status), P2-25 (invoice due-date 8th)

**Completed 2026-07-29:**
- P0-1 (PII → private MinIO + signed URLs)
- P0-2 (DevPickerScreen → LoginScreen)
- P2-26 (error response shape) — mobile parser coordination needed

**Verified:**
- pip-audit: 34 → 12 CVEs (Django/simplejwt/Pillow/requests bumps closed the runtime-critical ones)
- Django check: clean (0 issues)
- Django check --deploy: 42 → 6 warnings (remaining 6 are DEBUG-only security warnings; production sets them via `if not DEBUG:`)
- pytest: 16/16 passing in 7.25s
- OpenAPI: spectacular --validate clean, schema generates 2669 lines

## Session 2026-07-31 — build repair

**Fixed:**
- **Dev API crash loop.** `payments/0007` had half-applied: MySQL does not roll
  back DDL, so when its `invoice_lease_period_unique` step hit duplicate rows the
  four already-created CHECK constraints survived while `django_migrations` stayed
  at `0006`. Every restart then died on "Duplicate check constraint name". Dropped
  the orphans and added a `RunPython` dedupe as 0007's *first* operation, so a
  failure now aborts before any DDL runs instead of recreating the trap. The
  dedupe only removes duplicates carrying no payment and zero `amount_paid`;
  anything holding money raises and asks for a human.
- **Env-dependent migration state.** `MaintenanceRequest.photo` used
  `storage=PrivateMediaStorage if settings.USE_S3 else None`, so the deconstructed
  field — and therefore `makemigrations --check` — differed by environment. Replaced
  with the module-level callable `private_media_storage`; drift check is now
  identical with `USE_S3` true or false.
- **Backups were empty for ~2 months.** Every archive in `kasa-backups` was 20
  bytes. Two causes, both in `backup/backup.sh`: MariaDB's `mysqldump` (what
  Debian's `default-mysql-client` provides) rejects Oracle-only
  `--set-gtid-purged=OFF`, and `mysqldump | gzip > f` yields gzip's exit status so
  the failure looked like success. Verified a repaired run produces an 86,980-byte
  dump / 16 KiB archive covering 36 tables. Also needed
  `--ssl-verify-server-cert=0` (MySQL's self-signed cert) and `--no-tablespaces`
  (backup user lacks PROCESS) — both latent failures the flag fix alone would have
  exposed.
- **Stale image + unpinned CVEs.** requirements.txt already pinned fixed urllib3 /
  requests / Pillow, but the running image predated them; `pyjwt` (simplejwt's
  signer) and `msgpack` were unpinned. Pinned both, upgraded pip in the Dockerfile.
  pip-audit: **43 vulns / 7 packages → 6 / 1** (then 0 after the pip bump).

**Verified this session:**
- pytest: **45 passed, 0 skipped** against MySQL — includes both row-lock
  concurrency tests that skip on SQLite and had never actually run.
- `makemigrations --check`: clean under `USE_S3=True` and `USE_S3=False`.
- Django check: 0 issues. `flutter analyze`: no issues. `flutter test`: 4 passed.
- Production VPS: api/celery/beat/db/redis/minio all up; DB holds 4 users, 10
  units and **zero** leases/invoices/payments, so 0007 applies there cleanly.

---

## P0 — Block any real user (data integrity, money, PII)

1. **PII in public MinIO bucket** (`/cso` Finding 1+2). Tenant national ID photos and lease PDFs are publicly readable with predictable URLs. Use `PrivateMediaStorage` (already exists at `apps/core/storage_backends.py`) and generate signed URLs on demand.
   Files: `backend/apps/accounts/views.py:200`, `backend/apps/tenants/views.py:82`, `docker-compose.{yml,prod.yml}` line ~125 (the `mc anonymous set public` command).

2. **Mobile uses DevPickerScreen, not LoginScreen** (`/autoplan` B). Single-line swap in `mobile/lib/core/router.dart:41`. Also delete `dev_picker_screen.dart` references and remove the hardcoded credentials block from `mobile/lib/core/constants.dart`.

3. **Mobile refresh token rotation bug** (`/autoplan` B1). Add one line to `mobile/lib/core/api/api_client.dart:~109`:
   ```dart
   await _storage.write(key: 'refresh_token', value: resp.data['refresh']);
   ```

4. **Invoice amount_paid race condition** (`/autoplan` B2). Wrap in `transaction.atomic()` with `select_for_update()` on the Invoice row, in both `process_mpesa_payment` and `process_stk_callback` (`backend/apps/payments/tasks.py`). Same fix for `record_payment` (`backend/apps/payments/views.py:~127-142`).

5. **Django 5.1.4 → 5.1.15** (`/health`). 16 known CVEs (PYSEC-2025-1, CVE-2025-57833, CVE-2025-59681/2, CVE-2025-13372, CVE-2025-64460). One-line bump in `backend/requirements.txt`, rebuild image.

6. **djangorestframework-simplejwt 5.3.1 → 5.5.1** (`/health`). CVE-2024-22513 affects the auth path directly.

7. **Pillow 11.0.0 → 12.2.0+** (`/health`). 5 CVEs in image parsing — affects every uploaded ID photo and maintenance photo.

---

## P1 — Block production launch

8. **OTP uses random.randint** (`/autoplan` B3). Replace with `secrets.randbelow(900000) + 100000` in `backend/apps/accounts/views.py:PasswordResetRequestView`.

9. **KCB/Equity IPN fail-open** (`/cso` Finding 3). Change `return True` to `return settings.DEBUG` in `_verify_signature` and `_verify_basic_auth` in `backend/apps/payments/bank_views.py`.

10. **Raw exceptions in 500 responses** (`/autoplan` S2+S3). Three sites: `UploadIdPhotoView`, `send_lease` (PDF gen + S3 upload). Log the exception, return a generic message with a request ID.

11. **MinIO console port 9001 exposed** (`/cso` Finding 8 / `/autoplan` S8). Remove `"9001:9001"` from `docker-compose.prod.yml`. Use SSH tunnel for console access.

12. **`ALLOWED_HOSTS += [".sslip.io"]` runs in prod** (`/cso` Finding 4). Gate behind an env var:
    ```python
    if env.bool("ALLOW_SSLIP_HOSTS", default=False):
        ALLOWED_HOSTS += [".sslip.io"]
    ```

13. **No automated tests** (`/autoplan` + `/health`). Add `pytest.ini` with `DJANGO_SETTINGS_MODULE = config.settings`. Write at minimum:
    - `tests/test_payments.py` — invoice race, idempotency key, partial payment, OTP entropy
    - `tests/test_auth.py` — refresh rotation, password reset OTP flow
    - `tests/test_webhooks.py` — Safaricom IP allowlist enforcement, KCB HMAC verification
    - `tests/test_phone.py` — E.164 normalization edge cases

14. **No backup strategy** (`/cso` Finding 5). Add a `backup` service to `docker-compose.prod.yml` that does daily `mysqldump | gzip` to a separate MinIO bucket. Document restore.

15. **No rate limiting on auth endpoints** (`/autoplan` S6). Add `PasswordResetThrottle` at 3/min and `RegisterThrottle` at 5/min in `apps/core/throttles.py`; apply on the views directly.

16. **38 broken OpenAPI schema generations** (`/health`). Add `swagger_fake_view` guard to every ViewSet's `get_queryset()`:
    ```python
    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.queryset.none() if self.queryset else MyModel.objects.none()
        # ... real logic
    ```
    And add `serializer_class` (or `@extend_schema`) to APIView subclasses (M-Pesa webhooks, Reports, ChangePassword, PasswordReset).

17. **No CI/CD** (`/cso` Finding 6 + `/health`). Add `.github/workflows/ci.yml`:
    - `pip install -r requirements.txt`
    - `python manage.py check --deploy`
    - `pytest -x`
    - `pip-audit --strict`
    - `flutter analyze` (mobile job)
    Enable Dependabot for both `requirements.txt` and `pubspec.yaml`.

---

## P2 — Hardening before scale

18. **Money precision** (`/autoplan` B4). Replace `float(amount)` with `Decimal(str(amount))` in `record_payment` view AND the C2B webhook (`MpesaC2BConfirmView` passes `float(amount)` to Celery).

19. **send_payment_receipt_sms no retry** (`/autoplan` B7). Add `bind=True, max_retries=3, default_retry_delay=5` and a `Payment.DoesNotExist` retry.

20. **PublicMediaStorage instantiated at import time** (`/autoplan` B6). Remove the parentheses in `tenants/models.py`: `storage=PublicMediaStorage` (class, not instance).

21. **Swagger exposed in prod** (`/autoplan` S4). Wrap both schema routes in `if settings.DEBUG:` in `backend/config/urls.py`.

22. **Redis port 6379 publicly bound in dev** (`/cso` Finding 7). Remove `ports:` block from Redis in `docker-compose.yml`.

23. **MFA for landlord accounts** (`/cso` Finding 9). Optional TOTP via `django-otp` / `pyotp`. Make mandatory for any account with > N units.

24. **Dual unit-status sync** (`/autoplan`). Remove the `perform_create/update` hooks in `LeaseViewSet`; let the `post_save` signal in `tenants/signals.py` be the sole source of truth.

25. **Invoices due same day as creation** (`/autoplan` B8). Set `due_date = period_start + timedelta(days=7)` in `generate_monthly_invoices`, OR move generation to the 25th of the prior month so 7/3-day reminders work.

26. **Inconsistent error response shape** (`/autoplan` DX). Standardize on `{"error": {"code": "...", "message": "..."}}` via a custom DRF exception handler.

---

## P0 (new) — found 2026-07-31, resolved in Coolify config 2026-08-18

All four items below are staged and confirmed applied in Coolify's stored
config. None are *live* yet — they take effect on the next deploy, which is
still pending (see `handoff.md`).

34. ~~**Production `SECRET_KEY` is insecure.**~~ — DONE. `manage.py check --deploy`
    had flagged `security.W009`: simplejwt signs HS256 tokens with `SECRET_KEY`,
    so a weak key means forgeable access tokens. Rotated to a 64-char random key
    (40 unique chars) directly in Coolify's stored config, verified round-trip
    through its encryption. Applies on next deploy; rotating invalidates existing
    sessions and refresh tokens, which is fine pre-launch.

35. ~~**Nightly backups were silently empty.**~~ — DONE and verified end-to-end.
    Every archive in `kasa-backups` from ~May through 2026-07-31 was a 20-byte
    empty gzip: MariaDB's `mysqldump` rejects the Oracle-only
    `--set-gtid-purged=OFF`, and `mysqldump | gzip > f` reported gzip's exit
    status instead of mysqldump's, so the failure read as success. Fixed in
    `backup/backup.sh`. A live production dump (94,501 bytes, 36 tables) was
    restored into an isolated container and matched prod exactly — 89
    migrations, same row counts. See `handoff.md` "Restore procedure" for the
    rehearsal record.

36. ~~**Signed document URLs would be served over plain HTTP.**~~ — DONE. MinIO
    was on a published port 9000 over plain HTTP at a bare IP —
    `S3_PUBLIC_URL=http://37.221.93.219:9000/rental-assets`, no
    `S3_PUBLIC_ENDPOINT_URL` set. Moved MinIO to Traefik-routed TLS at
    `files-rwrwarkqwn77gwu6zbky1ppo.37.221.93.219.sslip.io` (labels committed in
    `docker-compose.prod.yml`, matching the resolver Coolify already uses for
    `api`), and set `S3_PUBLIC_ENDPOINT_URL`, `S3_PUBLIC_URL`, and
    `S3_SIGNED_URL_EXPIRES` in Coolify. Applies on next deploy.

37. ~~**`.sslip.io` wildcard is in production `ALLOWED_HOSTS`.**~~ — DONE. P1-12
    gated the code path behind `ALLOW_SSLIP_HOSTS`, but the deployed env listed
    `.sslip.io` literally, accepting any sslip.io subdomain — i.e. any host
    resolving to an arbitrary IP. Removed from the deployed `ALLOWED_HOSTS`; only
    the specific host in actual use remains. Applies on next deploy.

---

## P3 — Strategic / product gaps

27. **No tenant/landlord onboarding flow** — CEO finding from autoplan. Can't ship without it.
28. ~~**No lease creation UI in mobile**~~ — DONE. `tenants_screen.dart` posts to `/api/v1/tenants/leases/`.
29. **Jenga/bank reconciliation is dead code** — remove or feature-flag until live credentials exist. Now fails closed and has `tests/test_bank_reconciliation.py`, but still dormant.
30. ~~**Caretaker role under-tested**~~ — DONE. `tests/test_authorization.py` (349 lines) covers the role matrix; `docs/api-permission-matrix.md` documents it.
31. **No push notifications** — `firebase_core` / `firebase_messaging` are declared in `pubspec.yaml` but unused in `mobile/lib`, and the backend has no device-token or FCM dispatch path. Dependency only, not an implementation.
32. **No rent receipt PDF** — autoplan-flagged; tenants in Kenya expect a printable receipt. (SMS receipts exist; PDF does not.)
33. **No late fee logic** — Kenyan leases universally charge late fees. No code anywhere.

---

## Quick wins (≤ 5 minutes each)

- Remove `9001:9001` from `docker-compose.prod.yml` (#11)
- Bump Django, simplejwt, Pillow in `requirements.txt` (#5-7)
- Change `random.randint` → `secrets.randbelow` (#8)
- Add one line for refresh token persistence (#3)
- Change `return True` → `return settings.DEBUG` in two methods (#9)
- Gate `.sslip.io` behind env var (#12)
- Wrap Swagger routes in `if settings.DEBUG:` (#21)
- Remove parentheses on `PublicMediaStorage()` (#20)

That's ~8 quick fixes that close several CRITICAL/HIGH items in one short session.

---

## What's already good (don't break)

- Safaricom webhook IP allowlist middleware (when `DEBUG=False`)
- django-axes brute-force protection (5 failures → 1h lockout)
- JWT short access token (30 min) with refresh blacklist
- Idempotency keys on Payment for M-Pesa replay protection
- C2B select_for_update on STK request row (just need to extend to the Invoice row)
- Phone normalization to E.164 throughout
- Non-root user in backend Dockerfile (`USER django`)
- `.env` properly gitignored; no secrets in git history
- Flutter analyze: clean
- Healthchecks on MySQL, Redis, MinIO with sensible intervals
