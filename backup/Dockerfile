# Minimal backup runner: mysql-client (provides mysqldump) + mc (MinIO client).
#
# WHY python:3.12-slim and not mysql:8.0:
#   mysql:8.0 is oraclelinux:9-slim under the hood — fine in theory but
#   microdnf has been flaky in BuildKit runs (Coolify build hit exit 127
#   on a clean `microdnf install`). python:3.12-slim is the same Debian
#   base our api uses; apt-get is reliable and the install path is short.
# WHY default-mysql-client and not the full mysql server:
#   mysqldump-compatible binary in <30MB. Backup container stays small.
FROM python:3.12-slim

ARG MC_VERSION=RELEASE.2024-11-21T17-21-54Z

RUN apt-get update && apt-get install -y --no-install-recommends \
      default-mysql-client \
      ca-certificates \
      curl \
      gzip \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSLfo /usr/local/bin/mc \
      "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}" \
    && chmod +x /usr/local/bin/mc

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
