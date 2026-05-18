FROM mysql:9.7
# Copy performance config with correct permissions (avoids world-writable warning on Docker Desktop/Windows)
COPY conf.d/performance.cnf /etc/mysql/conf.d/performance.cnf
RUN chmod 644 /etc/mysql/conf.d/performance.cnf

# WHY: Django's test runner needs CREATE DATABASE on `test_<DB_NAME>`. The app
# user owns DB_NAME by default; granting on `test_%` limits the privilege to
# test databases only. The MySQL entrypoint runs *.sh files in this directory
# once on first container start (when the data volume is empty).
COPY init-grant-test-db.sh /docker-entrypoint-initdb.d/01-grant-test-db.sh
RUN chmod +x /docker-entrypoint-initdb.d/01-grant-test-db.sh
