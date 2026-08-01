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
  RAW_FILE="/tmp/${DB_NAME}-${STAMP}.sql"
  DUMP_FILE="/tmp/${DB_NAME}-${STAMP}.sql.gz"
  echo "[backup] dumping ${DB_NAME} -> ${DUMP_FILE}"

  # WHY --single-transaction: dumps InnoDB tables without table locks (safe
  # against live writes). --routines + --triggers preserve stored procs.
  #
  # WHY no --set-gtid-purged: Debian's default-mysql-client is MariaDB's
  # mysqldump, which rejects that Oracle-only flag outright ("unknown variable").
  #
  # WHY --ssl-verify-server-cert=0: the MariaDB client verifies certificates by
  # default and the MySQL server presents a self-signed cert, so the connection
  # is refused. The link is container-to-container on a private Docker network;
  # this keeps the traffic encrypted but skips chain validation.
  #
  # WHY --no-tablespaces: the backup role is a plain app user without the
  # PROCESS privilege that tablespace introspection requires.
  #
  # WHY dump to an uncompressed file first: `mysqldump | gzip > f` reports the
  # exit status of gzip, not mysqldump, so a failed dump still looked like a
  # success and shipped a 20-byte empty archive every night. Writing the raw
  # dump first lets us test mysqldump's own status.
  if ! mysqldump \
      --host="$DB_HOST" --port="$DB_PORT" \
      --user="$DB_USER" --password="$DB_PASSWORD" \
      --ssl-verify-server-cert=0 --no-tablespaces \
      --single-transaction --quick --routines --triggers \
      "$DB_NAME" > "$RAW_FILE"; then
    echo "[backup] ERROR: mysqldump failed" >&2
    rm -f "$RAW_FILE"
    continue
  fi

  # WHY check the trailer: mysqldump can exit 0 having written a truncated dump
  # (killed mid-stream, disk full). It always ends with this marker when whole.
  if ! tail -c 512 "$RAW_FILE" | grep -q "Dump completed"; then
    echo "[backup] ERROR: dump incomplete (no 'Dump completed' trailer); discarding" >&2
    rm -f "$RAW_FILE"
    continue
  fi

  gzip -c "$RAW_FILE" > "$DUMP_FILE"
  rm -f "$RAW_FILE"
  SIZE=$(stat -c%s "$DUMP_FILE")
  echo "[backup] dump OK (${SIZE} bytes), uploading..."
  if mc cp "$DUMP_FILE" "local/$BACKUP_BUCKET/$(basename "$DUMP_FILE")"; then
    echo "[backup] uploaded to local/$BACKUP_BUCKET/$(basename "$DUMP_FILE")"
  else
    echo "[backup] ERROR: upload failed; keeping local dump for next attempt" >&2
  fi
  rm -f "$DUMP_FILE"

  # Retention sweep — drop dumps older than RETENTION_DAYS.
  echo "[backup] retention sweep (older than ${RETENTION_DAYS}d)..."
  mc rm --recursive --force --older-than "${RETENTION_DAYS}d" \
      "local/$BACKUP_BUCKET" >/dev/null 2>&1 || true

  echo "[backup] sleeping until next cycle"
done
