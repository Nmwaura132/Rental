# Production configuration

Production secrets are supplied at runtime and must never be committed.

1. Copy `.env.example` to `.env.production` and replace every placeholder.
2. Set `DEBUG=False`, the production host names, strong database/Redis/MinIO
   credentials, payment credentials, and:

   ```dotenv
   S3_ENDPOINT_URL=http://minio:9000
   S3_PUBLIC_ENDPOINT_URL=https://files.example.com
   S3_PUBLIC_URL=https://files.example.com/rental-assets
   S3_SIGNED_URL_EXPIRES=3600
   ```

3. Validate the fully rendered configuration:

   ```bash
   docker compose --env-file .env.production -f docker-compose.prod.yml config
   ```

4. Deploy using the same explicit environment file:

   ```bash
   ENV_FILE=.env.production docker compose \
     --env-file .env.production \
     -f docker-compose.prod.yml up -d --build
   ```

The startup command applies database migrations before starting Gunicorn. The
MinIO initialization job creates a private bucket and removes anonymous access.

## Deploying with Coolify

Production runs on Coolify. A push to `main` deploys on its own: GitHub calls
Coolify's webhook (repo Settings → Webhooks) and the app's Auto deploy is set to
"Deploy on push". Environment variables are set in Coolify, not in a file; their
names are case-sensitive.

## SMS

SMS goes out through MobileSasa:

```dotenv
MOBILESASA_API_KEY=mbs_...       # API token, scope "Send messages"
MOBILESASA_SENDER_ID=MOBILESASA  # a sender ID registered on the account
```

Each SMS is recorded as a Notification, sent or failed with MobileSasa's
response code (for example `0402` no credit, `0404` unknown sender ID).

Sign-in and sign-up codes depend on SMS, so delivery must work on every
network. Sender IDs are approved per network: the shared `MOBILESASA` ID
delivers on Safaricom but Airtel holds it at "Sent". Register Kasa's own
sender ID with MobileSasa for Safaricom, Airtel and Telkom, then set
`MOBILESASA_SENDER_ID` to it. MobileSasa's delivery reports
(`POST https://api.mobilesasa.com/v2/dlr`) show each message's final status.

## File storage

MinIO runs from Chainguard's build (`cgr.dev/chainguard/minio`): MinIO no
longer publishes `minio/minio` or `minio/mc`. It runs as uid 65532; the
`minio-permissions` step hands the data volume to that user before MinIO
starts. Nightly database backups land in the `kasa-backups` bucket, 30 days
kept. They are on the same server, so copy them off it as well.

## Where tenants pay rent

Tenants are shown a paybill and account number to pay to. Behind a bank's shared
paybill (Caritas) set these in `.env.production`:

```dotenv
RENT_PAYBILL=899790
RENT_ACCOUNT_PREFIX=623943#
STK_PUSH_ENABLED=false
```

Tenants then pay to `623943#<house number>`, exactly as the landlord numbered the
unit, and the app shows those details in place of a "Pay with M-Pesa" button: a
shared paybill cannot send M-Pesa prompts. Leave `RENT_PAYBILL` out entirely when
using a paybill of your own (it then follows `MPESA_SHORTCODE`); an empty value
overrides that fallback. `RENT_DUE_DAY` (default `5`) is the day each month's rent
falls due.

## Mobile release

Release builds are signed with Kasa's upload key, kept outside the repository
at `C:\Users\user\.kasa\kasa-upload.jks`; `mobile/android/key.properties`
(git-ignored, copy also in `C:\Users\user\.kasa\`) holds its alias and
password. **Back up both files somewhere off this computer.** Android only
installs an update signed with the same key, so losing it means every tester
must uninstall and reinstall. Once the app is on Google Play with Play App
Signing, a lost upload key can be reset through Play support.

Key certificate SHA-256: `39:85:88:EB:7A:7A:B2:62:78:FF:76:70:2E:FF:AC:8E:A6:12:94:D4:7E:83:62:76:63:27:DA:22:5B:98:A7:4F`

For testers, send the 64-bit APK (fits nearly every phone in use):

```bash
cd mobile
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://rwrwarkqwn77gwu6zbky1ppo.37.221.93.219.sslip.io \
  --dart-define=MEDIA_BASE_URL=https://files-rwrwarkqwn77gwu6zbky1ppo.37.221.93.219.sslip.io
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Raise `version:` in `pubspec.yaml` (the number after `+`) for every build
handed out, or phones will refuse it as an update.

## Mobile build

Build the mobile app with production endpoints:

```bash
cd mobile
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=MEDIA_BASE_URL=https://files.example.com
```
