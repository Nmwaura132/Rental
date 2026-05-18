# Minimal backup runner: mysqldump (from official mysql image) + mc binary.
#
# WHY start from mysql:8.0 instead of alpine + apk add mariadb-client:
# mysqldump-from-mysql-8 produces output that's guaranteed identical to the
# tooling that maintains the running DB. mariadb-dump diverges slightly on
# default-charset and view definitions.
FROM mysql:8.0

# mc binary — pinned URL; Dependabot can't auto-update this, manual bump only.
ARG MC_VERSION=RELEASE.2024-11-21T17-21-54Z
RUN microdnf install -y curl tzdata gzip ca-certificates 2>/dev/null || \
    apt-get update && apt-get install -y --no-install-recommends curl tzdata gzip ca-certificates && rm -rf /var/lib/apt/lists/*
RUN curl -sSLo /usr/local/bin/mc \
      "https://dl.min.io/client/mc/release/linux-amd64/archive/mc.${MC_VERSION}" \
    && chmod +x /usr/local/bin/mc

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
