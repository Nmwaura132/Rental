FROM mysql:8.0
# Copy performance config with correct permissions (avoids world-writable warning on Docker Desktop/Windows)
COPY conf.d/performance.cnf /etc/mysql/conf.d/performance.cnf
RUN chmod 644 /etc/mysql/conf.d/performance.cnf
