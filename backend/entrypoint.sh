#!/bin/sh
set -e

echo "Waiting for MySQL..."
while ! nc -z "$DB_HOST" "$DB_PORT"; do
  sleep 1
done
echo "MySQL is up."

# Only run migrations on the Django API server, not on Celery workers
# This prevents a race condition where multiple containers try to create
# the django_migrations table simultaneously on startup.
case "$1" in
  python)
    echo "Running migrations..."
    python manage.py migrate --noinput --fake-initial
    echo "Collecting static files..."
    python manage.py collectstatic --noinput
    ;;
esac

exec "$@"
