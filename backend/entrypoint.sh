#!/bin/sh
set -e

echo "Waiting for MySQL..."
while ! nc -z "$DB_HOST" "$DB_PORT"; do
  sleep 1
done
echo "MySQL is up."

# Only run migrations on the Django API server, not on Celery workers
# or other services. We look for 'manage.py' or 'gunicorn' in the command.
case "$*" in
  *"manage.py"*|*"gunicorn"*)
    echo "Running migrations..."
    python manage.py migrate --noinput --fake-initial
    echo "Collecting static files..."
    python manage.py collectstatic --noinput || echo "collectstatic had errors (non-fatal), continuing..."
    ;;
esac

exec "$@"
