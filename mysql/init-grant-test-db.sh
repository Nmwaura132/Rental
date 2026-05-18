#!/bin/bash
# Grant the app user CREATE/DROP privileges on `test_<DB_NAME>` databases so
# Django's test runner can manage them. Scope is limited to test_* — production
# DB privileges are unaffected.
#
# The MySQL official entrypoint runs scripts in /docker-entrypoint-initdb.d/
# exactly once, after the data dir is initialized and a temporary mysqld is
# listening on the unix socket. Env vars MYSQL_USER and MYSQL_PASSWORD are
# available here from docker-compose env_file.
set -euo pipefail

if [ -z "${MYSQL_USER:-}" ]; then
  echo "init-grant-test-db: MYSQL_USER not set, skipping."
  exit 0
fi

mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
GRANT ALL PRIVILEGES ON \`test_%\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL

echo "init-grant-test-db: granted test_* privileges to ${MYSQL_USER}"
