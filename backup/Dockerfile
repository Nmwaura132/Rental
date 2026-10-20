# Minimal backup runner: mysql-client (provides mysqldump) + boto3 for MinIO.
#
# WHY python:3.12-slim and not mysql:8.0:
#   mysql:8.0 is oraclelinux:9-slim under the hood — fine in theory but
#   microdnf has been flaky in BuildKit runs (Coolify build hit exit 127
#   on a clean `microdnf install`). python:3.12-slim is the same Debian
#   base our api uses; apt-get is reliable and the install path is short.
# WHY default-mysql-client and not the full mysql server:
#   mysqldump-compatible binary in <30MB. Backup container stays small.
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      default-mysql-client \
      ca-certificates \
      gzip \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

# WHY boto3 and not MinIO's mc: mc is no longer downloadable (see store.py).
# Pinned to the API's version so both talk to MinIO the same way.
RUN pip install --no-cache-dir boto3==1.35.91

COPY store.py /store.py

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
