#!/bin/sh
# Daily MySQL backup -> gzip -> MinIO backups bucket.
#
# WHY this runs as a sidecar container instead of cron-on-host:
#   1. Cron-on-host requires the operator to remember to install + maintain it
#      separately from Docker Compose. A sidecar is declarative and gets
#      deployed/upgraded with the rest of the stack via Coolify.
#   2. Coolify only manages docker-compose services; out-of-band cron jobs
#      drift silently and break.
#
# Loop pattern: compute seconds until next BACKUP_HOUR:00 EAT, sleep, dump,
# upload, retain N days, repeat. Survives container restarts cleanly.
set -eu

# Defaults — override via env in compose.
: "${DB_HOST:=db}"
: "${DB_PORT:=3306}"
: "${DB_NAME:?DB_NAME required}"
: "${DB_USER:?DB_USER required}"
: "${DB_PASSWORD:?DB_PASSWORD required}"
: "${MINIO_ENDPOINT:=http://minio:9000}"
: "${MINIO_ROOT_USER:?MINIO_ROOT_USER required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD required}"
: "${BACKUP_BUCKET:=kasa-backups}"
: "${BACKUP_HOUR:=2}"            # 02:00 — quiet hour for Kenyan tenants
: "${RETENTION_DAYS:=30}"
: "${TZ:=Africa/Nairobi}"

export TZ

echo "[backup] starting | tz=$TZ | hour=$BACKUP_HOUR | retention=${RETENTION_DAYS}d"

# Configure mc alias once.
mc alias set local "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing "local/$BACKUP_BUCKET" >/dev/null

while true; do
  # Sleep until next BACKUP_HOUR:00 in TZ.
  now_h=$(date +%H)
  now_m=$(date +%M)
  now_s=$(date +%S)
  if [ "$now_h" -lt "$BACKUP_HOUR" ]; then
    secs=$(( (BACKUP_HOUR - now_h) * 3600 - now_m * 60 - now_s ))
  else
    secs=$(( (24 - now_h + BACKUP_HOUR) * 3600 - now_m * 60 - now_s ))
  fi
  echo "[backup] next run in ${secs}s ($(date -d "+${secs} seconds" '+%Y-%m-%d %H:%M:%S %Z'))"
  sleep "$secs"

  STAMP=$(date +%Y%m%d-%H%M%S)
  DUMP_FILE="/tmp/${DB_NAME}-${STAMP}.sql.gz"
  echo "[backup] dumping ${DB_NAME} -> ${DUMP_FILE}"

  # WHY --single-transaction: dumps InnoDB tables without table locks (safe
  # against live writes). --routines + --triggers preserve stored procs.
  # --set-gtid-purged=OFF avoids GTID-restore complications on MySQL 8.
  if mysqldump \
      --host="$DB_HOST" --port="$DB_PORT" \
      --user="$DB_USER" --password="$DB_PASSWORD" \
      --single-transaction --quick --routines --triggers \
      --set-gtid-purged=OFF \
      "$DB_NAME" | gzip -c > "$DUMP_FILE"; then
    SIZE=$(stat -c%s "$DUMP_FILE")
    echo "[backup] dump OK (${SIZE} bytes), uploading..."
    if mc cp "$DUMP_FILE" "local/$BACKUP_BUCKET/$(basename "$DUMP_FILE")"; then
      echo "[backup] uploaded to local/$BACKUP_BUCKET/$(basename "$DUMP_FILE")"
    else
      echo "[backup] ERROR: upload failed; keeping local dump for next attempt" >&2
    fi
    rm -f "$DUMP_FILE"
  else
    echo "[backup] ERROR: mariadb-dump failed" >&2
    rm -f "$DUMP_FILE"
  fi

  # Retention sweep — drop dumps older than RETENTION_DAYS.
  echo "[backup] retention sweep (older than ${RETENTION_DAYS}d)..."
  mc rm --recursive --force --older-than "${RETENTION_DAYS}d" \
      "local/$BACKUP_BUCKET" >/dev/null 2>&1 || true

  echo "[backup] sleeping until next cycle"
done
