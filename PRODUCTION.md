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

Build the mobile app with production endpoints:

```bash
cd mobile
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=MEDIA_BASE_URL=https://files.example.com
```
