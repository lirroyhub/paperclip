FROM debian:bookworm-slim

# --- Install backup tooling -------------------------------------------------
# postgres-client : pg_dump for the database dump
# rclone          : upload to Google Drive (runs in Linux, so no macOS dyld wall)
# ca-certificates : TLS for rclone -> Google
# tzdata          : so the cron schedule respects your timezone
# curl            : only needed to fetch supercronic during build (removed after)
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-client \
        rclone \
        ca-certificates \
        tzdata \
        curl \
    && rm -rf /var/lib/apt/lists/*

# --- Install supercronic (container-native cron) ----------------------------
# amd64 build, because Catalina/Intel host is x86_64.
# Version pinned and SHA1 verified so a tampered/truncated download fails the
# build instead of silently shipping.
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=cd48d45c4b10f3f0bfdd3a57d054cd05ac96812b

RUN curl -fsSLO "$SUPERCRONIC_URL" \
    && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
    && chmod +x "$SUPERCRONIC" \
    && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
    && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic \
    && apt-get purge -y curl && apt-get autoremove -y

# --- App files --------------------------------------------------------------
COPY crontab /app/crontab
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

WORKDIR /app

# supercronic must be PID 1 so it handles SIGTERM/SIGINT gracefully.
# It inherits all container env vars and logs job output to stdout/stderr,
# which surface via `docker compose logs backup`.
CMD ["supercronic", "/app/crontab"]
